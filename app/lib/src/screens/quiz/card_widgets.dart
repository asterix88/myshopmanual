part of '../quiz_screen.dart';

// A kartu in the quiz (QuizQuestion.isCard). The front only asks; the
// mechanic answers in their own words, turns the card, checks the manual
// page and the key points, then rates how easy it was. The rating is the
// answer sent to the server (chosen = index in [cardRatings]).

/// The front of a kartu: the question on a card with another card peeking
/// out underneath, so it reads differently from a question with choices.
class _CardFront extends StatelessWidget {
  const _CardFront({required this.question, required this.tags});

  final QuizQuestion question;

  /// Unit, topic and "Ulangan", the same row as on other questions.
  final Widget tags;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tags,
          const SizedBox(height: 12),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The next card in the pile.
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: -8,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                Positioned.fill(
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    child: _FrontText(question: question),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrontText extends StatelessWidget {
  const _FrontText({required this.question});

  final QuizQuestion question;

  @override
  Widget build(BuildContext context) {
    // The question sits in the middle when it fits and scrolls when a long
    // one does not.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill('Kartu', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
                const SizedBox(height: 24),
                const Spacer(flex: 2),
                Text(question.prompt, style: const TextStyle(fontSize: 22, height: 1.38, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Divider(height: 1, color: AppColors.line),
                const SizedBox(height: 14),
                Text(
                  'Jelaskan dengan bahasamu sendiri, lalu balik kartu',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The back of a kartu: the question small, the page it was made from and
/// the key points to compare with what the mechanic said.
class _CardBack extends StatefulWidget {
  const _CardBack({required this.question, required this.tags, required this.api, required this.onOpenManual});

  final QuizQuestion question;
  final Widget tags;
  final QuizApi api;
  final VoidCallback onOpenManual;

  @override
  State<_CardBack> createState() => _CardBackState();
}

class _CardBackState extends State<_CardBack> {
  bool _keysOpen = true;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final points = q.keyPoints;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        widget.tags,
        const SizedBox(height: 10),
        Text(q.prompt, style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(question: q, onOpen: widget.onOpenManual),
              if (q.image != null)
                ColoredBox(
                  color: AppColors.viewerBackground,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: QuizPicture(api: widget.api, questionId: q.id, height: 236),
                  ),
                ),
            ],
          ),
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _keysOpen = !_keysOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        Text(
                          'POIN KUNCI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                            color: AppColors.muted,
                          ),
                        ),
                        const Spacer(),
                        AnimatedRotation(
                          turns: _keysOpen ? .5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: AppIcon(AppGlyph.chevronDown, size: 16, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_keysOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, point) in points.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '${i + 1}. $point',
                              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "PM PC210-10 / Halaman 115 ... Buka penuh" above the page picture.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.question, required this.onOpen});

  final QuizQuestion question;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = StoreScope.of(context).fileByKey(question.manualId)?.title ?? question.manualId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(10)),
            child: Center(child: AppIcon(AppGlyph.book, size: 18, color: AppColors.navy)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (question.page > 0)
                  Text('Halaman ${question.page}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Buka penuh')),
        ],
      ),
    );
  }
}

/// "Seberapa mudah kamu menjawab soal ini?" and the four ratings.
class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.onRate});

  /// Called with the index in [cardRatings].
  final ValueChanged<int> onRate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Seberapa mudah kamu menjawab soal ini?',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (i, label) in cardRatings.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => onRate(i),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: i == 0 ? AppColors.danger : AppColors.ink,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
