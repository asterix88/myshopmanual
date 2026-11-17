/// nyel AI chat. This file holds the chat page and its logic (sending a
/// question, history, quota); the pieces it draws are part files under
/// `chat/`:
///
/// - `intro.dart`      intro, attached page, questions left today
/// - `bubble.dart`     one bubble: answer text, page pictures, rating
/// - `input_bar.dart`  "working" indicators and the input bar
library;

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

part 'chat/bubble.dart';
part 'chat/input_bar.dart';
part 'chat/intro.dart';

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
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy),
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
