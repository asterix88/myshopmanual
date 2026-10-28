import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai.dart';
import '../models.dart';
import '../page_image.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// nyel AI: answers from the manuals downloaded on the phone, citing the
/// pages it used. Needs internet; the search itself runs on the phone.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.client, this.file, this.page});

  /// For tests; the app uses a plain [http.Client].
  final http.Client? client;

  /// The manual page open in the viewer when nyel AI was opened from it: the
  /// next question is about that page. The chat then opens over the viewer,
  /// so going back returns to the page.
  final ManualFile? file;
  final int? page;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final AiChat _chat = AiChat(store: StoreScope.read(context), client: _client);
  final List<ChatEntry> _entries = [];

  /// The page the next question is about, until it is sent or taken off.
  late ManualFile? _file = widget.file;
  late final int? _page = widget.page;

  static const _pageSuggestions = ['Terjemahkan halaman ini', 'Jelaskan halaman ini', 'Ringkas langkah kerjanya'];

  /// Messages sent or answered while the chat is open: they pop in, like in
  /// WhatsApp. Earlier ones loaded from the phone just appear.
  final _fresh = <ChatEntry>{};
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    // The conversation is kept on the phone, so it carries on after a restart.
    _chat.load().then((entries) {
      if (!mounted || entries.isEmpty || _entries.isNotEmpty) return;
      setState(() => _entries.addAll(entries));
      _scrollToEnd();
    });
  }

  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _status;

  // Search in the conversation: the bubbles holding the words, and the one
  // shown now (counted from the newest, like a chat app).
  bool _searching = false;
  final _searchInput = TextEditingController();
  List<int> _hits = const [];
  int _hit = 0;
  final _bubbleKeys = <GlobalKey>[];

  static const _examples = [
    'Lampu hydraulic oil filter clogging menyala, apa yang harus dilakukan?',
    'Berapa tekanan relief main valve PC210?',
    'Interval penggantian oli engine D85?',
  ];

  // The daily count starts again at midnight: redraw then, in case the
  // chat stays open across it.
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    if (widget.client == null) _client.close();
    _input.dispose();
    _searchInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final question = (text ?? _input.text).trim();
    if (question.isEmpty || _status != null) return;
    if (StoreScope.read(context).aiQuestionsLeft == 0) return;
    final chat = _chat;
    final store = StoreScope.read(context);
    final file = _file;
    final page = _page;
    _input.clear();
    setState(() {
      _file = null;
      final entry = ChatEntry.user(
        question,
        page: file == null || page == null
            ? null
            : AiSource(id: 0, file: file, unitName: store.unitNameOf(file), page: page),
      );
      _fresh.add(entry);
      _entries.add(entry);
      _status = 'Memahami pertanyaan…';
    });
    _scrollToEnd();
    ChatEntry answer;
    try {
      answer = await chat.ask(
        question,
        file: file,
        page: page,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
    } on AiException catch (e) {
      answer = ChatEntry.assistant(e.message, failed: true);
    } catch (e, stack) {
      // Never leave the chat stuck on its status line.
      debugPrint('nyel AI failed: $e\n$stack');
      answer = ChatEntry.assistant('Terjadi kesalahan di aplikasi saat mencari jawaban. Coba lagi.', failed: true);
    }
    if (!mounted) return;
    setState(() {
      _fresh.add(answer);
      _entries.add(answer);
      _status = null;
    });
    _scrollToEnd();
    try {
      await chat.save(_entries);
    } on Object catch (e) {
      debugPrint('saving the chat failed: $e');
    }
  }

  /// 👍 sends the rating straight away; 👎 "Jawaban salah" first asks what is
  /// wrong. Both go to the admins with the question and the answer.
  Future<void> _rate(int index, {required bool good}) async {
    final entry = _entries[index];
    final question = _entries.take(index).lastWhere((e) => e.fromUser, orElse: () => ChatEntry.user('')).text;
    var text = '';
    if (!good) {
      final note = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          title: const Text('Jawaban salah?'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Jawaban ini dikirim ke admin untuk diperiksa dan dipakai memperbaiki nyel AI.'),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Apa yang salah? (boleh kosong)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kirim'),
            ),
          ],
        ),
      );
      text = note.text.trim();
      note.dispose();
      if (ok != true || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _chat.report(question: question, answer: entry, rating: good ? 'good' : 'bad', note: text);
      if (!mounted) return;
      setState(() => entry.rating = good ? 'good' : 'bad');
      messenger.showSnackBar(SnackBar(
        content: Text(good ? 'Terima kasih atas penilaiannya.' : 'Terima kasih, laporan terkirim ke admin.'),
      ));
      await _chat.save(_entries);
    } on AiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      debugPrint('rating failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Penilaian belum terkirim. Coba lagi.')));
    }
  }

  void _newChat() {
    setState(_entries.clear);
    _closeSearch();
    _chat.clear();
  }

  String get _query => _searchInput.text.trim();

  void _closeSearch() {
    _searchInput.clear();
    setState(() {
      _searching = false;
      _hits = const [];
    });
  }

  void _findHits() {
    final query = _query.toLowerCase();
    setState(() {
      _hits = query.isEmpty
          ? const []
          : [
              for (final (i, e) in _entries.indexed)
                if (e.text.toLowerCase().contains(query)) i,
            ];
      _hit = _hits.length - 1;
    });
    _showHit();
  }

  void _moveHit(int step) {
    if (_hits.isEmpty) return;
    setState(() => _hit = (_hit + step).clamp(0, _hits.length - 1));
    _showHit();
  }

  void _showHit() {
    if (_hits.isEmpty) return;
    final index = _hits[_hit];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = index < _bubbleKeys.length ? _bubbleKeys[index].currentContext : null;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: 0.1, duration: const Duration(milliseconds: 250));
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        // The list is anchored at the bottom (reverse), so 0 is the newest.
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  GlobalKey _bubbleKey(int i) {
    while (_bubbleKeys.length <= i) {
      _bubbleKeys.add(GlobalKey());
    }
    return _bubbleKeys[i];
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.pendingAiQuestion != null) {
      // "Tanya nyel AI" on a page: put the question in the box to edit or send.
      final question = store.takeAiQuestion()!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _input.value = TextEditingValue(
          text: question,
          selection: TextSelection.collapsed(offset: question.length),
        );
      });
    }
    // The other chat screen (the tab, or one opened from a manual page)
    // changed the conversation: show it as saved.
    if (_chat.revision >= 0 && _chat.revision != store.chatRevision && _status == null) {
      _chat.load().then((entries) {
        if (!mounted) return;
        setState(() {
          _entries
            ..clear()
            ..addAll(entries);
          _fresh.clear();
        });
        _scrollToEnd();
      });
    }
    final offline = store.online == false;
    final aboutPage = _file != null && _page != null;
    final hasManuals = store.catalog.files.isNotEmpty || store.local.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: Border(bottom: BorderSide(color: AppColors.line)),
        title: _searching
            ? TextField(
                controller: _searchInput,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _findHits(),
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Cari di obrolan…',
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : Row(
                children: [
                  Image.asset('assets/images/logo.png', width: 42, height: 42),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'nyel AI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
                      ),
                      Text(
                        'Teman diskusi masalah teknismu :)',
                        style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ],
              ),
        actions: [
          if (_searching) ...[
            if (_query.isNotEmpty)
              Center(
                child: Text(
                  _hits.isEmpty ? '0' : '${_hits.length - _hit}/${_hits.length}',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ),
            IconButton(
              tooltip: 'Lebih lama',
              onPressed: _hits.isNotEmpty && _hit > 0 ? () => _moveHit(-1) : null,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Lebih baru',
              onPressed: _hits.isNotEmpty && _hit < _hits.length - 1 ? () => _moveHit(1) : null,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(tooltip: 'Tutup pencarian', onPressed: _closeSearch, icon: const Icon(Icons.close)),
          ] else if (_entries.isNotEmpty) ...[
            IconButton(
              tooltip: 'Cari di obrolan',
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'Percakapan baru',
              onPressed: _status == null ? _newChat : null,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty && aboutPage
                ? const _PageIntro()
                : _entries.isEmpty
                ? _Intro(examples: _examples, hasManuals: hasManuals, onExample: offline ? null : _send)
                // Every bubble is built (the chat keeps at most 60), so a
                // search hit far up can be scrolled to.
                // Reversed like WhatsApp: the view stays at the newest
                // message, so a new one grows in at the bottom and pushes the
                // rest up instead of appearing below the screen.
                : SingleChildScrollView(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, entry) in _entries.indexed)
                          _Bubble(
                            key: _bubbleKey(i),
                            entry: entry,
                            popIn: _fresh.contains(entry),
                            highlight: _searching ? _query : '',
                            current: _searching && _hits.isNotEmpty && _hits[_hit] == i,
                            onRate: entry.fromUser || entry.failed || _status != null ? null : (good) => _rate(i, good: good),
                          ),
                        if (_status != null) _Working(status: _status!),
                      ],
                    ),
                  ),
          ),
          if (store.aiIndexProgress case final p?) _Preparing(progress: p),
          if (store.aiQuestionsLeft case final left?) _QuestionsLeft(left: left),
          if (aboutPage)
            _AttachedPage(
              file: _file!,
              page: _page,
              suggestions: _pageSuggestions,
              onSuggestion: offline || _status != null || store.aiQuestionsLeft == 0 ? null : _send,
              onRemove: () => setState(() => _file = null),
            ),
          _InputBar(
            controller: _input,
            enabled: !offline && _status == null && store.aiQuestionsLeft != 0,
            hint: offline
                ? 'Butuh internet untuk bertanya'
                : store.aiQuestionsLeft == 0
                ? 'Jatah hari ini habis, coba lagi besok'
                : 'Tulis pertanyaan…',
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

/// What the chat shows before the first question about a manual page.
class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Tanya apa saja tentang halaman ini.\nTombol kembali membawa kamu ke halaman manual tadi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
        ),
      ),
    );
  }
}

/// The manual page the next question is about, with ready-made questions.
class _AttachedPage extends StatelessWidget {
  const _AttachedPage({
    required this.file,
    required this.page,
    required this.suggestions,
    required this.onSuggestion,
    required this.onRemove,
  });

  final ManualFile file;
  final int page;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestion;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: AppColors.border),
                        shape: const StadiumBorder(),
                        label: Text(s, style: TextStyle(fontSize: 13, color: AppColors.navy)),
                        onPressed: onSuggestion == null ? null : () => onSuggestion!(s),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 22, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Halaman $page',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
                        ),
                        Text(
                          '${store.unitNameOf(file)} · ${file.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lepas halaman',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How many of today's questions are left on this phone.
class _QuestionsLeft extends StatelessWidget {
  const _QuestionsLeft({required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        left == 0
            ? 'Jatah ${AppStore.aiDailyLimit} pertanyaan hari ini sudah habis.'
            : 'Sisa $left dari ${AppStore.aiDailyLimit} pertanyaan hari ini',
        style: TextStyle(fontSize: 12, color: left == 0 ? AppColors.orangeText : AppColors.muted),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.hasManuals, required this.onExample});

  final List<String> examples;
  final bool hasManuals;
  final ValueChanged<String>? onExample;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: AppIcon(AppGlyph.nyel, size: 30, color: AppColors.orange),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Tanya soal teknis',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Dijawab dari semua manual.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        if (!hasManuals) ...[
          const SizedBox(height: 8),
          Text(
            'Daftar manual belum termuat. Sambungkan ke internet lalu buka tab Home.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.orangeText),
          ),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'CONTOH',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted),
          ),
        ),
        for (final example in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: onExample == null ? null : () => onExample!(example),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(child: Text(example, style: const TextStyle(fontSize: 13))),
                  Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.entry,
    this.popIn = false,
    this.highlight = '',
    this.current = false,
    this.onRate,
  });

  final ChatEntry entry;

  /// Rates the answer 👍 (true) or 👎 (false); null for questions and errors.
  final void Function(bool good)? onRate;

  /// Pops in when first shown (a message just sent or answered).
  final bool popIn;

  /// Words searched for in the conversation, marked in the text.
  final String highlight;

  /// This bubble is the search hit shown now.
  final bool current;

  /// [runs] with every place [highlight] occurs marked.
  List<TextSpan> _spans(List<({String text, bool bold})> runs) {
    final query = highlight.toLowerCase();
    final mark = TextStyle(
      backgroundColor: current ? AppColors.orange : AppColors.highlight,
      color: current ? Colors.white : AppColors.ink,
    );
    return [
      for (final run in runs)
        if (query.isEmpty)
          TextSpan(
            text: run.text,
            style: run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
          )
        else
          TextSpan(
            style: run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
            children: [
              for (final (part, found) in _split(run.text, query)) TextSpan(text: part, style: found ? mark : null),
            ],
          ),
    ];
  }

  static Iterable<(String, bool)> _split(String text, String query) sync* {
    final lower = text.toLowerCase();
    var at = 0;
    while (true) {
      final found = lower.indexOf(query, at);
      if (found < 0) break;
      if (found > at) yield (text.substring(at, found), false);
      yield (text.substring(found, found + query.length), true);
      at = found + query.length;
    }
    if (at < text.length) yield (text.substring(at), false);
  }

  /// The answer laid out in blocks: paragraphs, short titles (a bold line or
  /// one ending in ':'), bullet points and numbered steps with their text
  /// indented, so a long answer reads like a tidy note.
  Widget _answerText(String text) {
    final style = TextStyle(fontSize: 14, height: 1.5, color: entry.failed ? AppColors.danger : AppColors.ink);
    final blocks = <Widget>[];
    var gap = false;
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        gap = true;
        continue;
      }
      final top = blocks.isEmpty ? 0.0 : (gap ? 10.0 : 4.0);
      gap = false;
      final indent = (raw.length - raw.trimLeft().length) >= 2 ? 16.0 : 0.0;
      final bullet = RegExp(r'^\s*[-•*]\s+(.*)$').firstMatch(line);
      final number = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$').firstMatch(line);
      final heading = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(line);
      final plain = line.trim();
      final Widget block;
      if (bullet != null || number != null) {
        block = Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: number != null ? 22 : 16,
                child: Text(
                  number != null ? '${number[1]}.' : '•',
                  style: style.copyWith(fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
              ),
              Expanded(child: Text.rich(TextSpan(children: _spans(boldRuns(bullet?[1] ?? number![2]!))), style: style)),
            ],
          ),
        );
      } else if (heading != null ||
          RegExp(r'^\*\*[^*]+\*\*:?$').hasMatch(plain) ||
          (plain.endsWith(':') && plain.length <= 60)) {
        final title = (heading?[1] ?? plain).replaceAll('**', '');
        block = Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 4),
          child: Text.rich(
            TextSpan(children: _spans([(text: title, bold: true)])),
            style: style.copyWith(color: entry.failed ? AppColors.danger : AppColors.navy),
          ),
        );
      } else {
        block = Text.rich(TextSpan(children: _spans(boldRuns(plain))), style: style);
      }
      blocks.add(Padding(padding: EdgeInsets.only(top: top), child: block));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  @override
  Widget build(BuildContext context) {
    final bubble = _bubble(context);
    return popIn ? _PopIn(fromRight: entry.fromUser, child: bubble) : bubble;
  }

  Widget _bubble(BuildContext context) {
    if (entry.fromUser) {
      final page = entry.page;
      final question = Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
          // Selectable like the answers, so a question can be copied. The
          // usual navy highlight and handles vanish on the navy bubble.
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: AppColors.orange.withAlpha(150),
                selectionHandleColor: AppColors.orange,
                cursorColor: AppColors.orange,
              ),
            ),
            child: DefaultSelectionStyle(
              selectionColor: AppColors.orange.withAlpha(150),
              cursorColor: AppColors.orange,
              child: SelectableText.rich(
                TextSpan(children: _spans([(text: entry.text, bold: false)])),
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
              ),
            ),
          ),
        ),
      );
      if (page == null) return question;
      // The page the question is about, above it like a forwarded message.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.navySoft,
              side: BorderSide.none,
              avatar: AppIcon(docGlyph(page.file), size: 16),
              label: Text(
                '${page.unitName} · ${page.file.type.label} · hlm ${page.page}',
                style: TextStyle(fontSize: 12, color: AppColors.navy),
              ),
              onPressed: () => openViewer(context, page.file, page: page.page),
            ),
          ),
          question,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Manual pages first, like a photo sent with a message; the
            // sources stay under the text.
            for (final picture in entry.pictures) ...[_PagePicture(source: picture), const SizedBox(height: 12)],
            SelectionArea(child: _answerText(withoutSourceNumbers(entry.text))),
            if (entry.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Sumber',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in entry.sources)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.navySoft,
                      side: BorderSide.none,
                      avatar: AppIcon(docGlyph(s.file), size: 16),
                      label: Text(
                        '${s.unitName} · ${s.file.type.label} · hlm ${s.page}',
                        style: TextStyle(fontSize: 12, color: AppColors.navy),
                      ),
                      onPressed: () => openViewer(context, s.file, page: s.page),
                    ),
                ],
              ),
            ],
            if (!entry.failed) _AnswerFooter(entry: entry, onRate: onRate),
          ],
        ),
      ),
    );
  }
}

/// Under an answer: a note when parts of it are not from a manual page, and
/// the 👍 and 👎 "Jawaban salah" buttons.
class _AnswerFooter extends StatelessWidget {
  const _AnswerFooter({required this.entry, required this.onRate});

  final ChatEntry entry;
  final void Function(bool good)? onRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: entry.hasUncheckedParts
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: AppIcon(AppGlyph.info, size: 15, color: AppColors.muted),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sebagian dari pengetahuan umum, belum dicek di manual. Cek manual unit sebelum dipakai.',
                          style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.muted),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (entry.rating case final rating?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(rating == 'good' ? AppGlyph.thumbUp : AppGlyph.thumbDown, size: 15, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    rating == 'good' ? 'Membantu' : 'Dilaporkan',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ),
            )
          else if (onRate case final rate?) ...[
            IconButton(
              tooltip: 'Jawaban membantu',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: AppColors.muted,
              icon: AppIcon(AppGlyph.thumbUp, size: 18, color: AppColors.muted),
              onPressed: () => rate(true),
            ),
            IconButton(
              tooltip: 'Jawaban salah',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: AppColors.muted,
              icon: AppIcon(AppGlyph.thumbDown, size: 18, color: AppColors.muted),
              onPressed: () => rate(false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grows a new message out of its corner of the screen, like WhatsApp.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.fromRight, required this.child});

  final bool fromRight;
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // The space opens up (pushing the older messages up) while the bubble
    // grows out of its bottom corner with a small bounce.
    return SizeTransition(
      sizeFactor: grow,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut)),
        child: ScaleTransition(
          alignment: widget.fromRight ? Alignment.bottomRight : Alignment.bottomLeft,
          scale: Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A manual page shown as a picture in an answer. Tapping it opens the page
/// in the viewer to zoom in.
class _PagePicture extends StatefulWidget {
  const _PagePicture({required this.source});

  final AiSource source;

  @override
  State<_PagePicture> createState() => _PagePictureState();
}

class _PagePictureState extends State<_PagePicture> {
  Future<File>? _thumb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drawn once into a small picture file (from the phone when downloaded,
    // else only this page's part of the PDF is fetched), so the chat never
    // keeps whole manuals open.
    _thumb ??= pageThumbnail(StoreScope.of(context), widget.source.file, widget.source.page);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openViewer(context, source.file, page: source.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              child: FutureBuilder<File>(
                future: _thumb,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Gambar tidak bisa dimuat', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    );
                  }
                  final file = snapshot.data;
                  if (file == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  return Image.file(file, fit: BoxFit.contain, cacheHeight: 600);
                },
              ),
            ),
            Container(
              color: AppColors.navySoft,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${source.unitName} · ${source.file.type.label} · hlm ${source.page}',
                      style: TextStyle(fontSize: 12, color: AppColors.navy),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 16, color: AppColors.navy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the input while the phone downloads the search indexes of
/// manuals that are not downloaded, in any state of the chat.
class _Preparing extends StatelessWidget {
  const _Preparing({required this.progress});

  final AiIndexProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final bytes = p.totalBytes == 0 ? null : (p.receivedBytes / p.totalBytes).clamp(0.0, 1.0);
    return Container(
      color: AppColors.navySoft,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menyiapkan indeks pencarian AI: ${p.ready} dari ${p.total} manual'
            '${p.totalBytes == 0 ? '' : ' (${formatSize(p.receivedBytes)} dari ${formatSize(p.totalBytes)})'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
          ),
          const SizedBox(height: 2),
          Text(
            'Sementara itu AI menjawab dari manual yang indeksnya sudah siap.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: bytes, minHeight: 4, borderRadius: BorderRadius.circular(2)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.enabled, required this.hint, required this.onSend});

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  // Enter on the keyboard starts a new line; the send button
                  // next to the field sends the question.
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.field,
                    hintText: hint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kirim',
                onPressed: enabled ? onSend : null,
                icon: Icon(Icons.send_rounded, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
