import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class DownloadProgress {
  DownloadProgress(this.total);

  final int total;
  int received = 0;
  bool cancelled = false;

  double get fraction => total == 0 ? 0 : (received / total).clamp(0, 1);
}

class DownloadCancelled implements Exception {}

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
    }
  }

  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final json = {
      'server': serverUrl,
      'local': {for (final e in local.entries) e.key: e.value.toJson()},
      'seen': seenKeys.toList(),
      'seen_initialized': _seenInitialized,
      'last_read': lastRead?.toJson(),
      'bookmarks': bookmarks,
    };
    await _root.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(_stateFile.path);
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
    } catch (e) {
      online = false;
      lastError = e is TimeoutException ? 'Tidak ada sinyal' : '$e';
    }
    notifyListeners();
  }

  /// Changes on the server since the user last looked (only meaningful once
  /// the catalog was fetched at least once).
  List<ManualUpdate> get updates =>
      computeUpdates(remote: catalog, local: local, seenKeys: seenKeys);

  void markUpdatesSeen() {
    final before = seenKeys.length;
    seenKeys.addAll(catalog.files.map((f) => f.key));
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
    return result;
  }

  /// Files of a unit: server entries, plus downloaded ones the server dropped.
  List<ManualFile> filesOf(Unit unit) {
    final files = [...unit.files];
    final keys = {for (final f in files) f.key};
    for (final m in local.values) {
      if (m.file.unitId == unit.id && !keys.contains(m.file.key)) files.add(m.file);
    }
    return files;
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
      }
      local[file.key] = LocalManual(file: file, unitName: unitName);
      seenKeys.add(file.key);
      await _save();
    } catch (e) {
      for (final target in targets.values) {
        final part = File('$target.part');
        if (await part.exists()) await part.delete();
      }
      if (e is! DownloadCancelled) rethrow;
    } finally {
      downloads.remove(file.key);
      notifyListeners();
    }
  }

  void cancelDownload(String key) {
    downloads[key]?.cancelled = true;
    notifyListeners();
  }

  /// Downloads [remote] to `<target>.part` and checks its sha256.
  Future<void> _fetch(RemoteFile remote, String target, DownloadProgress progress) async {
    await Directory(p.dirname(target)).create(recursive: true);
    final part = File('$target.part');
    final request = http.Request('GET', _url(remote.path));
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} untuk ${remote.path}');
    }
    final sink = part.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var lastNotify = DateTime.now();
    try {
      await for (final chunk in response.stream) {
        if (progress.cancelled) throw DownloadCancelled();
        sink.add(chunk);
        hasher.add(chunk);
        progress.received += chunk.length;
        if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 150)) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
      await sink.close();
      hasher.close();
      if (digestSink.value.toString() != remote.sha256) {
        throw const FileSystemException('File rusak saat diunduh, coba lagi');
      }
    } catch (_) {
      await sink.close().catchError((_) {});
      rethrow;
    }
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
  Map<String, String> searchableIndexes({DocType? type}) => {
        for (final m in local.values)
          if (m.file.searchable && (type == null || m.file.type == type))
            m.file.key: indexPath(m.file),
      };

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    _client.close();
    super.dispose();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
