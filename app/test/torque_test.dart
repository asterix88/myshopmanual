import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/unit_tabs.dart';
import 'package:mymanual/src/screens/viewer_screen.dart';
import 'package:mymanual/src/specs.dart';
import 'package:mymanual/src/store.dart';

import 'specs_test.dart' show catalogWithSpec;
import 'store_test.dart' show fixtureServer;

void main() {
  test('remove & install chapters are found under the manual\'s own groups', () {
    final toc = [
      (level: 1, title: '50 Disassembly and assembly', page: 400),
      (level: 2, title: '50 Undercarriage and frame', page: 401),
      (level: 3, title: 'Removal and installation of track roller assembly', page: 402),
      (level: 3, title: 'Removal  and installation of track roller assembly', page: 402),
      (level: 3, title: 'Carrier roller - remove and install', page: 406),
      (level: 3, title: 'Disassembly and assembly of idler', page: 409),
      (level: 2, title: 'Engine and cooling system', page: 430),
      (level: 3, title: 'Removal and installation of engine assy', page: 431),
    ];
    final parts = partPages('sm', toc);
    expect(parts.map((e) => (e.group, e.title, e.page, e.count)), [
      ('Undercarriage and frame', 'Track roller', 402, 4),
      ('Undercarriage and frame', 'Carrier roller', 406, 3),
      ('Engine and cooling system', 'Engine', 431, maxPartPages),
    ]);
    expect(partName('Disassembly and assembly of idler'), isNull);
    expect(partName('REMOVE AND INSTALL SUPPLY PUMP ASSEMBLY (RIGHT BANK)'), 'SUPPLY PUMP');

    // Older manuals: the component alone, REMOVAL and INSTALLATION under it.
    final old = partPages('sm', [
      (level: 1, title: '30 DISASSEMBLY AND ASSEMBLY', page: 457),
      (level: 2, title: 'SPECIAL TOOL LIST', page: 462),
      (level: 2, title: 'STARTING MOTOR', page: 467),
      (level: 3, title: 'REMOVAL', page: 467),
      (level: 3, title: 'INSTALLATION', page: 467),
      (level: 2, title: 'CYLINDER HEAD', page: 479),
      (level: 3, title: 'REMOVAL', page: 479),
      (level: 2, title: 'ENGINE FRONT SEAL', page: 489),
    ]);
    expect(old.map((e) => (e.group, e.title, e.page, e.count)), [
      ('DISASSEMBLY AND ASSEMBLY', 'Starting motor', 467, 12),
      ('DISASSEMBLY AND ASSEMBLY', 'Cylinder head', 479, 10),
    ]);
  });

  test('each line with a torque value is marked once', () {
    const text = 'Mounting bolt\n  824 – 1,030 Nm {84 – 105 kgm}\nNut: 98 N·m\nRemove the cover.\nBolt 70 lbf ft';
    final lines = [for (final (s, e) in torqueLines(text)) text.substring(s, e)];
    expect(lines, ['824 – 1,030 Nm {84 – 105 kgm}', 'Nut: 98 N·m', 'Bolt 70 lbf ft']);
    expect(torqueLines('Pressure 34.3 MPa\nNumber 3 m'), isEmpty);
    // A torque wrench's range in the tools table is not a tightening torque.
    expect(torqueLines('Torque wrench\n5 to 50 Nm\n20 to 200 Nm'), isEmpty);
  });

  testWidgets('Torsi lists the components in collapsible groups', (tester) async {
    final catalog = catalogWithSpec();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    (unit['spec'] as Map<String, dynamic>)['parts'] = [
      {'group': 'Undercarriage and frame', 'title': 'Track roller', 'file': 'OMM_Test_Unit', 'page': 402, 'count': 4},
      {'group': 'Undercarriage and frame', 'title': 'Carrier roller', 'file': 'OMM_Test_Unit', 'page': 406, 'count': 3},
      {'group': 'Engine and cooling system', 'title': 'Engine', 'file': 'OMM_Test_Unit', 'page': 431, 'count': 5},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('torque');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
    });

    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standar').last);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Standard tightening torque table'), findsOneWidget);
    expect(find.byType(GroupCard), findsNWidgets(3));
    // Standard tightening torque comes first as its own group, open; the
    // shop manual's groups start closed.
    expect(find.text('Standard tightening torque'), findsOneWidget);
    expect(find.text('OMM Test Unit · hlm 40'), findsOneWidget);
    expect(find.text('Track roller'), findsNothing);
    expect(find.text('Engine'), findsNothing);
    await tester.tap(find.text('Engine and cooling system'));
    await tester.pumpAndSettle();
    expect(find.text('Engine'), findsOneWidget);

    await tester.drag(find.text('Engine and cooling system'), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Engine'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final viewer = tester.widget<ViewerScreen>(find.byType(ViewerScreen));
    expect(viewer.torquePages, (431, 435));
    await tester.pumpWidget(const SizedBox());
    root.deleteSync(recursive: true);
  });
}
