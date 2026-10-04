import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Tanya AI: answers from the manuals downloaded on the phone, citing the
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
  AiChat? _chat;
  final List<ChatEntry> _entries = [];
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
    final chat = _chat ??= AiChat(store: StoreScope.read(context), client: _client);
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
    }
    if (!mounted) return;
    setState(() {
      _entries.add(answer);
      _status = null;
    });
    _scrollToEnd();
  }

  void _newChat() {
    setState(() {
      _chat = null;
      _entries.clear();
    });
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
    final offline = store.online == false;
    final hasManuals = store.searchableIndexes().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE6E8EB))),
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', width: 42, height: 42),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tanya AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(
                  'Jawaban dari manual yang terunduh',
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
          _InputBar(
            controller: _input,
            enabled: !offline && _status == null,
            hint: offline ? 'Butuh internet untuk bertanya' : 'Tulis pertanyaan…',
            onSend: _send,
          ),
        ],
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
              const Text('Tanya soal teknis, AI menjawab dari manual',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'AI mencari di manual yang sudah diunduh di HP ini, lalu menjawab dengan menyebut sumbernya. '
                'Ketuk sumber untuk membuka halamannya. Butuh internet.',
                style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF3A3F45)),
              ),
              if (!hasManuals) ...[
                const SizedBox(height: 12),
                const Text(
                  'Belum ada manual yang diunduh. Unduh dulu manual yang ingin ditanyakan dari tab Unit.',
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
                  const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.navy),
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
            if (entry.sources.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Sumber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
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
                        style: const TextStyle(fontSize: 12, color: AppColors.navy),
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
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
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
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF4F5F7),
                    hintText: hint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kirim',
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.send_rounded, color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
