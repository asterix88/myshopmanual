import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
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
        pictures = const [],
        failed = false;
  ChatEntry.assistant(this.text, {this.sources = const [], this.pictures = const [], this.failed = false})
      : fromUser = false;

  final bool fromUser;
  final String text;

  /// Pages cited in [text], in order of first citation.
  final List<AiSource> sources;

  /// Pages whose picture (a component drawing, diagram or parts figure) the
  /// AI chose to show with the answer.
  final List<AiSource> pictures;
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

  /// Asks [question]. The AI server searches the manuals and may take a
  /// while; [onStatus] says so.
  Future<ChatEntry> ask(String question, {void Function(String status)? onStatus}) async {
    _messages.add({'role': 'user', 'content': question});
    onStatus?.call('Mencari di manual dan menyusun jawaban…');
    final Map<String, dynamic> response;
    try {
      response = await _post({'messages': _messages, 'source_start': _sources.length + 1});
    } on AiException {
      _messages.removeLast();
      rethrow;
    }
    final added = (response['messages'] as List? ?? const []).cast<Map<String, dynamic>>();
    _messages.addAll(added);
    for (final s in (response['sources'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final file = store.fileByKey(s['key'] as String? ?? '');
      final id = s['id'] as int?;
      if (file == null || id == null) continue;
      _sources[id] = AiSource(id: id, file: file, unitName: store.unitNameOf(file), page: s['page'] as int);
    }
    final last = added.isEmpty ? null : added.last;
    if (last == null || last['role'] != 'assistant' || (last['tool_calls'] as List?)?.isNotEmpty == true) {
      return ChatEntry.assistant(
        'AI belum menemukan jawabannya di manual. Coba tanyakan dengan lebih spesifik.',
        failed: true,
      );
    }
    return _answer(last['content'] as String? ?? '');
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

  ChatEntry _answer(String content) {
    final cited = <AiSource>[];
    final pictures = <AiSource>[];
    // [Gambar S3] asks for page S3 to be shown as a picture under the answer.
    final raw = content.trim().replaceAllMapped(RegExp(r'[ \t]*\[Gambar\s+S(\d+)\]'), (m) {
      final source = _sources[int.parse(m[1]!)];
      if (source != null && !pictures.contains(source) && pictures.length < 3) pictures.add(source);
      return '';
    }).trim();
    final text = raw.replaceAllMapped(RegExp(r'(\s*)\[S(\d+)\]'), (m) {
      final source = _sources[int.parse(m[2]!)];
      if (source == null) return '';
      if (!cited.contains(source)) cited.add(source);
      return '${m[1]}[${cited.indexOf(source) + 1}]';
    });
    for (final source in pictures) {
      if (!cited.contains(source)) cited.add(source);
    }
    return ChatEntry.assistant(text.isEmpty ? 'AI tidak memberi jawaban. Coba lagi.' : text,
        sources: cited, pictures: pictures, failed: text.isEmpty);
  }

}

/// Splits [text] into plain and bold runs: the AI marks emphasis Markdown-style
/// with `**bold**` or `*bold*`, which the chat shows as bold without the stars.
List<({String text, bool bold})> boldRuns(String text) {
  final runs = <({String text, bool bold})>[];
  var last = 0;
  for (final m in RegExp(r'\*\*(.+?)\*\*|\*(?=\S)([^*\n]+?)(?<=\S)\*').allMatches(text)) {
    if (m.start > last) runs.add((text: text.substring(last, m.start), bold: false));
    runs.add((text: m[1] ?? m[2]!, bold: true));
    last = m.end;
  }
  if (last < text.length) runs.add((text: text.substring(last), bold: false));
  return runs;
}
