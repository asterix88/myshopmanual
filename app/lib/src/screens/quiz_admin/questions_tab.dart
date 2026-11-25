part of '../quiz_admin_screen.dart';

// Tab Soal: the question list with drafts, generator jobs and bulk approval.

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
      // While Nyel AI is working, look again every 15 s.
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
    await sendQuizPicture(store, widget.api, file, q.question.page, {q.question.id: q.question.autoEdit});
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
      // One drawing per page, shared by the questions that need a picture.
      final byPage = <String, List<AdminQuestion>>{};
      for (final q in passed.where((q) => q.needsPicture)) {
        byPage.putIfAbsent('${q.question.manualId}#${q.question.page}', () => []).add(q);
      }
      for (final group in byPage.values) {
        final file = store.fileByKey(group.first.question.manualId);
        if (file == null) continue;
        try {
          await sendQuizPicture(store, widget.api, file, group.first.question.page,
              {for (final q in group) q.question.id: q.question.autoEdit});
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
            Text('Berjalan di server, aplikasi boleh ditutup.',
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

/// A kartu's key points, which it shows instead of choices.
class _KeyPoints extends StatelessWidget {
  const _KeyPoints({required this.points});

  final List<String> points;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('POIN KUNCI',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: AppColors.muted)),
          const SizedBox(height: 4),
          for (final (i, point) in points.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${i + 1}. $point', style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
            ),
        ],
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
    // Gambar and kartu always have a picture; other types may add one.
    final (pictureIcon, pictureLabel) = switch (q) {
      QuizQuestion(isCard: true) => (Icons.crop, 'Atur area halaman'),
      QuizQuestion(image: null, needsPagePicture: false) => (Icons.add_photo_alternate_outlined, 'Tambah gambar'),
      _ => (Icons.crop, 'Atur gambar'),
    };
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
              if (item.source == 'ai') Pill('Nyel AI', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
          if (q.needsPagePicture || q.image != null) ...[
            const SizedBox(height: 8),
            q.image == null
                ? Text(
                    q.isCard
                        ? 'Halaman ${q.page} dipasang utuh di balik kartu saat disetujui.'
                        : 'Gambar dibuat dari halaman ${q.page} saat soal disetujui.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted))
                : QuizPicture(
                    key: ValueKey('${q.id}#${QuizApi.imageVersion(q.id)}'), api: api, questionId: q.id, height: 160),
          ],
          Wrap(
            spacing: 4,
            children: [
              _LinkButton(icon: pictureIcon, label: pictureLabel, onPressed: () => onAction('gambar')),
              if (q.image != null && !q.needsPagePicture)
                _LinkButton(
                  icon: Icons.delete_outline,
                  label: 'Hapus gambar',
                  color: AppColors.danger,
                  onPressed: () => onAction('hapus_gambar'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (q.isCard)
            _KeyPoints(points: q.keyPoints)
          else ...[
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
          ],
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
