import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/auth.dart';
import 'package:mymanual/src/store.dart';

import 'store_test.dart' show fixtureServer, testSession;

void main() {
  test('answers saved before keep no [1] numbers in their text', () {
    expect(withoutSourceNumbers('Ganti filter [1]. Cek tekanan [2, 3].\n- Langkah [4]'),
        'Ganti filter. Cek tekanan.\n- Langkah');
    expect(withoutSourceNumbers('Isi [oli] mesin'), 'Isi [oli] mesin');
  });

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
    expect(requests.first['features'], ['view_page', 'reasoning']);
    // Second request: question, the AI's tool call, then the pages found.
    final messages = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'tool']);
    expect(((messages[1]['tool_calls'] as List).single as Map)['id'], 'call_1');
    final result = messages[2];
    expect(result['tool_call_id'], 'call_1');
    expect(result['content'], contains('[S1] TEST1-1 · OMM Test Unit · page 2'));
    expect(result['content'], contains('HYDRAULIC OIL FILTER CLOGGING CAUTION LAMP'));
    expect(statuses, contains('Mencari di manual: hydraulic oil filter clogging lamp'));

    // Source marks leave the text; cited pages become sources, in order.
    expect(answer.failed, isFalse);
    expect(answer.text, 'Lampu menyala karena **filter** tersumbat. Ganti elemen.');
    expect(answer.sources.map((s) => s.page), [2, 3]);
    // [Gambar S#] lines become pictures of those pages, not text.
    expect(answer.pictures.map((s) => s.page), [3]);
    store.dispose();
  });

  test("the model's thinking goes back within a question and is dropped after it", () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final Map<String, dynamic> message = requests.length == 1
          ? {
              'role': 'assistant',
              'content': '',
              'reasoning_content': 'Cari tabel E-3 dulu.',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'search_manuals', 'arguments': jsonEncode({'query': 'filter', 'unit': ''})},
                },
              ],
            }
          : {'role': 'assistant', 'content': 'Secara umum, ganti filter.', 'reasoning_content': 'Selesai.'};
      return http.Response(jsonEncode({'finish_reason': 'stop', 'message': message}), 200);
    });
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('Filter?');
    final second = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    expect(second[1]['reasoning_content'], 'Cari tabel E-3 dulu.');
    // Not from a manual page: the answer says it needs checking.
    expect(answer.hasUncheckedParts, isTrue);

    await chat.ask('Lagi?');
    final third = (requests[2]['messages'] as List).cast<Map<String, dynamic>>();
    expect(third.where((m) => m.containsKey('reasoning_content')), isEmpty);
    store.dispose();
  });

  test('a wrong answer is reported with its question and pages', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    late http.Request sent;
    final worker = MockClient((request) async {
      sent = request;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    await chat.report(
      question: 'Tegangan terminal R?',
      answer: ChatEntry.assistant('Tidak ada nilai [1].'),
      note: 'Ada di E-3',
    );
    expect(sent.url.toString(), 'https://ai.test/feedback');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['question'], 'Tegangan terminal R?');
    expect(body['answer'], 'Tidak ada nilai.');
    expect(body['note'], 'Ada di E-3');
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
    expect(answer.text, 'Kabel 105 merah-putih.');
    expect(answer.pictures.map((s) => s.page), [2]);

    // The next question no longer carries the large picture.
    await chat.ask('Terima kasih');
    final later = (requests[2]['messages'] as List).cast<Map<String, dynamic>>();
    expect(later.where((m) => m['content'] is List), isEmpty);
    store.dispose();
  });

  test('a question asked from a manual page carries the page text and keeps the page', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    final file = store.catalog.files.single;

    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'finish_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'Terjemahan halaman [S1].'},
          }),
          200);
    });
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final answer = await chat.ask('terjemahkan halaman ini', file: file, page: 2);

    final question = ((requests.single['messages'] as List).single as Map)['content'] as String;
    expect(question, contains('[S1] TEST1-1 · OMM Test Unit · page 2'));
    expect(question, contains('HYDRAULIC OIL FILTER CLOGGING CAUTION LAMP'));
    expect(question, endsWith('Question: terjemahkan halaman ini'));
    expect(answer.sources.map((s) => s.page), [2]);

    // The page shown above the question is kept with the conversation.
    final page = AiSource(id: 0, file: file, unitName: 'TEST1-1', page: 2);
    final revision = store.chatRevision;
    await chat.save([ChatEntry.user('terjemahkan halaman ini', page: page), answer]);
    expect(store.chatRevision, revision + 1);
    final restored = await AiChat(store: store, client: worker).load();
    expect(restored.first.page?.page, 2);
    expect(restored.first.page?.file.key, file.key);
    store.dispose();
  });

  test('the chat is kept on the phone and only recent questions go to the AI', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    await store.download(store.catalog.files.single, unitName: 'TEST1-1');
    await store.signIn(testSession(admin: true), refreshNow: false);

    final requests = <Map<String, dynamic>>[];
    final worker = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final n = requests.length;
      return http.Response(
          jsonEncode({
            'finish_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'Jawaban $n [S1].'},
          }),
          200);
    });
    var chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final entries = [ChatEntry.user('Pertanyaan 1'), await chat.ask('Pertanyaan 1')];
    await chat.save(entries);

    // The app is opened again: the conversation is still there and carries on.
    chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    final restored = await chat.load();
    expect(restored.map((e) => (e.fromUser, e.text)), [(true, 'Pertanyaan 1'), (false, 'Jawaban 1.')]);
    for (var i = 2; i <= 7; i++) {
      await chat.ask('Pertanyaan $i');
    }
    final sent = (requests.last['messages'] as List).cast<Map<String, dynamic>>();
    final questions = [for (final m in sent) if (m['role'] == 'user') m['content']];
    expect(questions, ['Pertanyaan 3', 'Pertanyaan 4', 'Pertanyaan 5', 'Pertanyaan 6', 'Pertanyaan 7']);

    // A new conversation forgets it on the phone too.
    await chat.clear();
    expect(await AiChat(store: store, client: worker).load(), isEmpty);
    store.dispose();
  });

  test('each phone gets ten questions a day unless an admin is logged in', () async {
    final store = await AppStore.open(root: root, client: fixtureServer());
    await store.setServerUrl('https://example.test');
    final worker = MockClient((request) async => http.Response(
        jsonEncode({
          'finish_reason': 'stop',
          'message': {'role': 'assistant', 'content': 'Oke.'},
        }),
        200));
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    for (var i = 0; i < AppStore.aiDailyLimit; i++) {
      expect(store.aiQuestionsLeft, AppStore.aiDailyLimit - i);
      await chat.ask('Tanya $i');
    }
    expect(store.aiQuestionsLeft, 0);
    await expectLater(
      chat.ask('Satu lagi'),
      throwsA(isA<AiException>().having((e) => e.message, 'message', contains('sudah habis'))),
    );

    // The admin's phone has no limit.
    await store.signIn(testSession(admin: true), refreshNow: false);
    expect(store.aiQuestionsLeft, isNull);
    await chat.ask('Admin bebas');
    store.dispose();

    // The count survives a restart.
    final reopened = await AppStore.open(root: root, client: fixtureServer());
    expect(reopened.aiOwner, isTrue);
    await reopened.signOut();
    expect(reopened.aiQuestionsLeft, 0);
    reopened.dispose();
  });

  test('nyel AI gets the session and swaps it once when the server says it is old', () async {
    final store = await AppStore.open(root: root, client: MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return http.Response(jsonEncode({...testSession(token: 'baru').toJson(), 'status': 'ok'}), 200);
      }
      return http.Response('not found', 404);
    }));
    await store.signIn(testSession(token: 'lama'), refreshNow: false);
    final sent = <String?>[];
    final worker = MockClient((request) async {
      sent.add(request.headers[sessionHeader]);
      if (request.headers[sessionHeader] == 'lama') {
        return http.Response(jsonEncode({'error': 'refresh', 'message': 'Sesi perlu diperbarui.'}), 401);
      }
      return http.Response(
          jsonEncode({
            'finish_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'Oke.'},
          }),
          200);
    });
    final chat = AiChat(store: store, client: worker, endpoint: Uri.parse('https://ai.test/chat'));
    expect((await chat.ask('halo')).text, 'Oke.');
    expect(sent, ['lama', 'baru']);
    expect(store.session!.token, 'baru');
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
    // The Cari tab searches it too, although the manual is not downloaded.
    expect(store.searchableIndexes(), {file.key: store.cachedIndexPath(file)});
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
