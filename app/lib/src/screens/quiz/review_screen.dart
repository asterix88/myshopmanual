part of '../quiz_screen.dart';

// Looking back at the answers of a finished quiz.

/// The questions of a set with the right answer and why; tap to open.
class QuizReviewScreen extends StatefulWidget {
  const QuizReviewScreen({super.key, required this.questions, required this.first, required this.chosen});

  final List<QuizQuestion> questions;
  final Map<String, bool> first;
  final Map<String, int> chosen;

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Soal sesi ini'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                for (final (i, q) in widget.questions.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => setState(() => _open = _open == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Mark(right: widget.first[q.id]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  [?q.unit, widget.first[q.id] == false ? 'Diulang besok' : q.topicName].join(' · '),
                                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                                if (_open == i) ...[
                                  const SizedBox(height: 8),
                                  _Answer(question: q, chosen: widget.chosen[q.id]),
                                  if (q.page > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('Manual hal. ${q.page}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
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

/// The right answer and why; for a kartu, the mechanic's rating and the
/// key points.
class _Answer extends StatelessWidget {
  const _Answer({required this.question, required this.chosen});

  final QuizQuestion question;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final rating = q.isCard ? cardRatings.elementAtOrNull(chosen ?? -1) : null;
    final (label, value) = q.isCard ? ('Penilaianmu: ', rating) : ('Jawaban: ', q.answerText);
    final why = q.isCard ? [for (final (i, p) in q.keyPoints.indexed) '${i + 1}. $p'].join('\n') : q.explain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value != null)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: label),
              TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
        const SizedBox(height: 4),
        Text(why, style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.right});

  final bool? right;

  @override
  Widget build(BuildContext context) {
    final color = right == null ? AppColors.border : (right! ? AppColors.green : AppColors.danger);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: AppIcon(right == false ? AppGlyph.cross : AppGlyph.check, size: 14, color: Colors.white),
      ),
    );
  }
}
