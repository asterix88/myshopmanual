import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/auth.dart';
import 'package:mymanual/src/screens/search_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/stats_screen.dart';
import 'package:mymanual/src/stats.dart';
import 'package:mymanual/src/store.dart';
import 'package:mymanual/src/theme.dart';

import 'store_test.dart' show fixtureServer, testSession;

/// What the server's /admin/stats answers (ai-worker/src/stats.ts).
Map<String, dynamic> overviewJson() => {
      'users': 52,
      'active': 38,
      'opens': 412,
      'ai': 167,
      'section_list': ['TRACK', 'WHEEL', 'SUPPORT'],
      'manuals': [
        {'file': 'TEST1-1/sm', 'unit': 'TEST1-1', 'title': 'Shop Manual', 'n': 64, 'people': 21, 'shared': false},
        {'file': 'PANDUAN MLU/mlu', 'unit': 'PANDUAN MLU', 'title': 'Panduan MLU', 'n': 12, 'people': 9, 'shared': true},
      ],
      'units': [
        {'unit': 'TEST1-1', 'n': 64},
      ],
      'topics': [
        {'name': 'Relief valve', 'n': 11},
      ],
      'ratings': {'good': 58, 'bad': 6},
      'questions': [
        {'id': 7, 'at': DateTime.now().millisecondsSinceEpoch, 'nrp': '1', 'name': 'Ali', 'sections': ['TRACK'], 'unit': '', 'q': 'Berapa tekanan main relief?'},
      ],
      'searches': [
        {'q': 'relief valve', 'n': 9, 'people': 4},
      ],
      'missing': [
        {'q': 'xyz seal', 'n': 3, 'people': 2},
      ],
      'per_section': [
        {'section': 'TRACK', 'active': 30, 'total': 40, 'has_manual': true},
        {'section': 'SUPPORT', 'active': 0, 'total': 12, 'has_manual': false},
      ],
      'trend': {'active': 12, 'opens': -8, 'ai': null},
      'people': [
        {'nrp': '1', 'name': 'Ali Akbar', 'sections': ['TRACK'], 'last': DateTime.now().millisecondsSinceEpoch, 'manuals': 12, 'ai': 3, 'searches': 4},
      ],
      'inactive': [
        {'nrp': '2', 'name': 'Budi', 'sections': ['WHEEL'], 'never': true, 'last': 0},
        {'nrp': '3', 'name': 'Candra', 'sections': ['TRACK'], 'never': false, 'old_app': true, 'last': DateTime.now().millisecondsSinceEpoch},
      ],
    };

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('stats');
    AppStore.retryDelays = const [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('what the user does is kept and sent once the server answers', () async {
    var up = false;
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path == '/stats') {
        if (!up) throw const SocketException('offline');
        expect(request.headers[sessionHeader], 't');
        sent.addAll([for (final e in (jsonDecode(request.body) as Map)['events'] as List) (e as Map).cast()]);
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return fixtureServer().send(http.Request(request.method, request.url)).then(http.Response.fromStream);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(), refreshNow: false);
    final file = store.catalog.files.isEmpty ? null : store.catalog.files.first;
    await store.refresh();
    final f = file ?? store.catalog.files.first;

    store.usage.opened(f);
    store.usage.searched('relief valve', 3);
    store.usage.searched('Relief Valve', 3); // the same search again: counted once
    store.usage.asked(question: 'Apa SL1?', answer: 'Spring loaded', sources: const [], queries: const ['SL1']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await store.usage.send();
    expect(sent, isEmpty);

    // Still there after the app starts again.
    final again = await AppStore.open(root: root, client: client);
    up = true;
    await again.usage.send();
    expect(sent.map((e) => e['kind']), ['open', 'search', 'ai']);
    expect(sent.first['file'], f.key);
    expect(sent.first['sec'], 'TRACK');
    sent.clear();
    await again.usage.send();
    expect(sent, isEmpty);

    // Logging out sends what is left first.
    again.usage.searched('seal kit', 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await again.signOut();
    expect(sent.map((e) => e['q']), ['seal kit']);
    store.dispose();
    again.dispose();
  });

  test('the phone tells the server its app version', () {
    final json = const DeviceInfo('id', 'HP').toJson();
    expect(json['model'], 'HP');
    // Local and test builds have none; the APK workflow sets it.
    expect(json.containsKey('app'), isFalse);
  });

  test('nothing is kept without a login', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    store.usage.searched('seal', 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(File('${root.path}/usage.json').existsSync(), isFalse);
    store.dispose();
  });

  test('the belum aktif list as text for WhatsApp', () {
    final rows = [
      InactiveRow({'nrp': '2', 'name': 'Budi', 'sections': ['WHEEL'], 'never': true, 'last': 0}),
      InactiveRow({'nrp': '3', 'name': 'Candra', 'sections': ['TRACK'], 'old_app': true, 'last': DateTime.now().millisecondsSinceEpoch}),
    ];
    final text = inactiveText(rows, ['TRACK', 'WHEEL'], {'TRACK': [rows[1]], 'WHEEL': [rows[0]]});
    expect(text, 'Belum aktif di MyManual (2 orang)\n\n*TRACK* (1)\n1. Candra (3) - terakhir hari ini, app lama\n\n*WHEEL* (1)\n1. Budi (2) - belum pernah login');
    expect(monthLabel(DateTime(2026, 10)), 'Oktober 2026');
  });

  testWidgets('a search counts once it is finished, not the words on the way', (tester) async {
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.signIn(testSession(), refreshNow: false);
    });
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: SearchScreen())));
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
    }

    Future<List<String>> queued() async {
      // The log is written with real file calls, which go on between pumps.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      final file = File('${root.path}/usage.json');
      final text = file.existsSync() ? file.readAsStringSync() : '[]';
      return [for (final e in jsonDecode(text) as List) (e as Map)['q'] as String];
    }

    for (final typed in ['re', 'reli', 'relief valve']) {
      await tester.enterText(find.byType(TextField), typed);
      await settle();
    }
    expect(await queued(), isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle();
    expect(await queued(), ['relief valve']);

    // Another search replaces it: the first one counts.
    await tester.enterText(find.byType(TextField), 'seal');
    await settle();
    await tester.enterText(find.byType(TextField), 'track roller');
    await settle();
    expect(await queued(), ['relief valve', 'seal']);

    // Leaving Cari counts the last one.
    await tester.pumpWidget(const SizedBox());
    expect(await queued(), ['relief valve', 'seal', 'track roller']);
    await tester.runAsync(() async => store.dispose());
  });

  test('time labels', () {
    final now = DateTime(2026, 10, 30, 12);
    expect(whenLabel(DateTime(2026, 10, 30, 9, 5), now: now), '09.05');
    expect(whenLabel(DateTime(2026, 10, 29, 23), now: now), 'kemarin');
    expect(whenLabel(DateTime(2026, 10, 25), now: now), '5 hari lalu');
    expect(daysAgo(DateTime(2026, 10, 30, 1), now: now), 'hari ini');
    expect(initials('Ali Akbar Siregar'), 'AA');
    expect(initials('Budi'), 'BU');
  });

  testWidgets('the tabs swipe; filters and numbers stay; offline keeps the last numbers', (tester) async {
    var online = true;
    final asked = <String>[];
    final client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      asked.add('${request.url.path} ${request.body}');
      if (request.url.path == '/admin/stats') return http.Response(jsonEncode(overviewJson()), 200);
      if (request.url.path == '/admin/stats/search') {
        return http.Response(
          jsonEncode({
            'q': 'xyz seal', 'n': 3, 'people': 2,
            'who': [
              {'nrp': '1', 'name': 'Ali', 'sections': ['TRACK'], 'at': DateTime.now().millisecondsSinceEpoch},
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/stats/handled') return http.Response(jsonEncode({'ok': true}), 200);
      return http.Response('{}', 404);
    });
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.signIn(testSession(admin: true), refreshNow: false);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(theme: buildTheme(dark: false), home: StatsScreen(client: client)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('38 / 52'), findsOneWidget);
    expect(find.text('▲ 12%'), findsOneWidget);
    expect(find.text('▼ 8%'), findsOneWidget);
    expect(find.textContaining('1 kata tidak ketemu · 6 jawaban dinilai salah', findRichText: true), findsOneWidget);
    expect(find.text('Shop Manual'), findsOneWidget);
    expect(find.text('Semua section · 9 orang'), findsOneWidget);

    // Swipe to nyel AI: the numbers stay.
    await tester.drag(find.text('Shop Manual'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Relief valve', findRichText: true), findsOneWidget);
    expect(find.text('58 membantu'), findsOneWidget);
    expect(find.text('38 / 52'), findsOneWidget);

    // A tap on a tab goes there too.
    await tester.tap(find.text('Cari'));
    await tester.pumpAndSettle();
    expect(find.text('xyz seal'), findsOneWidget);
    await tester.tap(find.text('xyz seal'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('0 hasil di semua manual'), findsOneWidget);
    await tester.tap(find.text('Tandai sudah ditangani'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(asked.where((a) => a.startsWith('/admin/stats/handled')).single, contains('xyz seal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pengguna'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Akbar'), findsOneWidget);
    expect(find.text('belum ada manual'), findsOneWidget);
    expect(find.text('2 belum aktif'), findsOneWidget);
    await tester.tap(find.text('2 belum aktif'));
    await tester.pumpAndSettle();
    expect(find.text('app lama'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.tap(find.byTooltip('Salin daftar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(copied, contains('Candra (3)'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // "Perlu tindakan" leads to the searches that found nothing.
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('kata tidak ketemu', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('xyz seal'), findsOneWidget);
    await tester.tap(find.text('Pengguna'));
    await tester.pumpAndSettle();

    // A week: asked with period 7.
    await tester.tap(find.text('7 hari'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(asked.last, contains('"period":"7"'));

    // Offline, another section: the cached numbers of that filter are not
    // there, so the period's last numbers are not mixed in; back on "Semua"
    // they show with the offline bar.
    online = false;
    await tester.tap(find.text('WHEEL'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Koneksi terputus'), findsOneWidget);
    await tester.tap(find.text('Semua'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Koneksi terputus'), findsOneWidget);
    expect(find.text('38 / 52'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('the Quiz tab: weak topics, a hard question with its picks, never played', (tester) async {
    final asked = <String>[];
    final hardRow = {
      'id': 'q1', 'section': 'TRACK', 'unit': 'PC210-10M0', 'topic': 'standar', 'type': 'pg',
      'prompt': 'Setelan main relief PC210-10 saat power max?',
      'choices': ['37.3 MPa', '34.8 MPa', '31.4 MPa', '29.4 MPa'], 'answer': 0, 'explain': 'Main relief 37.3 MPa.',
      'manual_id': 'TEST1-1/sm', 'page': 12, 'image': null, 'status': 'terbit', 'source': 'admin',
      'check_note': null, 'created_by': 'ADM', 'reviewed_by': null, 'updated_at': 0, 'reports': 0, 'answered': 14,
      'job_id': null, 'curator_score': null, 'curator_note': null, 'passed': false, 'wrong_pct': 79,
    };
    final client = MockClient((request) async {
      asked.add('${request.url.path} ${request.body}');
      return switch (request.url.path) {
        '/admin/stats' => http.Response(jsonEncode(overviewJson()), 200),
        '/admin/stats/quiz' => http.Response(
            jsonEncode({
              'players': 31, 'users': 52, 'correct': 74, 'trend_correct': 6, 'sets': 186,
              'per_section': [
                {'section': 'TRACK', 'players': 26, 'total': 40},
              ],
              'topics': [
                {'topic': 'standar', 'answers': 88, 'correct': 52},
              ],
              'hard': [
                {'id': 'q1', 'prompt': hardRow['prompt'], 'unit': 'PC210-10M0', 'topic': 'standar', 'answers': 14, 'correct': 21},
              ],
              'top': [
                {'nrp': '1', 'name': 'Ali Akbar', 'section': 'TRACK', 'xp': 640, 'streak': 12},
              ],
              'never': [
                {'nrp': 'N1', 'name': 'Mekanik Satu', 'sections': ['SUPPORT'], 'never': true, 'last': 0},
              ],
            }),
            200),
        '/admin/stats/quiz/question' => http.Response(jsonEncode({...hardRow, 'picks': [3, 9, 1, 1], 'answers': 14}), 200),
        _ => http.Response('{}', 404),
      };
    });
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.signIn(testSession(admin: true), refreshNow: false);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(theme: buildTheme(dark: false), home: StatsScreen(client: client)),
    ));
    Future<void> wait() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await wait();
    final tab = find.descendant(of: find.byType(TabBar), matching: find.text('Quiz'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await wait();
    expect(asked.where((a) => a.startsWith('/admin/stats/quiz ')), isNotEmpty);
    expect(find.text('52%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ali Akbar'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Ali Akbar'), findsOneWidget);
    await tester.ensureVisible(find.text('Setelan main relief PC210-10 saat power max?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setelan main relief PC210-10 saat power max?'));
    await wait();
    expect(asked.last, contains('"id":"q1"'));
    expect(find.text('14 jawaban · 21% benar'), findsOneWidget);
    expect(find.text('Tarik soal'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => store.dispose());
  });
}
