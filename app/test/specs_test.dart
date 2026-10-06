import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/screens/specs_screen.dart';
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
    await tester.tap(find.text('Spek').last);
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
    await tester.tap(find.text('Spek').last);
    await settle(tester);
    expect(find.text('Standard tightening torque table'), findsOneWidget);
    expect(find.text('OMM Test Unit · hlm 40'), findsOneWidget);

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
}
