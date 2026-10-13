// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mymanual/src/ai.dart';
import 'package:mymanual/src/store.dart';

/// Asks nyel AI the questions in tool/ai_eval.json (ones it once got wrong)
/// against a local AI server with the real manuals, and checks each answer.
/// Run by .github/workflows/ai-eval.yml with the admin code (to read the
/// manuals' indexes) and the AI keys.
class _AdminClient extends http.BaseClient {
  _AdminClient(this.code);

  final String code;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host == 'files.mymanual.my.id') request.headers['x-admin-code'] = code;
    // The pages each search found, so a wrong answer can be traced to the
    // search or to the model.
    if (request.url.port == 8787 && request is http.Request) {
      final messages = (jsonDecode(request.body) as Map)['messages'] as List;
      for (final m in messages.reversed.takeWhile((m) => (m as Map)['role'] == 'tool')) {
        final found = RegExp(r'^\[S\d+\][^\n]*', multiLine: true).allMatches('${(m as Map)['content']}');
        print('  found: ${found.map((f) => f[0]).join(' | ')}');
      }
    }
    return _inner.send(request);
  }
}

void main() {
  test('nyel AI answers the questions it once got wrong', () async {
    final cases = (jsonDecode(File('tool/ai_eval.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final client = _AdminClient(Platform.environment['OWNER_CODE'] ?? '');
    final store = await AppStore.open(root: Directory.systemTemp.createTempSync('eval'), client: client);
    await store.setServerUrl(defaultServerUrl);
    expect(store.catalog.files, isNotEmpty, reason: 'catalog not loaded');
    final failures = <String>[];
    for (final c in cases) {
      final question = c['question'] as String;
      final chat = AiChat(
        store: store,
        client: client,
        endpoint: Uri.parse('http://127.0.0.1:8787/chat'),
        largeSheets: (file) async => const [],
      );
      final statuses = <String>[];
      ChatEntry answer;
      try {
        answer = await chat.ask(question, onStatus: statuses.add);
      } on Object catch (e) {
        failures.add('$question\n  error: $e');
        continue;
      }
      final text = answer.text;
      print('\n#### $question\n${statuses.where((s) => s.startsWith('Mencari')).join('\n')}\n---\n$text\n'
          'sources: ${answer.sources.map((s) => '${s.unitName} ${s.file.type.label} p${s.page}').join(', ')}');
      for (final pattern in (c['must'] as List? ?? const []).cast<String>()) {
        if (!RegExp(pattern, caseSensitive: false).hasMatch(text)) failures.add('$question\n  missing /$pattern/');
      }
      final pages = (c['pages'] as List? ?? const []).cast<int>();
      if (pages.isNotEmpty && !answer.sources.any((s) => pages.contains(s.page))) {
        failures.add('$question\n  cites none of pages $pages');
      }
      for (final pattern in (c['must_not'] as List? ?? const []).cast<String>()) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(text)) failures.add('$question\n  has /$pattern/');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
