import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'search.dart';
import 'store.dart';

/// Address of the Worker in ai-worker/, which holds the AI provider's API key.
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

/// A conversation with the AI. The Worker is stateless: the full history, in
/// the OpenAI-style chat format, including the AI's tool calls and the pages
/// found, is kept here and sent on every request.
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
      final message = (response['message'] as Map).cast<String, dynamic>();
      final toolCalls = (message['tool_calls'] as List? ?? const []).cast<Map<String, dynamic>>();
      _messages.add({
        'role': 'assistant',
        'content': message['content'],
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      });

      if (toolCalls.isEmpty) return _answer(message['content'] as String? ?? '');
      for (final call in toolCalls) {
        final function = (call['function'] as Map).cast<String, dynamic>();
        Map<String, dynamic> args;
        try {
          args = (jsonDecode(function['arguments'] as String? ?? '{}') as Map).cast<String, dynamic>();
        } on FormatException {
          args = const {};
        }
        final query = (args['query'] as String? ?? '').trim();
        onStatus?.call('Mencari di manual: $query');
        _messages.add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'content': await _search(query, (args['unit'] as String? ?? '').trim()),
        });
      }
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
    final pages = await Isolate.run(() => searchPageTextsSync(indexes.isEmpty ? all : indexes, query, limit: 5));
    if (pages.isEmpty) return 'No matching pages for "$query".';

    final out = StringBuffer();
    for (final p in pages) {
      final manual = store.localManual(p.fileKey)!;
      final id = _sources.length + 1;
      _sources[id] = AiSource(id: id, file: manual.file, unitName: manual.unitName, page: p.page);
      // Kept short: free tiers limit tokens per minute.
      final text = p.text.length > 1800 ? '${p.text.substring(0, 1800)}…' : p.text;
      out
        ..writeln('[S$id] ${manual.unitName} · ${manual.file.title} · page ${p.page}'
            '${p.section == null ? '' : ' · section: ${p.section}'}')
        ..writeln(text)
        ..writeln();
    }
    return out.toString();
  }

  ChatEntry _answer(String content) {
    final raw = content.trim();
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
