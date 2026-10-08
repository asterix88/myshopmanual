import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/cetok.dart';
import 'package:mymanual/src/screens/cetok_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

const _parts = [
  {'id': 1, 'unit': 'PC210-10MO', 'pn': '600-211-1340; 600-211-1341', 'desc': 'CARTRIDGE', 'loc': 'LOGISTIK', 'qty': 4, 'status': 'rfu', 'remarks': ''},
  {'id': 2, 'unit': 'D375A-6R', 'pn': '195-27-33110', 'desc': 'BOLT', 'loc': 'LAYDOWN', 'qty': 0, 'status': null, 'remarks': 'BEKAS'},
];

/// A stand-in for Cetok Online's database: answers its RPCs and records them.
class FakeCetok {
  final calls = <(String, Map<String, dynamic>)>[];
  String? failWith;
  var parts = [..._parts];

  Future<http.Response> handle(http.Request request) async {
    final function = request.url.pathSegments.last;
    final args = jsonDecode(request.body) as Map<String, dynamic>;
    calls.add((function, args));
    expect(request.headers['apikey'], 'test-key');
    expect(request.headers['authorization'], 'Bearer test-key');
    if (failWith != null) return http.Response(jsonEncode({'message': failWith}), 400);
    if (function == 'get_all_data') {
      return http.Response(jsonEncode({'parts': parts, 'transactions': []}), 200);
    }
    return http.Response('null', 200);
  }
}

void main() {
  late Directory root;
  late FakeCetok server;
  Cetok cetok({http.Client? client}) => Cetok(
        cachePath: '${root.path}/cetok.json',
        client: client ?? MockClient(server.handle),
        baseUrl: Uri.parse('https://cetok.test'),
        key: 'test-key',
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('cetok');
    server = FakeCetok();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('unit names match the manuals by model code', () {
    expect(unitModelCode('PC210-10MO'), 'PC210');
    expect(unitModelCode('D375A-6R'), 'D375');
    expect(unitModelCode('D85ESS-2'), 'D85');
    expect(unitModelCode('PC500LC-10R'), 'PC500');
    expect(unitModelCode('CAT395'), 'CAT395');
  });

  test('reads the stock like the website and keeps a copy for offline', () async {
    final c = cetok();
    await c.open();
    expect(server.calls.single.$1, 'get_all_data');
    expect(server.calls.single.$2, {'p_riwayat_limit': 1, 'p_show_hidden': false});
    expect(c.parts, hasLength(2));
    final first = c.parts.first;
    expect(first.numbers, ['600-211-1340', '600-211-1341']);
    expect(first.status, 'RFU');
    expect(first.remarks, isNull);
    expect(c.parts.last.status, isNull);
    expect(first.matches('1341'), isTrue);
    expect(first.matches('cartr'), isTrue);
    expect(first.matches('bolt'), isFalse);
    expect(c.units, ['PC210-10MO', 'D375A-6R']);
    expect(c.locations, ['LAYDOWN', 'LOGISTIK']);

    // Offline next time: the saved list shows, with the database's message.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final offline = cetok(client: MockClient((_) async => throw const SocketException('offline')));
    await offline.open();
    expect(offline.parts.map((p) => p.pn), c.parts.map((p) => p.pn));
    expect(offline.error, contains('Tidak bisa terhubung'));
  });

  test('changes go through the existing database functions', () async {
    final c = cetok();
    await c.open();
    final part = c.parts.first;
    await c.take(part, qty: 2, note: ' servis ', name: ' budi ');
    expect(server.calls[1].$1, 'ambil_barang');
    expect(server.calls[1].$2, {'p_id': '1', 'p_qty': 2, 'p_note': 'servis', 'p_nama': 'budi'});
    expect(server.calls[2].$1, 'get_all_data');
    expect(c.name, 'budi');

    await c.move(part, qty: 1, location: 'LAYDOWN', status: 'NOT RFU', note: 'x', name: 'budi');
    expect(server.calls[3].$1, 'transfer_stok');
    expect(server.calls[3].$2,
        {'p_source_id': '1', 'p_qty': 1, 'p_dest_loc': 'LAYDOWN', 'p_dest_status': 'NOT RFU', 'p_note': 'x', 'p_nama': 'budi'});

    await c.add(
      unit: 'CAT395',
      pn: '123',
      desc: 'SEAL',
      location: 'FABRIKASI',
      qty: 3,
      status: 'RFU',
      remarks: '',
      name: 'budi',
    );
    expect(server.calls[5].$1, 'input_barang');
    expect(server.calls[5].$2['p_unit'], 'CAT395');
    expect(server.calls[5].$2['p_qty'], 3);
  });

  test("the database's own message is shown when a change is refused", () async {
    final c = cetok();
    await c.open();
    server.failWith = 'Stok tidak cukup';
    await expectLater(
      c.take(c.parts.first, qty: 9, note: 'x', name: 'y'),
      throwsA(isA<CetokException>().having((e) => e.message, 'message', 'Stok tidak cukup')),
    );
  });

  testWidgets('Home shows Cetok Online; a part opens its details', (tester) async {
    late AppStore store;
    final manuals = fixtureServer();
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/rest/v1/rpc/')) {
        return http.Response(jsonEncode({'parts': _parts}), 200);
      }
      return manuals.send(request).then(http.Response.fromStream);
    });
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: client);
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('MANUAL BOOK'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(CetokCard), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('CETOK ONLINE').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5 && find.text('CARTRIDGE').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(CetokScreen), findsOneWidget);
    expect(find.text('Ambil'), findsWidgets);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('CARTRIDGE'), findsOneWidget);

    await tester.tap(find.text('CARTRIDGE'));
    await tester.pumpAndSettle();
    expect(find.text('Buka di Partsbook PC210'), findsOneWidget);
    expect(find.text('Pindahkan'), findsOneWidget);
    expect(find.textContaining('Tanya'), findsNothing);
  });
}
