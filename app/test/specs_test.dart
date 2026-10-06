import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/main.dart';
import 'package:mymanual/src/specs.dart';
import 'package:mymanual/src/store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'store_test.dart' show fixtureServer;

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

  testWidgets('the Spek tab lists each section for the unit', (tester) async {
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
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('TEST1-1'), findsWidgets);
    for (final section in specSections) {
      expect(find.text(section.title), findsOneWidget);
    }
    // The fixture manual has no spec bookmarks.
    expect(find.textContaining('Tidak ditemukan'), findsNWidgets(specSections.length));
    root.deleteSync(recursive: true);
  });
}
