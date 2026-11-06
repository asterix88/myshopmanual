import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../quiz.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'quiz_screen.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Admins: the questions nyel AI drafted wait here until an admin approves
/// them (Anas's decision in the Quiz PRD), plus questions pulled by reports
/// or by too many wrong answers.
class QuizAdminScreen extends StatefulWidget {
  const QuizAdminScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizAdminScreen> createState() => _QuizAdminScreenState();
}

class _QuizAdminScreenState extends State<QuizAdminScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final QuizApi _api = QuizApi(StoreScope.read(context), _client);

  static const _tabs = [
    ('draf', 'Draf'),
    ('perlu_cek', 'Perlu cek'),
    ('ditarik', 'Ditarik'),
    ('terbit', 'Terbit'),
    ('laporan', 'Laporan'),
  ];

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: QuizBar(
          title: 'Kelola soal quiz',
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xB3FFFFFF),
            indicatorColor: AppColors.orange,
            labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [for (final t in _tabs) Tab(text: t.$2)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in _tabs)
              t.$1 == 'laporan' ? _ReportsTab(api: _api) : _QuestionsTab(api: _api, status: t.$1),
          ],
        ),
      ),
    );
  }
}

class _QuestionsTab extends StatefulWidget {
  const _QuestionsTab({required this.api, required this.status});

  final QuizApi api;
  final String status;

  @override
  State<_QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<_QuestionsTab> with AutomaticKeepAliveClientMixin {
  List<AdminQuestion>? _list;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.questions(widget.status);
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _decide(AdminQuestion q, String action, {Map<String, dynamic>? edit}) async {
    try {
      await widget.api.decide(q.question.id, action, edit: edit);
      if (!mounted) return;
      final done = switch (action) {
        'setujui' => 'Soal diterbitkan',
        'tolak' => 'Soal ditolak',
        'tarik' => 'Soal ditarik',
        _ => 'Perubahan disimpan',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      QuizApi.changed.value++;
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit(AdminQuestion q) async {
    final edit = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => QuizEditScreen(question: q)),
    );
    if (edit == null) return;
    await _decide(q, edit.remove('_publish') == true ? 'setujui' : 'ubah', edit: edit);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _list;
    if (list == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Gagal memuat soal',
              message: '$_error',
              action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
            );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(children: [
              EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Tidak ada soal',
                message: widget.status == 'draf'
                    ? 'Buat draf dari halaman manual: buka manual, lalu ketuk ikon Quiz di atas.'
                    : null,
              ),
            ])
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _QuestionCard(
                item: list[i],
                onAction: (action) => action == 'ubah' ? _edit(list[i]) : _decide(list[i], action),
              ),
            ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.item, required this.onAction});

  final AdminQuestion item;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final q = item.question;
    final store = StoreScope.of(context);
    final note = item.checkNote;
    final warn = note != null && (note.startsWith('Cek') || note.startsWith('Ditarik') || note.startsWith('Lebih'));
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (q.unit != null) Pill(q.unit!, background: AppColors.navySoft, foreground: AppColors.navy),
              Text('${q.topicName} · ${item.section}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              if (item.source == 'ai') Pill('nyel AI', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 8),
          for (final (i, c) in q.choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: i == q.answer
                        ? AppIcon(AppGlyph.check, size: 16, color: AppColors.green)
                        : Text('ABCD'[i.clamp(0, 3)], style: TextStyle(fontSize: 13, color: AppColors.muted)),
                  ),
                  Expanded(
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == q.answer ? FontWeight.w600 : FontWeight.w400,
                        color: i == q.answer ? AppColors.green : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(q.explain, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          InkWell(
            onTap: store.fileByKey(q.manualId) == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ViewerScreen(fileKey: q.manualId, initialPage: q.page)),
                    ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${store.fileByKey(q.manualId)?.title ?? q.manualId} · hal. ${q.page}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: warn ? AppColors.amberSoft : AppColors.greenSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(note, style: TextStyle(fontSize: 12, color: warn ? AppColors.amber : AppColors.green)),
            ),
          ],
          if (item.answered > 0 || item.reports > 0) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (item.answered > 0) '${item.answered} jawaban · ${item.wrongPct ?? 0}% salah',
                if (item.reports > 0) '${item.reports} laporan',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.status != 'terbit')
                FilledButton(onPressed: () => onAction('setujui'), child: const Text('Setujui')),
              OutlinedButton(onPressed: () => onAction('ubah'), child: const Text('Ubah')),
              if (item.status == 'draf' || item.status == 'perlu_cek' || item.status == 'ditarik')
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => onAction('tolak'),
                  child: const Text('Tolak'),
                ),
              if (item.status == 'terbit')
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => onAction('tarik'),
                  child: const Text('Tarik'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.api});

  final QuizApi api;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<QuizReport>? _list;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.reports();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return _error == null ? const Center(child: CircularProgressIndicator()) : EmptyState(icon: Icons.cloud_off_outlined, title: '$_error');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (list.isEmpty)
            const EmptyState(icon: Icons.flag_outlined, title: 'Tidak ada laporan')
          else
            AppCard(
              child: Column(
                children: [
                  for (final (i, r) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.prompt, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${r.note.isEmpty ? 'Tanpa catatan' : r.note} · ${r.name}',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          Text(
                            r.status == 'ditarik' ? 'Soal ditarik, lihat tab Ditarik' : 'Soal masih terbit',
                            style: TextStyle(fontSize: 12, color: r.status == 'ditarik' ? AppColors.amber : AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Edit a question; returns the changed fields (with _publish when
/// "Simpan & terbitkan" was chosen).
class QuizEditScreen extends StatefulWidget {
  const QuizEditScreen({super.key, required this.question});

  final AdminQuestion question;

  @override
  State<QuizEditScreen> createState() => _QuizEditScreenState();
}

class _QuizEditScreenState extends State<QuizEditScreen> {
  late final QuizQuestion q = widget.question.question;
  late final _prompt = TextEditingController(text: q.prompt);
  late final _explain = TextEditingController(text: q.explain);
  late final _choices = [for (final c in q.choices) TextEditingController(text: c)];
  late int _answer = q.answer;
  late String _topic = q.topic;

  @override
  void dispose() {
    _prompt.dispose();
    _explain.dispose();
    for (final c in _choices) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _fields() => {
        'section': widget.question.section,
        'unit': q.unit ?? '',
        'topic': _topic,
        'type': q.type,
        'prompt': _prompt.text.trim(),
        'choices': [for (final c in _choices) c.text.trim()],
        'answer': _answer,
        'explain': _explain.text.trim(),
        'manual_id': q.manualId,
        'page': q.page,
      };

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Ubah soal'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: quizTopics.containsKey(_topic) ? _topic : 'struktur',
            decoration: const InputDecoration(labelText: 'Topik'),
            items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: (v) => setState(() => _topic = v ?? _topic),
          ),
          const SizedBox(height: 12),
          TextField(controller: _prompt, maxLines: null, decoration: const InputDecoration(labelText: 'Pertanyaan')),
          const SizedBox(height: 16),
          const SectionLabel('Pilihan (ketuk lingkaran untuk kunci jawaban)'),
          for (final (i, c) in _choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Jadikan kunci jawaban',
                    onPressed: () => setState(() => _answer = i),
                    icon: Icon(
                      i == _answer ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: i == _answer ? AppColors.green : AppColors.muted,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: c,
                      readOnly: q.type == 'bs',
                      decoration: InputDecoration(labelText: 'Pilihan ${'ABCD'[i.clamp(0, 3)]}'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(controller: _explain, maxLines: null, decoration: const InputDecoration(labelText: 'Penjelasan')),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, _fields()),
                child: const Text('Simpan'),
              ),
            ),
            if (widget.question.status != 'terbit') ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, {..._fields(), '_publish': true}),
                  child: const Text('Simpan & terbitkan'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// From the viewer (admins): nyel AI drafts questions from this page. The
/// page text comes from the manual's search index on the phone.
class QuizGenerateSheet extends StatefulWidget {
  const QuizGenerateSheet({super.key, required this.file, required this.page, this.client});

  final ManualFile file;
  final int page;
  final http.Client? client;

  @override
  State<QuizGenerateSheet> createState() => _QuizGenerateSheetState();
}

class _QuizGenerateSheetState extends State<QuizGenerateSheet> {
  late final http.Client _client = widget.client ?? http.Client();
  String _topic = 'struktur';
  int _count = 3;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _go() async {
    final store = StoreScope.read(context);
    final file = widget.file;
    setState(() {
      _busy = true;
      _status = 'Membaca halaman ${widget.page}…';
    });
    try {
      if (!file.searchable) throw Exception('Manual ini berupa gambar, teksnya tidak bisa dibaca.');
      final indexes = await store.aiIndexes(where: (f) => f.key == file.key);
      final path = indexes[file.key];
      if (path == null) throw Exception('Indeks manual belum ada di HP. Coba lagi saat ada sinyal.');
      final page = widget.page;
      final found = await _pageText(path, page);
      final text = found?.text.trim() ?? '';
      if (text.length < 80) throw Exception('Halaman ini hampir tanpa teks. Pilih halaman lain.');
      if (!mounted) return;
      setState(() => _status = 'nyel AI menyusun soal…');
      final result = await QuizApi(store, _client).generate(
        section: store.unitById(file.unitId)?.section ?? 'TRACK',
        unit: file.unitId,
        topic: _topic,
        manualId: file.key,
        page: page,
        text: text,
        count: _count,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.saved == 0
            ? 'Tidak ada soal yang layak dari halaman ini.'
            : '${result.saved} draf soal dibuat. Tinjau di menu ⋮ > Kelola soal quiz.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Buat soal quiz', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'nyel AI membuat draf dari halaman ${widget.page}. Draf baru muncul ke mekanik setelah admin menyetujui.',
              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _topic,
              decoration: const InputDecoration(labelText: 'Topik'),
              items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: _busy ? null : (v) => setState(() => _topic = v ?? _topic),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Jumlah soal', style: TextStyle(fontSize: 14))),
                for (final n in const [1, 3, 5])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text('$n'),
                      selected: _count == n,
                      onSelected: _busy ? null : (_) => setState(() => _count = n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _go,
                child: _busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text(_status ?? ''),
                        ],
                      )
                    : const Text('Buat draf'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads one page's text in the background. A top-level function, so the
/// isolate gets only the path and page number and never the screen's state
/// (a closure inside the State drags the widget tree along, which an isolate
/// refuses).
Future<({String text, String? section})?> _pageText(String path, int page) =>
    Isolate.run(() => pageTextSync(path, page));
