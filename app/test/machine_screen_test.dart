import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/models.dart';
import 'package:mymanual/src/screens/machine_screen.dart';
import 'package:mymanual/src/screens/shell.dart';
import 'package:mymanual/src/screens/unit_screen.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureCatalog, fixtureServer;

void main() {
  test('a title starting with PB is a partsbook', () {
    expect(DocType.of('other', 'PB PC1250SP-11 SN J20001'), DocType.partsbook);
    expect(DocType.of('other', 'HYD SCHEMATIC PC1250-8'), DocType.other);
    expect(DocType.of('omm', 'PB something'), DocType.omm);
  });

  test('units are listed biggest machine first', () {
    final ids = ['PC210-10MO', 'D85ESS-2', 'CAT395', 'PC1250-11', 'D375A-8', 'PC500-10', 'PC2000-11R', 'D155A-6'];
    final units = [for (final id in ids) Unit(id: id, name: id, kind: '', files: const [])]
      ..sort((a, b) => b.sizeClass.compareTo(a.sizeClass));
    expect(units.where((u) => u.machine == Machine.excavator).map((u) => u.id),
        ['PC2000-11R', 'PC1250-11', 'CAT395', 'PC500-10', 'PC210-10MO']);
    expect(units.where((u) => u.machine == Machine.bulldozer).map((u) => u.id), ['D375A-8', 'D155A-6', 'D85ESS-2']);
  });

  test('a unit page lists subfolders first, then Shop Manual, OMM, Partsbook, the rest', () {
    final catalog = Catalog.fromJson(fixtureCatalog());
    final base = catalog.units.single.files.single;
    ManualFile f(String title, DocType type, [String group = '']) => ManualFile(
          unitId: 'U', id: title, title: title, type: type, pages: 1, searchable: true,
          pdf: base.pdf, index: base.index, updatedAt: null, group: group);
    final files = [
      f('Schematic', DocType.other),
      f('PB', DocType.partsbook),
      f('OMM', DocType.omm),
      f('Wiring', DocType.other, 'System Diagram'),
      f('SM', DocType.shopManual),
      f('Engine', DocType.other, 'Machine'),
    ]..sort(ManualFile.pageOrder);
    expect(files.map((f) => f.title), ['Engine', 'Wiring', 'SM', 'OMM', 'PB', 'Schematic']);
  });

  testWidgets('unit rows fill the page and skip the empty-phone note', (tester) async {
    final catalog = fixtureCatalog();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    catalog['units'] = [
      for (final id in ['PC1250-11', 'PC2000-11R', 'PC210-10MO', 'PC500LC-10', 'PC300-8']) {...unit, 'id': id, 'name': id},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('machine');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
    });
    await tester.pumpWidget(StoreScope(
      store: store,
      child: const MaterialApp(home: MachineScreen(machine: Machine.excavator)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(UnitRow), findsNWidgets(5));
    // A model with a picture shows it whatever its suffix (PC500 -> PC500LC-10 too).
    final pictures = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image as AssetImage).assetName);
    expect(pictures, [
      'assets/units/pc2000.png',
      'assets/units/pc1250.png',
      'assets/units/pc500.png',
      'assets/units/pc210.png',
    ]);
    expect(find.textContaining('belum ada file'), findsNothing);
    // A model without a picture shows its code instead.
    expect(find.text('PC300'), findsOneWidget);
    // The last row ends near the bottom of the page instead of leaving space.
    final body = tester.getRect(find.byType(ListView));
    final last = tester.getRect(find.byType(UnitRow).last);
    expect(body.bottom - last.bottom, lessThan(4));
  });

  testWidgets('subfolders of a unit folder open as their own folder page', (tester) async {
    final catalog = fixtureCatalog();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    final file = (unit['files'] as List).single as Map<String, dynamic>;
    unit['files'] = [
      file,
      {...file, 'id': 'System_Diagram_file', 'title': 'Hydraulic diagram', 'group': 'System Diagram'},
      {...file, 'id': 'System_Diagram_Electric_file', 'title': 'Wiring', 'group': 'System Diagram / Electric'},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('unit');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
    });
    expect(store.catalog.files.last.folder, ['System Diagram', 'Electric']);
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: UnitScreen(unitId: unit['id'] as String)),
    ));
    await tester.pumpAndSettle();

    // The unit page lists the subfolder (not its files) above the unit
    // folder's own files.
    expect(find.text('Hydraulic diagram'), findsNothing);
    expect(find.text('2 file'), findsOneWidget);
    expect(tester.getTopLeft(find.text('OMM Test Unit')).dy,
        greaterThan(tester.getTopLeft(find.text('System Diagram')).dy));

    // Opening it shows its files and its own subfolder.
    await tester.tap(find.text('System Diagram'));
    await tester.pumpAndSettle();
    expect(find.text('Hydraulic diagram'), findsOneWidget);
    expect(find.text('OMM Test Unit'), findsNothing);
    expect(find.text('Electric'), findsOneWidget);
    expect(find.text('Wiring'), findsNothing);

    await tester.tap(find.text('Electric'));
    await tester.pumpAndSettle();
    expect(find.text('Wiring'), findsOneWidget);
    expect(find.text('TEST1-1 / System Diagram'), findsOneWidget);
  });
}
