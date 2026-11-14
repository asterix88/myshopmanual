import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/inspection.dart';
import 'package:mymanual/src/screens/inspection_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

Map<String, dynamic> _row(int row, String unit, String model, String date, String problem, {String action = ''}) => {
      'row': row,
      'case': '1',
      'inspector': 'TAUFIK',
      'leader': 'NOVAL',
      'unit': unit,
      'model': model,
      'hm': '10615,0',
      'date': date,
      'problem': problem,
      'action': action,
      'status': action.isEmpty ? 'OPEN' : 'CLOSE',
    };

/// A stand-in for the server's /inspection endpoints, holding the sheet.
class FakeInspectionServer {
  final calls = <(String, Map<String, dynamic>?)>[];
  bool offline = false;
  String? refuse;
  final rows = <Map<String, dynamic>>[
    _row(5, 'D5143', 'D155A-6R', '04/11/2026', 'HOSE RETURN FUEL LEAKING'),
    _row(6, 'E5138', 'PC210-10M0', '01/09/2026', 'PIN BUCKET AUS'),
    _row(7, 'E5138', 'PC210-10M0', '02/11/2026', 'SEAL CYLINDER BOCOR', action: 'DONE'),
    _row(8, 'E52027', 'PC2000-11R', '03/11/2026', 'AC KURANG DINGIN'),
  ];

  Map<String, dynamic> get data => {
        'sections': ['TRACK'],
        'sheet_url': 'https://docs.google.com/spreadsheets/d/x/edit',
        'inspector': 'BUDI',
        'tabs': {
          'TRACK': {'updated': '12/11/2026 9:10:00', 'rows': rows, 'leaders': ['NOVAL', 'SOFYAN']},
        },
        'pop': [
          ['E5138', 'PC210-10M0', 'TRACK'],
          ['E5141', 'PC210-10M0', 'TRACK'],
          ['C577067', '777', 'WHEEL'],
        ],
      };

  Future<http.Response> handle(http.Request request) async {
    final body = request.method == 'POST' ? jsonDecode(request.body) as Map<String, dynamic> : null;
    calls.add((request.url.path, body));
    if (offline) throw const SocketException('offline');
    if (refuse != null) return http.Response(jsonEncode({'error': 'moved', 'message': refuse}), 409);
    switch (request.url.path) {
      case '/inspection':
        return http.Response(jsonEncode(data), 200);
      case '/inspection/action':
        final r = rows.firstWhere((r) => r['unit'] == body!['unit'] && r['problem'] == body['problem']);
        r['action'] = body!['action'];
        return http.Response(jsonEncode({'row': r['row'], 'status': r['action'] == '' ? 'OPEN' : 'CLOSE'}), 200);
      case '/inspection/add':
        final problems = body!['problems'] as List;
        for (var i = 0; i < problems.length; i++) {
          rows.add(_row(9 + i, body['unit'] as String, body['model'] as String, body['date'] as String, problems[i] as String));
        }
        return http.Response(jsonEncode({'rows': [9]}), 200);
    }
    return http.Response('{}', 404);
  }
}

void main() {
  late Directory root;
  late FakeInspectionServer server;
  Inspection make({http.Client? client}) => Inspection(
        cachePath: '${root.path}/inspection.json',
        client: client ?? MockClient(server.handle),
        baseUrl: Uri.parse('https://ai.test'),
        retryEvery: const Duration(hours: 1),
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('inspection');
    server = FakeInspectionServer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('models sort by their numbers; sheet dates are day/month', () {
    final models = ['PC2000-11R', 'PC210-10M0', 'D155A-6R', 'PC1250SP-11R']..sort(naturalCompare);
    expect(models, ['D155A-6R', 'PC210-10M0', 'PC1250SP-11R', 'PC2000-11R']);
    expect(parseSheetDate('04/11/2026'), DateTime(2026, 11, 4));
    expect(sheetDate(DateTime(2026, 3, 7)), '07/03/2026');
    expect(inspectionUnitKey(' e-51.38 '), 'E5138');
    expect(shortUpdate('12/11/2026 9:10:00'), '12/11 09:10');
  });

  test('reads the sheet, sorted by model, unit and oldest date', () async {
    final data = make();
    await data.open();
    final rows = data.tabs['TRACK']!.rows;
    expect(rows.map((r) => r.unit), ['D5143', 'E5138', 'E5138', 'E52027']);
    expect(rows[1].problem, 'PIN BUCKET AUS', reason: 'oldest first');
    expect(rows[2].closed, isTrue);
    expect(data.popIndex['E5141']!.model, 'PC210-10M0');
    expect(data.inspector, 'BUDI');
    expect(lastHm(data.tabs['TRACK'], 'e5138'), '10615,0');
  });

  test('closing a finding sends ACTION in uppercase', () async {
    final data = make();
    await data.open();
    final row = data.tabs['TRACK']!.rows[1];
    expect(await data.setAction(row, ' done replace '), isTrue);
    expect(server.calls.last.$1, '/inspection/action');
    expect(server.calls.last.$2, containsPair('action', 'DONE REPLACE'));
    expect(server.calls.last.$2, containsPair('row', 6));
    expect(data.tabs['TRACK']!.rows[1].closed, isTrue);
    expect(data.pendingCount, 0);
  });

  test('without signal changes wait on the phone and go later', () async {
    final data = make();
    await data.open();
    server.offline = true;
    final row = data.tabs['TRACK']!.rows[1];
    expect(await data.setAction(row, 'done'), isFalse);
    expect(data.pendingCount, 1);
    final shown = data.tabs['TRACK']!.rows[1];
    expect(shown.closed, isTrue);
    expect(shown.pending, isTrue);
    await data.add(
      section: 'TRACK',
      unit: 'e5141',
      model: '',
      hm: '800',
      date: DateTime(2026, 11, 14),
      leader: 'noval',
      problems: ['lampu mati', ' '],
    );
    expect(data.pendingCount, 2);
    expect(data.tabs['TRACK']!.rows.where((r) => r.pending), hasLength(2));

    // The queue survives the app being closed.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = make();
    await again.open();
    expect(again.pendingCount, 2);
    expect(again.tabs['TRACK']!.rows.where((r) => r.pending), hasLength(2));

    server.offline = false;
    await again.refresh();
    expect(again.pendingCount, 0);
    final adds = server.calls.where((c) => c.$1 == '/inspection/add').toList();
    expect(adds.last.$2!['unit'], 'E5141');
    expect(adds.last.$2!['date'], '14/11/2026');
    expect(adds.last.$2!['leader'], 'NOVAL');
    expect(adds.last.$2!['problems'], ['LAMPU MATI']);
    expect(adds.last.$2!['id'], isNotEmpty);
    expect(again.tabs['TRACK']!.rows.any((r) => r.unit == 'E5141' && !r.pending), isTrue);
    expect(again.tabs['TRACK']!.rows.where((r) => r.pending), isEmpty);
  });

  test('a change the sheet refuses is dropped and shown', () async {
    final data = make();
    await data.open();
    server.refuse = 'Temuan ini sudah berubah';
    await data.setAction(data.tabs['TRACK']!.rows[0], 'ok');
    expect(data.pendingCount, 0);
    expect(data.refused, 'Temuan ini sudah berubah');
  });

  testWidgets('Daily Inspection: list, filter, close a finding, add one', (tester) async {
    late AppStore store;
    final manuals = fixtureServer();
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/inspection')) return server.handle(request);
      return manuals.send(request).then(http.Response.fromStream);
    });
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
      await store.signIn(testSession(), refreshNow: false);
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Daily Inspection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily Inspection'));
    Future<void> settle(Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await settle(find.text('PIN BUCKET AUS'));
    expect(find.byType(InspectionScreen), findsOneWidget);
    expect(find.text('TRACK · Update 12/11 09:10'), findsOneWidget);
    expect(find.byKey(const Key('inspection-sheet-link')), findsOneWidget);
    expect(find.text('CLOSE'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('Remark'), findsNothing);

    // Model filter: a sheet with each model and its counts.
    await tester.tap(find.byKey(const Key('inspection-model-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Model unit'), findsOneWidget);
    expect(find.text('3 open · 1 close'), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-option-D155A-6R')));
    await tester.pumpAndSettle();
    expect(find.text('PIN BUCKET AUS'), findsNothing);
    expect(find.text('HOSE RETURN FUEL LEAKING'), findsOneWidget);
    await tester.tap(find.text('Hapus filter'));
    await tester.pumpAndSettle();

    // Close a finding.
    await tester.tap(find.text('PIN BUCKET AUS'));
    await tester.pumpAndSettle();
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Cth: done, replace saat service'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('inspection-action')), 'replace pin');
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspection-save-action')));
    await settle(find.text('E5138 CLOSE'));
    expect(find.text('E5138 CLOSE'), findsOneWidget);
    expect(find.text('Urungkan'), findsOneWidget);
    expect(server.calls.last.$2, containsPair('action', 'REPLACE PIN'));
    expect(find.text('CLOSE'), findsNWidgets(2));

    // Add a finding for a unit that is in POP UNIT.
    ScaffoldMessenger.of(tester.element(find.byType(InspectionScreen))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inspection-add')));
    await tester.pumpAndSettle();
    expect(find.text('Temuan baru'), findsOneWidget);
    expect(find.text('Masuk ke sheet Inspection Track Open 2026'), findsOneWidget);
    expect(find.text('BUDI'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('add-unit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-unit')), 'c577067');
    await tester.pump();
    expect(find.text('Unit ini milik section Wheel'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('add-unit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-unit')), 'e51');
    await tester.pump();
    expect(find.byKey(const Key('unit-hit-E5141')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('unit-hit-E5141')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unit-hit-E5141')));
    await tester.pump();
    expect(find.text('Terisi dari POP UNIT'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('add-hm')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-hm')), '800');
    await tester.ensureVisible(find.byKey(const Key('leader-NOVAL')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leader-NOVAL')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('add-problem-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-problem-0')), 'lampu mati');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('add-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-save')));
    await settle(find.text('1 temuan baru · E5141'));
    expect(find.text('1 temuan baru · E5141'), findsOneWidget);
    final add = server.calls.lastWhere((c) => c.$1 == '/inspection/add').$2!;
    expect(add['model'], 'PC210-10M0');
    expect(add['section'], 'TRACK');
    expect(add['problems'], ['LAMPU MATI']);
  });
}
