import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai.dart' show aiUrl;
import 'auth.dart';
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

  /// nyel AI writes draft questions from one manual page.
  Future<({int saved, List<String> skipped})> generate({
    required String section,
    required String unit,
    required String topic,
    required String manualId,
    required int page,
    required String text,
    required int count,
  }) async {
    final data = await _call('/admin/quiz/generate', {
      'section': section,
      'unit': unit,
      'topic': topic,
      'manual_id': manualId,
      'page': page,
      'text': text,
      'count': count,
    });
    return (saved: (data['saved'] as num).toInt(), skipped: [for (final s in data['skipped'] as List) '$s']);
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
        explain = j['explain'] as String? ?? '',
        manualId = j['manual_id'] as String? ?? '',
        page = _int(j['page']),
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

  /// Asked again (was wrong, or its date has come).
  final bool review;
  final int? level;

  String get topicName => quizTopics[topic] ?? topic;
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
        me = j['me'] == true;

  final int rank;
  final String nrp;
  final String name;
  final String section;
  final int avatar;
  final int xp;

  /// Places up (+) or down (-) since the night before.
  final int change;
  final bool me;
}

class Board {
  Board(Map<String, dynamic> j)
      : period = j['period'] as String? ?? '',
        rows = [for (final r in j['rows'] as List? ?? const []) BoardRow(r as Map<String, dynamic>)],
        me = j['me'] == null ? null : BoardRow(j['me'] as Map<String, dynamic>);

  final String period;
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
