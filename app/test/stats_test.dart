import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/auth.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/stats_screen.dart';
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
        {'section': 'TRACK', 'active': 30, 'total': 40},
      ],
      'people': [
        {'nrp': '1', 'name': 'Ali Akbar', 'sections': ['TRACK'], 'last': DateTime.now().millisecondsSinceEpoch, 'manuals': 12, 'ai': 3, 'searches': 4},
      ],
      'inactive': [
        {'nrp': '2', 'name': 'Budi', 'sections': ['WHEEL'], 'never': true, 'last': 0},
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
    sent.clear();
    await again.usage.send();
    expect(sent, isEmpty);
    store.dispose();
    again.dispose();
  });

  test('nothing is kept without a login', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    store.usage.searched('seal', 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(File('${root.path}/usage.json').existsSync(), isFalse);
    store.dispose();
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
    expect(find.text('1 belum aktif'), findsOneWidget);

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
}
