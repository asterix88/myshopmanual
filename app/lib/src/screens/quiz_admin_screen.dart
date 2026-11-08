import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart' show PdfDocument;

import '../models.dart';
import '../page_image.dart';
import '../quiz.dart';
import '../quiz_edit.dart';
import '../search.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'quiz_crop_screen.dart';
import 'quiz_screen.dart';
import 'quiz_job_screen.dart';
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
          trailing: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizJobScreen(client: widget.client))),
            icon: const AppIcon(AppGlyph.sparkle, color: Colors.white, size: 18),
            label: const Text('Buat draf kuis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
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
  List<QuizJob> _jobs = const [];
  Object? _error;
  String _type = '';
  bool _bulk = false;
  Timer? _poll;

  bool get _drafts => widget.status == 'draf';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    QuizApi.changed.addListener(_load);
  }

  @override
  void dispose() {
    QuizApi.changed.removeListener(_load);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.questions(widget.status);
      final jobs = _drafts ? await widget.api.jobs() : const <QuizJob>[];
      if (!mounted) return;
      setState(() {
        _list = list;
        _jobs = jobs;
        _error = null;
      });
      // While nyel AI is working, look again every 15 s.
      _poll?.cancel();
      if (jobs.any((j) => j.running)) _poll = Timer(const Duration(seconds: 15), _load);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _decide(AdminQuestion q, String action, {Map<String, dynamic>? edit}) async {
    try {
      if (action == 'setujui' && q.needsPicture) await _picture(q);
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
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// "Atur gambar": the admin chooses the part of the page to show.
  Future<void> _crop(AdminQuestion q) async {
    final file = StoreScope.read(context).fileByKey(q.question.manualId);
    if (file == null) {
      showError(context, Exception('Manual soal ini tidak ada di daftar.'));
      return;
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => QuizCropScreen(api: widget.api, file: file, question: q.question),
    ));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gambar soal disimpan')));
      QuizApi.changed.value++;
    }
  }

  /// "Hapus gambar" on a pg/bs question.
  Future<void> _removePicture(AdminQuestion q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus gambar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.removeImage(q.question.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gambar dihapus')));
      QuizApi.changed.value++;
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Draws a picture question's page with its words covered and sends it.
  Future<void> _picture(AdminQuestion q) async {
    final store = StoreScope.read(context);
    final file = store.fileByKey(q.question.manualId);
    if (file == null) throw Exception('Manual soal ini tidak ada di daftar. Gambarnya tidak bisa dibuat.');
    await sendQuizPicture(store, widget.api, file, q.question.page, {q.question.id: q.question.pictureTarget});
  }

  /// "Setujui semua yang lolos": pictures first, then one call.
  Future<void> _approveAll(List<AdminQuestion> passed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Setujui ${passed.length} soal?'),
        content: const Text('Soal yang lolos kurator langsung terbit ke quiz mekanik.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Setujui')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulk = true);
    try {
      final store = StoreScope.read(context);
      // One drawing per page, shared by its picture questions.
      final byPage = <String, List<AdminQuestion>>{};
      for (final q in passed.where((q) => q.needsPicture)) {
        byPage.putIfAbsent('${q.question.manualId}#${q.question.page}', () => []).add(q);
      }
      for (final group in byPage.values) {
        final file = store.fileByKey(group.first.question.manualId);
        if (file == null) continue;
        try {
          await sendQuizPicture(store, widget.api, file, group.first.question.page,
              {for (final q in group) q.question.id: q.question.pictureTarget});
        } on Object {
          // Left as a draft; the admin sees it after.
        }
      }
      final result = await widget.api.approve([for (final q in passed) q.question.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.left.isEmpty
            ? '${result.published} soal diterbitkan'
            : '${result.published} soal diterbitkan, ${result.left.length} tetap di Draf'),
      ));
      QuizApi.changed.value++;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _bulk = false);
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
    final all = _list;
    if (all == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Gagal memuat soal',
              message: '$_error',
              action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
            );
    }
    final list = _type.isEmpty ? all : all.where((q) => q.question.type == _type).toList();
    final passed = all.where((q) => q.passed).toList();
    final counts = {for (final t in quizTypes.keys) t: all.where((q) => q.question.type == t).length};
    final jobs = _jobs.where((j) => j.running || DateTime.now().difference(j.createdAt).inHours < 24).take(2);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          for (final job in jobs) ...[_JobCard(job: job), const SizedBox(height: 12)],
          if (_drafts && passed.isNotEmpty) ...[
            _BulkCard(
              passed: passed.length,
              toCheck: all.length - passed.length,
              busy: _bulk,
              onApprove: () => _approveAll(passed),
            ),
            const SizedBox(height: 12),
          ],
          if (all.isNotEmpty && counts.values.where((n) => n > 0).length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (t, label) in [('', 'Semua'), for (final e in quizTypes.entries) (e.key, e.value)])
                    if (t.isEmpty || counts[t]! > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.isEmpty ? label : '$label ${counts[t]}'),
                          selected: _type == t,
                          onSelected: (_) => setState(() => _type = t),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (list.isEmpty)
            EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Tidak ada soal',
              message: _drafts
                  ? 'Ketuk "Buat draf kuis" di atas, atau buka manual lalu ketuk ikon Quiz.'
                  : null,
            )
          else
            for (final (i, q) in list.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              _QuestionCard(
                item: q,
                api: widget.api,
                onAction: (action) => switch (action) {
                  'ubah' => _edit(q),
                  'gambar' => _crop(q),
                  'hapus_gambar' => _removePicture(q),
                  _ => _decide(q, action),
                },
              ),
            ],
        ],
      ),
    );
  }
}

/// Question types with their names on screen.
const quizTypes = {'pg': 'Pilihan ganda', 'bs': 'Benar/Salah', 'gambar': 'Gambar'};

/// Draws [page] of [file] once and sends each picture question of that page
/// ([targets]: question id -> the callout number it asks about, or on a
/// labelled photo the asked label) the drawing that holds it; on a labelled
/// photo every label shows as a letter.
Future<void> sendQuizPicture(AppStore store, QuizApi api, ManualFile file, int page, Map<String, String?> targets,
    {Future<PdfDocument> Function()? open}) async {
  final drawn = await renderQuizPage(store, file, page, open: open);
  try {
    for (final MapEntry(key: id, value: target) in targets.entries) {
      final edit = QuizEdit.auto(drawn, target);
      final Uint8List png = await edit.png(drawn);
      await api.uploadImage(id, png, letter: edit.letter);
    }
  } finally {
    drawn.dispose();
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final QuizJob job;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (job.status) {
      'antri' => ('Menunggu giliran', AppColors.muted),
      'jalan' => ('Sedang dibuat', AppColors.navy),
      'gagal' => ('Gagal', AppColors.danger),
      _ => ('Selesai', AppColors.green),
    };
    final progress = job.pages == 0 ? 0.0 : job.pagesDone / job.pages;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [if (job.unit != null) job.unit!, job.title].join(' · '),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            job.error ??
                (job.running
                    ? 'Halaman ${job.pagesDone} dari ${job.pages} · ${job.kept} soal jadi'
                    : '${job.passed} lolos kurator · ${job.flagged} perlu dicek · ${job.dropped} dibuang'),
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (job.running) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.status == 'antri' ? null : progress,
                minHeight: 6,
                color: AppColors.navy,
                backgroundColor: AppColors.line,
              ),
            ),
            const SizedBox(height: 6),
            Text('Boleh tutup aplikasi, nyel AI tetap bekerja di server.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

class _BulkCard extends StatelessWidget {
  const _BulkCard({required this.passed, required this.toCheck, required this.busy, required this.onApprove});

  final int passed;
  final int toCheck;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$passed soal lolos kurator',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                if (toCheck > 0)
                  Text('$toCheck perlu dicek satu per satu',
                      style: const TextStyle(fontSize: 12, color: Color(0xCCFFFFFF))),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
            onPressed: busy ? null : onApprove,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Setujui $passed'),
          ),
        ],
      ),
    );
  }
}

/// A small text button with an icon, under a question's picture.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.icon, required this.label, required this.onPressed, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.item, required this.api, required this.onAction});

  final AdminQuestion item;
  final QuizApi api;
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
              Pill(quizTypes[q.type] ?? q.type, background: AppColors.greySoft, foreground: AppColors.inkSoft),
              if (item.curatorScore case final score?)
                Pill(
                  'Kurator $score/10',
                  background: score >= 7 ? AppColors.greenSoft : AppColors.amberSoft,
                  foreground: score >= 7 ? AppColors.green : AppColors.amber,
                ),
              if (item.source == 'ai') Pill('nyel AI', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
          if (q.type == 'gambar' || q.image != null) ...[
            const SizedBox(height: 8),
            q.image == null
                ? Text('Gambar dibuat dari halaman ${q.page} saat soal disetujui.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted))
                : QuizPicture(
                    key: ValueKey('${q.id}#${QuizApi.imageVersion(q.id)}'), api: api, questionId: q.id, height: 160),
          ],
          Wrap(
            spacing: 4,
            children: [
              _LinkButton(
                icon: q.image == null && q.type != 'gambar' ? Icons.add_photo_alternate_outlined : Icons.crop,
                label: q.image == null && q.type != 'gambar' ? 'Tambah gambar' : 'Atur gambar',
                onPressed: () => onAction('gambar'),
              ),
              if (q.image != null && q.type != 'gambar')
                _LinkButton(
                  icon: Icons.delete_outline,
                  label: 'Hapus gambar',
                  color: AppColors.danger,
                  onPressed: () => onAction('hapus_gambar'),
                ),
            ],
          ),
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
          if (item.curatorNote case final curator? when curator.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Kurator: $curator', style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.inkSoft)),
          ],
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
  String _kind = 'campur';
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
        kind: _kind,
      );
      if (result.pictures.isNotEmpty && mounted) {
        setState(() => _status = 'Membuat gambar soal…');
        try {
          await sendQuizPicture(store, QuizApi(store, _client), file, page,
              {for (final id in result.pictures) id: result.callouts[id]});
        } on Object {
          // Made again when the question is approved.
        }
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(result.saved == 0
            ? 'Tidak ada soal yang layak dari halaman ini.'
            : '${result.saved} draf soal dibuat${result.dropped > 0 ? ', ${result.dropped} dibuang kurator' : ''}. '
                'Tinjau di menu ⋮ > Kelola soal quiz.'),
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
    final kinds = [('campur', 'Campur'), for (final e in quizTypes.entries) (e.key, e.value)];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Buat soal quiz', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              '${widget.file.title} · hal. ${widget.page}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            const _SheetLabel('Jenis soal'),
            Row(children: [
              for (final (i, (k, label)) in kinds.take(2).indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: label, selected: _kind == k, onTap: _busy ? null : () => setState(() => _kind = k))),
              ],
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, (k, label)) in kinds.skip(2).indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: label, selected: _kind == k, onTap: _busy ? null : () => setState(() => _kind = k))),
              ],
            ]),
            if (_kind == 'gambar')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Mekanik melihat gambar bernomor, tanpa keterangan.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const SizedBox(height: 16),
            const _SheetLabel('Topik'),
            DropdownButtonFormField<String>(
              initialValue: _topic,
              isDense: true,
              icon: Icon(Icons.expand_more, color: AppColors.muted),
              style: TextStyle(fontSize: 14, color: AppColors.ink, fontFamily: 'Poppins'),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.navy)),
              ),
              items: [for (final t in quizTopics.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: _busy ? null : (v) => setState(() => _topic = v ?? _topic),
            ),
            const SizedBox(height: 16),
            const _SheetLabel('Jumlah soal'),
            Row(children: [
              for (final (i, n) in const [1, 3, 5].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Choice(label: '$n', selected: _count == n, onTap: _busy ? null : () => setState(() => _count = n))),
              ],
            ]),
            const SizedBox(height: 20),
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
            const SizedBox(height: 8),
            Text(
              'Draf dicek kurator, terbit setelah admin setuju.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.inkSoft)),
      );
}

/// One option box of the "Buat soal quiz" sheet.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.navySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.navy : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.navy : AppColors.inkSoft,
                ),
              ),
            ),
          ),
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
