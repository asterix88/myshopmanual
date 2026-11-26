part of '../quiz_screen.dart';

// An admin's preview of one question, as a mechanic sees it. Opened from the
// eye button on a question card in Kelola soal quiz. Nothing is sent to the
// server: no answer, no XP, no repeat schedule.

/// The question as shown in the quiz: choices, a gambar's picture, or a
/// kartu with its front and back. Choose, Periksa and read the explanation
/// to see both results.
class QuizPreviewScreen extends StatefulWidget {
  const QuizPreviewScreen({super.key, required this.question, required this.api});

  final QuizQuestion question;
  final QuizApi api;

  @override
  State<QuizPreviewScreen> createState() => _QuizPreviewScreenState();
}

class _QuizPreviewScreenState extends State<QuizPreviewScreen> {
  int? _picked;
  bool _checked = false;

  /// A kartu shows its back.
  bool _flipped = false;

  QuizQuestion get _q => widget.question;

  void _openManual() {
    final q = _q;
    final store = StoreScope.read(context);
    if (store.fileByKey(q.manualId) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manual ${q.manualId} tidak ada di daftar manual HP ini')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ViewerScreen(fileKey: q.manualId, initialPage: q.page)));
  }

  /// Unit and topic, like the quiz. No Recall or Ulangan: a preview has no history.
  Widget _tags() => Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_q.unit != null) Pill(_q.unit!, background: AppColors.navySoft, foreground: AppColors.navy),
          Text(_q.topicName, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Preview soal', close: true, trailing: _PreviewBadge()),
      body: _q.isCard ? _card() : _question(),
    );
  }

  Widget _question() {
    final q = _q;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _tags(),
              const SizedBox(height: 14),
              Text(q.prompt, style: const TextStyle(fontSize: 17, height: 1.45, fontWeight: FontWeight.w600)),
              if (q.image != null) ...[
                const SizedBox(height: 12),
                QuizPicture(api: widget.api, questionId: q.id),
              ] else if (q.needsPagePicture) ...[
                const SizedBox(height: 12),
                _PendingPicture(page: q.page),
              ],
              const SizedBox(height: 16),
              for (final (i, choice) in q.choices.indexed) ...[
                _Option(
                  letter: 'ABCD'[i.clamp(0, 3)],
                  text: choice,
                  state: !_checked
                      ? (_picked == i ? _OptState.picked : _OptState.idle)
                      : i == q.answer
                          ? _OptState.right
                          : i == _picked
                              ? _OptState.wrong
                              : _OptState.dim,
                  onTap: _checked ? null : () => setState(() => _picked = i),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        _BottomBar(child: _checked ? _feedback() : _checkButton()),
      ],
    );
  }

  Widget _checkButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _picked == null ? null : () => setState(() => _checked = true),
          child: const Text('Periksa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  /// The result sheet without XP, the repeat note, "Tanya Nyel AI" and the report flag.
  Widget _feedback() {
    final q = _q;
    final right = _picked == q.answer;
    final color = right ? AppColors.green : AppColors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: AppIcon(right ? AppGlyph.check : AppGlyph.cross, size: 14, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Text(right ? 'Benar' : 'Belum tepat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            const Spacer(),
            Text('Tanpa XP', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .22),
          child: SingleChildScrollView(
            child: Text(q.explain, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkSoft)),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (q.page > 0) _LinkButton(glyph: AppGlyph.book, label: 'Manual hal. ${q.page}', onTap: _openManual),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  /// A kartu: the front with "Balik kartu", then the back. The four ratings are
  /// left out; a rating would be an answer.
  Widget _card() {
    final q = _q;
    return Column(
      children: [
        Expanded(
          child: _flipped
              ? _CardBack(question: q, tags: _tags(), api: widget.api, onOpenManual: _openManual)
              : _CardFront(question: q, tags: _tags()),
        ),
        _BottomBar(
          child: SizedBox(
            height: 52,
            child: _flipped
                ? FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  )
                : FilledButton.icon(
                    onPressed: () => setState(() => _flipped = true),
                    icon: const AppIcon(AppGlyph.flip, size: 20, color: Colors.white),
                    label: const Text('Balik kartu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
          ),
        ),
      ],
    );
  }
}

/// "PREVIEW" in the navy bar, so it is never mistaken for a real quiz.
class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
      child: const Text(
        'PREVIEW',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .6, color: Colors.white),
      ),
    );
  }
}

/// A question whose picture is only drawn when it is approved.
class _PendingPicture extends StatelessWidget {
  const _PendingPicture({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Center(
        child: Text(
          'Gambar dibuat dari halaman $page saat soal disetujui',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    );
  }
}
