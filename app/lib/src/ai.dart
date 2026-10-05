import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'page_image.dart';
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
/// Draws a manual page, or a quarter of it (see [pageRegions]), as a PNG.
typedef PageImage = Future<Uint8List> Function(ManualFile file, int page, String region);

class AiChat {
  AiChat({required this.store, required this.client, Uri? endpoint, PageImage? pageImage})
      : _endpoint = endpoint ?? Uri.parse('$aiUrl/chat'),
        _pageImage = pageImage ?? ((file, page, region) => renderPageImage(store, file, page, region));

  final AppStore store;
  final http.Client client;
  final Uri _endpoint;
  final PageImage _pageImage;

  final List<Map<String, dynamic>> _messages = [];
  final Map<int, AiSource> _sources = {};

  /// Manuals by the id the AI knows them by in this conversation (M1, M2…).
  final Map<String, ManualFile> _manuals = {};

  /// Requests per question: each search or look at a page costs one round.
  static const maxRounds = 6;

  /// Page pictures the AI may look at per question; each is a large request.
  static const maxViews = 4;
  var _views = 0;

  /// Asks [question]; [onStatus] reports what is happening while it works.
  Future<ChatEntry> ask(String question, {void Function(String status)? onStatus}) async {
    _dropOldPictures();
    _views = 0;
    _messages.add({'role': 'user', 'content': question});
    // Every manual on the server can be searched, downloaded or not; manuals
    // that are only pictures (diagrams, scans) can be looked at.
    final files = store.catalog.files.followedBy(store.local.values.map((m) => m.file)).toSet().toList();
    _manuals
      ..clear()
      ..addAll({for (final (i, f) in files.indexed) 'M${i + 1}': f});
    final manuals = [
      for (final MapEntry(key: id, value: f) in _manuals.entries)
        '[$id] ${store.unitNameOf(f)}: ${f.title} (${f.type.label}, ${f.pages} pages'
            '${f.searchable ? '' : ', pictures only: not searchable, use view_page'})',
    ];

    for (var round = 0; round < maxRounds; round++) {
      onStatus?.call(round == 0 ? 'Memahami pertanyaan…' : 'Menyusun jawaban…');
      final response = await _post({
        'messages': _messages,
        'manuals': manuals,
        // Tells the server this app can show the AI manual pages.
        'features': const ['view_page'],
      });
      final message = (response['message'] as Map).cast<String, dynamic>();
      final toolCalls = (message['tool_calls'] as List? ?? const []).cast<Map<String, dynamic>>();
      _messages.add({
        'role': 'assistant',
        'content': message['content'],
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      });

      if (toolCalls.isEmpty) return _answer(message['content'] as String? ?? '');
      final pictures = <Map<String, dynamic>>[];
      for (final call in toolCalls) {
        final function = (call['function'] as Map).cast<String, dynamic>();
        Map<String, dynamic> args;
        try {
          args = (jsonDecode(function['arguments'] as String? ?? '{}') as Map).cast<String, dynamic>();
        } on FormatException {
          args = const {};
        }
        final String content;
        if (function['name'] == 'view_page') {
          content = await _view(args, pictures, onStatus: onStatus);
        } else {
          final query = (args['query'] as String? ?? '').trim();
          content = await _search(query, (args['unit'] as String? ?? '').trim(), onStatus: onStatus);
        }
        _messages.add({'role': 'tool', 'tool_call_id': call['id'], 'content': content});
      }
      // Tool results can only carry text, so the pages the AI asked to see
      // follow as pictures in one message.
      if (pictures.isNotEmpty) {
        _messages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Pictures of the pages requested with view_page:'},
            ...pictures,
          ],
        });
      }
    }
    return ChatEntry.assistant(
      'AI belum menemukan jawabannya di manual. Coba tanyakan dengan lebih spesifik.',
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
  Future<String> _search(String query, String unit, {void Function(String status)? onStatus}) async {
    final wanted = _normalize(unit);
    bool ofUnit(ManualFile f) =>
        _normalize(store.unitNameOf(f)).contains(wanted) || _normalize(f.unitId).contains(wanted);
    // A question about one unit fetches that unit's missing indexes (a few
    // files). Otherwise only indexes already on the phone are searched, so a
    // question never waits for every manual's index to download.
    var indexes = <String, String>{};
    var searchable = 0;
    if (wanted.isNotEmpty) {
      indexes = await store.aiIndexes(where: ofUnit, onStatus: onStatus);
      searchable = store.catalog.files.where((f) => f.searchable && ofUnit(f)).length;
    }
    if (indexes.isEmpty) {
      indexes = await store.aiIndexes(fetch: false);
      searchable = store.catalog.files.where((f) => f.searchable).length;
    }
    final notReady = searchable - indexes.length;
    final note = notReady > 0
        ? 'Note: $notReady manual(s) are still being prepared on the phone and were not searched.\n\n'
        : '';
    onStatus?.call('Mencari di manual: $query');
    final pages = await _searchInBackground(indexes, query);
    if (pages.isEmpty) return '${note}No matching pages for "$query".';

    final out = StringBuffer(note);
    for (final p in pages) {
      final file = store.fileByKey(p.fileKey)!;
      final unitName = store.unitNameOf(file);
      final id = _sources.length + 1;
      _sources[id] = AiSource(id: id, file: file, unitName: unitName, page: p.page);
      // Kept short: free tiers limit tokens per minute.
      final text = p.text.length > 1200 ? '${p.text.substring(0, 1200)}…' : p.text;
      out
        ..writeln('[S$id] $unitName · ${file.title} · page ${p.page}'
            '${p.section == null ? '' : ' · section: ${p.section}'}')
        ..writeln(text)
        ..writeln();
    }
    return out.toString();
  }

  /// Runs the search on another isolate so the chat stays smooth. Static on
  /// purpose: a closure made inside an instance method also carries `this`
  /// (the chat and its HTTP client), which can't be sent to an isolate.
  static Future<List<PageText>> _searchInBackground(Map<String, String> indexes, String query) =>
      Isolate.run(() => searchPageTextsSync(indexes, query, limit: 4));

  /// Looks up the page the AI asked to see and draws it; the picture goes
  /// into [pictures], and the returned text tells the AI its source id.
  Future<String> _view(Map<String, dynamic> args, List<Map<String, dynamic>> pictures,
      {void Function(String status)? onStatus}) async {
    final source = RegExp(r'^\[?S(\d+)\]?$').firstMatch((args['source'] as String? ?? '').trim());
    final known = source == null ? null : _sources[int.parse(source[1]!)];
    ManualFile? file;
    int? page;
    if (known != null) {
      file = known.file;
      page = known.page;
    } else {
      file = _manuals[(args['manual'] as String? ?? '').replaceAll(RegExp(r'[\[\]\s]'), '').toUpperCase()];
      page = (args['page'] as num?)?.toInt();
    }
    if (file == null || page == null || page < 1 || page > file.pages) {
      return 'No such page. Give a source id like "S3", or a manual id like "M2" with a page number from 1 '
          'to the page count shown in the manual list.';
    }
    if (_views >= maxViews) {
      return 'No more pictures for this question; answer with what you have seen.';
    }
    _views++;
    final region = pageRegions.contains(args['region']) ? args['region'] as String : 'full';
    final unitName = store.unitNameOf(file);
    onStatus?.call('Melihat gambar: $unitName · ${file.title} · hlm $page');
    final Uint8List png;
    try {
      png = await _pageImage(file, page, region);
    } on Object catch (e) {
      return 'The page could not be opened ($e). The phone may be offline and the manual not downloaded.';
    }
    final id = _sources.length + 1;
    _sources[id] = AiSource(id: id, file: file, unitName: unitName, page: page);
    final label = '[S$id] $unitName · ${file.title} · page $page${region == 'full' ? '' : ' ($region part)'}';
    pictures
      ..add({'type': 'text', 'text': label})
      ..add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'},
      });
    return 'The picture of $label is attached in the next message.';
  }

  /// Page pictures from earlier questions are dropped from the history (they
  /// are large); the AI can ask to see a page again.
  void _dropOldPictures() {
    for (final (i, m) in _messages.indexed) {
      if (m['role'] == 'user' && m['content'] is List) {
        _messages[i] = {
          'role': 'user',
          'content': 'Page pictures were shown here; they are no longer attached. '
              'Call view_page again to look at a page.',
        };
      }
    }
  }

  ChatEntry _answer(String content) {
    final cited = <AiSource>[];
    final pictures = <AiSource>[];
    // Some models cite as 【S3】 or 【S3†L4-L9】; read those as [S3].
    content = content.replaceAllMapped(
        RegExp(r'【\s*(Gambar\s+)?S(\d+)[^】]*】'), (m) => '[${m[1] ?? ''}S${m[2]}]');
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

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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
