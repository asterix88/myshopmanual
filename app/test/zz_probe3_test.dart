import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/search.dart';
import 'package:mymanual/src/store.dart';

/// Prints every request to the AI and its reply, so the tool calls (search
/// words) and what the phone answered with can be read afterwards.
class _Logging extends http.BaseClient {
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.port == 8787 && request is http.Request) {
      final body = jsonDecode(request.body) as Map;
      final messages = body['messages'] as List;
      final last = messages.last as Map;
      if (last['role'] == 'tool') {
        for (final m in messages.reversed.takeWhile((m) => (m as Map)['role'] == 'tool')) {
          final c = (m as Map)['content'].toString();
          print('--- TOOL RESULT (${c.length} chars)\n${c.length > 2500 ? c.substring(0, 2500) : c}');
        }
      }
    }
    final response = await _inner.send(request);
    if (request.url.port != 8787) return response;
    final bytes = await response.stream.toBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map;
    final m = data['message'] is Map ? data['message'] as Map : null;
    if (m == null) print('--- AI ERROR ${response.statusCode} ${data['message']}');
    print('--- AI model=${data['model']} web=${data['web']} calls=${jsonEncode(m?['tool_calls'])}');
    if ((m?['tool_calls'] as List?)?.isEmpty ?? true) print('--- ANSWER\n${m?['content']}');
    return http.StreamedResponse(Stream.value(bytes), response.statusCode, headers: response.headers);
  }
}

void main() {
  test('probe DKULKB', () async {
    final root = Directory.systemTemp.createTempSync('probe');
    final client = _Logging();
    final store = await AppStore.open(root: root, client: client);
    await store.setServerUrl('https://mymanual.my.id');
    print('catalog files: ${store.catalog.files.length}');
    final pc1250 = await store.aiIndexes(where: (f) => store.unitNameOf(f).toUpperCase().contains('PC1250'));
    print('PC1250 indexes: ${pc1250.length}');
    for (final q in ['DKULKB', 'DKULKB fault code', 'DKULKB error code', 'DKULKB failure code']) {
      print('\n=== search "$q"');
      for (final p in searchPageTextsSync(pc1250, q, limit: 4)) {
        final f = store.fileByKey(p.fileKey)!;
        print('${f.title} p${p.page} rank=${p.rank.toStringAsFixed(2)} section=${p.section}');
        print('   ${p.text.substring(0, p.text.length > 300 ? 300 : p.text.length).replaceAll('\n', ' ')}');
      }
    }
    final chat = AiChat(
      store: store,
      client: client,
      endpoint: Uri.parse('http://127.0.0.1:8787/chat'),
      pageImage: (file, page, region) async => base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII='),
      largeSheets: (file) async => const [],
    );
    for (final question in ['DKULKB', 'error DKULKB PC1250', 'CA234']) {
      print('\n\n######## ASK: $question');
      try {
        final entry = await chat.ask(question);
        print('######## FINAL: ${entry.text}');
      } catch (e) {
        print('######## ERROR $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
