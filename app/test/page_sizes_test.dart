import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/page_sizes.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('runs from the index expand to one size per page and back', () {
    final sizes = PageSizes.fromRuns([
      [1, 595, 842],
      [3, 842, 595],
      [1, 0, 0],
    ])!;
    expect(sizes.sizes, [const Size(595, 842), const Size(842, 595), const Size(842, 595), const Size(842, 595), null]);
    expect(sizes.isComplete, isFalse);
    expect(sizes[9], isNull);
    expect(sizes.toRuns(), [
      [1, 595, 842],
      [3, 842, 595],
      [1, 0, 0],
    ]);
    expect(PageSizes.fromRuns('nonsense'), isNull);
  });

  test('read from the index meta table; an older index has none', () {
    final dir = Directory.systemTemp.createTempSync('sizes');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.sqlite';
    final db = sqlite3.open(path)
      ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    expect(PageSizes.fromIndex(path), isNull);
    db.execute("INSERT INTO meta VALUES ('page_sizes', ?)", [jsonEncode([[2, 842, 595]])]);
    db.close();
    expect(PageSizes.fromIndex(path)!.sizes, [const Size(842, 595), const Size(842, 595)]);
    expect(PageSizes.fromIndex('${dir.path}/missing.sqlite'), isNull);
  });

  test('sizes measured on the phone are saved and merged with earlier visits', () {
    final dir = Directory.systemTemp.createTempSync('sizes');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/u/m.json';
    PageSizes.save(path, [const Size(595, 842), null, null]);
    PageSizes.save(path, [null, null, const Size(842, 595)]);
    expect(PageSizes.fromFile(path)!.sizes, [const Size(595, 842), null, const Size(842, 595)]);
    // Nothing measured: nothing written.
    PageSizes.save('${dir.path}/none.json', [null]);
    expect(File('${dir.path}/none.json').existsSync(), isFalse);
  });
}
