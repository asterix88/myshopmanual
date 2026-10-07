import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai.dart';
import '../models.dart';
import '../page_image.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Nyel AI: answers from the manuals downloaded on the phone, citing the
/// pages it used. Needs internet; the search itself runs on the phone.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.client});

  /// For tests; the app uses a plain [http.Client].
  final http.Client? client;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final AiChat _chat = AiChat(store: StoreScope.read(context), client: _client);
  final List<ChatEntry> _entries = [];
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

  static const _examples = [
    'Lampu hydraulic oil filter clogging menyala, apa yang harus dilakukan?',
    'Berapa tekanan relief main valve PC210?',
    'Interval penggantian oli engine D85?',
  ];

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final question = (text ?? _input.text).trim();
    if (question.isEmpty || _status != null) return;
    if (StoreScope.read(context).aiQuestionsLeft == 0) return;
    final chat = _chat;
    _input.clear();
    setState(() {
      _entries.add(ChatEntry.user(question));
      _status = 'Memahami pertanyaan…';
    });
    _scrollToEnd();
    ChatEntry answer;
    try {
      answer = await chat.ask(question, onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
    } on AiException catch (e) {
      answer = ChatEntry.assistant(e.message, failed: true);
    } catch (e, stack) {
      // Never leave the chat stuck on its status line.
      debugPrint('Nyel AI failed: $e\n$stack');
      answer = ChatEntry.assistant('Terjadi kesalahan di aplikasi saat mencari jawaban. Coba lagi.', failed: true);
    }
    if (!mounted) return;
    setState(() {
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

  void _newChat() {
    setState(_entries.clear);
    _chat.clear();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.pendingAiQuestion != null) {
      // "Tanya Nyel AI" on a page: put the question in the box to edit or send.
      final question = store.takeAiQuestion()!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _input.value = TextEditingValue(
          text: question,
          selection: TextSelection.collapsed(offset: question.length),
        );
      });
    }
    final offline = store.online == false;
    final hasManuals = store.catalog.files.isNotEmpty || store.local.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: Border(bottom: BorderSide(color: AppColors.line)),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 42, height: 42),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nyel AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(
                  'Teman diskusi masalah teknismu :)',
                  style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Percakapan baru',
              onPressed: _status == null ? _newChat : null,
              icon: const Icon(Icons.add_comment_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _Intro(
                    examples: _examples,
                    hasManuals: hasManuals,
                    onExample: offline ? null : _send,
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    children: [
                      for (final entry in _entries) _Bubble(entry: entry),
                      if (_status != null) _Working(status: _status!),
                    ],
                  ),
          ),
          if (store.aiIndexProgress case final p?) _Preparing(progress: p),
          if (store.aiQuestionsLeft case final left?) _QuestionsLeft(left: left),
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
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tanya soal teknis ke Nyel AI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Nyel AI mencari di semua manual, termasuk yang belum diunduh, dan bisa melihat gambar seperti wiring '
                'atau hydraulic diagram. Kalau manual tidak membahasnya, Nyel AI menjawab dari ilmu elektrik, '
                'hidrolik dan mekanis, ditandai "Secara umum". Isi dari manual diberi sumber; ketuk sumber untuk '
                'membuka halamannya. Butuh internet.',
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.inkSoft),
              ),
              if (!hasManuals) ...[
                const SizedBox(height: 12),
                Text(
                  'Daftar manual belum termuat. Sambungkan ke internet lalu buka tab Unit.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.orangeText),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Contoh pertanyaan'),
        const SizedBox(height: 8),
        for (final example in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: onExample == null ? null : () => onExample!(example),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(child: Text(example, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
          child: Text(entry.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText.rich(
              TextSpan(children: [
                for (final run in boldRuns(entry.text))
                  TextSpan(text: run.text, style: run.bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
              ]),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: entry.failed ? AppColors.danger : AppColors.ink,
              ),
            ),
            for (final picture in entry.pictures) ...[
              const SizedBox(height: 12),
              _PagePicture(source: picture),
            ],
            if (entry.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Sumber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (i, s) in entry.sources.indexed)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.navySoft,
                      side: BorderSide.none,
                      label: Text(
                        '[${i + 1}] ${s.unitName} · ${s.file.type.label} · hlm ${s.page}',
                        style: TextStyle(fontSize: 12, color: AppColors.navy),
                      ),
                      onPressed: () => openViewer(context, s.file, page: s.page),
                    ),
                ],
              ),
            ],
          ],
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
            child: Text(status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
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
