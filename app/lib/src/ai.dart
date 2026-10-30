import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'diagnostics.dart';
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

  Map<String, dynamic> toJson() => {'id': id, 'file': file.key, 'unit': unitName, 'page': page};

  /// Null when the manual is no longer on the server or the phone.
  static AiSource? fromJson(AppStore store, Map<String, dynamic> json) {
    final file = store.fileByKey(json['file'] as String? ?? '');
    if (file == null) return null;
    return AiSource(id: json['id'] as int, file: file, unitName: json['unit'] as String, page: json['page'] as int);
  }
}

/// What the user sees of one exchange.
class ChatEntry {
  ChatEntry.user(this.text, {this.page})
      : fromUser = true,
        sources = const [],
        pictures = const [],
        failed = false;
  ChatEntry.assistant(this.text, {this.sources = const [], this.pictures = const [], this.failed = false})
      : fromUser = false,
        page = null;

  final bool fromUser;
  final String text;

  /// The manual page the question was asked about (from the viewer's nyel AI
  /// button), shown above the question.
  final AiSource? page;

  /// Pages cited in [text], in order of first citation.
  final List<AiSource> sources;

  /// Pages whose picture (a component drawing, diagram or parts figure) the
  /// AI chose to show with the answer.
  final List<AiSource> pictures;
  final bool failed;

  /// How the mechanic rated this answer: 'good' (👍) or 'bad' (👎, "Jawaban
  /// salah"); null when not rated.
  String? rating;

  Map<String, dynamic> toJson() => {
        'user': fromUser,
        'text': text,
        if (page != null) 'page': page!.toJson(),
        if (sources.isNotEmpty) 'sources': [for (final s in sources) s.toJson()],
        if (pictures.isNotEmpty) 'pictures': [for (final s in pictures) s.toJson()],
        if (failed) 'failed': true,
        if (rating != null) 'rating': rating,
      };

  static ChatEntry fromJson(AppStore store, Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    if (json['user'] == true) {
      final page = json['page'];
      return ChatEntry.user(text,
          page: page is Map ? AiSource.fromJson(store, page.cast<String, dynamic>()) : null);
    }
    List<AiSource> list(String key) => [
          for (final s in (json[key] as List? ?? const [])) ?AiSource.fromJson(store, (s as Map).cast<String, dynamic>()),
        ];
    return ChatEntry.assistant(text,
        sources: list('sources'), pictures: list('pictures'), failed: json['failed'] == true)
      // Versions before 👍 kept only 'reported' for a 👎.
      ..rating = json['rating'] as String? ?? (json['reported'] == true ? 'bad' : null);
  }

  /// Parts of the answer come from the AI's general knowledge rather than a
  /// manual page: it says so ("Secara umum", "pengetahuan umum") or cites no
  /// page at all.
  bool get hasUncheckedParts =>
      !fromUser &&
      !failed &&
      (sources.isEmpty || RegExp(r'secara umum|pengetahuan umum|nilai umum', caseSensitive: false).hasMatch(text));
}

/// A rated answer (👍 or 👎), as admins see it.
class AnswerReport {
  AnswerReport({
    required this.good,
    required this.at,
    required this.name,
    required this.nrp,
    required this.question,
    required this.answer,
    required this.sources,
    required this.note,
  });

  factory AnswerReport.fromJson(Map<String, dynamic> json) => AnswerReport(
        good: json['rating'] == 'good',
        at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num?)?.toInt() ?? 0),
        name: json['name'] as String? ?? '',
        nrp: json['nrp'] as String? ?? '',
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        sources: [for (final s in json['sources'] as List? ?? const []) '$s'],
        note: json['note'] as String? ?? '',
      );

  /// 👍; otherwise 👎 "Jawaban salah".
  final bool good;
  final DateTime at;
  final String name;
  final String nrp;
  final String question;
  final String answer;
  final List<String> sources;
  final String note;
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

/// Finds the large drawing sheets of a manual (see [findLargeSheets]).
typedef LargeSheets = Future<List<int>> Function(ManualFile file);

class AiChat {
  AiChat({
    required this.store,
    required this.client,
    Uri? endpoint,
    PageImage? pageImage,
    LargeSheets? largeSheets,
  })  : _endpoint = endpoint ?? Uri.parse('$aiUrl/chat'),
        _pageImage = pageImage ?? ((file, page, region) => renderPageImage(store, file, page, region)),
        _largeSheets = largeSheets ?? ((file) => findLargeSheets(store, file));

  final AppStore store;
  final http.Client client;
  final Uri _endpoint;
  final PageImage _pageImage;
  final LargeSheets _largeSheets;

  /// Large drawing sheets per manual, found the first time the AI looks at it.
  final Map<String, List<int>> _sheets = {};

  final List<Map<String, dynamic>> _messages = [];
  final Map<int, AiSource> _sources = {};

  /// Manuals by the id the AI knows them by in this conversation (M1, M2…).
  final Map<String, ManualFile> _manuals = {};

  /// Requests per question: each search or look at a page costs one round.
  static const maxRounds = 4;

  /// Page pictures the AI may look at per question; each is a large request.
  static const maxViews = 6;
  var _views = 0;

  /// Asks [question]; [onStatus] reports what is happening while it works.
  /// With [file] and [page] the question is about that manual page (the one
  /// open in the viewer): its text goes with the question.
  Future<ChatEntry> ask(
    String question, {
    ManualFile? file,
    int? page,
    void Function(String status)? onStatus,
  }) async {
    if (store.aiQuestionsLeft == 0) {
      throw AiException('Jatah ${AppStore.aiDailyLimit} pertanyaan hari ini sudah habis. Coba lagi besok.');
    }
    _dropOldPictures();
    _dropOldReasoning();
    _keepRecentQuestions();
    _views = 0;
    final content = file != null && page != null
        ? await _aboutPage(_sourceFor(file, page), question, onStatus: onStatus)
        : question;
    _messages.add({'role': 'user', 'content': content});
    Diagnostics.log('ask (${question.length} chars, ${_messages.length} messages)');
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

    // What the AI searched for, for the usage statistics' topics.
    final queries = <String>[];
    var unit = file?.unitId ?? '';
    for (var round = 0; round < maxRounds; round++) {
      onStatus?.call(round == 0 ? 'Memahami pertanyaan…' : 'Menyusun jawaban…');
      Diagnostics.log('ai round $round');
      final response = await _post({
        'messages': _messages,
        'manuals': manuals,
        // Tells the server this app can show the AI manual pages and sends
        // back the model's reasoning within a question.
        'features': const ['view_page', 'reasoning', 'read_page'],
        // The last round: the server asks for the answer with what was found.
        if (round == maxRounds - 1) 'final': true,
      });
      final message = (response['message'] as Map).cast<String, dynamic>();
      final toolCalls = (message['tool_calls'] as List? ?? const []).cast<Map<String, dynamic>>();
      _messages.add({
        'role': 'assistant',
        'content': message['content'],
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
        // The model's thinking goes back with each round of this question.
        if (message['reasoning_content'] case final String reasoning when reasoning.isNotEmpty)
          'reasoning_content': reasoning,
      });

      if (toolCalls.isEmpty) {
        store.countAiQuestion();
        final answer = _answer(message['content'] as String? ?? '');
        if (!answer.failed) {
          store.usage.asked(
            question: question,
            answer: answer.text,
            sources: [
              for (final s in answer.sources)
                '${switch (s.file.type) {
                  DocType.shopManual => 'SM',
                  DocType.omm => 'OMM',
                  DocType.partsbook => 'PB',
                  DocType.other => s.file.title,
                }} ${s.unitName} · hal. ${s.page}',
            ],
            queries: queries,
            unit: unit,
          );
        }
        return answer;
      }
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
        } else if (function['name'] == 'read_page') {
          content = await _read((args['source'] as String? ?? '').trim(), onStatus: onStatus);
        } else {
          final query = (args['query'] as String? ?? '').trim();
          final searchUnit = (args['unit'] as String? ?? '').trim();
          if (query.isNotEmpty) queries.add(query);
          if (unit.isEmpty) unit = searchUnit;
          content = await _search(query, searchUnit, onStatus: onStatus);
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
    store.countAiQuestion();
    return ChatEntry.assistant(
      'AI belum menemukan jawabannya di manual. Coba tanyakan dengan lebih spesifik.',
      failed: true,
    );
  }

  /// Sends the mechanic's rating of an answer, 'good' (👍) or 'bad' (👎,
  /// "Jawaban salah"): the question, the answer and the pages it cited, with
  /// what the mechanic says is wrong.
  Future<void> report({
    required String question,
    required ChatEntry answer,
    String rating = 'bad',
    String note = '',
  }) async {
    await _post({
      'rating': rating,
      'question': question,
      'answer': withoutSourceNumbers(answer.text),
      'sources': [for (final s in answer.sources) '${s.unitName} · ${s.file.title} · hlm ${s.page}'],
      'note': note,
    }, to: _endpoint.replace(path: '/feedback'));
  }

  /// The newest answer ratings (admins only).
  Future<List<AnswerReport>> reports() async {
    final data = await _post(null, to: _endpoint.replace(path: '/feedback'));
    return [
      for (final r in data['reports'] as List? ?? const []) AnswerReport.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  /// POSTs [body] to the chat (or [to]); a null body is a GET.
  Future<Map<String, dynamic>> _post(Map<String, dynamic>? body, {Uri? to, bool renewed = false}) async {
    final session = store.session;
    final url = to ?? _endpoint;
    final headers = {
      'content-type': 'application/json',
      if (_aiToken.isNotEmpty) 'authorization': 'Bearer $_aiToken',
      if (session != null) sessionHeader: session.token,
    };
    final http.Response response;
    try {
      response = await (body == null
              ? client.get(url, headers: headers)
              : client.post(url, headers: headers, body: jsonEncode(body)))
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
    // The server takes a session for a day; swap it and ask again.
    if (response.statusCode == 401 && session != null && !renewed) {
      if (await store.renewSession() != null) return _post(body, to: to, renewed: true);
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
    Diagnostics.log('search "$query" in ${indexes.length} indexes');
    final pages = await _searchInBackground(indexes, query);
    if (pages.isEmpty) return '${note}No matching pages for "$query".';

    final out = StringBuffer(note);
    for (final p in pages) {
      final file = store.fileByKey(p.fileKey)!;
      final unitName = store.unitNameOf(file);
      final id = _nextSourceId();
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
    // Looking at a part of a page already seen keeps the same source id, so
    // the answer cites and shows that page once.
    final seen = _sources.values.where((s) => s.file.key == file!.key && s.page == page).firstOrNull;
    final id = seen?.id ?? _nextSourceId();
    _sources[id] ??= AiSource(id: id, file: file, unitName: unitName, page: page);
    final label = '[S$id] $unitName · ${file.title} · page $page${region == 'full' ? '' : ' ($region part)'}';
    pictures
      ..add({'type': 'text', 'text': label})
      ..add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'},
      });
    return 'The picture of $label is attached in the next message.${await _sheetHint(file)}';
  }

  /// The source id of [page] of [file], the one it already has if the AI saw it.
  AiSource _sourceFor(ManualFile file, int page) {
    final seen = _sources.values.where((s) => s.file.key == file.key && s.page == page).firstOrNull;
    if (seen != null) return seen;
    final id = _nextSourceId();
    return _sources[id] = AiSource(id: id, file: file, unitName: store.unitNameOf(file), page: page);
  }

  /// Longest page text sent with a question; a full page of a manual is
  /// usually well under this.
  static const maxPageText = 6000;

  /// [question] with the page it is about: the page's text from the manual's
  /// index, so "translate this page" works without looking at a picture.
  Future<String> _aboutPage(AiSource source, String question, {void Function(String status)? onStatus}) async {
    final file = source.file;
    ({String text, String? section})? found;
    if (file.searchable) {
      onStatus?.call('Membaca halaman ${source.page}…');
      final indexes = await store.aiIndexes(where: (f) => f.key == file.key, onStatus: onStatus);
      final path = indexes[file.key];
      if (path != null) found = await _pageTextInBackground(path, source.page);
    }
    final text = found == null
        ? null
        : found.text.length > maxPageText
            ? '${found.text.substring(0, maxPageText)}…'
            : found.text;
    final label = '[S${source.id}] ${source.unitName} · ${file.title} · page ${source.page}'
        '${found?.section == null ? '' : ' · section: ${found!.section}'}';
    return [
      'The user is reading this manual page in the app and asks about it ("this page" / "halaman ini" means it): '
          '$label',
      if (text != null) ...[
        'Text of the page:\n$text',
        'For drawings or tables the text does not show well, call view_page with source "S${source.id}".',
      ] else
        'This page has no readable text; call view_page with source "S${source.id}" to look at it.',
      'Question: $question',
    ].join('\n\n');
  }

  /// The whole text of a page search found ([source] like "S3"), for tables
  /// that go on past the start search shows.
  Future<String> _read(String source, {void Function(String status)? onStatus}) async {
    final id = RegExp(r'^\[?S(\d+)\]?$').firstMatch(source);
    final known = id == null ? null : _sources[int.parse(id[1]!)];
    if (known == null) return 'Unknown source "$source". Use a source id from the search results.';
    if (!known.file.searchable) return 'This manual has no text; use view_page.';
    onStatus?.call('Membaca halaman ${known.page}…');
    final indexes = await store.aiIndexes(where: (f) => f.key == known.file.key, onStatus: onStatus);
    final path = indexes[known.file.key];
    final found = path == null ? null : await _pageTextInBackground(path, known.page);
    if (found == null) return 'The text of this page could not be read; use view_page.';
    final text = found.text.length > maxPageText ? '${found.text.substring(0, maxPageText)}…' : found.text;
    return '[S${known.id}] ${known.unitName} · ${known.file.title} · page ${known.page}'
        '${found.section == null ? '' : ' · section: ${found.section}'}\n$text';
  }

  static Future<({String text, String? section})?> _pageTextInBackground(String path, int page) =>
      Isolate.run(() => pageTextSync(path, page));

  /// Tells the AI which pages of [file] are large drawing sheets, so after
  /// one look it can go straight to the drawing.
  Future<String> _sheetHint(ManualFile file) async {
    final sheets = _sheets[file.key] ??= await _largeSheets(file).catchError((Object _) => const <int>[]);
    if (sheets.isEmpty) return '';
    final shown = sheets.take(40).join(', ');
    return ' In this manual, pages $shown${sheets.length > 40 ? ' and more' : ''} are large drawing sheets '
        '(much bigger than its other pages).';
  }

  /// Questions the AI still sees from earlier in the conversation. The whole
  /// history is sent with every question, so keeping it short keeps answers
  /// fast and the AI bill small even when the chat is kept for days.
  static const rememberedQuestions = 5;

  void _keepRecentQuestions() {
    final starts = [
      for (final (i, m) in _messages.indexed)
        if (m['role'] == 'user' && m['content'] is String && !(m['content'] as String).startsWith('Page pictures')) i,
    ];
    if (starts.length < rememberedQuestions) return;
    _messages.removeRange(0, starts[starts.length - rememberedQuestions + 1]);
    // Pages only the forgotten questions used are not needed any more.
    final used = {
      for (final m in _messages)
        for (final match in RegExp(r'S(\d+)').allMatches(jsonEncode(m['content'] ?? ''))) int.parse(match[1]!),
    };
    _sources.removeWhere((id, _) => !used.contains(id));
  }

  int _nextSourceId() => _sources.keys.fold(0, (a, b) => a > b ? a : b) + 1;

  /// Most chat bubbles kept on the phone; older ones are dropped.
  static const keptEntries = 60;

  /// Saves [entries] (what the chat shows) and what the AI needs to carry on,
  /// so the conversation is still there the next time the app opens.
  Future<void> save(List<ChatEntry> entries) async {
    _dropOldPictures();
    _dropOldReasoning();
    final file = File(store.chatHistoryPath);
    final json = jsonEncode({
      'entries': [for (final e in entries.skip(entries.length > keptEntries ? entries.length - keptEntries : 0)) e.toJson()],
      'messages': _messages,
      'sources': [for (final s in _sources.values) s.toJson()],
    });
    final part = File('${file.path}.part');
    await part.writeAsString(json);
    await part.rename(file.path);
    _changed();
  }

  /// [AppStore.chatRevision] when this chat last loaded or saved the
  /// conversation; another chat screen saving makes them differ.
  int revision = -1;

  /// Tells other chat screens (the nyel AI tab and the one opened from a
  /// manual page share one conversation) that it changed.
  void _changed() {
    store.chatChanged();
    revision = store.chatRevision;
  }

  /// Loads the saved conversation; returns the chat bubbles to show.
  Future<List<ChatEntry>> load() async {
    revision = store.chatRevision;
    final file = File(store.chatHistoryPath);
    try {
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _messages
        ..clear()
        ..addAll([for (final m in json['messages'] as List? ?? const []) (m as Map).cast<String, dynamic>()]);
      final sources = [
        for (final s in json['sources'] as List? ?? const []) ?AiSource.fromJson(store, (s as Map).cast<String, dynamic>()),
      ];
      _sources
        ..clear()
        ..addAll({for (final source in sources) source.id: source});
      return [
        for (final e in json['entries'] as List? ?? const []) ChatEntry.fromJson(store, (e as Map).cast<String, dynamic>()),
      ];
    } on Object catch (e) {
      // A damaged history starts a new conversation rather than breaking the tab.
      Diagnostics.log('chat history unreadable: $e');
      return [];
    }
  }

  /// Forgets the conversation, on the phone too.
  Future<void> clear() async {
    _messages.clear();
    _sources.clear();
    final file = File(store.chatHistoryPath);
    if (await file.exists()) await file.delete();
    _changed();
  }

  /// The model's thinking is only needed within its own question, and it is
  /// long, so it is not kept after the answer.
  void _dropOldReasoning() {
    for (final m in _messages) {
      m.remove('reasoning_content');
    }
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
    // [S3] (or [S3, S5]) marks where a fact came from: the page joins the
    // sources under the answer and the mark leaves the text, which reads
    // cleaner without numbers in it.
    final text = raw.replaceAllMapped(RegExp(r'[ \t]*\[(S\d+(?:\s*,\s*S?\d+)*)\]'), (m) {
      for (final id in RegExp(r'\d+').allMatches(m[1]!)) {
        final source = _sources[int.parse(id[0]!)];
        if (source != null && !cited.contains(source)) cited.add(source);
      }
      return '';
    }).trim();
    for (final source in pictures) {
      if (!cited.contains(source)) cited.add(source);
    }
    return ChatEntry.assistant(text.isEmpty ? 'AI tidak memberi jawaban. Coba lagi.' : text,
        sources: cited, pictures: pictures, failed: text.isEmpty);
  }

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// [text] without the [1], [2] source numbers older answers carried.
String withoutSourceNumbers(String text) =>
    text.replaceAll(RegExp(r'[ \t]*\[\d{1,2}(?:\s*,\s*\d{1,2})*\](?=[\s.,;:)!?]|$)'), '');

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
