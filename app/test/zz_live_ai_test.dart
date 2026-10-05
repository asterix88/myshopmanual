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
