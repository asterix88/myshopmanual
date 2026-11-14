import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The sections that have a Daily Inspection tab in the admin's sheet.
const inspectionSections = ['TRACK', 'WHEEL', 'SUPPORT'];

/// "e-51 38" -> "E5138": how unit codes are compared (as the server does).
String inspectionUnitKey(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s.\-]'), '');

/// "Track" for TRACK.
String sectionLabel(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

/// Example unit codes per section, for the Code unit field.
const unitExamples = {'TRACK': 'E5138', 'WHEEL': 'C577067', 'SUPPORT': 'CP531'};

/// One finding: a row of an "INSPECTION <SECTION> OPEN 2026" tab.
class InspectionRow {
  InspectionRow({
    required this.section,
    required this.row,
    required this.kase,
    required this.inspector,
    required this.leader,
    required this.unit,
    required this.model,
    required this.hm,
    required this.date,
    required this.problem,
    required this.action,
    this.pending = false,
    this.localId,
  });

  factory InspectionRow.fromJson(String section, Map<String, dynamic> j) => InspectionRow(
        section: section,
        row: (j['row'] as num?)?.toInt() ?? 0,
        kase: '${j['case'] ?? ''}',
        inspector: '${j['inspector'] ?? ''}',
        leader: '${j['leader'] ?? ''}',
        unit: '${j['unit'] ?? ''}',
        model: '${j['model'] ?? ''}',
        hm: '${j['hm'] ?? ''}',
        date: '${j['date'] ?? ''}',
        problem: '${j['problem'] ?? ''}',
        action: '${j['action'] ?? ''}',
      );

  final String section;

  /// Row number in the sheet; 0 for a finding not sent yet.
  final int row;
  final String kase;
  final String inspector;
  final String leader;
  final String unit;
  final String model;
  final String hm;

  /// dd/mm/yyyy, as the sheet shows it.
  final String date;
  final String problem;
  String action;

  /// Changed on the phone and not on the sheet yet.
  bool pending;

  /// For findings added on the phone and not sent yet.
  final String? localId;

  bool get closed => action.trim().isNotEmpty;

  /// Identifies the row in the app, also after the sheet is read again.
  String get id => localId ?? '$section:$row:${inspectionUnitKey(unit)}:${problem.toUpperCase()}';

  DateTime? get found => parseSheetDate(date);

  /// Days since it was found; null when the date can't be read.
  int? ageOn(DateTime today) {
    final d = found;
    if (d == null) return null;
    return DateTime(today.year, today.month, today.day).difference(d).inDays;
  }

  Map<String, dynamic> toJson() => {
        'row': row,
        'case': kase,
        'inspector': inspector,
        'leader': leader,
        'unit': unit,
        'model': model,
        'hm': hm,
        'date': date,
        'problem': problem,
        'action': action,
      };
}

/// "04/11/2026" -> 4 Nov 2026.
DateTime? parseSheetDate(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s.trim());
  if (m == null) return null;
  final d = int.parse(m[1]!), mo = int.parse(m[2]!), y = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

String sheetDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// A unit of POP UNIT AMM-SBS.
class PopUnit {
  const PopUnit(this.unit, this.model, this.section);

  final String unit;
  final String model;
  final String section;
}

class InspectionTab {
  InspectionTab({required this.updated, required this.rows, required this.leaders});

  /// The sheet's LAST UPDATE, e.g. "12/11/2026 9:10:00".
  final String updated;
  final List<InspectionRow> rows;

  /// The section's group leaders, most frequent first.
  final List<String> leaders;
}

/// Compares "PC210-10M0" and "PC1250SP-11R" by their numbers, so PC210
/// comes before PC1250.
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toUpperCase()).toList();
  final y = re.allMatches(b.toUpperCase()).toList();
  for (var i = 0; i < min(x.length, y.length); i++) {
    final p = x[i][0]!, q = y[i][0]!;
    final c = x[i][1] != null && y[i][1] != null ? int.parse(p).compareTo(int.parse(q)) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// Model, then unit, then the oldest finding first.
int compareFindings(InspectionRow a, InspectionRow b) {
  var c = naturalCompare(a.model, b.model);
  if (c != 0) return c;
  c = naturalCompare(a.unit, b.unit);
  if (c != 0) return c;
  final da = a.found, db = b.found;
  if (da != null && db != null) c = da.compareTo(db);
  return c != 0 ? c : a.row.compareTo(b.row);
}

class InspectionException implements Exception {
  InspectionException(this.message, {this.code = 'server', this.network = false});

  final String message;
  final String code;

  /// No answer from the server: the change stays queued.
  final bool network;

  @override
  String toString() => message;
}

/// Daily Inspection Monitoring: the admin's Google Sheet, read and written
/// through the MyManual server (ai-worker/src/inspection.ts). A copy stays
/// on the phone, and changes made without signal wait in a queue that is
/// sent by itself once the server answers again.
class Inspection extends ChangeNotifier {
  Inspection({required this.cachePath, required this.client, required this.baseUrl, this.retryEvery = const Duration(minutes: 1)});

  final String cachePath;
  final http.Client client;
  final Uri baseUrl;
  final Duration retryEvery;

  List<String> sections = const [];
  String sheetUrl = '';
  String inspector = '';
  List<PopUnit> pop = const [];

  /// Admins only: the robot could not open the sheet at the last check.
  String? healthProblem;

  /// The sheet as last read, without the queued changes.
  Map<String, InspectionTab> _server = {};

  /// What the screens show: the sheet plus the queued changes.
  Map<String, InspectionTab> tabs = {};
  DateTime? fetched;
  bool loading = false;
  String? error;

  /// The last change the sheet refused (e.g. the row was deleted).
  String? refused;

  final List<Map<String, dynamic>> _queue = [];
  bool _loaded = false;
  bool _flushing = false;
  Timer? _retry;

  int get pendingCount => _queue.length;

  Map<String, PopUnit>? _popIndex;
  Map<String, PopUnit> get popIndex => _popIndex ??= {for (final u in pop) inspectionUnitKey(u.unit): u};

  Future<void> open() async {
    if (!_loaded) {
      _loaded = true;
      await _load();
    }
    await refresh();
  }

  Future<void> _load() async {
    try {
      final file = File(cachePath);
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _apply(j['data'] as Map<String, dynamic>? ?? const {});
      final at = j['fetched'] as String?;
      fetched = at == null ? null : DateTime.tryParse(at);
      _queue
        ..clear()
        ..addAll([for (final q in j['queue'] as List? ?? const []) (q as Map).cast<String, dynamic>()]);
      _overlay();
      notifyListeners();
    } on Object catch (e) {
      debugPrint('inspection cache unreadable: $e');
    }
  }

  Map<String, dynamic>? _raw;

  void _apply(Map<String, dynamic> data) {
    _raw = data;
    sections = [for (final s in data['sections'] as List? ?? const []) '$s'];
    sheetUrl = data['sheet_url'] as String? ?? '';
    inspector = data['inspector'] as String? ?? '';
    pop = [
      for (final u in data['pop'] as List? ?? const [])
        if (u is List && u.length >= 3) PopUnit('${u[0]}', '${u[1]}', '${u[2]}'),
    ];
    _popIndex = null;
    final health = data['health'];
    healthProblem = health is Map && health['ok'] == false ? '${health['message'] ?? 'Robot tidak bisa membuka sheet.'}' : null;
    final t = (data['tabs'] as Map?)?.cast<String, dynamic>() ?? const {};
    _server = {
      for (final e in t.entries)
        e.key: InspectionTab(
          updated: '${(e.value as Map)['updated'] ?? ''}',
          rows: [
            for (final r in (e.value as Map)['rows'] as List? ?? const [])
              InspectionRow.fromJson(e.key, (r as Map).cast<String, dynamic>()),
          ],
          leaders: [for (final l in (e.value as Map)['leaders'] as List? ?? const []) '$l'],
        ),
    };
  }

  /// tabs = the sheet with the queued changes laid over it.
  void _overlay() {
    final out = <String, InspectionTab>{};
    for (final e in _server.entries) {
      out[e.key] = InspectionTab(
        updated: e.value.updated,
        leaders: e.value.leaders,
        rows: [for (final r in e.value.rows) InspectionRow.fromJson(e.key, r.toJson())],
      );
    }
    for (final op in _queue) {
      final tab = out[op['section']];
      if (tab == null) continue;
      if (op['kind'] == 'action') {
        final hit = _find(tab.rows, op);
        if (hit != null) {
          hit.action = op['action'] as String;
          hit.pending = true;
        }
      } else if (op['kind'] == 'add') {
        final problems = [for (final p in op['problems'] as List) '$p'];
        for (var i = 0; i < problems.length; i++) {
          tab.rows.add(InspectionRow(
            section: op['section'] as String,
            row: 0,
            kase: '${i + 1}',
            inspector: op['inspector'] as String? ?? inspector,
            leader: op['leader'] as String,
            unit: op['unit'] as String,
            model: op['model'] as String,
            hm: op['hm'] as String,
            date: op['date'] as String,
            problem: problems[i],
            action: '',
            pending: true,
            localId: '${op['id']}:$i',
          ));
        }
      }
    }
    for (final t in out.values) {
      t.rows.sort(compareFindings);
    }
    tabs = out;
  }

  InspectionRow? _find(List<InspectionRow> rows, Map<String, dynamic> op) {
    final unit = inspectionUnitKey(op['unit'] as String);
    final problem = (op['problem'] as String).toUpperCase();
    InspectionRow? any;
    for (final r in rows) {
      if (inspectionUnitKey(r.unit) != unit || r.problem.toUpperCase() != problem) continue;
      if (r.row == op['row']) return r;
      any ??= r;
    }
    return any;
  }

  /// Sends what waits in the queue, then reads the sheet again.
  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      await flush();
      final data = await _call('GET', '/inspection');
      _apply(data);
      // A change refused for an old session goes now that it is renewed.
      if (_queue.isNotEmpty) await flush();
      fetched = DateTime.now();
      error = null;
      _overlay();
      unawaited(_save());
    } on InspectionException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Writes ACTION of [row] (empty = open again). Returns false when it
  /// waits in the queue (no signal).
  Future<bool> setAction(InspectionRow row, String action) async {
    final text = action.trim().toUpperCase();
    if (row.localId != null) {
      // Not on the sheet yet: change the queued finding instead.
      throw InspectionException('Temuan ini belum terkirim ke sheet. Tunggu sampai terkirim, lalu isi Action.');
    }
    // A newer action for the same finding replaces a queued one.
    _queue.removeWhere((q) =>
        q['kind'] == 'action' &&
        q['section'] == row.section &&
        inspectionUnitKey(q['unit'] as String) == inspectionUnitKey(row.unit) &&
        (q['problem'] as String).toUpperCase() == row.problem.toUpperCase());
    _queue.add({
      'kind': 'action',
      'id': _newId(),
      'section': row.section,
      'row': row.row,
      'unit': row.unit,
      'problem': row.problem,
      'action': text,
    });
    return _changed();
  }

  /// New findings, one sheet row per problem. Returns false when they wait
  /// in the queue (no signal).
  Future<bool> add({
    required String section,
    required String unit,
    required String model,
    required String hm,
    required DateTime date,
    required String leader,
    required List<String> problems,
  }) {
    _queue.add({
      'kind': 'add',
      'id': _newId(),
      'section': section,
      'unit': unit.trim().toUpperCase(),
      'model': model.trim().toUpperCase(),
      'hm': hm.trim(),
      'date': sheetDate(date),
      'leader': leader.trim().toUpperCase(),
      'inspector': inspector,
      'problems': [for (final p in problems) if (p.trim().isNotEmpty) p.trim().toUpperCase()],
    });
    return _changed();
  }

  Future<bool> _changed() async {
    _overlay();
    notifyListeners();
    await _save();
    await flush();
    return _queue.isEmpty;
  }

  /// Sends the queue in order. Stops at the first change the server did
  /// not answer (tried again later); drops one the sheet refused.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    var sent = false;
    try {
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        final body = Map<String, dynamic>.of(op)..remove('kind');
        try {
          final res = await _call('POST', op['kind'] == 'add' ? '/inspection/add' : '/inspection/action', body);
          if (op['kind'] == 'action') _confirmAction(op, res);
          sent = true;
        } on InspectionException catch (e) {
          if (e.network) break;
          refused = e.message;
        }
        _queue.removeAt(0);
        await _save();
      }
    } finally {
      _flushing = false;
      _scheduleRetry();
    }
    if (sent) {
      _overlay();
      notifyListeners();
    }
  }

  /// The sheet took the action: keep it in the copy until it is read again.
  void _confirmAction(Map<String, dynamic> op, Map<String, dynamic> res) {
    final tab = _server[op['section']];
    if (tab == null) return;
    final hit = _find(tab.rows, {...op, 'row': (res['row'] as num?)?.toInt() ?? op['row']});
    hit?.action = op['action'] as String;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (_queue.isEmpty) return;
    _retry = Timer(retryEvery, () async {
      await flush();
      if (_queue.isEmpty) await refresh();
    });
  }

  String _newId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
  }

  Future<Map<String, dynamic>> _call(String method, String path, [Map<String, dynamic>? body]) async {
    final http.Response response;
    try {
      final url = baseUrl.resolve(path);
      response = await (method == 'GET'
              ? client.get(url)
              : client.post(url, headers: {'content-type': 'application/json'}, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw InspectionException('Tidak ada sinyal. Data yang tampil adalah salinan terakhir.', code: 'network', network: true);
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      data = null;
    }
    if (response.statusCode != 200 || data == null) {
      // A server that is down, or a sheet it can't open now, is like no
      // signal: changes wait. Refusals (4xx) are final.
      final temporary = response.statusCode >= 500 || response.statusCode == 401 || data == null;
      throw InspectionException(
        data?['message'] as String? ?? 'Server sedang bermasalah (kode ${response.statusCode}).',
        code: data?['error'] as String? ?? 'server',
        network: temporary,
      );
    }
    return data;
  }

  Future<void> _save() async {
    try {
      final file = File(cachePath);
      await file.parent.create(recursive: true);
      final tmp = File('$cachePath.${DateTime.now().microsecondsSinceEpoch}.tmp');
      final data = _raw == null
          ? <String, dynamic>{}
          : {
              ..._raw!,
              'tabs': {
                for (final e in _server.entries)
                  e.key: {
                    'updated': e.value.updated,
                    'leaders': e.value.leaders,
                    'rows': [for (final r in e.value.rows) r.toJson()],
                  },
              },
            };
      await tmp.writeAsString(jsonEncode({'data': data, 'fetched': fetched?.toIso8601String(), 'queue': _queue}));
      await tmp.rename(cachePath);
    } on Object catch (e) {
      debugPrint('saving inspection cache failed: $e');
    }
  }

  /// After logging out: the next person on this phone starts empty.
  Future<void> clear() async {
    _retry?.cancel();
    _queue.clear();
    _raw = null;
    _server = {};
    tabs = {};
    sections = const [];
    pop = const [];
    _popIndex = null;
    fetched = null;
    error = null;
    _loaded = false;
    try {
      final f = File(cachePath);
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      debugPrint('removing inspection cache failed: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }
}

/// The last HM written for [unit] in the tab, or null.
String? lastHm(InspectionTab? tab, String unit) {
  final key = inspectionUnitKey(unit);
  InspectionRow? best;
  for (final r in tab?.rows ?? const <InspectionRow>[]) {
    if (inspectionUnitKey(r.unit) != key || r.hm.isEmpty) continue;
    if (best == null || compareDates(r, best) > 0) best = r;
  }
  return best?.hm;
}

int compareDates(InspectionRow a, InspectionRow b) {
  final x = a.found, y = b.found;
  if (x == null || y == null) return a.row.compareTo(b.row);
  final c = x.compareTo(y);
  return c != 0 ? c : a.row.compareTo(b.row);
}
