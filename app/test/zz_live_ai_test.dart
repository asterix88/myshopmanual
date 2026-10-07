import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/store.dart';

void main() {
  test('live AI general knowledge', () async {
    final root = Directory.systemTemp.createTempSync('live');
    final store = await AppStore.open(root: root);
    await store.setServerUrl('https://mymanual.my.id');
    print('online=${store.online} files=${store.catalog.files.length}');
    for (final q in [
      'Apa itu Komatsu Smart Construction Retrofit kit?',
      'Apa itu standar kebersihan oli ISO 4406 dan berapa target untuk oli hidrolik?',
      'Apa itu SL1?',
      'Cara kerja steering clutch tipe SL1 saat tuas netral?',
    ]) {
      // Each question in a new chat, as after the new-chat button.
      final chat = AiChat(store: store, client: http.Client(), endpoint: Uri.parse('http://127.0.0.1:8787/chat'));
      print('\n=== Q: $q');
      try {
        final a = await chat.ask(q, onStatus: (s) => print('  [$s]'));
        print(a.text);
      } catch (e) {
        print('  EXCEPTION $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
