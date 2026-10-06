import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  testWidgets('a page of a manual not on the phone is drawn from pieces fetched from the server', (tester) async {
    await tester.runAsync(() async {
      Pdfrx.pdfiumModulePath ??= File('build/native_assets/linux/libpdfium.so').absolute.path;
      Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfcache').path;
      final ranges = <String>[];
      final server = fixtureServer();
      final client = MockClient((request) async {
        final range = request.headers['Range'];
        final whole = await server.get(request.url);
        if (range == null || !request.url.path.endsWith('.pdf')) return whole;
        ranges.add(range);
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final end = math.min(int.parse(m[2]!) + 1, whole.bodyBytes.length);
        return http.Response.bytes(whole.bodyBytes.sublist(int.parse(m[1]!), end), 206);
      });
      final store = await AppStore.open(root: Directory.systemTemp.createTempSync('remote'), client: client);
      await store.setServerUrl('https://example.test');
      final file = store.catalog.files.single;
      expect(store.isDownloaded(file.key), isFalse);
      final png = await renderPageImage(store, file, 2, 'full', longest: 400);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      expect(ranges, isNotEmpty);
      // The viewer's cache file for this manual is never touched.
      expect(Directory('${Pdfrx.cacheDirectoryPath}/pdfrx.cache').existsSync(), isFalse);
      store.dispose();
    });
  });
}
