import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/chat_screen.dart';
import 'package:mymanual/src/screens/unit_tabs.dart';
import 'package:mymanual/src/specs.dart';
import 'package:mymanual/src/store.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

import 'store_test.dart' show fixtureCatalog, fixtureServer;

String indexWithToc(Directory dir, String name, List<(String, int)> toc) {
  final path = p.join(dir.path, '$name.sqlite');
  final db = sqlite3.open(path);
  db.execute('CREATE TABLE toc (seq INTEGER PRIMARY KEY, level INTEGER NOT NULL, '
      'title TEXT NOT NULL, page INTEGER NOT NULL)');
  for (final (i, (title, page)) in toc.indexed) {
    db.execute('INSERT INTO toc VALUES (?, 1, ?, ?)', [i, title, page]);
  }
  db.close();
  return path;
}

/// The fixture catalog with a spek.pdf for TEST1 (the fixture PDF stands in for it).
Map<String, dynamic> catalogWithSpec() {
  final catalog = fixtureCatalog();
  final unit = (catalog['units'] as List).single as Map<String, dynamic>;
  final pdf = (unit['files'] as List).single['pdf'] as Map<String, dynamic>;
  unit['spec'] = {
    ...pdf,
    'pages': [
      {'section': 0, 'title': 'Standard tightening torque table', 'file': 'OMM_Test_Unit', 'page': 40, 'at': 2, 'count': 1},
      {'section': 1, 'title': 'Table of fuel, coolant and lubricants', 'file': 'OMM_Test_Unit', 'page': 80, 'at': 3, 'count': 1},
    ],
    'service': [
      {'hours': 0, 'title': 'MAINTENANCE SCHEDULE CHART', 'file': 'OMM_Test_Unit', 'page': 100, 'at': 1, 'count': 1, 'item': false},
      {'hours': 250, 'title': 'EVERY 250 HOURS SERVICE', 'file': 'OMM_Test_Unit', 'page': 110, 'at': 2, 'count': 1, 'item': false},
      {'hours': 250, 'title': 'CHECK ENGINE OIL LEVEL', 'file': 'OMM_Test_Unit', 'page': 111, 'at': 2, 'count': 1, 'item': true},
      {'hours': 500, 'title': 'EVERY 500 HOURS SERVICE', 'file': 'OMM_Test_Unit', 'page': 120, 'at': 3, 'count': 1, 'item': false},
      {'hours': 500, 'title': 'REPLACE FUEL MAIN FILTER', 'file': 'OMM_Test_Unit', 'page': 121, 'at': 3, 'count': 1, 'item': true},
    ],
  };
  return catalog;
}

void main() {
  test('spec pages are found in the manuals\' bookmarks', () {
    final dir = Directory.systemTemp.createTempSync('specs');
    final sm = indexWithToc(dir, 'sm', [
      ('Standard tightening torque table', 12),
      ('Standard  tightening torque table', 12),
      ('Standard value table for engine', 40),
      ('Testing and adjusting main relief valve pressure', 310),
      ('Hydraulic oil filter clogging caution lamp', 88),
    ]);
    final omm = indexWithToc(dir, 'omm', [
      ('Use of fuel, coolant and lubricants according to ambient temperature', 150),
      ('Table of fuel, coolant and lubricants', 151),
    ]);
    final pages = findSpecPagesSync({'sm': sm, 'omm': omm, 'broken': p.join(dir.path, 'none.sqlite')});

    expect(pages[0].map((e) => (e.fileKey, e.page)), [('sm', 12)]);
    expect(pages[1].map((e) => e.page), [150, 151]);
    expect(pages[2].map((e) => e.page), [40, 310]);
    dir.deleteSync(recursive: true);
  });


  Future<void> settle(WidgetTester tester) async {
    // The tab is built once the pages slide to it, then reads its data.
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('without spek.pdf the tab falls back to the manuals\' bookmarks', (tester) async {
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('specs');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer());
      await store.setServerUrl('https://example.test');
      await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standar').last);
    await settle(tester);

    expect(find.text('TEST1-1'), findsWidgets);
    for (final tab in ['Torsi', 'Kapasitas', 'Nilai standar']) {
      expect(find.text(tab), findsOneWidget);
    }
    // The fixture manual has no spec bookmarks.
    expect(find.text('Tidak ditemukan di bookmark manual unit ini'), findsOneWidget);
    root.deleteSync(recursive: true);
  });

  testWidgets('spek.pdf is fetched and its pages open from the phone', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('specs');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalogWithSpec()));
      await store.setServerUrl('https://example.test');
      await store.fetchSpecPacks();
    });
    final unit = store.units.single;
    expect(store.readySpecPath(unit), isNotNull);

    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standar').last);
    await settle(tester);
    expect(find.text('Standard tightening torque table'), findsOneWidget);
    expect(find.textContaining('hlm'), findsNothing);

    await tester.tap(find.text('Kapasitas'));
    await tester.pumpAndSettle();
    expect(find.text('Table of fuel, coolant and lubricants'), findsOneWidget);

    await tester.tap(find.text('Table of fuel, coolant and lubricants'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final viewer = tester.widget<SpecViewerScreen>(find.byType(SpecViewerScreen));
    expect(viewer.path, store.readySpecPath(unit));
    expect(viewer.page, 3);
    expect(find.text('Buka manual lengkap'), findsOneWidget);
    expect(find.byType(AiCircleButton), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A newer spek.pdf replaces the old one.
    await tester.runAsync(() async {
      final catalog = catalogWithSpec();
      final spec = ((catalog['units'] as List).single as Map<String, dynamic>)['spec'] as Map<String, dynamic>;
      final index = ((catalog['units'] as List).single['files'] as List).single['index'] as Map<String, dynamic>;
      spec.addAll(index);
      final old = store.readySpecPath(unit)!;
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
      await store.fetchSpecPacks();
      expect(File(old).existsSync(), isFalse);
      expect(store.readySpecPath(store.units.single), isNotNull);
    });
    root.deleteSync(recursive: true);
  });

  testWidgets('Servis lists each interval, and Tanya nyel AI fills the chat', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('specs');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalogWithSpec()));
      await store.setServerUrl('https://example.test');
      await store.fetchSpecPacks();
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servis').last);
    await tester.pumpAndSettle();

    expect(find.text('HM 250'), findsOneWidget);
    expect(find.text('HM 500'), findsOneWidget);
    expect(find.text('Maintenance Schedule Chart'), findsOneWidget);
    expect(find.text('Check Engine Oil Level'), findsOneWidget);
    await tester.tap(find.text('HM 500'));
    await tester.pumpAndSettle();
    expect(find.text('Replace Fuel Main Filter'), findsOneWidget);

    await tester.tap(find.text('Replace Fuel Main Filter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<SpecViewerScreen>(find.byType(SpecViewerScreen)).page, 3);
    await tester.tap(find.byType(AiCircleButton));
    await tester.pumpAndSettle();
    expect(find.byType(SpecViewerScreen), findsNothing);
    final input = tester.widget<EditableText>(
        find.descendant(of: find.byType(ChatScreen), matching: find.byType(EditableText)));
    expect(input.controller.text, contains('REPLACE FUEL MAIN FILTER'));
    expect(input.controller.text, contains('TEST1-1'));
    root.deleteSync(recursive: true);
  });

  testWidgets('Servis shows Caterpillar tabs by name, ordered by hours', (tester) async {
    Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
    final catalog = catalogWithSpec();
    final unit = (catalog['units'] as List).single as Map<String, dynamic>;
    (unit['spec'] as Map<String, dynamic>)['service'] = [
      {'hours': 0, 'title': 'Maintenance Interval Schedule', 'file': 'OMM_Test_Unit', 'page': 100, 'at': 1, 'count': 1, 'item': false},
      {'hours': 1000000, 'tab': 'Saat perlu', 'title': 'When Required', 'file': 'OMM_Test_Unit', 'page': 100, 'at': 1, 'count': 1, 'item': false},
      {'hours': 1000000, 'tab': 'Saat perlu', 'title': 'Fuses - Replace', 'file': 'OMM_Test_Unit', 'page': 130, 'at': 2, 'count': 1, 'item': true},
      {'hours': 500, 'tab': 'Initial 500', 'title': 'Initial 500 Service Hours', 'file': 'OMM_Test_Unit', 'page': 101, 'at': 1, 'count': 1, 'item': false},
      {'hours': 500, 'tab': 'Initial 500', 'title': 'Final Drive Oil - Change', 'file': 'OMM_Test_Unit', 'page': 140, 'at': 3, 'count': 1, 'item': true},
      {'hours': 500, 'title': 'Every 500 Service Hours', 'file': 'OMM_Test_Unit', 'page': 101, 'at': 1, 'count': 1, 'item': false},
      {'hours': 500, 'title': 'Swing Bearing - Lubricate', 'file': 'OMM_Test_Unit', 'page': 150, 'at': 3, 'count': 1, 'item': true},
    ];
    late AppStore store;
    final root = Directory.systemTemp.createTempSync('specs');
    await tester.runAsync(() async {
      store = await AppStore.open(root: root, client: fixtureServer(catalog: catalog));
      await store.setServerUrl('https://example.test');
      await store.fetchSpecPacks();
    });
    await tester.pumpWidget(MyManualApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servis').last);
    await tester.pumpAndSettle();

    final initial = tester.getTopLeft(find.text('Initial 500')).dx;
    final hm500 = tester.getTopLeft(find.text('HM 500')).dx;
    final required = tester.getTopLeft(find.text('Saat perlu')).dx;
    expect(initial < hm500 && hm500 < required, isTrue);
    // The first tab (Initial 500) holds only its own items.
    expect(find.text('Final Drive Oil - Change'), findsOneWidget);
    expect(find.text('Swing Bearing - Lubricate'), findsNothing);
    await tester.tap(find.text('HM 500'));
    await tester.pumpAndSettle();
    expect(find.text('Swing Bearing - Lubricate'), findsOneWidget);
    await tester.tap(find.text('Saat perlu'));
    await tester.pumpAndSettle();
    expect(find.text('Fuses - Replace'), findsOneWidget);
    root.deleteSync(recursive: true);
  });
}
