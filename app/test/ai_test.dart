import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('mymanual'));
  tearDown(() => root.deleteSync(recursive: true));

  test('the AI searches the downloaded manuals and its answer cites the pages', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    await store.download(store.catalog.files.single, unitName: 'TEST1-1');

    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      final Map<String, dynamic> reply = requests.length == 1
          ? {
              'stop_reason': 'tool_use',
              'content': [
                {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
                {
                  'type': 'tool_use',
                  'id': 'toolu_1',
                  'name': 'search_manuals',
                  'input': {'query': 'hydraulic oil filter clogging lamp', 'unit': 'TEST1'},
                },
              ],
            }
          : {
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'Lampu menyala karena **filter** tersumbat [S1]. Ganti elemen [S2] [S9].'},
              ],
            };
      return http.Response(jsonEncode(reply), 200, headers: {'content-type': 'application/json'});
    });

    final statuses = <String>[];
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('Lampu filter oli hidrolik menyala?', onStatus: statuses.add);

    expect(requests.first['manuals'], ['TEST1-1: OMM Test Unit (OMM)']);
    // Second request: question, the AI's turn kept as sent, then the pages found.
    final messages = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
    expect((messages[1]['content'] as List).first['signature'], 'sig');
    final result = (messages[2]['content'] as List).single as Map<String, dynamic>;
    expect(result['tool_use_id'], 'toolu_1');
    expect(result['content'], contains('[S1] TEST1-1 · OMM Test Unit · page 2'));
    expect(result['content'], contains('HYDRAULIC OIL FILTER CLOGGING CAUTION LAMP'));
    expect(statuses, contains('Mencari di manual: hydraulic oil filter clogging lamp'));

    // Citations renumbered per answer; an id that was never shown is dropped.
    expect(answer.failed, isFalse);
    expect(answer.text, 'Lampu menyala karena filter tersumbat [1]. Ganti elemen [2].');
    expect(answer.sources.map((s) => s.page), [2, 3]);
    store.dispose();
  });

  test('a Worker error shows its message', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    final worker = MockClient((_) async => http.Response(
        jsonEncode({'error': 'busy', 'message': 'AI sedang sibuk. Coba lagi sebentar lagi.'}), 429));
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    await expectLater(
      chat.ask('halo'),
      throwsA(isA<AiException>().having((e) => e.message, 'message', 'AI sedang sibuk. Coba lagi sebentar lagi.')),
    );
    store.dispose();
  });
}
