/// Statistik tab Nyel AI: the questions asked and their ratings.
library;

import 'package:flutter/material.dart';

import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../answer_reports_screen.dart';
import '../shell.dart';
import 'format.dart';
import 'widgets.dart';

class QuestionTile extends StatelessWidget {
  const QuestionTile(this.q, {super.key, required this.onTap, this.showName = true, this.showSection = true});

  final QuestionRow q;
  final VoidCallback onTap;
  final bool showName;
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final meta = [
      if (showName) q.name,
      if (showName && showSection && q.sections.isNotEmpty) q.sections.join(', '),
      if (q.unit.isNotEmpty) unitName(store, q.unit),
      whenLabel(q.at),
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(meta.join(' · '), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class AiTab extends StatelessWidget {
  const AiTab({super.key, required this.data, required this.onQuestion, this.showSection = true});

  final StatsOverview data;
  final ValueChanged<int> onQuestion;
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: statsListPadding,
      children: [
        const StatsCaps('Topik paling ditanya'),
        if (data.topics.isEmpty)
          const NoneYet('Belum ada pertanyaan.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in data.topics)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: cardShadow,
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: t.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${t.n}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ])),
                ),
            ],
          ),
        const StatsCaps('Penilaian jawaban'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final (icon, color, text) in [
                      (Icons.thumb_up_alt_outlined, AppColors.green, '${data.good} membantu'),
                      (Icons.thumb_down_alt_outlined, AppColors.danger, '${data.bad} salah'),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AnswerReportsScreen()),
                ),
                child: const Text('Lihat'),
              ),
            ],
          ),
        ),
        const StatsCaps('Pertanyaan terbaru'),
        if (data.questions.isEmpty)
          const NoneYet('Belum ada pertanyaan.')
        else
          CardRows([
            for (final q in data.questions) QuestionTile(q, showSection: showSection, onTap: () => onQuestion(q.id)),
          ]),
      ],
    );
  }
}
