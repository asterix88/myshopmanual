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
    final ids = ['PC210', 'D85', 'CAT395', 'PC1250-11', 'D375A-8', 'PC500', 'PC2000-11R', 'D155'];
    final units = [for (final id in ids) Unit(id: id, name: id, kind: '', files: const [])]
      ..sort((a, b) => b.sizeClass.compareTo(a.sizeClass));
    expect(units.where((u) => u.machine == Machine.excavator).map((u) => u.id),
        ['PC2000-11R', 'PC1250-11', 'CAT395', 'PC500', 'PC210']);
    expect(units.where((u) => u.machine == Machine.bulldozer).map((u) => u.id), ['D375A-8', 'D155', 'D85']);
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
      for (final id in ['PC1250-11', 'PC2000-11R', 'PC210', 'PC500']) {...unit, 'id': id, 'name': id},
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

    expect(find.byType(UnitRow), findsNWidgets(4));
    expect(find.textContaining('belum ada file'), findsNothing);
    expect(find.text('PC1250'), findsOneWidget);
    // The last row ends near the bottom of the page instead of leaving space.
    final body = tester.getRect(find.byType(ListView));
    final last = tester.getRect(find.byType(UnitRow).last);
    expect(body.bottom - last.bottom, lessThan(4));
  });

  testWidgets('files from subfolders of a unit folder sit under their subfolder name', (tester) async {
    final catalog = fixtureCatalog();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    final file = (unit['files'] as List).single as Map<String, dynamic>;
    unit['files'] = [
      file,
      {...file, 'id': 'System_Diagram_file', 'title': 'Hydraulic diagram', 'group': 'System Diagram'},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('unit');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
    });
    expect(store.catalog.files.last.group, 'System Diagram');
    await tester.pumpWidget(StoreScope(
      store: store,
      child: MaterialApp(home: UnitScreen(unitId: unit['id'] as String)),
    ));
    await tester.pumpAndSettle();

    // The subfolder comes first, then the files placed in the unit folder.
    final heading = tester.getTopLeft(find.text('System Diagram')).dy;
    final grouped = tester.getTopLeft(find.text('Hydraulic diagram')).dy;
    expect(grouped, greaterThan(heading));
    expect(tester.getTopLeft(find.text('OMM Test Unit')).dy, greaterThan(grouped));
  });
}
