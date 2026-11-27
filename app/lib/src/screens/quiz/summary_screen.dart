part of '../quiz_screen.dart';

// The page after a quiz: score and what to read again.

/// After the last question: right answers, XP, rank, streak.
class QuizSummaryScreen extends StatelessWidget {
  const QuizSummaryScreen({
    super.key,
    required this.daily,
    required this.unit,
    required this.questions,
    required this.first,
    required this.chosen,
    required this.result,
    required this.offline,
    required this.xpWithoutBonus,
    required this.minutes,
    this.streakBefore,
    this.day,
  });

  final bool daily;
  final String? unit;
  final List<QuizQuestion> questions;
  final Map<String, bool> first;
  final Map<String, int> chosen;

  /// null when the set could not be closed on the server (no signal).
  final FinishResult? result;
  final bool offline;
  final int xpWithoutBonus;
  final int minutes;

  /// The streak before this quiz and its quiz day, when known: the
  /// flame then shows the streak going up.
  final int? streakBefore;
  final String? day;

  @override
  Widget build(BuildContext context) {
    final right = result?.score ?? first.values.where((v) => v).length;
    final total = result?.total ?? questions.length;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: QuizBar(title: daily ? 'Quiz selesai' : 'Quiz $unit selesai', close: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Text('Jawaban benar', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$right', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    TextSpan(text: '/$total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.muted)),
                  ]),
                ),
                Text(minutes < 2 ? 'sekitar 1 menit' : '$minutes menit', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '+${result?.xp ?? xpWithoutBonus}',
                  label: 'XP',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(value: (result?.rank ?? 0) > 0 ? '${result!.rank}' : '-', label: 'Peringkat'),
              ),
            ],
          ),
          if (daily && result != null) ...[
            const SizedBox(height: 12),
            _StreakMoment(result: result!, before: streakBefore, day: day),
          ],
          if (offline) ...[
            const SizedBox(height: 12),
            AppCard(
              color: AppColors.amberSoft,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  AppIcon(AppGlyph.cloudOff, size: 20, color: AppColors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'XP dan streak dihitung saat ada koneksi internet',
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => QuizReviewScreen(questions: questions, first: first, chosen: chosen),
            )),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const AppIcon(AppGlyph.list, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lihat ${questions.length} soal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QuizHubScreen())),
            child: const Text('Selesai', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}

/// The daily quiz's streak: a big flame pops in, the number rolls up from
/// the streak before, and today's flame in the week lights up.
class _StreakMoment extends StatelessWidget {
  const _StreakMoment({required this.result, required this.before, required this.day});

  final FinishResult result;
  final int? before;
  final String? day;

  @override
  Widget build(BuildContext context) {
    final up = !result.freezeUsed && before != null && result.streak > before!;
    final today = day ?? quizDayOf(DateTime.now());
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          const PopIn(child: Flame(size: 88, live: true)),
          const SizedBox(height: 8),
          _RollingNumber(from: up ? before! : result.streak, to: result.streak),
          Text(
            result.freezeUsed ? 'Libur streak terpakai' : 'hari streak · pertahankan besok',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          StreakWeek(day: today, lastDaily: today, streak: result.streak, size: 26, lightUp: up),
        ],
      ),
    );
  }
}

/// [from], then [to] rolling up into its place.
class _RollingNumber extends StatefulWidget {
  const _RollingNumber({required this.from, required this.to});

  final int from;
  final int to;

  @override
  State<_RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<_RollingNumber> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.from == widget.to) {
      _c.value = 1;
    } else {
      _wait = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = 40.0;
    final style = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1, color: AppColors.ink);
    return SizedBox(
      height: height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, _) => Stack(
            alignment: Alignment.center,
            children: [
              if (widget.from != widget.to && _c.value < 1)
                Transform.translate(offset: Offset(0, -height * _a.value), child: Text('${widget.from}', style: style)),
              Transform.translate(
                offset: Offset(0, height * (1 - _a.value)),
                child: Text('${widget.to}', style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
