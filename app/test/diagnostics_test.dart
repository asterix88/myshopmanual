import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mymanual/src/diagnostics.dart';
import 'package:mymanual/src/page_image.dart';
import 'package:mymanual/src/store.dart';
import 'package:pdfrx/pdfrx.dart';

import 'store_test.dart' show fixtureServer;

void main() {
  test('the problem log keeps the last steps and survives restarts', () async {
    final dir = Directory.systemTemp.createTempSync('diag');
    await Diagnostics.start(dir: dir);
    Diagnostics.log('ask (12 chars)');
    Diagnostics.reset();
    await Diagnostics.start(dir: dir);
    final lines = File('${dir.path}/diagnostics.log').readAsLinesSync();
    expect(lines.map((l) => l.substring(20)), ['app started', 'ask (12 chars)', 'app started']);
    Diagnostics.reset();
  });

  testWidgets('a page under an AI answer is drawn once into a small picture file', (tester) async {
    await tester.runAsync(() async {
      // flutter test builds PDFium as a native asset but does not load it
      // by itself.
      Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
      Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
      final store = await AppStore.open(root: Directory.systemTemp.createTempSync('thumb'), client: fixtureServer());
      await store.setServerUrl('https://example.test');
      final file = store.catalog.files.single;
      await store.download(file, unitName: 'TEST1-1');
      final first = await pageThumbnail(store, file, 2);
      final bytes = first.readAsBytesSync();
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
      final again = await pageThumbnail(store, file, 2);
      expect(again.path, first.path);
      expect(again.lastModifiedSync(), first.lastModifiedSync());
      store.dispose();
    });
  });
}
