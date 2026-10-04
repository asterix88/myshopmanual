import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'search.dart';
import 'store.dart';

/// Address of the Worker in ai-worker/, which holds the Anthropic API key.
/// Override with `flutter build apk --dart-define=AI_URL=...`.
const _buildAiUrl = String.fromEnvironment('AI_URL');
const aiUrl = _buildAiUrl == '' ? 'https://ai.mymanual.my.id' : _buildAiUrl;

/// Optional shared token the Worker checks (its APP_TOKEN secret).
const _aiToken = String.fromEnvironment('AI_TOKEN');

/// A manual page the AI was shown, numbered so its answer can cite it.
class AiSource {
  const AiSource({required this.id, required this.file, required this.unitName, required this.page});

  final int id;
  final ManualFile file;
  final String unitName;
  final int page;
}

/// What the user sees of one exchange.
class ChatEntry {
  ChatEntry.user(this.text)
      : fromUser = true,
        sources = const [],
        failed = false;
  ChatEntry.assistant(this.text, {this.sources = const [], this.failed = false}) : fromUser = false;

  final bool fromUser;
  final String text;

  /// Pages cited in [text], in order of first citation.
  final List<AiSource> sources;
  final bool failed;
}

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A conversation with the AI. The Worker is stateless: the full history,
/// including the AI's tool calls and the pages found, is kept here and sent
/// on every request. History is only ever appended to.
class AiChat {
  AiChat({required this.store, required this.client, Uri? endpoint})
      : _endpoint = endpoint ?? Uri.parse('$aiUrl/chat');

  final AppStore store;
  final http.Client client;
  final Uri _endpoint;

  final List<Map<String, dynamic>> _messages = [];
  final Map<int, AiSource> _sources = {};

  /// Requests per question: each search the AI asks for costs one round.
  static const maxRounds = 6;

  /// Asks [question]; [onStatus] reports what is happening while it works.
  Future<ChatEntry> ask(String question, {void Function(String status)? onStatus}) async {
    _messages.add({'role': 'user', 'content': question});
    final manuals = [
      for (final m in store.local.values)
        if (m.file.searchable) '${m.unitName}: ${m.file.title} (${m.file.type.label})',
    ];

    for (var round = 0; round < maxRounds; round++) {
      onStatus?.call(round == 0 ? 'Memahami pertanyaan…' : 'Menyusun jawaban…');
      final response = await _post({'messages': _messages, 'manuals': manuals});
      final content = (response['content'] as List).cast<Map<String, dynamic>>();
      _messages.add({'role': 'assistant', 'content': content});

      final stopReason = response['stop_reason'] as String?;
      if (stopReason == 'tool_use') {
        final results = <Map<String, dynamic>>[];
        for (final block in content.where((b) => b['type'] == 'tool_use')) {
          final input = (block['input'] as Map).cast<String, dynamic>();
          final query = (input['query'] as String? ?? '').trim();
          onStatus?.call('Mencari di manual: $query');
          results.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': await _search(query, (input['unit'] as String? ?? '').trim()),
          });
        }
        _messages.add({'role': 'user', 'content': results});
        continue;
      }
      if (stopReason == 'refusal') {
        return ChatEntry.assistant('Maaf, pertanyaan ini tidak bisa dijawab oleh AI.', failed: true);
      }
      return _answer(content);
    }
    return ChatEntry.assistant(
      'AI belum menemukan jawabannya di manual yang terunduh. Coba tanyakan dengan lebih spesifik.',
      failed: true,
    );
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await client
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              if (_aiToken.isNotEmpty) 'authorization': 'Bearer $_aiToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
    } on Exception {
      throw AiException('Tidak bisa terhubung ke AI. Periksa sinyal internet.');
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      data = null;
    }
    if (response.statusCode != 200 || data == null) {
      throw AiException(data?['message'] as String? ?? 'AI sedang bermasalah (kode ${response.statusCode}).');
    }
    return data;
  }

  /// Runs the AI's search on the phone's own indexes and formats the pages,
  /// each under a source id the answer can cite.
  Future<String> _search(String query, String unit) async {
    final all = store.searchableIndexes();
    final wanted = _normalize(unit);
    final indexes = wanted.isEmpty
        ? all
        : {
            for (final e in all.entries)
              if (_normalize(store.unitNameOf(store.localManual(e.key)!.file)).contains(wanted) ||
                  _normalize(e.key.split('/').first).contains(wanted))
                e.key: e.value,
          };
    final pages = await Isolate.run(() => searchPageTextsSync(indexes.isEmpty ? all : indexes, query));
    if (pages.isEmpty) return 'No matching pages for "$query".';

    final out = StringBuffer();
    for (final p in pages) {
      final manual = store.localManual(p.fileKey)!;
      final id = _sources.length + 1;
      _sources[id] = AiSource(id: id, file: manual.file, unitName: manual.unitName, page: p.page);
      final text = p.text.length > 3000 ? '${p.text.substring(0, 3000)}…' : p.text;
      out
        ..writeln('[S$id] ${manual.unitName} · ${manual.file.title} · page ${p.page}'
            '${p.section == null ? '' : ' · section: ${p.section}'}')
        ..writeln(text)
        ..writeln();
    }
    return out.toString();
  }

  ChatEntry _answer(List<Map<String, dynamic>> content) {
    final raw = content.where((b) => b['type'] == 'text').map((b) => b['text'] as String).join('\n').trim();
    final cited = <AiSource>[];
    final text = raw.replaceAll('**', '').replaceAllMapped(RegExp(r'(\s*)\[S(\d+)\]'), (m) {
      final source = _sources[int.parse(m[2]!)];
      if (source == null) return '';
      if (!cited.contains(source)) cited.add(source);
      return '${m[1]}[${cited.indexOf(source) + 1}]';
    });
    return ChatEntry.assistant(text.isEmpty ? 'AI tidak memberi jawaban. Coba lagi.' : text,
        sources: cited, failed: text.isEmpty);
  }

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
