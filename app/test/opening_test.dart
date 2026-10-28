import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/splash_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

Future<http.Response> _files(http.Request request) => fixtureServer()
    .send(http.Request(request.method, request.url)..headers.addAll(request.headers))
    .then(http.Response.fromStream);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('opening');
    AppStore.retryDelays = const [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('the opening animation plays before login and after a day away, not on a quick return', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    final now = DateTime(2026, 10, 28, 9);
    expect(store.wantsSplash(now), isTrue, reason: 'nobody logged in');
    await store.signIn(testSession(), refreshNow: false);
    store.lastActive = now.subtract(const Duration(minutes: 40));
    expect(store.wantsSplash(now), isFalse);
    store.lastActive = now.subtract(const Duration(hours: 23));
    expect(store.wantsSplash(now), isFalse);
    store.lastActive = now.subtract(const Duration(days: 1));
    expect(store.wantsSplash(now), isTrue);

    // Remembered across restarts, with the introduction being seen.
    store.markActive();
    await store.finishIntro();
    store.dispose();
    final again = await AppStore.open(root: root, client: fixtureServer());
    expect(again.lastActive, isNotNull);
    expect(again.wantsSplash(DateTime.now()), isFalse);
    expect(again.introSeen, isTrue);
    again.dispose();
  });

  testWidgets('splash, login, introduction once, then Home', (tester) async {
    late AppStore store;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/login') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['pin'] != '1234') {
          return http.Response(jsonEncode({'error': 'pin', 'message': 'PIN salah.'}), 403);
        }
        return http.Response(jsonEncode({...testSession().toJson(), 'status': 'ok'}), 200);
      }
      return _files(request);
    });
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
    });
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true, splash: true, intro: true));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(SplashScreen.duration);
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-nrp')), '21045678');
    await tester.runAsync(() async {
      await tester.enterText(find.byKey(const Key('login-pin')), '9999');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('PIN salah.'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.enterText(find.byKey(const Key('login-pin')), '1234');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    // The tick, then the header grows into the introduction.
    for (var i = 0; i < 30 && !store.loggedIn; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(store.loggedIn, isTrue);
    expect(find.text('Semua manual, satu genggaman'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('intro-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Nilai standar tanpa membuka ribuan halaman'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('intro-next')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.introSeen, isTrue);
    expect(find.text('Dokumen teknis'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('a quick return opens Home straight away', (tester) async {
    late AppStore store;
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.signIn(testSession(), refreshNow: false);
      // Saves run in order, so this also waits for markActive's save.
      store.markActive();
      await store.finishIntro();
    });
    final splash = store.wantsSplash(DateTime.now());
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true, splash: splash, intro: true));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Dokumen teknis'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('the opening animation waits for the notification permission question', (tester) async {
    final ready = Completer<void>();
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(ready: ready.future, onDone: () => done = true),
      ),
    );
    await tester.pump(SplashScreen.duration * 2);
    expect(done, isFalse);
    ready.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(SplashScreen.duration);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
  });
}
