import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/page_image.dart';
import 'package:mymanual/src/quiz.dart';
import 'package:mymanual/src/quiz_reminders.dart';
import 'package:mymanual/src/screens/quiz_admin_screen.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:mymanual/src/screens/quiz_hub_screen.dart';
import 'package:mymanual/src/screens/quiz_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/search.dart' show pageHeading;
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

Map<String, dynamic> homeJson({int questions = 30, String daily = 'belum', int streak = 3}) => {
      'daily': daily,
      'session_id': null,
      'streak': streak,
      'best_streak': 5,
      'xp_week': 120,
      'xp_total': 900,
      'rank_week': 2,
      'avatar': 3,
      'questions': questions,
      'mastered': 4,
      'last_daily': '2026-11-05',
      'day': '2026-11-06',
      'freeze_week': null,
    };

Map<String, dynamic> question(String id) => {
      'id': id,
      'unit': 'TEST1-1',
      'topic': 'hidrolik',
      'type': 'pg',
      'prompt': 'Soal $id: fungsi main relief valve?',
      'choices': ['Membatasi tekanan', 'Menambah debit', 'Mendinginkan oli', 'Menyaring oli'],
      'answer': 0,
      'explain': 'Relief valve membuka saat tekanan melewati setelan.',
      'manual_id': 'TEST1-1/sm',
      'page': 12,
    };

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('quiz');
    AppStore.retryDelays = const [];
    QuizApi.lastHome = null;
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('an answer without signal is kept and sent with the next call', () async {
    var up = false;
    final sent = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/quiz')) {
        if (!up) throw const SocketException('offline');
        if (request.url.path == '/quiz/answer') {
          sent.add((jsonDecode(request.body) as Map)['question_id'] as String);
          return http.Response(jsonEncode({'correct': true, 'xp': 10, 'level': 1, 'next_days': 1}), 200);
        }
        return http.Response(jsonEncode(homeJson()), 200);
      }
      return fixtureServer().send(http.Request(request.method, request.url)).then(http.Response.fromStream);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(), refreshNow: false);
    final api = QuizApi(store, client);

    final result = await api.answer(QuizAnswer(sessionId: 's1', questionId: 'q1', chosen: 0, ms: 5000));
    expect(result, isNull);
    expect(File('${root.path}/quiz_pending.json').existsSync(), isTrue);

    up = true;
    final home = await api.home();
    expect(sent, ['q1']);
    expect(home.questions, 30);
    expect(home.streak, 3);
    expect(QuizApi.lastHome, same(home));
    expect(File('${root.path}/quiz_pending.json').existsSync(), isFalse);
    store.dispose();
  });

  Future<AppStore> openStore(WidgetTester tester, http.Client client, {bool admin = false}) async {
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
      await store.signIn(testSession(admin: admin), refreshNow: false);
    });
    return store;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the Home card shows the streak and hides with no questions', (tester) async {
    var questions = 30;
    final client = MockClient((request) async => http.Response(jsonEncode(homeJson(questions: questions)), 200));
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: Scaffold(body: QuizHomeCard(key: const ValueKey(1), client: client))),
    ));
    await settle(tester);
    expect(find.text('Quiz harian').evaluate().isNotEmpty || find.text('Jaga streakmu').evaluate().isNotEmpty, isTrue);
    expect(find.text('3'), findsOneWidget);

    // No published question yet: a mechanic sees nothing.
    questions = 0;
    QuizApi.lastHome = null;
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: Scaffold(body: QuizHomeCard(key: const ValueKey(2), client: client))),
    ));
    await settle(tester);
    expect(find.byType(Text), findsNothing);
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a set: choose, Periksa, a wrong answer comes back, then the summary', (tester) async {
    final answers = <(String, int)>[];
    final client = MockClient((request) async {
      final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
      return switch (request.url.path) {
        '/quiz/session' => http.Response(
            jsonEncode({'id': 's1', 'unit': null, 'questions': [question('q1'), question('q2')], 'answered': []}),
            200,
          ),
        '/quiz/answer' => () {
            answers.add((body['question_id'] as String, body['chosen'] as int));
            final right = body['chosen'] == 0;
            return http.Response(jsonEncode({'correct': right, 'xp': right ? 10 : 2, 'level': right ? 1 : 0, 'next_days': 1}), 200);
          }(),
        '/quiz/finish' => http.Response(
            jsonEncode({'score': 1, 'total': 2, 'xp_session': 22, 'streak': 4, 'freeze_used': false, 'rank': 2}),
            200,
          ),
        _ => http.Response(jsonEncode(homeJson()), 200),
      };
    });
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizPlayScreen(client: client))));
    await settle(tester);

    expect(find.text('Soal q1: fungsi main relief valve?'), findsOneWidget);
    await tester.tap(find.text('Membatasi tekanan'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    expect(find.text('Benar'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);

    // q2 wrong: it comes back at the end.
    await tester.tap(find.text('Menambah debit'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    expect(find.text('Belum tepat'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);
    expect(find.text('Soal q2: fungsi main relief valve?'), findsOneWidget);
    await tester.tap(find.text('Membatasi tekanan'));
    await tester.pump();
    await tester.tap(find.text('Periksa'));
    await settle(tester);
    await tester.tap(find.text('Lanjut'));
    await settle(tester);

    expect(answers, [('q1', 0), ('q2', 1), ('q2', 0)]);
    expect(find.text('Selesai'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });

  test('a page without bookmarks is named by its title line', () {
    expect(pageHeading('12\nHYDRAULIC SYSTEM OVERVIEW\nMain pump supplies oil to...'), 'HYDRAULIC SYSTEM OVERVIEW');
    expect(pageHeading('Page 3 of 220\n© Komatsu 2020\nEngine cooling'), 'Engine cooling');
    expect(pageHeading('1\n2\n'), isNull);
  });

  test('an explanation starts with the fact', () {
    expect(cleanExplain('Halaman menyatakan bahwa OLSS mengurangi kerugian.'), 'OLSS mengurangi kerugian.');
    expect(cleanExplain('Menurut manual, relief valve membuka.'), 'Relief valve membuka.');
    expect(cleanExplain('Relief valve membatasi tekanan.'), 'Relief valve membatasi tekanan.');
  });

  test('a quiz picture covers words but keeps callout numbers', () {
    const text = '3. Main relief valve\n12';
    final rects = [for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 100, i * 10.0 + 9, 90)];
    final boxes = wordsToCover(text, rects);
    // "Main", "relief", "valve"; not "3." and not "12".
    expect(boxes.length, 3);
    expect(boxes.first.left, 30);
    expect(boxes.first.right, 69);
  });

  testWidgets('Draf: job progress, curator score, approve all that passed', (tester) async {
    final approved = <String>[];
    Map<String, dynamic> draft(String id, {bool passed = true, int score = 8}) => {
          ...question(id),
          'section': 'TRACK',
          'status': 'draf',
          'source': 'ai',
          'check_note': 'Angka di jawaban ada di halaman sumber.',
          'reports': 0,
          'answered': 0,
          'curator_score': score,
          'curator_note': 'Jelas.',
          'passed': passed,
        };
    final client = MockClient((request) async {
      final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
      return switch (request.url.path) {
        '/admin/quiz/questions' => http.Response(
            jsonEncode({
              'questions': body['status'] == 'draf' ? [draft('q1'), draft('q2'), draft('q3', passed: false, score: 5)] : [],
            }),
            200),
        '/admin/quiz/jobs' => http.Response(
            jsonEncode({
              'jobs': [
                {'id': 'j1', 'unit': 'TEST1-1', 'title': 'Shop Manual', 'count': 30, 'status': 'jalan', 'pages': 10, 'pages_done': 4, 'passed': 9, 'flagged': 2, 'dropped': 1, 'created_at': DateTime.now().millisecondsSinceEpoch},
              ],
            }),
            200),
        '/admin/quiz/approve' => () {
            approved.addAll([for (final id in body['ids'] as List) '$id']);
            return http.Response(jsonEncode({'ok': true, 'published': 2, 'left': []}), 200);
          }(),
        _ => http.Response(jsonEncode({'reports': []}), 200),
      };
    });
    final store = await openStore(tester, client, admin: true);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizAdminScreen(client: client))));
    await settle(tester);
    expect(find.text('Sedang dibuat'), findsOneWidget);
    expect(find.text('Halaman 4 dari 10 · 11 soal jadi'), findsOneWidget);
    expect(find.text('Kurator 8/10'), findsWidgets);
    expect(find.text('2 soal lolos kurator'), findsOneWidget);
    await tester.tap(find.text('Setujui 2'));
    await settle(tester);
    await tester.tap(find.text('Setujui').last);
    await settle(tester);
    expect(approved, ['q1', 'q2']);
    expect(find.text('2 soal diterbitkan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a picture question shows its picture from the server', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.path);
      return switch (request.url.path) {
        '/quiz/session' => http.Response(
            jsonEncode({
              'id': 's1',
              'questions': [
                {...question('g1'), 'type': 'gambar', 'prompt': 'Komponen nomor 3 adalah?', 'image': 'quiz/img/g1.png'},
              ],
              'answered': [],
            }),
            200),
        '/quiz/image/g1' => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
        _ => http.Response(jsonEncode(homeJson()), 200),
      };
    });
    final store = await openStore(tester, client);
    await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizPlayScreen(client: client))));
    await settle(tester);
    expect(find.text('Komponen nomor 3 adalah?'), findsOneWidget);
    expect(asked, contains('/quiz/image/g1'));
    expect(find.text('Ketuk untuk perbesar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  group('quiz reminders', () {
    QuizHome h({String daily = 'belum', int streak = 3, int questions = 30}) =>
        QuizHome(homeJson(daily: daily, streak: streak, questions: questions));
    final morning = DateTime(2026, 11, 6, 6, 0);

    test('not done yet: today 07.00 with the streak, 20.00 warning, then each day at 07.00', () {
      final plan = planReminders(morning, const ReminderSettings(), h());
      expect(plan.first.at, DateTime(2026, 11, 6, 7));
      expect(plan.first.body, '10 soal, sekitar 4 menit. Streak 3 hari.');
      final warnings = plan.where((r) => r.title.startsWith('Streak')).toList();
      expect(warnings.single.at, DateTime(2026, 11, 6, 20));
      expect(warnings.single.title, 'Streak 3 hari belum aman');
      final daily = plan.where((r) => r.title == 'Quiz harian menunggu').toList();
      expect(daily.length, 7);
      // Tomorrow the streak is only safe if today's quiz gets done.
      expect(daily[1].body, '10 soal, sekitar 4 menit.');
    });

    test('done today: nothing today, tomorrow keeps the streak', () {
      final plan = planReminders(DateTime(2026, 11, 6, 9), const ReminderSettings(), h(daily: 'selesai'));
      expect(plan.every((r) => r.at.isAfter(DateTime(2026, 11, 7, 4))), isTrue);
      expect(plan.first.at, DateTime(2026, 11, 7, 7));
      expect(plan.first.body, endsWith('Streak 3 hari.'));
      expect(plan.where((r) => r.title.startsWith('Streak')).single.at, DateTime(2026, 11, 7, 20));
    });

    test('settings: off, another time, no streak, no questions', () {
      expect(planReminders(morning, const ReminderSettings(daily: false, streak: false), h()), isEmpty);
      expect(planReminders(morning, const ReminderSettings(), h(questions: 0)), isEmpty);
      final noStreak = planReminders(morning, const ReminderSettings(hour: 5, minute: 30), h(streak: 0));
      expect(noStreak.any((r) => r.title.startsWith('Streak')), isFalse);
      // 05.30 today has passed: the first one is tomorrow.
      expect(noStreak.first.at, DateTime(2026, 11, 7, 5, 30));
      expect(quizDayOf(DateTime(2026, 11, 7, 3, 59)), '2026-11-06');
    });

    testWidgets('the Quiz page saves the reminder time', (tester) async {
      final client = MockClient((request) async => request.url.path == '/quiz/home'
          ? http.Response(jsonEncode(homeJson()), 200)
          : http.Response(jsonEncode({'rows': [], 'me': null}), 200));
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      final store = await openStore(tester, client);
      await tester.pumpWidget(StoreScope(store: store, child: MaterialApp(home: QuizHubScreen(client: client))));
      await settle(tester);
      expect(find.text('Pengingat harian'), findsOneWidget);
      await tester.ensureVisible(find.text('07.00'));
      await tester.pump();
      await tester.tap(find.text('07.00'));
      await settle(tester);
      expect(find.text('Jam pengingat'), findsOneWidget);
      await tester.tap(find.text('12.00'));
      await settle(tester);
      expect(QuizReminders.load(root).hour, 12);
      expect(find.text('12.00'), findsOneWidget);
      await tester.tap(find.text('Pengingat harian'));
      await settle(tester);
      expect(QuizReminders.load(root).daily, isFalse);
      expect(find.text('12.00'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => store.dispose());
    });
  });
}
