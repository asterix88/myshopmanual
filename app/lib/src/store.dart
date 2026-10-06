import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Server address: the R2 bucket's custom domain (r2.dev is blocked by some
/// mobile operators), unless a build overrides it with
/// `flutter build apk --dart-define=CATALOG_URL=https://pub-xxxx.r2.dev`.
const _buildServerUrl = String.fromEnvironment('CATALOG_URL');
const defaultServerUrl = _buildServerUrl == ''
    ? 'https://mymanual.my.id'
    : _buildServerUrl;

/// How far [AppStore.fetchAllAiIndexes] has come.
class AiIndexProgress {
  AiIndexProgress({required this.total, required this.ready, required this.totalBytes});

  final int total;
  int ready;
  final int totalBytes;

  /// Bytes of indexes finished (or given up on).
  int doneBytes = 0;
  final _inFlight = <DownloadProgress>{};

  int get receivedBytes => doneBytes + _inFlight.fold(0, (s, p) => s + p.received);
}

class DownloadProgress {
  DownloadProgress(this.total);

  final int total;
  int received = 0;
  bool cancelled = false;

  /// Stopped with "Jeda": what arrived is kept so the download can resume.
  bool paused = false;

  double get fraction => total == 0 ? 0 : (received / total).clamp(0, 1);
}

class DownloadCancelled implements Exception {}

/// The connection dropped mid-download. What arrived is kept, so the next
/// try continues from there.
class DownloadInterrupted implements Exception {
  @override
  String toString() => 'Koneksi terputus. Ketuk "Lanjutkan unduhan" untuk meneruskan dari posisi terakhir.';
}

/// Everything the app knows: the server catalog (cached for offline use),
/// which manuals are on the phone, downloads in progress, and reading state.
class AppStore extends ChangeNotifier {
  AppStore._(this._root, this._client);

  static Future<AppStore> open({Directory? root, http.Client? client}) async {
    root ??= await getApplicationSupportDirectory();
    final store = AppStore._(root, client ?? http.Client());
    await store._load();
    return store;
  }

  final Directory _root;
  final http.Client _client;

  Catalog catalog = Catalog.empty;
  Map<String, LocalManual> local = {};
  Set<String> seenKeys = {};
  bool _seenInitialized = false;
  LastRead? lastRead;
  Map<String, List<int>> bookmarks = {};
  String serverUrl = defaultServerUrl;

  /// null = not checked yet this session.
  bool? online;
  DateTime? lastChecked;
  String? lastError;

  final Map<String, DownloadProgress> downloads = {};

  File get _stateFile => File(p.join(_root.path, 'state.json'));
  File get _catalogFile => File(p.join(_root.path, 'catalog.json'));

  String pdfPath(ManualFile f) => p.join(_root.path, 'manuals', f.unitId, '${f.id}.pdf');
  String indexPath(ManualFile f) => p.join(_root.path, 'manuals', f.unitId, '${f.id}.sqlite');

  /// A small picture of a manual page shown under an AI answer; the version
  /// is in the name so an updated manual draws it again.
  String pageThumbPath(ManualFile f, int page) =>
      p.join(_root.path, 'page-thumbs', f.unitId, '${f.id}-${f.pdf.sha256.substring(0, 12)}-$page.png');

  bool isDownloaded(String key) => local.containsKey(key);

  Future<void> _load() async {
    if (await _catalogFile.exists()) {
      try {
        catalog = Catalog.fromJson(jsonDecode(await _catalogFile.readAsString()));
      } on FormatException {
        catalog = Catalog.empty;
      }
    }
    if (await _stateFile.exists()) {
      final json = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
      final savedUrl = json['server'] as String?;
      // The old r2.dev address was saved by earlier builds; it is blocked by
      // some mobile operators, so move those installs to the new default.
      if (savedUrl != null && savedUrl.isNotEmpty && !savedUrl.contains('.r2.dev')) {
        serverUrl = savedUrl;
      }
      local = {
        for (final e in (json['local'] as Map<String, dynamic>? ?? {}).entries)
          e.key: LocalManual.fromJson(e.value as Map<String, dynamic>),
      };
      seenKeys = {...(json['seen'] as List? ?? []).cast<String>()};
      _seenInitialized = json['seen_initialized'] as bool? ?? false;
      final lr = json['last_read'];
      lastRead = lr == null ? null : LastRead.fromJson(lr as Map<String, dynamic>);
      bookmarks = {
        for (final e in (json['bookmarks'] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as List).cast<int>(),
      };
      aiOwner = json['ai_owner'] as bool? ?? false;
      _aiDay = json['ai_day'] as String? ?? '';
      _aiAsked = json['ai_asked'] as int? ?? 0;
    }
  }

  /// Questions to Tanya AI per day on this phone, to keep the AI bill small.
  static const aiDailyLimit = 10;

  /// The admin's phone (unlocked with the admin code) has no daily limit.
  bool aiOwner = false;
  String _aiDay = '';
  int _aiAsked = 0;

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Questions left today, or null when there is no limit.
  int? get aiQuestionsLeft {
    if (aiOwner) return null;
    final asked = _aiDay == _today() ? _aiAsked : 0;
    return (aiDailyLimit - asked).clamp(0, aiDailyLimit);
  }

  /// Counts one answered question against today's limit.
  void countAiQuestion() {
    final today = _today();
    if (_aiDay != today) {
      _aiDay = today;
      _aiAsked = 0;
    }
    _aiAsked++;
    _scheduleSave();
    notifyListeners();
  }

  void setAiOwner(bool owner) {
    aiOwner = owner;
    _scheduleSave();
    notifyListeners();
  }

  /// Where the Tanya AI conversation is kept between app starts.
  String get chatHistoryPath => p.join(_root.path, 'chat.json');

  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    await _root.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(_stateJson());
    await tmp.rename(_stateFile.path);
  }

  String _stateJson() {
    final json = {
      'server': serverUrl,
      'local': {for (final e in local.entries) e.key: e.value.toJson()},
      'seen': seenKeys.toList(),
      'seen_initialized': _seenInitialized,
      'last_read': lastRead?.toJson(),
      'bookmarks': bookmarks,
      'ai_owner': aiOwner,
      'ai_day': _aiDay,
      'ai_asked': _aiAsked,
    };
    return jsonEncode(json);
  }

  Uri _url(String path) {
    final base = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    return Uri.parse(base).resolve(path);
  }

  Future<void> setServerUrl(String url) async {
    serverUrl = url.trim();
    await _save();
    await refresh();
  }

  /// Fetches catalog.json. Offline is normal: the cached catalog stays.
  Future<void> refresh() async {
    if (serverUrl.isEmpty) {
      online = false;
      lastError = 'Alamat server belum diatur';
      notifyListeners();
      return;
    }
    try {
      final response = await _client
          .get(_url('catalog.json'), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      final body = utf8.decode(response.bodyBytes);
      catalog = Catalog.fromJson(jsonDecode(body) as Map<String, dynamic>);
      await _root.create(recursive: true);
      await _catalogFile.writeAsString(body);
      if (!_seenInitialized) {
        // First connection: everything on the server is the starting point,
        // not "new", so the bell only lights for later changes.
        seenKeys = {for (final f in catalog.files) f.key};
        _seenInitialized = true;
        await _save();
      }
      online = true;
      lastChecked = DateTime.now();
      lastError = null;
      if (autoFetchAiIndexes) unawaited(fetchAllAiIndexes());
    } catch (e) {
      online = false;
      lastError = _friendlyError(e);
      debugPrint('catalog refresh failed: $e');
    }
    notifyListeners();
  }

  /// A short reason a mechanic can act on, instead of the raw exception.
  static String _friendlyError(Object e) {
    if (e is TimeoutException) return 'Sinyal lemah, server tidak menjawab.';
    if (e is SocketException || e is http.ClientException) return 'Tidak ada koneksi internet.';
    return 'Server sedang bermasalah.';
  }

  /// Changes on the server since the user last looked (only meaningful once
  /// the catalog was fetched at least once).
  List<ManualUpdate> get updates =>
      computeUpdates(remote: catalog, local: local, seenKeys: seenKeys);

  /// Updates the user has not looked at yet: what the bell counts.
  List<ManualUpdate> get unseenUpdates => [
        for (final u in updates)
          if (!seenKeys.contains(u.seenKey)) u,
      ];

  /// What the update list shows. A withdrawn manual is listed until the user
  /// has seen it once; after that there is nothing left to do about it.
  List<ManualUpdate> get listedUpdates => [
        for (final u in updates)
          if (u.kind != UpdateKind.withdrawn || !seenKeys.contains(u.seenKey)) u,
      ];

  void markUpdatesSeen() {
    final before = seenKeys.length;
    final pending = updates;
    seenKeys.addAll(catalog.files.map((f) => f.key));
    seenKeys.addAll(pending.map((u) => u.seenKey));
    if (seenKeys.length != before) {
      _scheduleSave();
      notifyListeners();
    }
  }

  Unit? unitById(String id) {
    for (final u in catalog.units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Units to show: the server catalog plus any unit that only exists on the
  /// phone (withdrawn from the server, or the catalog never loaded).
  List<Unit> get units {
    final result = [...catalog.units];
    final known = {for (final u in result) u.id};
    final orphans = <String, List<LocalManual>>{};
    for (final m in local.values) {
      if (!known.contains(m.file.unitId)) {
        orphans.putIfAbsent(m.file.unitId, () => []).add(m);
      }
    }
    for (final e in orphans.entries) {
      result.add(Unit(
        id: e.key,
        name: e.value.first.unitName,
        kind: '',
        files: [for (final m in e.value) m.file],
      ));
    }
    // Biggest machines first; equal sizes by model code.
    result.sort((a, b) {
      final bySize = b.sizeClass.compareTo(a.sizeClass);
      return bySize != 0 ? bySize : a.id.compareTo(b.id);
    });
    return result;
  }

  /// Files of a unit: server entries, plus downloaded ones the server dropped.
  List<ManualFile> filesOf(Unit unit) {
    final files = [...unit.files];
    final keys = {for (final f in files) f.key};
    for (final m in local.values) {
      if (m.file.unitId == unit.id && !keys.contains(m.file.key)) files.add(m.file);
    }
    return files..sort(ManualFile.pageOrder);
  }

  LocalManual? localManual(String key) => local[key];

  /// Where a manual's PDF lives on the server, for reading it without
  /// downloading.
  Uri pdfUri(ManualFile f) => _url(f.pdf.path);

  /// The manual for [key]: the downloaded copy if there is one, else the
  /// server's entry.
  ManualFile? fileByKey(String key) => local[key]?.file ?? catalog.file(key);

  String unitNameOf(ManualFile f) => local[f.key]?.unitName ?? unitById(f.unitId)?.name ?? f.unitId;

  int get usedBytes => local.values.fold(0, (sum, m) => sum + m.file.downloadSize);

  Future<void> download(ManualFile file, {required String unitName}) async {
    if (downloads.containsKey(file.key)) return;
    final progress = DownloadProgress(file.downloadSize);
    downloads[file.key] = progress;
    notifyListeners();
    final targets = {file.index: indexPath(file), file.pdf: pdfPath(file)};
    try {
      for (final e in targets.entries) {
        await _fetch(e.key, e.value, progress);
      }
      // Swap both in only once both arrived intact, so an update that fails
      // halfway leaves the old version usable.
      for (final target in targets.values) {
        await File('$target.part').rename(target);
        await _deleteIfExists(File('$target.part.sha'));
      }
      local[file.key] = LocalManual(file: file, unitName: unitName);
      seenKeys.add(file.key);
      await _save();
    } on DownloadCancelled {
      // Cancelled on purpose: free the space. Paused keeps the parts.
      if (!progress.paused) {
        for (final target in targets.values) {
          await _deleteIfExists(File('$target.part'));
          await _deleteIfExists(File('$target.part.sha'));
        }
      }
    } on SocketException {
      throw DownloadInterrupted();
    } on HandshakeException {
      throw DownloadInterrupted();
    } on TimeoutException {
      throw DownloadInterrupted();
    } on http.ClientException {
      throw DownloadInterrupted();
    } finally {
      downloads.remove(file.key);
      notifyListeners();
    }
  }

  /// Stops a download but keeps what arrived, to continue later.
  void pauseDownload(String key) {
    final progress = downloads[key];
    if (progress == null) return;
    progress
      ..paused = true
      ..cancelled = true;
    notifyListeners();
  }

  void cancelDownload(String key) {
    downloads[key]?.cancelled = true;
    notifyListeners();
  }

  /// Bytes already downloaded for [file] by an interrupted download.
  int partialBytes(ManualFile file) {
    var total = 0;
    for (final (remote, target) in [(file.index, indexPath(file)), (file.pdf, pdfPath(file))]) {
      final part = File('$target.part');
      final tag = File('$target.part.sha');
      if (part.existsSync() && tag.existsSync() && tag.readAsStringSync() == remote.sha256) {
        total += part.lengthSync();
      }
    }
    return total;
  }

  /// Downloads [remote] to `<target>.part` and checks its sha256. A `.part`
  /// left by an interrupted try of the same version (recorded in
  /// `<target>.part.sha`) is continued with an HTTP Range request.
  Future<void> _fetch(RemoteFile remote, String target, DownloadProgress progress) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final part = File('$target.part');
    final tag = File('$target.part.sha');
    var have = 0;
    if (await part.exists()) {
      final sameVersion = await tag.exists() && await tag.readAsString() == remote.sha256;
      have = sameVersion ? await part.length() : 0;
      if (!sameVersion || have > remote.size) {
        await part.delete();
        have = 0;
      }
    }
    await tag.writeAsString(remote.sha256);
    progress.received += have;
    notifyListeners();

    if (have < remote.size) {
      final request = http.Request('GET', _url(remote.path));
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      final IOSink sink;
      if (have > 0 && response.statusCode == 206) {
        sink = part.openWrite(mode: FileMode.append);
      } else if (response.statusCode == 200) {
        // The server sent the whole file: start over.
        progress.received -= have;
        sink = part.openWrite();
      } else {
        throw HttpException('HTTP ${response.statusCode} untuk ${remote.path}');
      }
      var lastNotify = DateTime.now();
      try {
        // A dropped connection can stall without an error; treat 30 s of
        // silence as an interruption.
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (progress.cancelled) throw DownloadCancelled();
          sink.add(chunk);
          progress.received += chunk.length;
          if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 150)) {
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close().catchError((_) {});
      }
    }

    final path = part.path;
    final digest = await Isolate.run(() => sha256.bind(File(path).openRead()).first);
    if (digest.toString() != remote.sha256) {
      await _deleteIfExists(part);
      await _deleteIfExists(tag);
      throw const FileSystemException('File rusak saat diunduh, coba lagi');
    }
  }

  static Future<void> _deleteIfExists(File f) async {
    if (await f.exists()) await f.delete();
  }

  Future<void> deleteManuals(Iterable<String> keys) async {
    for (final key in keys.toList()) {
      final m = local.remove(key);
      if (m == null) continue;
      for (final path in [pdfPath(m.file), indexPath(m.file)]) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      bookmarks.remove(key);
      if (lastRead?.fileKey == key) lastRead = null;
    }
    await _save();
    notifyListeners();
  }

  void setLastRead(String fileKey, int page, {String? section}) {
    lastRead = LastRead(fileKey: fileKey, page: page, section: section);
    _scheduleSave();
    notifyListeners();
  }

  bool isBookmarked(String key, int page) => bookmarks[key]?.contains(page) ?? false;

  void toggleBookmark(String key, int page) {
    final pages = bookmarks.putIfAbsent(key, () => []);
    if (!pages.remove(page)) {
      pages
        ..add(page)
        ..sort();
    }
    _scheduleSave();
    notifyListeners();
  }

  /// Index files of every downloaded, searchable manual: {fileKey: path}.
  /// Whether a successful [refresh] fetches the search index of every manual
  /// in the background, so Tanya AI never waits for one. The app turns it on;
  /// tests leave it off.
  bool autoFetchAiIndexes = false;

  /// Progress of [fetchAllAiIndexes] while it runs: indexes ready of total,
  /// and bytes received of the bytes it has to fetch.
  AiIndexProgress? get aiIndexProgress => _aiIndexRun;
  AiIndexProgress? _aiIndexRun;

  /// Fetches every missing search index for Tanya AI (indexes only, never
  /// PDFs), a few at a time, and deletes cached indexes of manuals no longer
  /// on the server. A failed index is skipped; after several failures in a
  /// row (offline) it stops and tries again on the next refresh.
  Future<void> fetchAllAiIndexes() async {
    if (_aiIndexRun != null) return;
    final files = [for (final f in catalog.files) if (f.searchable) f];
    final missing = [for (final f in files) if (_readyAiIndex(f) == null) f];
    final run = _aiIndexRun = AiIndexProgress(
      total: files.length,
      ready: files.length - missing.length,
      totalBytes: missing.fold(0, (s, f) => s + f.index.size),
    );
    notifyListeners();
    var failuresInARow = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < missing.length && failuresInARow < 3) {
        final file = missing[next++];
        final got = await aiIndexes(where: (f) => f.key == file.key);
        if (got.isEmpty) {
          failuresInARow++;
        } else {
          failuresInARow = 0;
          run.ready++;
        }
        run.doneBytes += file.index.size;
        notifyListeners();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
      if (failuresInARow < 3) await _deleteStaleAiIndexes();
    } finally {
      _aiIndexRun = null;
      notifyListeners();
    }
  }

  Future<void> _deleteStaleAiIndexes() async {
    final keep = {for (final f in catalog.files) cachedIndexPath(f)};
    final dir = Directory(p.join(_root.path, 'index-cache'));
    if (!await dir.exists()) return;
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File && entry.path.endsWith('.sqlite') && !keep.contains(entry.path)) await entry.delete();
    }
  }

  /// Where the search index of a manual that is not downloaded is kept for
  /// Tanya AI; the version is in the name so an update fetches it afresh.
  String cachedIndexPath(ManualFile f) =>
      p.join(_root.path, 'index-cache', f.unitId, '${f.id}-${f.index.sha256.substring(0, 12)}.sqlite');

  /// Search indexes for Tanya AI over every manual on the server, by file
  /// key: a downloaded manual uses its own index; for any other only the small
  /// index is fetched (not the PDF) and kept. [where] narrows the manuals, so
  /// a question about one unit only fetches that unit's indexes. A manual
  /// whose index can't be fetched (offline) is left out.
  ///
  /// With [fetch] false nothing is downloaded: only indexes already on the
  /// phone are returned.
  Future<Map<String, String>> aiIndexes({
    bool Function(ManualFile file)? where,
    void Function(String status)? onStatus,
    bool fetch = true,
  }) async {
    final result = <String, String>{};
    for (final file in catalog.files.followedBy(local.values.map((m) => m.file))) {
      if (!file.searchable || result.containsKey(file.key) || !(where?.call(file) ?? true)) continue;
      final ready = _readyAiIndex(file);
      if (ready != null) {
        result[file.key] = ready;
        continue;
      }
      if (!fetch) continue;
      final target = cachedIndexPath(file);
      onStatus?.call('Mengambil indeks ${unitNameOf(file)} · ${file.type.label}…');
      // The background fetch and a question may want the same index at
      // once; they share one download.
      final download = _aiIndexFetches[file.key] ??=
          _fetchAiIndex(file, target).whenComplete(() {
            // A block body: returning the removed future would await itself.
            _aiIndexFetches.remove(file.key);
          });
      try {
        await download;
      } on Exception {
        continue;
      }
      result[file.key] = target;
    }
    return result;
  }

  final _aiIndexFetches = <String, Future<void>>{};

  /// The index of [file] if it is on the phone already, else null.
  String? _readyAiIndex(ManualFile file) {
    if (isDownloaded(file.key)) return indexPath(file);
    final cached = cachedIndexPath(file);
    return File(cached).existsSync() ? cached : null;
  }

  Future<void> _fetchAiIndex(ManualFile file, String target) async {
    final dir = Directory(p.dirname(target));
    if (await dir.exists()) {
      // Older versions of this manual's index.
      final old = RegExp('^${RegExp.escape(file.id)}-[0-9a-f]{12}\\.sqlite\$');
      await for (final entry in dir.list()) {
        if (old.hasMatch(p.basename(entry.path))) await entry.delete();
      }
    }
    final progress = DownloadProgress(file.index.size);
    final run = _aiIndexRun;
    run?._inFlight.add(progress);
    try {
      await _fetch(file.index, target, progress);
    } finally {
      run?._inFlight.remove(progress);
    }
    await File('$target.part').rename(target);
    await _deleteIfExists(File('$target.part.sha'));
  }

  /// Search indexes for the Cari tab, by file key: every manual whose index
  /// is on the phone, downloaded or not (the small indexes of the others are
  /// fetched in the background for Tanya AI).
  Map<String, String> searchableIndexes({DocType? type}) => {
        for (final file in catalog.files.followedBy(local.values.map((m) => m.file)))
          if (file.searchable && (type == null || file.type == type))
            file.key: ?_readyAiIndex(file),
      };

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      // Last write on the way out, done right away so the next start reads
      // it; nobody is left to report a failure to.
      try {
        _root.createSync(recursive: true);
        final tmp = File('${_stateFile.path}.tmp')..writeAsStringSync(_stateJson());
        tmp.renameSync(_stateFile.path);
      } on FileSystemException catch (e) {
        debugPrint('saving state failed: $e');
      }
    }
    _client.close();
    super.dispose();
  }
}
