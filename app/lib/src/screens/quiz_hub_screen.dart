/// Kuis: the quiz hub (streak header, today's quiz, links to Quiz per unit,
/// Leaderboard and reminders). The other quiz pages live under `quiz_hub/`:
///
/// - `home_card.dart`            the quiz card on Home
/// - `units_screen.dart`         Quiz per unit
/// - `leaderboard_screen.dart`   Leaderboard page (period tabs, list)
/// - `leaderboard_widgets.dart`  podium, "kejar" card, rows, streak badge
/// - `avatar_picker_screen.dart` choosing an avatar
/// - `reminder_settings.dart`    quiz reminder time and switches
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../quiz.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/quiz_widgets.dart';
import 'quiz_admin_screen.dart';
import 'quiz_hub/leaderboard_screen.dart';
import 'quiz_hub/reminder_settings.dart';
import 'quiz_hub/units_screen.dart';
import 'quiz_screen.dart';
import 'shell.dart';

export 'quiz_hub/home_card.dart' show QuizHomeCard;
export 'quiz_hub/units_screen.dart' show QuizUnitsScreen;

/// The Quiz page: streak this week, rank, XP, leaderboard and Quiz per unit.
class QuizHubScreen extends StatefulWidget {
  const QuizHubScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizHubScreen> createState() => _QuizHubScreenState();
}

class _QuizHubScreenState extends State<QuizHubScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final QuizApi _api = QuizApi(StoreScope.read(context), _client);
  QuizHome? _home = QuizApi.lastHome;
  Board? _board;
  Object? _error;

  @override
  void initState() {
    super.initState();
    QuizApi.changed.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    QuizApi.changed.removeListener(_load);
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final home = await _api.home();
      final board = await _api.leaderboard();
      if (mounted) {
        setState(() {
          _home = home;
          _board = board;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    final store = StoreScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: QuizBar(
        title: 'Quiz',
        trailing: (store.session?.managesQuiz ?? false)
            ? IconButton(
                tooltip: 'Kelola soal',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizAdminScreen())),
                icon: const AppIcon(AppGlyph.pencil, color: Colors.white, size: 20),
              )
            : null,
      ),
      body: home == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Gagal memuat quiz',
                  message: 'Periksa koneksi internet.',
                  action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
                children: [
                  _StreakHeader(home: home),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppCard(
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                _HubStat(home.rankWeek > 0 ? '${home.rankWeek}' : '-', 'Peringkat'),
                                VerticalDivider(width: 1, indent: 12, endIndent: 12, color: AppColors.line),
                                _HubStat('${home.xpWeek}', 'XP minggu'),
                                VerticalDivider(width: 1, indent: 12, endIndent: 12, color: AppColors.line),
                                _HubStat('${home.mastered}', 'Dikuasai'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          child: Column(
                            children: [
                              if (!home.done && home.questions > 0)
                                _HubRow(
                                  glyph: AppGlyph.quiz,
                                  title: home.daily == 'lanjutkan' ? 'Lanjutkan quiz harian' : 'Mulai quiz harian',
                                  subtitle: '10 soal · sekitar 4 menit',
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizPlayScreen())),
                                ),
                              _HubRow(
                                glyph: AppGlyph.trophy,
                                title: 'Leaderboard',
                                subtitle: _boardLine(),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                              ),
                              _HubRow(
                                glyph: AppGlyph.unit,
                                title: 'Quiz per unit',
                                subtitle: '10 soal per model',
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizUnitsScreen())),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        QuizReminderSettings(home: home),
                        const SizedBox(height: 12),
                        Text(
                          'Rekor streak ${home.bestStreak} hari · Total ${home.xpTotal} XP',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _boardLine() {
    final board = _board;
    final dept = StoreScope.read(context).session?.department ?? '';
    final name = dept.isEmpty ? 'Departemen' : titleCaseWords(dept);
    final me = board?.me;
    if (board == null || me == null) return name;
    if (me.rank <= 1) return '$name · posisi 1';
    final above = board.rows.where((r) => r.rank == me.rank - 1).firstOrNull;
    if (above == null) return name;
    return '$name · ${above.xp - me.xp + 1} XP lagi ke posisi ${above.rank}';
  }
}

String titleCaseWords(String s) =>
    s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

class _StreakHeader extends StatelessWidget {
  const _StreakHeader({required this.home});

  final QuizHome home;

  @override
  Widget build(BuildContext context) {
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final today = DateTime.tryParse('${home.day}T00:00:00Z') ?? DateTime.now().toUtc();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final last = home.lastDaily == null ? null : DateTime.tryParse('${home.lastDaily}T00:00:00Z');
    final first = last?.subtract(Duration(days: home.streak - 1));
    FlameLook lookOf(DateTime d) {
      if (d.isAfter(today)) return FlameLook.off;
      if (last != null && first != null && !d.isBefore(first) && !d.isAfter(last) && home.streak > 0) return FlameLook.done;
      if (d == today) return FlameLook.today;
      return FlameLook.off;
    }

    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flame(size: 36, look: home.streak > 0 ? FlameLook.done : FlameLook.off, onDark: true),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Streak ${home.streak} hari',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(
                      home.done ? 'Quiz hari ini selesai' : 'Belum quiz hari ini',
                      style: const TextStyle(fontSize: 12, color: Color(0xBFFFFFFF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Builder(builder: (context) {
                  final d = monday.add(Duration(days: i));
                  final isToday = d == today;
                  return Column(
                    children: [
                      Flame(size: 28, look: lookOf(d), onDark: true),
                      const SizedBox(height: 4),
                      Text(
                        days[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                          color: isToday ? Colors.white : const Color(0xB3FFFFFF),
                        ),
                      ),
                    ],
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubStat extends StatelessWidget {
  const _HubStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy)),
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      );
}

class _HubRow extends StatelessWidget {
  const _HubRow({required this.glyph, required this.title, required this.subtitle, required this.onTap, this.last = false});

  final AppGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: AppColors.divider))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
              child: Center(child: AppIcon(glyph, size: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
