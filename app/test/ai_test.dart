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

  test('the server searches any manual, downloaded or not, and the answer cites its pages', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;

    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      final start = body['source_start'] as int;
      return http.Response(
        jsonEncode({
          'messages': [
            {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_${requests.length}',
                  'type': 'function',
                  'function': {'name': 'search_manuals', 'arguments': '{"query":"hydraulic oil filter","unit":""}'},
                },
              ],
            },
            {'role': 'tool', 'tool_call_id': 'call_${requests.length}', 'content': '[S$start] ...'},
            {
              'role': 'assistant',
              'content': 'Lampu menyala karena **filter** tersumbat [S$start]. Ganti elemen [S${start + 1}] [S99].'
                  '\n[Gambar S${start + 1}]',
            },
          ],
          'sources': [
            {'id': start, 'key': file.key, 'page': 2},
            {'id': start + 1, 'key': file.key, 'page': 3},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('Lampu filter oli hidrolik menyala?');

    // Nothing is downloaded: the search ran on the server.
    expect(store.isDownloaded(file.key), isFalse);
    expect(requests.single['source_start'], 1);
    expect(answer.failed, isFalse);
    // Citations renumbered per answer; an id that was never returned is dropped.
    expect(answer.text, 'Lampu menyala karena **filter** tersumbat [1]. Ganti elemen [2].');
    expect(answer.sources.map((s) => s.page), [2, 3]);
    expect(answer.sources.first.unitName, 'TEST1-1');
    // [Gambar S#] lines become pictures of those pages, not text.
    expect(answer.pictures.map((s) => s.page), [3]);

    // The next question sends the whole conversation, ids continuing.
    await chat.ask('Berapa intervalnya?');
    expect(requests[1]['source_start'], 3);
    expect((requests[1]['messages'] as List).map((m) => (m as Map)['role']),
        ['user', 'assistant', 'tool', 'assistant', 'user']);
    store.dispose();
  });

  test('a failed request is not kept in the conversation', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    var calls = 0;
    late List<dynamic> sent;
    final worker = MockClient((request) async {
      sent = (jsonDecode(request.body) as Map)['messages'] as List;
      if (calls++ == 0) return http.Response(jsonEncode({'error': 'busy', 'message': 'penuh'}), 429);
      return http.Response(
          jsonEncode({
            'messages': [
              {'role': 'assistant', 'content': 'Halo.'},
            ],
            'sources': [],
          }),
          200);
    });
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    await expectLater(chat.ask('halo'), throwsA(isA<AiException>()));
    final answer = await chat.ask('halo lagi');
    expect(sent.map((m) => (m as Map)['content']), ['halo lagi']);
    expect(answer.text, 'Halo.');
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

  test('stars in an answer become bold runs', () {
    expect(boldRuns('Ganti **filter oli** dan *seal*, lalu cek 2 * 3 kali.'), [
      (text: 'Ganti ', bold: false),
      (text: 'filter oli', bold: true),
      (text: ' dan ', bold: false),
      (text: 'seal', bold: true),
      (text: ', lalu cek 2 * 3 kali.', bold: false),
    ]);
  });
}
