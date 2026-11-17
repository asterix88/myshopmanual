import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/auth.dart';
import 'package:mymanual/src/diagnostics.dart';
import 'package:mymanual/src/error_reports.dart';
import 'package:mymanual/src/screens/error_reports_screen.dart';

import 'store_test.dart' show testSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('errors'));
  tearDown(() {
    ErrorReports.reset();
    Diagnostics.reset();
  });

  Future<void> start({
    Session? session,
    http.Client? client,
    List<Map<Object?, Object?>> exits = const [],
    Future<Session?> Function()? renew,
  }) =>
      ErrorReports.start(
        dir: dir,
        session: () => session,
        renew: renew ?? () async => null,
        client: () => client ?? MockClient((_) async => http.Response('{}', 500)),
        endpoint: Uri.parse('https://ai.test/errors'),
        exits: exits,
        delay: const Duration(hours: 1),
      );

  test('the same error is kept once with a count and survives a restart', () async {
    await start();
    ErrorReports.record('error', 'Bad state: no page 3', 'at viewer');
    ErrorReports.record('error', 'Bad state: no page 3', 'at viewer again');
    ErrorReports.record('error', 'Other', '');
    ErrorReports.reset();
    await start();
    expect(ErrorReports.pending.length, 2);
    expect(ErrorReports.pending.first['count'], 2);
    expect(ErrorReports.pending.first['stack'], 'at viewer again');
  });

  test('errors the app did not handle are recorded through Diagnostics', () async {
    final original = FlutterError.onError;
    addTearDown(() => FlutterError.onError = original);
    FlutterError.onError = (_) {};
    await Diagnostics.start(dir: dir);
    await start();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));
    expect(ErrorReports.pending.single['message'], 'Bad state: boom');
  });

  test('Android closing the app is reported once, but not crashes from before the first start', () async {
    final old = {'time': 1000, 'reason': 'CRASH', 'description': 'lama'};
    await start(exits: [old]);
    expect(ErrorReports.pending, isEmpty);
    ErrorReports.reset();
    await start(exits: [
      {'time': 3000, 'reason': 'CRASH_NATIVE', 'description': 'signal 11'},
      {'time': 2000, 'reason': 'USER_REQUESTED'},
      old,
    ]);
    expect(ErrorReports.pending.single['kind'], 'CRASH_NATIVE');
    expect(ErrorReports.pending.single['message'], 'Aplikasi ditutup Android (CRASH_NATIVE): signal 11');
    ErrorReports.reset();
    await start(exits: [
      {'time': 3000, 'reason': 'CRASH_NATIVE', 'description': 'signal 11'},
    ]);
    expect(ErrorReports.pending.single['count'], 1);
  });

  test('nothing is sent without a login; a sent list is emptied', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.headers[sessionHeader], 'tok');
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"ok":true}', 200);
    });
    await start(client: client);
    ErrorReports.record('error', 'A', '');
    expect(await ErrorReports.send(), isFalse);
    expect(bodies, isEmpty);

    ErrorReports.reset();
    await start(client: client, session: testSession(token: 'tok'));
    expect(await ErrorReports.send(), isTrue);
    expect(bodies.single['items'], [isA<Map<String, dynamic>>().having((i) => i['message'], 'message', 'A')]);
    expect(ErrorReports.pending, isEmpty);
    ErrorReports.reset();
    await start();
    expect(ErrorReports.pending, isEmpty);
  });

  test('an old session is swapped once; a failed send keeps the list', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return request.headers[sessionHeader] == 'new'
          ? http.Response('{"ok":true}', 200)
          : http.Response('{"error":"refresh"}', 401);
    });
    await start(client: client, session: testSession(token: 'old'), renew: () async => testSession(token: 'new'));
    ErrorReports.record('error', 'A', '');
    expect(await ErrorReports.send(), isTrue);
    expect(calls, 2);

    ErrorReports.reset();
    await start(session: testSession());
    ErrorReports.record('error', 'B', '');
    expect(await ErrorReports.send(), isFalse);
    expect(ErrorReports.pending.single['message'], 'B');
  });

  testWidgets('admins see each problem with how often and on how many phones', (tester) async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'groups': [
              {
                'kind': 'CRASH_NATIVE',
                'message': 'Aplikasi ditutup Android (CRASH_NATIVE)',
                'stack': 'Catatan aplikasi sebelum tertutup:\nopen viewer',
                'count': 4,
                'phones': 2,
                'people': ['Ali (A1)', 'Budi (B2)'],
                'apps': ['1.1.215'],
                'last': DateTime(2026, 11, 17, 9, 5).millisecondsSinceEpoch,
              },
            ],
          }),
          200,
        ));
    await tester.pumpWidget(MaterialApp(home: ErrorReportsScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Crash native'), findsOneWidget);
    expect(find.text('4x · 2 HP · versi 1.1.215'), findsOneWidget);
    await tester.tap(find.text('Aplikasi ditutup Android (CRASH_NATIVE)'));
    await tester.pumpAndSettle();
    expect(find.text('Ali (A1), Budi (B2)'), findsOneWidget);
    expect(find.textContaining('open viewer'), findsOneWidget);
  });
}
