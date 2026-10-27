import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/auth.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

/// The fixture manuals server, for a request a MockClient already received.
Future<http.Response> _files(http.Request request) => fixtureServer()
    .send(http.Request(request.method, request.url)..headers.addAll(request.headers))
    .then(http.Response.fromStream);

Map<String, dynamic> _sessionJson(Session s) => {...s.toJson(), 'status': 'ok'};

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('auth');
    AppStore.retryDelays = const [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('installs using the public bucket address move to the login server', () async {
    File('${root.path}/state.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'server': 'https://mymanual.my.id'}));
    final store = await AppStore.open(root: root, client: fixtureServer());
    expect(store.serverUrl, 'https://files.mymanual.my.id');
    store.dispose();
  });

  test('the session goes only to MyManual servers', () async {
    final seen = <String, String?>{};
    final store = await AppStore.open(
      root: root,
      client: MockClient((request) async {
        seen[request.url.host] = request.headers[sessionHeader];
        if (request.url.host.contains('supabase')) return http.Response(jsonEncode({'parts': []}), 200);
        return _files(request);
      }),
    );
    await store.signIn(testSession(token: 'abc'));
    await store.cetok.open();
    expect(seen['files.mymanual.my.id'], 'abc');
    expect(seen.entries.where((e) => e.key.contains('supabase')).single.value, isNull);
    store.dispose();
  });

  test('Cetok shows every location when the admin chose so on the server', () async {
    var all = true;
    final hidden = <Object?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/app/config') return http.Response(jsonEncode({'cetok_all': all}), 200);
      if (request.url.host.contains('supabase')) {
        hidden.add((jsonDecode(request.body) as Map)['p_show_hidden']);
        return http.Response(jsonEncode({'parts': []}), 200);
      }
      return _files(request);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(), refreshNow: false);
    await store.cetok.open();
    all = false;
    await store.cetok.refresh();
    expect(hidden, [true, false]);
    store.dispose();
  });

  test('without signal Cetok keeps the last choice', () async {
    var online = true;
    final hidden = <Object?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/app/config') {
        if (!online) throw const SocketException('offline');
        return http.Response(jsonEncode({'cetok_all': true}), 200);
      }
      if (request.url.host.contains('supabase')) {
        hidden.add((jsonDecode(request.body) as Map)['p_show_hidden']);
        return http.Response(jsonEncode({'parts': []}), 200);
      }
      return _files(request);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(), refreshNow: false);
    await store.cetok.open();
    online = false;
    await store.cetok.refresh();
    expect(hidden, [true, true]);
    store.dispose();
  });

  test('online pieces name the file version so the server can answer from its cache', () async {
    final seen = <Uri>[];
    final store = await AppStore.open(
      root: root,
      client: MockClient((request) async {
        seen.add(request.url);
        return _files(request);
      }),
    );
    await store.signIn(testSession(), refreshNow: false);
    await store.refresh();
    final file = store.catalog.files.single;
    // The fixture server sends whole files, which fetchPdfRange refuses.
    await expectLater(store.fetchPdfRange(file, 0, 10), throwsA(isA<HttpException>()));
    expect(seen.last.queryParameters['v'], file.pdf.sha256.substring(0, 12));
    store.dispose();
  });

  test('an old session is swapped before the catalog is fetched, and stays after a restart', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.url.path} ${request.headers[sessionHeader]}');
      if (request.url.path == '/auth/refresh') {
        return http.Response(jsonEncode(_sessionJson(testSession(token: 'baru'))), 200);
      }
      return _files(request);
    });
    final store = await AppStore.open(root: root, client: client);
    final old = testSession(token: 'lama');
    await store.signIn(
      Session(
        token: old.token,
        nrp: old.nrp,
        name: old.name,
        admin: false,
        issuedAt: DateTime.now().subtract(const Duration(days: 2)),
        expiresAt: DateTime.now().add(const Duration(days: 28)),
      ),
    );
    expect(calls, ['/auth/refresh lama', '/catalog.json baru']);
    expect(store.online, isTrue);
    store.dispose();

    final reopened = await AppStore.open(root: root, client: client);
    expect(reopened.session!.token, 'baru');
    reopened.dispose();
  });

  test('the server asking for a new session mid-download swaps it and tries again', () async {
    var refreshed = false;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        refreshed = true;
        return http.Response(jsonEncode(_sessionJson(testSession(token: 'baru'))), 200);
      }
      if (request.headers[sessionHeader] != 'baru' && request.url.path != '/catalog.json') {
        return http.Response(jsonEncode({'error': 'refresh'}), 401);
      }
      return _files(request);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession(token: 'lama'));
    final file = store.catalog.files.single;
    await store.download(file, unitName: 'TEST1-1');
    expect(refreshed, isTrue);
    expect(store.isDownloaded(file.key), isTrue);
    store.dispose();
  });

  test('a deactivated NRP is logged out and its manuals removed', () async {
    var active = true;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return active
            ? http.Response(jsonEncode(_sessionJson(testSession())), 200)
            : http.Response(jsonEncode({'error': 'inactive', 'message': 'NRP ini sudah tidak aktif.'}), 403);
      }
      return _files(request);
    });
    final store = await AppStore.open(root: root, client: client);
    await store.signIn(testSession());
    final file = store.catalog.files.single;
    await store.download(file, unitName: 'TEST1-1');
    expect(File(store.pdfPath(file)).existsSync(), isTrue);

    active = false;
    expect(await store.renewSession(), isNull);
    expect(store.loggedIn, isFalse);
    expect(store.isDownloaded(file.key), isFalse);
    expect(File(store.pdfPath(file)).existsSync(), isFalse);
    store.dispose();
  });

  test('no signal does not log anyone out', () async {
    final store = await AppStore.open(
      root: root,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await store.signIn(testSession(), refreshNow: false);
    expect(await store.renewSession(), isNull);
    expect(store.loggedIn, isTrue);
    store.dispose();
  });

  test('30 days without internet logs out but keeps the manuals', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.signIn(testSession());
    final file = store.catalog.files.single;
    await store.download(file, unitName: 'TEST1-1');
    store.dispose();

    final s = testSession();
    File('${root.path}/auth.json').writeAsStringSync(jsonEncode(Session(
      token: s.token,
      nrp: s.nrp,
      name: s.name,
      admin: false,
      issuedAt: DateTime.now().subtract(const Duration(days: 31)),
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    ).toJson()));
    final reopened = await AppStore.open(root: root, client: fixtureServer());
    expect(reopened.loggedIn, isFalse);
    expect(reopened.isDownloaded(file.key), isTrue);
    reopened.dispose();
  });

  testWidgets('first login: NRP and starting PIN, then a new PIN, then the app', (tester) async {
    late AppStore store;
    final sent = <String, Map<String, dynamic>>{};
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/auth/')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent[request.url.path] = body;
        if (request.url.path == '/auth/login') {
          if (body['pin'] != '111111') {
            return http.Response(jsonEncode({'error': 'pin', 'message': 'PIN salah, sisa 4 kali coba.'}), 403);
          }
          return http.Response(jsonEncode({'status': 'set_pin', 'setup': 'S', 'name': 'Budi'}), 200);
        }
        return http.Response(jsonEncode(_sessionJson(testSession())), 200);
      }
      return _files(request);
    });
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
    });
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true));
    await tester.pumpAndSettle();
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Versi lokal'), findsOneWidget);
    await tester.tap(find.byTooltip('Lihat PIN'));
    await tester.pump();
    expect(find.byTooltip('Sembunyikan PIN'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-nrp')), '21045678');
    await tester.enterText(find.byKey(const Key('login-pin')), '000000');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('PIN salah, sisa 4 kali coba.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-pin')), '111111');
    await tester.runAsync(() async {
      await tester.tap(find.text('Masuk'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Halo, Budi'), findsOneWidget);
    expect(find.text('Buat PIN baru Anda'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byKey(const Key('pin-new')), matching: find.byType(TextField)), '1234');
    // The sixth digit of the repeated PIN saves it.
    await tester.runAsync(() async {
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('pin-repeat')), matching: find.byType(TextField)), '1234');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(sent['/auth/pin']!['pin'], '1234');
    expect(store.loggedIn, isTrue);
    expect(find.text('Dokumen teknis'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });

  testWidgets('only admins see Kelola karyawan, which lists employees and makes a new starting PIN', (tester) async {
    late AppStore store;
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/admin/employees':
          return http.Response(
              jsonEncode({
                'employees': [
                  {'nrp': '21045678', 'name': 'Budi', 'admin': false, 'active': true, 'status': 'active', 'seen': 1, 'devices': ['Samsung SM-A546E'], 'ai_today': 4},
                  {'nrp': '21051133', 'name': 'Rudi', 'admin': false, 'active': true, 'status': 'new', 'seen': 0, 'devices': [], 'ai_today': 0},
                ],
              }),
              200);
        case '/admin/pin':
          return http.Response(jsonEncode({'ok': true, 'pin': '4829'}), 200);
      }
      return _files(request);
    });
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
      await store.signIn(testSession(), refreshNow: false);
    });
    await tester.pumpWidget(MyManualApp(store: store, requireLogin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    expect(find.text('NRP 21045678'), findsOneWidget);
    expect(find.text('Kelola karyawan'), findsNothing);
    expect(find.text('Keluar'), findsOneWidget);
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    await tester.runAsync(() => store.signIn(testSession(admin: true), refreshNow: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Kelola karyawan'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('Belum login 1'), findsOneWidget);

    await tester.tap(find.text('Rudi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat PIN awal baru'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Buat PIN'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('4829'), findsOneWidget);
    await tester.runAsync(() async => store.dispose());
  });
}
