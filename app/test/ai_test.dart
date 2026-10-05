import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
              'finish_reason': 'tool_calls',
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'search_manuals',
                      'arguments': jsonEncode({'query': 'hydraulic oil filter clogging lamp', 'unit': 'TEST1'}),
                    },
                  },
                ],
              },
            }
          : {
              'finish_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': 'Lampu menyala karena **filter** tersumbat 【S1†L3-L5】. Ganti elemen [S2] [S9].\n[Gambar S2]\n[Gambar S9]',
              },
            };
      return http.Response(jsonEncode(reply), 200, headers: {'content-type': 'application/json'});
    });

    final statuses = <String>[];
    // Like the app's real client, which holds open sockets: nothing in it may
    // be sent along with the search to the background isolate.
    final client = _UnsendableClient(worker);
    final chat = AiChat(store: store, client: client, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('Lampu filter oli hidrolik menyala?', onStatus: statuses.add);
    client.close();

    expect(requests.first['manuals'], ['[M1] TEST1-1: OMM Test Unit (OMM, 4 pages)']);
    expect(requests.first['features'], ['view_page']);
    // Second request: question, the AI's tool call, then the pages found.
    final messages = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'tool']);
    expect(((messages[1]['tool_calls'] as List).single as Map)['id'], 'call_1');
    final result = messages[2];
    expect(result['tool_call_id'], 'call_1');
    expect(result['content'], contains('[S1] TEST1-1 · OMM Test Unit · page 2'));
    expect(result['content'], contains('HYDRAULIC OIL FILTER CLOGGING CAUTION LAMP'));
    expect(statuses, contains('Mencari di manual: hydraulic oil filter clogging lamp'));

    // Citations renumbered per answer; an id that was never shown is dropped.
    expect(answer.failed, isFalse);
    expect(answer.text, 'Lampu menyala karena **filter** tersumbat [1]. Ganti elemen [2].');
    expect(answer.sources.map((s) => s.page), [2, 3]);
    // [Gambar S#] lines become pictures of those pages, not text.
    expect(answer.pictures.map((s) => s.page), [3]);
    store.dispose();
  });

  test('the AI can look at a manual page as a picture and show it', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');

    final requests = <Map<String, dynamic>>[];
    Map<String, dynamic> reply(Map<String, dynamic> message) => {'finish_reason': 'stop', 'message': message};
    final worker = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final Map<String, dynamic> body = switch (requests.length) {
        1 => reply({
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'v1',
                'type': 'function',
                'function': {
                  'name': 'view_page',
                  'arguments': jsonEncode({'manual': 'M1', 'page': 2, 'region': 'top-left'}),
                },
              },
              {
                'id': 'v2',
                'type': 'function',
                'function': {'name': 'view_page', 'arguments': jsonEncode({'manual': 'M1', 'page': 9})},
              },
              {
                'id': 'v3',
                'type': 'function',
                'function': {'name': 'view_page', 'arguments': jsonEncode({'manual': 'M1', 'page': 2})},
              },
            ],
          }),
        2 => reply({'role': 'assistant', 'content': 'Kabel 105 merah-putih [S1].\n[Gambar S1]'}),
        _ => reply({'role': 'assistant', 'content': 'Oke.'}),
      };
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

    final drawn = <String>[];
    final chat = AiChat(
      store: store,
      client: worker,
      endpoint: Uri.parse('https://ai.test/chat'),
      pageImage: (file, page, region) async {
        drawn.add('${file.id} $page $region');
        return Uint8List.fromList([1, 2, 3]);
      },
      largeSheets: (file) async => [3, 4],
    );
    final statuses = <String>[];
    final answer = await chat.ask('Kabel apa ke CN-E12?', onStatus: statuses.add);

    // Only the existing page was drawn; the wrong page number got a hint.
    final id = store.catalog.files.single.id;
    expect(drawn, ['$id 2 top-left', '$id 2 full']);
    final messages = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'tool', 'tool', 'tool', 'user']);
    // The whole of a page already seen in part keeps its source id.
    expect(messages[4]['content'], contains('[S1] TEST1-1 · OMM Test Unit · page 2 is attached'));
    expect(messages[2]['content'], contains('[S1] TEST1-1 · OMM Test Unit · page 2 (top-left part)'));
    // After a first look, the AI learns where the drawing sheets are.
    expect(messages[2]['content'], contains('pages 3, 4 are large drawing sheets'));
    expect(messages[3]['content'], startsWith('No such page'));
    final parts = (messages[5]['content'] as List).cast<Map<String, dynamic>>();
    expect(parts.last['image_url'], {'url': 'data:image/png;base64,AQID'});
    expect(statuses, contains('Melihat gambar: TEST1-1 · OMM Test Unit · hlm 2'));

    // The page the AI looked at is cited and shown under the answer.
    expect(answer.text, 'Kabel 105 merah-putih [1].');
    expect(answer.pictures.map((s) => s.page), [2]);

    // The next question no longer carries the large picture.
    await chat.ask('Terima kasih');
    final later = (requests[2]['messages'] as List).cast<Map<String, dynamic>>();
    expect(later.where((m) => m['content'] is List), isEmpty);
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

  test('a question about a unit fetches only the index of its manuals that are not downloaded', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;

    var round = 0;
    final worker = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final Map<String, dynamic> message = round++ == 0
          ? {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'search_manuals', 'arguments': jsonEncode({'query': 'hydraulic oil filter', 'unit': 'TEST1'})},
                },
              ],
            }
          : {'role': 'assistant', 'content': 'Ganti elemen filter [S1].'};
      expect(body['manuals'], isNotEmpty);
      return http.Response(jsonEncode({'finish_reason': 'stop', 'message': message}), 200);
    });

    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('Filter oli hidrolik?');

    expect(answer.failed, isFalse);
    expect(answer.sources.single.file.key, file.key);
    expect(store.isDownloaded(file.key), isFalse);
    expect(File(store.cachedIndexPath(file)).existsSync(), isTrue);
    expect(File(store.pdfPath(file)).existsSync(), isFalse);
    store.dispose();
  });

  test('a question about no unit searches only indexes already on the phone, without waiting', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;

    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final Map<String, dynamic> message = requests.length == 1
          ? {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'search_manuals', 'arguments': jsonEncode({'query': 'hydraulic oil filter', 'unit': ''})},
                },
              ],
            }
          : {'role': 'assistant', 'content': 'Indeks manual masih disiapkan.'};
      return http.Response(jsonEncode({'finish_reason': 'stop', 'message': message}), 200);
    });

    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    await chat.ask('Filter oli hidrolik?');

    final tool = (requests[1]['messages'] as List).cast<Map<String, dynamic>>().last;
    expect(tool['content'], contains('1 manual(s) are still being prepared'));
    expect(File(store.cachedIndexPath(file)).existsSync(), isFalse);
    store.dispose();
  });

  test('the search index of every manual is fetched in the background, PDFs are not', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final file = store.catalog.files.single;
    final stale = File('${root.path}/index-cache/OLD/Gone-0123456789ab.sqlite')
      ..createSync(recursive: true);

    final progress = <String>[];
    store.addListener(() {
      if (store.aiIndexProgress case final p?) progress.add('${p.ready}/${p.total} ${p.receivedBytes}/${p.totalBytes}');
    });
    await store.fetchAllAiIndexes();

    expect(progress.first, '0/1 0/${file.index.size}');
    expect(progress.last, '1/1 ${file.index.size}/${file.index.size}');
    expect(File(store.cachedIndexPath(file)).existsSync(), isTrue);
    expect(File(store.pdfPath(file)).existsSync(), isFalse);
    expect(stale.existsSync(), isFalse);
    expect(store.aiIndexProgress, isNull);
    store.dispose();
  });
}

/// An HTTP client holding something that can't cross isolates, as a real
/// `http.Client` does.
class _UnsendableClient extends http.BaseClient {
  _UnsendableClient(this._inner);

  final http.Client _inner;
  final _port = ReceivePort();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() {
    _port.close();
    _inner.close();
  }
}
