import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai.dart' show aiUrl;
import 'auth.dart';
import 'store.dart';

/// "Statistik pemakaian" for admins: what the server counted from the
/// phones' usage logs (ai-worker/src/stats.ts). Each answer is plain JSON,
/// read through the small classes below.
class StatsApi {
  StatsApi(this.store, this.client, {Uri? base}) : _base = base ?? Uri.parse(aiUrl);

  final AppStore store;
  final http.Client client;
  final Uri _base;

  File get _cache => File('${store.root.path}/stats-cache.json');

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {bool renewed = false}) async {
    final session = store.session;
    if (session == null) throw AuthException('login', 'Silakan masuk lagi.');
    final http.Response response;
    try {
      response = await client
          .post(
            _base.resolve(path),
            headers: {'content-type': 'application/json', sessionHeader: session.token},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw AuthException('network', 'Koneksi terputus');
    } on Exception {
      throw AuthException('network', 'Koneksi terputus');
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      data = null;
    }
    // The server takes a session for a day; swap it and ask again.
    if (response.statusCode == 401 && !renewed && await store.renewSession() != null) {
      return _post(path, body, renewed: true);
    }
    if (response.statusCode != 200 || data == null) {
      throw AuthException(
        data?['error'] as String? ?? 'server',
        data?['message'] as String? ?? 'Server sedang bermasalah (kode ${response.statusCode}).',
      );
    }
    return data;
  }

  static Map<String, dynamic> _filter(StatsFilter f) => {'period': f.allTime ? 'all' : '30', 'section': f.section};

  /// Everything the four tabs show. Kept on the phone, so the last numbers
  /// stay on screen without internet ([cached]).
  Future<StatsOverview> overview(StatsFilter f) async {
    final data = await _post('/admin/stats', _filter(f));
    unawaited(_remember(f.key, data));
    return StatsOverview(data);
  }

  Future<StatsOverview?> cached(StatsFilter f) async {
    try {
      final all = jsonDecode(await _cache.readAsString()) as Map<String, dynamic>;
      final data = all[f.key];
      return data == null ? null : StatsOverview((data as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(String key, Map<String, dynamic> data) async {
    try {
      var all = <String, dynamic>{};
      try {
        all = jsonDecode(await _cache.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
      all[key] = data;
      await _cache.writeAsString(jsonEncode(all));
    } on FileSystemException {
      // Only a convenience.
    }
  }

  Future<ManualStats> manual(StatsFilter f, String file) async =>
      ManualStats(await _post('/admin/stats/manual', {..._filter(f), 'file': file}));

  Future<PersonStats> person(StatsFilter f, String nrp) async =>
      PersonStats(await _post('/admin/stats/person', {..._filter(f), 'nrp': nrp}));

  Future<AnswerStats> answer(int id) async => AnswerStats(await _post('/admin/stats/answer', {'id': id}));

  Future<SearchStats> search(StatsFilter f, String query) async =>
      SearchStats(await _post('/admin/stats/search', {..._filter(f), 'q': query}));

  /// "Tandai sudah ditangani": off the "Tidak ketemu" list until searched again.
  Future<void> markHandled(String query) => _post('/admin/stats/handled', {'q': query});
}

class StatsFilter {
  const StatsFilter({this.allTime = false, this.section = ''});

  /// false = the last 30 days.
  final bool allTime;

  /// '' = every section.
  final String section;

  String get key => '${allTime ? 'all' : '30'}:$section';
  String get periodLabel => allTime ? 'Semua waktu' : '30 hari';
}

int _int(Object? v) => (v as num? ?? 0).toInt();
String _str(Object? v) => v as String? ?? '';
List<Map<String, dynamic>> _list(Object? v) => [for (final e in v as List? ?? const []) (e as Map).cast<String, dynamic>()];
List<String> _strings(Object? v) => [for (final e in v as List? ?? const []) '$e'];
DateTime? _time(Object? v) => _int(v) == 0 ? null : DateTime.fromMillisecondsSinceEpoch(_int(v));

class StatsOverview {
  StatsOverview(Map<String, dynamic> json)
      : users = _int(json['users']),
        active = _int(json['active']),
        opens = _int(json['opens']),
        ai = _int(json['ai']),
        sectionList = _strings(json['section_list']),
        manuals = [for (final m in _list(json['manuals'])) ManualCount(m)],
        units = [for (final u in _list(json['units'])) (unit: _str(u['unit']), n: _int(u['n']))],
        topics = [for (final t in _list(json['topics'])) (name: _str(t['name']), n: _int(t['n']))],
        good = _int((json['ratings'] as Map?)?['good']),
        bad = _int((json['ratings'] as Map?)?['bad']),
        questions = [for (final q in _list(json['questions'])) QuestionRow(q)],
        searches = [for (final s in _list(json['searches'])) SearchCount(s)],
        missing = [for (final s in _list(json['missing'])) SearchCount(s)],
        perSection = [
          for (final s in _list(json['per_section']))
            (section: _str(s['section']), active: _int(s['active']), total: _int(s['total'])),
        ],
        people = [for (final p in _list(json['people'])) PersonRow(p)],
        inactive = [for (final p in _list(json['inactive'])) InactiveRow(p)];

  final int users;
  final int active;
  final int opens;
  final int ai;
  final List<String> sectionList;
  final List<ManualCount> manuals;
  final List<({String unit, int n})> units;
  final List<({String name, int n})> topics;
  final int good;
  final int bad;
  final List<QuestionRow> questions;
  final List<SearchCount> searches;
  final List<SearchCount> missing;
  final List<({String section, int active, int total})> perSection;
  final List<PersonRow> people;
  final List<InactiveRow> inactive;

  bool get isEmpty => opens == 0 && ai == 0 && searches.isEmpty && people.isEmpty;
}

class ManualCount {
  ManualCount(Map<String, dynamic> json)
      : file = _str(json['file']),
        unit = _str(json['unit']),
        title = _str(json['title']),
        n = _int(json['n']),
        people = _int(json['people']),
        shared = json['shared'] == true;

  final String file;
  final String unit;
  final String title;
  final int n;
  final int people;

  /// Panduan MLU, Basic Electric: every section reads it.
  final bool shared;
}

class QuestionRow {
  QuestionRow(Map<String, dynamic> json)
      : id = _int(json['id']),
        at = _time(json['at']),
        nrp = _str(json['nrp']),
        name = _str(json['name']),
        sections = _strings(json['sections']),
        unit = _str(json['unit']),
        question = _str(json['q']);

  final int id;
  final DateTime? at;
  final String nrp;
  final String name;
  final List<String> sections;
  final String unit;
  final String question;
}

class SearchCount {
  SearchCount(Map<String, dynamic> json)
      : query = _str(json['q']),
        n = _int(json['n']),
        people = _int(json['people']);

  final String query;
  final int n;
  final int people;
}

class PersonRow {
  PersonRow(Map<String, dynamic> json)
      : nrp = _str(json['nrp']),
        name = _str(json['name']),
        sections = _strings(json['sections']),
        last = _time(json['last']),
        manuals = _int(json['manuals']),
        ai = _int(json['ai']),
        searches = _int(json['searches']);

  final String nrp;
  final String name;
  final List<String> sections;
  final DateTime? last;
  final int manuals;
  final int ai;
  final int searches;
}

class InactiveRow {
  InactiveRow(Map<String, dynamic> json)
      : nrp = _str(json['nrp']),
        name = _str(json['name']),
        sections = _strings(json['sections']),
        never = json['never'] == true,
        last = _time(json['last']);

  final String nrp;
  final String name;
  final List<String> sections;

  /// Has never logged in.
  final bool never;
  final DateTime? last;
}

class ManualStats {
  ManualStats(Map<String, dynamic> json)
      : file = _str(json['file']),
        unit = _str(json['unit']),
        title = _str(json['title']),
        opens = _int(json['opens']),
        people = _int(json['people']),
        downloads = _int(json['downloads']),
        chapters = [for (final c in _list(json['chapters'])) (title: _str(c['title']), n: _int(c['n']))],
        readers = [
          for (final r in _list(json['readers'])) (nrp: _str(r['nrp']), name: _str(r['name']), n: _int(r['n'])),
        ];

  final String file;
  final String unit;
  final String title;
  final int opens;
  final int people;
  final int downloads;
  final List<({String title, int n})> chapters;
  final List<({String nrp, String name, int n})> readers;
}

class PersonStats {
  PersonStats(Map<String, dynamic> json)
      : nrp = _str(json['nrp']),
        name = _str(json['name']),
        sections = _strings(json['sections']),
        last = _time(json['last']),
        manualsOpened = _int(json['manuals_opened']),
        ai = _int(json['ai']),
        searches = _int(json['searches']),
        manuals = [
          for (final m in _list(json['manuals']))
            (file: _str(m['file']), unit: _str(m['unit']), title: _str(m['title']), n: _int(m['n'])),
        ],
        questions = [for (final q in _list(json['questions'])) QuestionRow(q)];

  final String nrp;
  final String name;
  final List<String> sections;
  final DateTime? last;
  final int manualsOpened;
  final int ai;
  final int searches;
  final List<({String file, String unit, String title, int n})> manuals;
  final List<QuestionRow> questions;
}

class AnswerStats {
  AnswerStats(Map<String, dynamic> json)
      : question = QuestionRow(json),
        answer = _str(json['answer']),
        sources = _strings(json['sources']),
        topic = _str(json['topic']),
        rating = _str(json['rating']);

  final QuestionRow question;
  final String answer;
  final List<String> sources;
  final String topic;

  /// 'good', 'bad', or '' when not rated.
  final String rating;
}

class SearchStats {
  SearchStats(Map<String, dynamic> json)
      : query = _str(json['q']),
        n = _int(json['n']),
        people = _int(json['people']),
        who = [
          for (final w in _list(json['who']))
            (nrp: _str(w['nrp']), name: _str(w['name']), sections: _strings(w['sections']), at: _time(w['at'])),
        ];

  final String query;
  final int n;
  final int people;
  final List<({String nrp, String name, List<String> sections, DateTime? at})> who;
}
