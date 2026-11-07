import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai.dart' show aiUrl;
import 'auth.dart';
import 'page_image.dart' show quizPictureTarget;
import 'quiz_reminders.dart';
import 'store.dart';

/// The Quiz: questions from the manuals, spaced repetition, XP and a
/// leaderboard. Everything is decided by the server (ai-worker/src/quiz*.ts):
/// the phone shows the questions, sends each answer and shows what the
/// server counted. Answers that could not be sent (no signal) wait in
/// quiz_pending.json and go with the next call.
class QuizApi {
  QuizApi(this.store, this.client, {Uri? base}) : _base = base ?? Uri.parse(aiUrl);

  final AppStore store;
  final http.Client client;
  final Uri _base;

  /// The last Home numbers, so the Home card has something to show at once.
  static QuizHome? lastHome;

  /// Goes up after a set is played, so the Home card and the Quiz page
  /// load their numbers again.
  static final changed = ValueNotifier(0);

  File get _pending => File('${store.root.path}/quiz_pending.json');

  Future<Map<String, dynamic>> _call(String path, [Map<String, dynamic>? body, bool renewed = false]) async {
    final session = store.session;
    if (session == null) throw AuthException('login', 'Silakan masuk lagi.');
    final http.Response response;
    try {
      final headers = {'content-type': 'application/json', sessionHeader: session.token};
      final url = _base.resolve(path);
      response = await (body == null
              ? client.get(url, headers: headers)
              : client.post(url, headers: headers, body: jsonEncode(body)))
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
      return _call(path, body, true);
    }
    if (response.statusCode != 200 || data == null) {
      throw AuthException(
        data?['error'] as String? ?? 'server',
        data?['message'] as String? ?? 'Server sedang bermasalah (kode ${response.statusCode}).',
      );
    }
    return data;
  }

  // ---- Mechanic ----

  Future<QuizHome> home() async {
    await sendPending();
    final home = QuizHome(await _call('/quiz/home'));
    lastHome = home;
    unawaited(QuizReminders.sync(store.root, home));
    return home;
  }

  Future<List<QuizUnit>> units() async {
    final data = await _call('/quiz/units');
    return [for (final u in data['units'] as List) QuizUnit(u as Map<String, dynamic>)];
  }

  /// A set of 10 questions; [unit] null = Quiz harian.
  Future<QuizSession> start({String? unit}) async =>
      QuizSession(await _call('/quiz/session', {'mode': unit == null ? 'harian' : 'unit', 'unit': ?unit}));

  /// Sends one answer. Without signal it is kept and sent later; null then.
  Future<AnswerResult?> answer(QuizAnswer a) async {
    try {
      return AnswerResult(await _call('/quiz/answer', a.toJson()));
    } on AuthException catch (e) {
      if (e.code != 'network') rethrow;
      await _keep(a);
      return null;
    }
  }

  /// Sends answers kept while offline; true when none are left.
  Future<bool> sendPending() async {
    final list = await _readPending();
    if (list.isEmpty) return true;
    final left = <Map<String, dynamic>>[];
    for (final a in list) {
      try {
        await _call('/quiz/answer', a);
      } on AuthException catch (e) {
        // Too old or no longer part of a set: the server will never take it.
        if (e.code == 'network' || e.code == 'login') left.add(a);
      }
    }
    await _writePending(left);
    return left.isEmpty;
  }

  Future<bool> hasPending() async => (await _readPending()).isNotEmpty;

  Future<FinishResult> finish(String sessionId) async {
    await sendPending();
    return FinishResult(await _call('/quiz/finish', {'session_id': sessionId}));
  }

  Future<Board> leaderboard({bool month = false}) async =>
      Board(await _call('/quiz/leaderboard?period=${month ? 'month' : 'week'}'));

  Future<void> setAvatar(int avatar) => _call('/quiz/avatar', {'avatar': avatar});

  Future<bool> report(String questionId, String note) async =>
      (await _call('/quiz/report', {'question_id': questionId, 'note': note}))['pulled'] == true;

  Future<List<Map<String, dynamic>>> _readPending() async {
    try {
      return [for (final a in jsonDecode(await _pending.readAsString()) as List) (a as Map).cast<String, dynamic>()];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePending(List<Map<String, dynamic>> list) async {
    try {
      if (list.isEmpty) {
        if (await _pending.exists()) await _pending.delete();
      } else {
        await _pending.writeAsString(jsonEncode(list));
      }
    } on FileSystemException {
      // Nothing more to do; the answer is lost but the set goes on.
    }
  }

  Future<void> _keep(QuizAnswer a) async => _writePending([...await _readPending(), a.toJson()]);

  // ---- Admin ----

  /// nyel AI writes draft questions from one manual page; [kind] is campur,
  /// pg, bs or gambar. The curator checks them before they are saved.
  Future<GenerateResult> generate({
    required String section,
    required String unit,
    required String topic,
    required String manualId,
    required int page,
    required String text,
    required int count,
    String kind = 'campur',
  }) async {
    final data = await _call('/admin/quiz/generate', {
      'section': section,
      'unit': unit,
      'topic': topic,
      'manual_id': manualId,
      'page': page,
      'text': text,
      'count': count,
      'kind': kind,
    });
    return GenerateResult(data);
  }

  /// "Buat draf kuis" step 1: nyel AI picks pages from the table of contents.
  Future<List<PlannedPage>> plan({
    required String unit,
    required String topic,
    required String toc,
    required int pages,
    required int count,
    required QuizMix mix,
  }) async {
    final data = await _call('/admin/quiz/plan', {
      'unit': unit,
      'topic': topic,
      'toc': toc,
      'pages': pages,
      'count': count,
      'mix': mix.toJson(),
    });
    return [for (final p in data['pages'] as List) PlannedPage(p as Map<String, dynamic>)];
  }

  /// "Buat draf kuis" step 2: the pages with their text; the server goes on
  /// by itself. Returns the job id.
  Future<String> startJob({
    required String section,
    required String unit,
    required String manualId,
    required String title,
    required String topic,
    required int count,
    required QuizMix mix,
    required List<Map<String, dynamic>> pages,
  }) async {
    final data = await _call('/admin/quiz/job', {
      'section': section,
      'unit': unit,
      'manual_id': manualId,
      'title': title,
      'topic': topic,
      'count': count,
      'mix': mix.toJson(),
      'pages': pages,
    });
    return data['id'] as String;
  }

  Future<List<QuizJob>> jobs() async {
    final data = await _call('/admin/quiz/jobs', {});
    return [for (final j in data['jobs'] as List) QuizJob(j as Map<String, dynamic>)];
  }

  /// Publishes the drafts among [ids] that passed the curator (picture
  /// questions need their picture first). Returns how many were published.
  Future<({int published, List<String> left})> approve(List<String> ids) async {
    final data = await _call('/admin/quiz/approve', {'ids': ids});
    return (published: _int(data['published']), left: [for (final id in data['left'] as List? ?? const []) '$id']);
  }

  /// Sends the picture of a "gambar" question (PNG).
  /// [letter]: on a labelled photo, the asked label's letter; the server
  /// puts it in place of "[X]" in the question.
  Future<void> uploadImage(String id, Uint8List png, {String? letter}) async {
    final session = store.session;
    if (session == null) throw AuthException('login', 'Silakan masuk lagi.');
    final http.Response response;
    try {
      response = await client
          .put(
            _base.resolve('/admin/quiz/image/${Uri.encodeComponent(id)}${letter == null ? '' : '?letter=$letter'}'),
            headers: {'content-type': 'image/png', sessionHeader: session.token},
            body: png,
          )
          .timeout(const Duration(seconds: 60));
    } on Exception {
      throw AuthException('network', 'Koneksi terputus');
    }
    if (response.statusCode != 200) {
      throw AuthException('server', 'Gambar soal gagal dikirim (kode ${response.statusCode}).');
    }
    _images[id] = png;
    _versions[id] = imageVersion(id) + 1;
  }

  static final _images = <String, Uint8List>{};
  static final _versions = <String, int>{};

  /// Goes up each time this phone sends [questionId] a new picture, so a
  /// picture on screen knows to show the new one.
  static int imageVersion(String questionId) => _versions[questionId] ?? 0;

  /// The picture of a "gambar" question, kept in memory once loaded.
  Future<Uint8List> image(String questionId) async {
    final known = _images[questionId];
    if (known != null) return known;
    final session = store.session;
    if (session == null) throw AuthException('login', 'Silakan masuk lagi.');
    final http.Response response;
    try {
      response = await client
          .get(_base.resolve('/quiz/image/${Uri.encodeComponent(questionId)}'), headers: {sessionHeader: session.token})
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw AuthException('network', 'Koneksi terputus');
    }
    if (response.statusCode != 200) throw AuthException('server', 'Gambar soal tidak ada.');
    if (_images.length > 30) _images.clear();
    return _images[questionId] = response.bodyBytes;
  }

  Future<List<AdminQuestion>> questions(String status) async {
    final data = await _call('/admin/quiz/questions', {'status': status});
    return [for (final q in data['questions'] as List) AdminQuestion(q as Map<String, dynamic>)];
  }

  /// setujui, ubah, tolak or tarik; [edit] saves changed fields first.
  Future<void> decide(String id, String action, {Map<String, dynamic>? edit}) =>
      _call('/admin/quiz/question/${Uri.encodeComponent(id)}', {'action': action, 'question': ?edit});

  Future<List<QuizReport>> reports() async {
    final data = await _call('/admin/quiz/reports', {});
    return [for (final r in data['reports'] as List) QuizReport(r as Map<String, dynamic>)];
  }
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// Topics, as the server stores them, with their names on screen.
const quizTopics = {
  'struktur': 'Structure and function',
  'torsi': 'Torsi',
  'kapasitas': 'Kapasitas oli & cairan',
  'standar': 'Nilai standar & tekanan',
  'fault': 'Fault code & troubleshooting',
  'servis': 'Perawatan berkala',
  'sistem': 'Sistem',
};

class QuizHome {
  QuizHome(Map<String, dynamic> j)
      : daily = j['daily'] as String? ?? 'belum',
        sessionId = j['session_id'] as String?,
        streak = _int(j['streak']),
        bestStreak = _int(j['best_streak']),
        xpWeek = _int(j['xp_week']),
        xpTotal = _int(j['xp_total']),
        rankWeek = _int(j['rank_week']),
        avatar = _int(j['avatar']),
        questions = _int(j['questions']),
        mastered = _int(j['mastered']),
        lastDaily = j['last_daily'] as String?,
        day = j['day'] as String? ?? '',
        freezeWeek = j['freeze_week'] as String?;

  /// belum, lanjutkan or selesai.
  final String daily;
  final String? sessionId;
  final int streak;
  final int bestStreak;
  final int xpWeek;
  final int xpTotal;
  final int rankWeek;
  final int avatar;

  /// Published questions this mechanic can get.
  final int questions;

  /// Questions at level 4 or more.
  final int mastered;
  final String? lastDaily;

  /// Today's quiz day ("2026-11-06", starts 04.00).
  final String day;
  final String? freezeWeek;

  bool get done => daily == 'selesai';
}

class QuizQuestion {
  QuizQuestion(Map<String, dynamic> j)
      : id = j['id'] as String,
        unit = j['unit'] as String?,
        topic = j['topic'] as String? ?? '',
        type = j['type'] as String? ?? 'pg',
        prompt = j['prompt'] as String? ?? '',
        choices = [for (final c in j['choices'] as List? ?? const []) '$c'],
        answer = _int(j['answer']),
        explain = cleanExplain(j['explain'] as String? ?? ''),
        manualId = j['manual_id'] as String? ?? '',
        page = _int(j['page']),
        image = j['image'] as String?,
        review = j['review'] == true,
        level = (j['level'] as num?)?.toInt();

  final String id;
  final String? unit;
  final String topic;
  final String type;
  final String prompt;
  final List<String> choices;
  final int answer;
  final String explain;

  /// The manual's key on the phone ("PC210-10/sm") and page.
  final String manualId;
  final int page;

  /// A "gambar" question's picture (its key on the server), or null.
  final String? image;

  /// Asked again (was wrong, or its date has come).
  final bool review;
  final int? level;

  String get topicName => quizTopics[topic] ?? topic;

  /// What a picture question's picture is about (see [quizPictureTarget]).
  String? get pictureTarget => quizPictureTarget(prompt, choices, answer);
}

class QuizSession {
  QuizSession(Map<String, dynamic> j)
      : id = j['id'] as String,
        unit = j['unit'] as String?,
        questions = [for (final q in j['questions'] as List) QuizQuestion(q as Map<String, dynamic>)],
        answered = {
          for (final a in j['answered'] as List? ?? const [])
            (a as Map)['question_id'] as String: (chosen: _int(a['chosen']), correct: a['correct'] == true),
        };

  final String id;
  final String? unit;
  final List<QuizQuestion> questions;

  /// First answers already sent (a set continued after leaving it).
  final Map<String, ({int chosen, bool correct})> answered;
}

class QuizAnswer {
  QuizAnswer({required this.sessionId, required this.questionId, required this.chosen, required this.ms})
      : id = '${DateTime.now().microsecondsSinceEpoch}-$questionId',
        at = DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String sessionId;
  final String questionId;
  final int chosen;
  final int ms;
  final int at;

  Map<String, dynamic> toJson() =>
      {'id': id, 'session_id': sessionId, 'question_id': questionId, 'chosen': chosen, 'ms': ms, 'at': at};
}

class AnswerResult {
  AnswerResult(Map<String, dynamic> j)
      : correct = j['correct'] == true,
        xp = _int(j['xp']),
        level = _int(j['level']),
        nextDays = _int(j['next_days']);

  final bool correct;
  final int xp;
  final int level;
  final int nextDays;
}

class FinishResult {
  FinishResult(Map<String, dynamic> j)
      : score = _int(j['score']),
        total = _int(j['total']),
        xp = _int(j['xp_session']),
        streak = _int(j['streak']),
        freezeUsed = j['freeze_used'] == true,
        rank = _int(j['rank']);

  final int score;
  final int total;
  final int xp;
  final int streak;
  final bool freezeUsed;
  final int rank;
}

class BoardRow {
  BoardRow(Map<String, dynamic> j)
      : rank = _int(j['rank']),
        nrp = j['nrp'] as String? ?? '',
        name = j['name'] as String? ?? '',
        section = j['section'] as String? ?? '',
        avatar = _int(j['avatar']),
        xp = _int(j['xp']),
        change = _int(j['change']),
        streak = _int(j['streak']),
        me = j['me'] == true;

  final int rank;
  final String nrp;
  final String name;
  final String section;
  final int avatar;
  final int xp;

  /// Places up (+) or down (-) since the night before.
  final int change;

  /// Streak still standing today (0 when broken).
  final int streak;
  final bool me;
}

class Board {
  Board(Map<String, dynamic> j)
      : period = j['period'] as String? ?? '',
        rows = [for (final r in j['rows'] as List? ?? const []) BoardRow(r as Map<String, dynamic>)],
        me = j['me'] == null ? null : BoardRow(j['me'] as Map<String, dynamic>),
        count = _int(j['count']);

  final String period;

  /// Mechanics with XP on this board.
  final int count;
  final List<BoardRow> rows;
  final BoardRow? me;
}

class QuizUnit {
  QuizUnit(Map<String, dynamic> j)
      : unit = j['unit'] as String,
        total = _int(j['total']),
        seen = _int(j['seen']),
        mastered = _int(j['mastered']);

  final String unit;
  final int total;
  final int seen;
  final int mastered;
}

class AdminQuestion {
  AdminQuestion(this.json) : question = QuizQuestion(json);

  final Map<String, dynamic> json;
  final QuizQuestion question;

  String get section => json['section'] as String? ?? '';
  String get status => json['status'] as String? ?? '';
  String get source => json['source'] as String? ?? '';
  String? get checkNote => json['check_note'] as String?;
  int get reports => _int(json['reports']);
  int get answered => _int(json['answered']);
  int? get wrongPct => (json['wrong_pct'] as num?)?.toInt();
  String? get jobId => json['job_id'] as String?;

  /// 1..10 from the curator; null when it did not check the question.
  int? get curatorScore => (json['curator_score'] as num?)?.toInt();
  String? get curatorNote => json['curator_note'] as String?;

  /// Curator 7+ and the numbers found on the page: "Setujui semua" takes it.
  bool get passed => json['passed'] == true;
  bool get needsPicture => question.type == 'gambar' && question.image == null;
}

class GenerateResult {
  GenerateResult(Map<String, dynamic> j)
      : saved = _int(j['saved']),
        pictures = [for (final id in j['pictures'] as List? ?? const []) '$id'],
        callouts = {for (final e in (j['callouts'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
        dropped = _int(j['dropped']);

  final int saved;

  /// Saved "gambar" questions, which still need their picture.
  final List<String> pictures;

  /// The number each picture question asks about, by question id.
  final Map<String, String> callouts;

  /// Thrown away by the curator.
  final int dropped;
}

/// The share of each question type in "Buat draf kuis", in percent.
class QuizMix {
  const QuizMix({this.pg = 60, this.bs = 20, this.gambar = 20});

  final int pg;
  final int bs;
  final int gambar;

  Map<String, int> toJson() => {'pg': pg, 'bs': bs, 'gambar': gambar};

  /// How many of [count] questions are of each type (like the server).
  ({int pg, int bs, int gambar}) split(int count) {
    final g = (count * gambar / 100).round();
    final b = (count * bs / 100).round();
    return (pg: count - g - b < 0 ? 0 : count - g - b, bs: b, gambar: g);
  }
}

class PlannedPage {
  PlannedPage(Map<String, dynamic> j)
      : page = _int(j['page']),
        kind = j['kind'] == 'gambar' ? 'gambar' : 'teks',
        topic = j['topic'] as String? ?? 'struktur';

  final int page;
  final String kind;
  final String topic;
}

class QuizJob {
  QuizJob(Map<String, dynamic> j)
      : id = j['id'] as String,
        unit = j['unit'] as String?,
        title = j['title'] as String? ?? '',
        count = _int(j['count']),
        status = j['status'] as String? ?? '',
        pages = _int(j['pages']),
        pagesDone = _int(j['pages_done']),
        passed = _int(j['passed']),
        flagged = _int(j['flagged']),
        dropped = _int(j['dropped']),
        error = j['error'] as String?,
        createdAt = DateTime.fromMillisecondsSinceEpoch(_int(j['created_at']));

  final String id;
  final String? unit;
  final String title;
  final int count;

  /// antri, jalan, selesai or gagal.
  final String status;
  final int pages;
  final int pagesDone;
  final int passed;
  final int flagged;
  final int dropped;
  final String? error;
  final DateTime createdAt;

  bool get running => status == 'antri' || status == 'jalan';
  int get kept => passed + flagged;
}

class QuizReport {
  QuizReport(Map<String, dynamic> j)
      : questionId = j['question_id'] as String,
        name = j['name'] as String? ?? '',
        note = j['note'] as String? ?? '',
        prompt = j['prompt'] as String? ?? '',
        unit = j['unit'] as String?,
        status = j['status'] as String? ?? '';

  final String questionId;
  final String name;
  final String note;
  final String prompt;
  final String? unit;
  final String status;
}

/// "Halaman menyatakan bahwa OLSS ..." -> "OLSS ...": an explanation starts
/// with the fact (older questions; the server cleans new ones the same way).
String cleanExplain(String text) {
  final out = text
      .trim()
      .replaceFirst(RegExp(r'^(menurut|berdasarkan)\s+(halaman|manual|teks)(\s+(ini|tersebut|sumber))?[,:]?\s+', caseSensitive: false), '')
      .replaceFirst(
        RegExp(r'^(halaman|manual|teks)(\s+(ini|tersebut|sumber))?\s+(menyatakan|menyebutkan|menjelaskan|mengatakan)(\s+bahwa)?[,:]?\s+',
            caseSensitive: false),
        '',
      );
  return out.isEmpty ? out : out[0].toUpperCase() + out.substring(1);
}
