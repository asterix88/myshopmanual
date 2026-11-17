/// AppStore: the app's one shared state (login, catalog, downloaded manuals,
/// settings saved in state.json). Screens reach it with `StoreScope.of`.
///
/// This file holds the state itself and login/refresh/saving. Bigger topics
/// are extensions on AppStore in their own files under `store/`:
///
/// - `downloads.dart`   download, pause, cancel, retry, delete manuals
/// - `updates.dart`     the bell: new / updated / withdrawn manuals
/// - `ai_index.dart`    search indexes fetched in the background for nyel AI
/// - `spec_packs.dart`  per-unit spek.pdf for the Standar and Servis tabs
///
/// They are `part` files, so they may use AppStore's private fields. Their
/// methods are extension methods: a file that calls them must import
/// `store.dart` itself (getting AppStore through another file is not enough).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai.dart' show aiUrl;
import 'auth.dart';
import 'cetok.dart';
import 'diagnostics.dart';
import 'inspection.dart';
import 'keep_alive.dart';
import 'models.dart';
import 'usage.dart';

part 'store/ai_index.dart';
part 'store/downloads.dart';
part 'store/spec_packs.dart';
part 'store/updates.dart';

/// Server address: the Worker that serves the R2 bucket to logged-in phones
/// (ai-worker/src/files.ts), unless a build overrides it with
/// `flutter build apk --dart-define=CATALOG_URL=https://...`.
const _buildServerUrl = String.fromEnvironment('CATALOG_URL');
const defaultServerUrl = _buildServerUrl == '' || _buildServerUrl == _publicBucketUrl
    ? 'https://files.mymanual.my.id'
    : _buildServerUrl;

/// The bucket's own public address, used before the NRP login; it is closed
/// once every phone has the login version.
const _publicBucketUrl = 'https://mymanual.my.id';

/// Addresses saved by older versions that the app moves to [defaultServerUrl]:
/// r2.dev is blocked by some mobile operators, and the public bucket closes.
bool _outdatedServer(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  return url.contains('.r2.dev') || host == 'mymanual.my.id';
}

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
  AppStore._(this._root, this._rawClient) {
    _client = SessionClient(_rawClient, session: () => session, renew: renewSession);
  }

  static Future<AppStore> open({Directory? root, http.Client? client}) async {
    root ??= await getApplicationSupportDirectory();
    final store = AppStore._(root, client ?? http.Client());
    await store._load();
    return store;
  }

  final Directory _root;

  /// Without the session; for logging in and for other servers (Cetok).
  final http.Client _rawClient;

  /// Adds the session to requests for the app's servers.
  late final http.Client _client;

  /// The employee logged in on this phone (auth.json), null when nobody is.
  Session? session;

  bool get loggedIn => session != null;

  /// Random id of this phone, sent with logins so the admin sees its phones.
  String _deviceId = '';

  /// Login and admin calls to the server.
  late final AuthApi auth = AuthApi(_rawClient);

  Catalog catalog = Catalog.empty;
  Map<String, LocalManual> local = {};
  Set<String> seenKeys = {};

  /// Updates cleared with the bin on the update list: not listed again.
  Set<String> dismissedUpdates = {};

  /// Every update the bell has announced, newest first: the update list
  /// keeps them after they are seen, until the bin clears them.
  List<ManualUpdate> updateLog = [];

  /// The Cari tab's last searches, newest first.
  List<String> recentSearches = [];
  bool _seenInitialized = false;
  LastRead? lastRead;

  /// When the app was last in use on this phone; the opening animation only
  /// plays after a day or more away.
  DateTime? lastActive;

  /// The four introduction pages after the first login were seen or skipped.
  bool introSeen = false;
  Map<String, List<int>> bookmarks = {};
  String serverUrl = defaultServerUrl;

  /// null = not checked yet this session.
  bool? online;
  DateTime? lastChecked;
  String? lastError;

  final Map<String, DownloadProgress> downloads = {};

  File get _stateFile => File(p.join(_root.path, 'state.json'));
  File get _sessionFile => File(p.join(_root.path, 'auth.json'));
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
      if (savedUrl != null && savedUrl.isNotEmpty && !_outdatedServer(savedUrl)) {
        serverUrl = savedUrl;
      }
      local = {
        for (final e in (json['local'] as Map<String, dynamic>? ?? {}).entries)
          e.key: LocalManual.fromJson(e.value as Map<String, dynamic>),
      };
      seenKeys = {...(json['seen'] as List? ?? []).cast<String>()};
      dismissedUpdates = {...(json['dismissed'] as List? ?? []).cast<String>()};
      updateLog = [
        for (final e in json['update_log'] as List? ?? const []) ?_logEntry(e as Map<String, dynamic>),
      ];
      recentSearches = (json['searches'] as List? ?? []).cast<String>();
      _seenInitialized = json['seen_initialized'] as bool? ?? false;
      final lr = json['last_read'];
      lastRead = lr == null ? null : LastRead.fromJson(lr as Map<String, dynamic>);
      bookmarks = {
        for (final e in (json['bookmarks'] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as List).cast<int>(),
      };
      _deviceId = json['device_id'] as String? ?? '';
      lastActive = DateTime.tryParse(json['last_active'] as String? ?? '');
      introSeen = json['intro_seen'] as bool? ?? false;
      // Light unless the user picked another look in the menu (Anas, 9 Oct
      // 2026); older versions saved 'system' without asking.
      themeChosen = json['theme_chosen'] as bool? ?? false;
      themeMode = themeChosen ? json['theme'] as String? ?? 'light' : 'light';
      _aiDay = json['ai_day'] as String? ?? '';
      _homeSection = json['home_section'] as String? ?? '';
      _reportedApp = json['reported_app'] as String? ?? '';
      if (json['convert'] case {'kind': final String kind, 'from': final String from, 'to': final String to}) {
        lastConvert = (kind: kind, from: from, to: to);
      }
      _aiAsked = json['ai_asked'] as int? ?? 0;
    }
    if (_deviceId.isEmpty) _deviceId = DeviceInfo.newId();
    if (await _sessionFile.exists()) {
      try {
        session = Session.fromJson(jsonDecode(await _sessionFile.readAsString()) as Map<String, dynamic>);
      } on Object {
        session = null;
      }
      if (session?.expired ?? false) {
        // 30 days without reaching the server: log out (Anas, 12 Oct 2026).
        Diagnostics.log('session expired offline');
        await signOut();
      }
    }
  }

  /// Questions to nyel AI per day on this phone, to keep the AI bill small.
  static const aiDailyLimit = 10;

  /// Admins have no daily limit.
  bool get aiOwner => session?.admin ?? false;
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

  /// The sections in the catalog besides SEMUA, A-Z: one for most NRPs;
  /// more for an NRP with several sections, and for admins, who see all.
  List<String> get sections =>
      ({for (final u in units) u.section}..remove(sharedSection)).toList()..sort();

  String _homeSection = '';

  /// The section whose folders Home shows when there is more than one.
  String get homeSection {
    final all = sections;
    if (all.contains(_homeSection)) return _homeSection;
    return all.contains(defaultSection) ? defaultSection : all.firstOrNull ?? defaultSection;
  }

  void setHomeSection(String section) {
    _homeSection = section;
    _scheduleSave();
    notifyListeners();
  }

  /// The units Home lists: those of [homeSection] and SEMUA.
  List<Unit> get homeUnits {
    final all = units;
    if (sections.length <= 1) return all;
    final section = homeSection;
    return [for (final u in all) if (u.section == section || u.section == sharedSection) u];
  }

  /// 'system' (follow the phone), 'light' or 'dark'.
  String themeMode = 'light';

  /// Whether the user picked [themeMode] in the menu.
  bool themeChosen = false;

  void setThemeMode(String mode) {
    themeMode = mode;
    themeChosen = true;
    _scheduleSave();
    notifyListeners();
  }

  Future<DeviceInfo> deviceInfo() async => DeviceInfo(_deviceId, await DeviceInfo.phoneModel());

  /// Keeps [s] as this phone's login and loads the catalog with it.
  Future<void> signIn(Session s, {bool refreshNow = true}) async {
    session = s;
    await _saveSession();
    await _save();
    Diagnostics.log('logged in ${s.nrp}');
    notifyListeners();
    if (refreshNow) await refresh();
  }

  Future<void> _saveSession() async {
    final s = session;
    if (s == null) return;
    await _root.create(recursive: true);
    final tmp = File('${_sessionFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(s.toJson()));
    await tmp.rename(_sessionFile.path);
  }

  /// Logs out. [revoked]: the NRP was deactivated, so the manuals on the
  /// phone are removed too.
  Future<void> signOut({bool revoked = false}) async {
    // What this user did offline is sent first, when the phone is online,
    // so it is not lost; the rest is cleared so it is not counted for the
    // next person who logs in on this phone.
    final s = session;
    if (s != null && !revoked && !s.expired) {
      await usage.send().timeout(const Duration(seconds: 8), onTimeout: () {});
      if (inspection.pendingCount > 0) await inspection.flush().timeout(const Duration(seconds: 8), onTimeout: () {});
    }
    session = null;
    await inspection.clear();
    await usage.clear();
    try {
      if (await _sessionFile.exists()) await _sessionFile.delete();
      // The conversation belongs to the one who logged out.
      final chat = File(chatHistoryPath);
      if (await chat.exists()) await chat.delete();
    } on FileSystemException catch (e) {
      debugPrint('logout cleanup failed: $e');
    }
    if (revoked) {
      Diagnostics.log('access revoked, removing manuals');
      for (final key in downloads.keys.toList()) {
        cancelDownload(key);
      }
      for (final dir in ['manuals', 'index-cache', 'spek', 'page-thumbs']) {
        try {
          final d = Directory(p.join(_root.path, dir));
          if (await d.exists()) await d.delete(recursive: true);
        } on FileSystemException catch (e) {
          debugPrint('removing $dir failed: $e');
        }
      }
      local = {};
      bookmarks = {};
      lastRead = null;
      await _save();
    }
    notifyListeners();
  }

  /// Whether opening the app now plays the opening animation: always before
  /// logging in, otherwise only after a day or more since the app was last
  /// used (a quick return goes straight to Home).
  bool wantsSplash(DateTime now) {
    final last = lastActive;
    return !loggedIn || last == null || now.difference(last) >= const Duration(days: 1);
  }

  /// The app is in use (started, or going to the background).
  void markActive() {
    lastActive = DateTime.now();
    // Straight away: the phone may stop the app soon after it leaves view.
    unawaited(_save());
  }

  Future<void> finishIntro() async {
    introSeen = true;
    notifyListeners();
    await _save();
  }

  /// Logs out when the session ran out while the phone was offline.
  Future<void> checkSessionExpiry() async {
    if (session?.expired ?? false) await signOut();
  }

  /// Back in front after time in the background, maybe days: swap an aged
  /// session and send the usage log, which a cold start would also do.
  Future<void> resumed() async {
    await checkSessionExpiry();
    if (session?.stale ?? false) await renewSession();
    unawaited(usage.send());
  }

  /// The app version the server last heard from this phone.
  String _reportedApp = '';

  Future<Session?>? _renewing;

  /// Swaps the session for a new one (the server only accepts a day-old
  /// one). Null when the server could not be reached or refused; a refusal
  /// because the NRP is no longer allowed logs out.
  Future<Session?> renewSession() {
    return _renewing ??= () async {
      final old = session;
      if (old == null) return null;
      try {
        final fresh = await auth.refresh(old, await deviceInfo());
        if (session == null) return null;
        session = fresh;
        await _saveSession();
        if (_reportedApp != currentApp) {
          _reportedApp = currentApp;
          await _save();
        }
        notifyListeners();
        return fresh;
      } on AuthException catch (e) {
        Diagnostics.log('session refresh refused: ${e.code}');
        if (e.revoked) await signOut(revoked: e.code != 'login');
        return null;
      }
    }()
        .whenComplete(() => _renewing = null);
  }

  /// Where the nyel AI conversation is kept between app starts.
  String get chatHistoryPath => p.join(_root.path, 'chat.json');

  /// What the user did, sent for the admins' usage statistics.
  late final UsageLog usage = UsageLog(
    path: p.join(_root.path, 'usage.json'),
    client: _client,
    endpoint: Uri.parse('$aiUrl/stats'),
    // Admins test the app; their use is not counted.
    enabled: () => loggedIn && !(session?.admin ?? false),
    section: () => homeSection,
    renew: () async => await renewSession() != null,
  );

  /// Cetok Online's parts stock (its own server), opened from the Home tab.
  late final Cetok cetok = Cetok(
    cachePath: p.join(_root.path, 'cetok.json'),
    client: _client,
    showAllSetting: _cetokShowAll,
  );

  /// Daily Inspection Monitoring (the admin's Google Sheet, through the
  /// MyManual server), opened from Fitur lainnya on Home.
  late final Inspection inspection = Inspection(
    cachePath: p.join(_root.path, 'inspection.json'),
    client: _client,
    baseUrl: Uri.parse(aiUrl),
  );

  /// Whether this NRP has a Daily Inspection tab: Track, Wheel or Support
  /// (sessions from before sections are Track), or an admin.
  bool get seesInspection {
    final s = session;
    if (s == null) return false;
    if (s.admin || s.sections.isEmpty) return true;
    return s.sections.any((x) => inspectionSections.contains(x.toUpperCase()));
  }

  /// The admin's choice of all or some Cetok locations; null when offline.
  Future<bool?> _cetokShowAll() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final s = session;
      if (s == null) return null;
      try {
        return (await auth.appConfig(s)).cetokAll;
      } on AuthException catch (e) {
        if (e.code != 'refresh' || attempt > 0 || await renewSession() == null) return null;
      }
    }
    return null;
  }

  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _saving = Future.value();

  /// One write at a time: two at once would share the .tmp file.
  Future<void> _save() => _saving = _saving.catchError((_) {}).then((_) => _write());

  Future<void> _write() async {
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
      'dismissed': dismissedUpdates.toList(),
      'update_log': [
        for (final u in updateLog)
          {'kind': u.kind.name, 'unit_id': u.file.unitId, 'unit_name': u.unitName, 'file': u.file.toJson()},
      ],
      'searches': recentSearches,
      'seen_initialized': _seenInitialized,
      'last_read': lastRead?.toJson(),
      'bookmarks': bookmarks,
      'device_id': _deviceId,
      if (lastActive case final t?) 'last_active': t.toIso8601String(),
      'intro_seen': introSeen,
      'theme': themeMode,
      'theme_chosen': themeChosen,
      'ai_day': _aiDay,
      if (_homeSection.isNotEmpty) 'home_section': _homeSection,
      if (_reportedApp.isNotEmpty) 'reported_app': _reportedApp,
      'ai_asked': _aiAsked,
      if (lastConvert case final c?) 'convert': {'kind': c.kind, 'from': c.from, 'to': c.to},
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

  /// The server's catalog right now, without saving it or changing anything
  /// on the phone (used by the background update check).
  Future<Catalog> fetchCatalog() async {
    final response = await _client
        .get(_url('catalog.json'), headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    return Catalog.fromJson(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }

  /// False until the catalog was fetched once: before that every manual on
  /// the server would count as new.
  bool get seenInitialized => _seenInitialized;

  /// Where the phone keeps its files (state, manuals, notes of the
  /// background update check).
  Directory get root => _root;

  /// Fetches catalog.json. Offline is normal: the cached catalog stays.
  Future<void> refresh() async {
    await checkSessionExpiry();
    // A new APK tells the server its version (Kelola karyawan, Statistik)
    // through the session swap, without waiting for the session to age.
    if ((session?.stale ?? false) || (session != null && _reportedApp != currentApp)) await renewSession();
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
      final otherSection = [
        for (final m in local.values)
          if (catalog.hiddenUnits.contains(m.file.unitId)) m.file.key,
      ];
      if (otherSection.isNotEmpty) await deleteManuals(otherSection);
      if (!_seenInitialized) {
        // First connection: everything on the server is the starting point,
        // not "new", so the bell only lights for later changes.
        seenKeys = {for (final f in catalog.files) f.key};
        _seenInitialized = true;
        await _save();
      }
      if (_remember(updates)) _scheduleSave();
      online = true;
      lastChecked = DateTime.now();
      lastError = null;
      unawaited(usage.send());
      if (autoFetchAiIndexes) {
        unawaited(fetchAllAiIndexes());
        unawaited(fetchSpecPacks());
      }
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

  static ManualUpdate? _logEntry(Map<String, dynamic> json) {
    try {
      return ManualUpdate(
        kind: UpdateKind.values.byName(json['kind'] as String),
        file: ManualFile.fromJson(json['unit_id'] as String, json['file'] as Map<String, dynamic>),
        unitName: json['unit_name'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remembers a search for the Cari tab's start page.
  void addRecentSearch(String query) {
    final q = query.trim();
    if (q.length < 2) return;
    recentSearches = [q, ...recentSearches.where((s) => s.toLowerCase() != q.toLowerCase())].take(8).toList();
    _scheduleSave();
    notifyListeners();
  }

  void removeRecentSearch(String query) {
    recentSearches = [...recentSearches]..remove(query);
    _scheduleSave();
    notifyListeners();
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

  /// The manual for [key]: the downloaded copy if there is one, else the
  /// server's entry.
  ManualFile? fileByKey(String key) => local[key]?.file ?? catalog.file(key);

  String unitNameOf(ManualFile f) => local[f.key]?.unitName ?? unitById(f.unitId)?.name ?? f.unitId;

  /// Manuals waiting in an "Unduh semua" run, downloaded one at a time.
  final Set<String> downloadQueue = {};

  /// Waits between tries of a dropped download.
  @visibleForTesting
  static List<Duration> retryDelays = const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];


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
  /// in the background, so nyel AI never waits for one. The app turns it on;
  /// tests leave it off.
  bool autoFetchAiIndexes = false;

  AiIndexProgress? _aiIndexRun;

  /// The kind and units the Konversi Satuan screen showed last.
  ({String kind, String from, String to})? lastConvert;

  void setLastConvert(String kind, String from, String to) {
    lastConvert = (kind: kind, from: from, to: to);
    _scheduleSave();
  }

  /// The unit shown on the Spek and Servis tabs, once picked (not saved).
  String? pickedUnitId;

  void pickUnit(String id) {
    pickedUnitId = id;
    notifyListeners();
  }

  /// A question waiting to be put in nyel AI's input box (from "Tanya nyel
  /// AI" on a page); the chat takes it with [takeAiQuestion].
  String? get pendingAiQuestion => _pendingAiQuestion;
  String? _pendingAiQuestion;

  /// Counts [askAi] calls, so the tab bar switches to nyel AI once per ask.
  int aiAsks = 0;

  void askAi(String question) {
    _pendingAiQuestion = question;
    aiAsks++;
    notifyListeners();
  }

  /// Goes up whenever the nyel AI conversation is saved or cleared, so a
  /// chat screen showing an older copy reloads it.
  int chatRevision = 0;

  void chatChanged() {
    chatRevision++;
    notifyListeners();
  }

  String? takeAiQuestion() {
    final q = _pendingAiQuestion;
    _pendingAiQuestion = null;
    return q;
  }

  bool _fetchingSpecs = false;

  /// Where the search index of a manual that is not downloaded is kept for
  /// nyel AI; the version is in the name so an update fetches it afresh.
  /// Pieces of a manual read online, kept so its pages open again at once
  /// (see [RemotePdf]).
  String pdfBlockDir(ManualFile f) =>
      p.join(_root.path, 'pdf-blocks', f.unitId, '${f.id}-${f.pdf.sha256.substring(0, 12)}');

  String get pdfBlockRoot => p.join(_root.path, 'pdf-blocks');

  final _aiIndexFetches = <String, Future<void>>{};

  /// [notifyListeners] for the topic files under store/ (extensions may
  /// not call it directly: it is protected).
  void _changed() => notifyListeners();

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

Future<void> _deleteIfExists(File f) async {
  if (await f.exists()) await f.delete();
}
