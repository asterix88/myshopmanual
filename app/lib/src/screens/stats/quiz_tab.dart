/// Statistik tab Quiz.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models.dart';
import '../../quiz.dart';
import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/excavator_loader.dart';
import '../quiz_admin_screen.dart' show QuizEditScreen;
import '../shell.dart';
import '../viewer_screen.dart';
import 'widgets.dart';

/// Quiz: who plays, which topics and questions go wrong, who is ahead.
/// Loads its own numbers, only once the tab is opened.
class QuizStatsTab extends StatefulWidget {
  const QuizStatsTab({
    super.key,
    required this.api,
    required this.filter,
    required this.onQuestion,
    required this.onNever,
    this.showSection = true,
  });

  final StatsApi api;
  final StatsFilter filter;
  final ValueChanged<String> onQuestion;
  final ValueChanged<List<InactiveRow>> onNever;
  final bool showSection;

  @override
  State<QuizStatsTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizStatsTab> with AutomaticKeepAliveClientMixin {
  late Future<QuizStats> _data = widget.api.quiz(widget.filter);

  @override
  bool get wantKeepAlive => true;

  Color _scoreColor(int pct) => pct < 60 ? AppColors.danger : (pct < 75 ? AppColors.amber : AppColors.navy);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<QuizStats>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: EmptyState(
              icon: Icons.wifi_off,
              title: 'Gagal memuat quiz',
              action: TextButton(
                onPressed: () => setState(() => _data = widget.api.quiz(widget.filter)),
                child: const Text('Coba lagi'),
              ),
            ),
          );
        }
        final d = snap.data;
        if (d == null) return const Center(child: ExcavatorLoader(label: 'Memuat quiz…'));
        final muted = TextStyle(fontSize: 11, color: AppColors.muted);
        return ListView(
          padding: statsListPadding,
          children: [
            const StatsCaps('Ringkasan quiz'),
            StatsTiles([
              ('${d.players}/${d.users}', 'Ikut quiz'),
              ('${d.correct}%', d.trendCorrect == null ? 'Benar' : 'Benar ${d.trendCorrect! >= 0 ? '▲' : '▼'}${d.trendCorrect!.abs()}'),
              ('${d.sets}', 'Set selesai'),
            ]),
            if (widget.showSection && d.perSection.isNotEmpty) ...[
              const StatsCaps('Ikut quiz per section'),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    for (final s in d.perSection)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(width: 76, child: Text(s.section, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(child: StatsBar(s.total == 0 ? 0 : s.players / s.total)),
                            SizedBox(
                              width: 52,
                              child: Text('${s.players}/${s.total}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const StatsCaps('Topik terlemah'),
            if (d.topics.isEmpty)
              const NoneYet('Belum ada jawaban')
            else
              CardRows([
                for (final t in d.topics.take(5))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(quizTopics[t.topic] ?? t.topic, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('${t.answers} jawaban', style: muted),
                              const SizedBox(height: 6),
                              _ScoreBar(t.correct / 100, color: _scoreColor(t.correct)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${t.correct}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            const StatsCaps('Soal paling sering salah'),
            if (d.hard.isEmpty)
              const NoneYet('Belum ada soal dengan 5 jawaban atau lebih')
            else
              CardRows([
                for (final q in d.hard)
                  InkWell(
                    onTap: () => widget.onQuestion(q.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.prompt,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text([if (q.unit.isNotEmpty) q.unit, quizTopics[q.topic] ?? q.topic, '${q.answers} jawaban'].join(' · '),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          VersionTag('${q.correct}% benar', warn: true, danger: q.correct < 40),
                          Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                        ],
                      ),
                    ),
                  ),
              ]),
            const StatsCaps('Paling rajin'),
            if (d.top.isEmpty)
              const NoneYet('Belum ada yang ikut quiz')
            else
              CardRows([
                for (final (i, p) in d.top.indexed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ),
                        InitialsAvatar(p.name, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text([if (widget.showSection) p.section, if (p.streak > 0) 'streak ${p.streak} hari'].join(' · '), style: muted),
                            ],
                          ),
                        ),
                        Text('${p.xp} XP', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            if (d.never.isNotEmpty) ...[
              const StatsCaps('Belum pernah ikut quiz'),
              AppCard(
                onTap: () => widget.onNever(d.never),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d.never.length} orang', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(_neverBySection(d.never), style: muted),
                        ],
                      ),
                    ),
                    Text('Lihat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _neverBySection(List<InactiveRow> people) {
    final n = <String, int>{};
    for (final p in people) {
      final s = p.sections.firstOrNull ?? defaultSection;
      n[s] = (n[s] ?? 0) + 1;
    }
    return [for (final e in n.entries) '${e.key} ${e.value}'].join(' · ');
  }
}

/// A bar in a status colour (red, amber or navy).
class _ScoreBar extends StatelessWidget {
  const _ScoreBar(this.fraction, {required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.greySoft),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      );
}

/// A question that often goes wrong: which choice people pick, then
/// Buka manual, Ubah soal or Tarik soal.
class QuizQuestionSheet extends StatelessWidget {
  const QuizQuestionSheet({super.key, required this.load});

  final Future<QuizQuestionStats> load;

  @override
  Widget build(BuildContext context) => LoadingSheet<QuizQuestionStats>(
        load: load,
        show: (context, s) {
          final admin = AdminQuestion(s.question);
          final q = admin.question;
          final total = s.picks.fold<int>(0, (a, b) => a + b);
          // A kartu is rated, not answered: its rows are the ratings, and
          // everything but Lupa counts as remembered.
          final rows = q.isCard ? cardRatings : q.choices;
          bool counts(int i) => q.isCard ? i > 0 : i == q.answer;
          bool marked(int i) => !q.isCard && i == q.answer;
          final right = [for (final (i, n) in s.picks.indexed) if (counts(i)) n].fold<int>(0, (a, b) => a + b);
          final rightPct = total == 0 ? 0 : right * 100 ~/ total;
          final store = StoreScope.read(context);
          final file = q.manualId.isEmpty ? null : store.fileByKey(q.manualId);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                [if (q.unit != null) q.unit!, q.topicName, if (q.page > 0) 'hal. ${q.page}'].join(' · '),
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Text(q.prompt, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.45)),
              const SizedBox(height: 4),
              Text('${s.answers} jawaban · $rightPct% ${q.isCard ? 'ingat' : 'benar'}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              for (final (i, c) in rows.indexed) ...[
                Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: marked(i) ? FontWeight.w600 : FontWeight.w400,
                            color: marked(i) ? AppColors.green : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: _ScoreBar(
                          total == 0 ? 0 : (s.picks.elementAtOrNull(i) ?? 0) / total,
                          color: marked(i) ? AppColors.green : AppColors.faint,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${total == 0 ? 0 : (s.picks.elementAtOrNull(i) ?? 0) * 100 ~/ total}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: file == null
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ViewerScreen(fileKey: file.key, initialPage: q.page),
                              )),
                      child: const Text('Buka manual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizEditScreen(question: admin))),
                      child: const Text('Ubah soal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Tarik soal ini?'),
                      content: const Text('Soal tidak muncul lagi di quiz'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tarik')),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await QuizApi(store, http.Client()).decide(q.id, 'tarik');
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Soal ditarik')));
                  } on Object catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Tarik soal'),
              ),
            ],
          );
        },
      );
}
