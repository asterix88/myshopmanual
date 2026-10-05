import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/store.dart';

Future<void> _ask(AppStore store, String q) async {
  final chat = AiChat(store: store, client: http.Client());
  final sw = Stopwatch()..start();
  print('\n=== Q: $q');
  try {
    final a = await chat.ask(q, onStatus: (s) => print('  [${sw.elapsed.inMilliseconds}ms] status: $s'));
    print('  [${sw.elapsed.inMilliseconds}ms] ANSWER failed=${a.failed} sources=${a.sources.length} pictures=${a.pictures.length}');
    print(a.text);
  } catch (e, st) {
    print('  [${sw.elapsed.inMilliseconds}ms] EXCEPTION ${e.runtimeType}: $e\n$st');
  }
}

void main() {
  test('live AI', () async {
    final root = Directory.systemTemp.createTempSync('live');
    final store = await AppStore.open(root: root);
    await store.setServerUrl('https://mymanual.my.id');
    print('online=${store.online} err=${store.lastError} files=${store.catalog.files.length}');
    // Like a fresh phone: nothing cached yet.
    await _ask(store, 'Berapa tekanan relief swing motor PC210?');
    await _ask(store, 'Bagaimana cara mengganti filter oli hidrolik?');
    final sw = Stopwatch()..start();
    await store.fetchAllAiIndexes();
    print('\nfetchAll done in ${sw.elapsed.inSeconds}s');
    await _ask(store, 'Bagaimana cara mengganti filter oli hidrolik?');
    await _ask(store, 'Apa arti kode error CA115 pada D155?');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
