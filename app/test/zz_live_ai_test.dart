import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/page_image.dart';
import 'package:mymanual/src/store.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('live AI with page pictures', () async {
    {
      Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM'];
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('pdfcache').path;
      final root = Directory.systemTemp.createTempSync('live');
      final store = await AppStore.open(root: root);
      await store.setServerUrl('https://mymanual.my.id');
      print('online=${store.online} files=${store.catalog.files.length}');
      for (final f in store.catalog.files.where((f) => f.id.contains('CAT359'))) {
        final doc = await PdfDocument.openUri(store.pdfUri(f), preferRangeAccess: true);
        print('DOC ${f.id} pages=${doc.pages.length} searchable=${f.searchable}');
        for (final pg in doc.pages) {
          final t = await pg.loadText();
          final txt = t?.fullText ?? '';
          print('  p${pg.pageNumber} ${pg.width.round()}x${pg.height.round()} text=${txt.length} ${txt.replaceAll(RegExp(r'\s+'), ' ').substring(0, txt.length < 80 ? txt.length : 80)}');
        }
        await doc.dispose();
      }
      final chat = AiChat(
        store: store,
        client: http.Client(),
        endpoint: Uri.parse('http://127.0.0.1:8787/chat'),
        pageImage: (f, p, r) async {
          final Uint8List png;
          try {
            png = await renderPageImage(store, f, p, r);
          } catch (e, st) {
            print('  RENDER FAILED ${f.id} p$p: $e\n$st');
            rethrow;
          }
          print('  drew ${f.id} p$p $r: ${png.length} bytes');
          File('${Directory.systemTemp.path}/view-${f.id}-$p-$r.png').writeAsBytesSync(png);
          return png;
        },
      );
      for (final q in [
        'Di hydraulic schematic CAT395, komponen apa saja yang terhubung ke main pump?',
      ]) {
        print('\n=== Q: $q');
        final sw = Stopwatch()..start();
        try {
          final a = await chat.ask(q, onStatus: (s) => print('  [${sw.elapsed.inMilliseconds}ms] $s'));
          print('  ANSWER failed=${a.failed} pictures=${a.pictures.map((s) => '${s.file.id} p${s.page}')}');
          print(a.text);
        } catch (e, st) {
          print('  EXCEPTION $e\n$st');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
