/// The quiz card on Home: today's quiz and the streak.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../quiz.dart';
import '../../theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/quiz_widgets.dart';
import '../quiz_admin_screen.dart';
import '../quiz_hub_screen.dart';
import '../quiz_screen.dart';
import '../shell.dart';

/// The Quiz card at the top of Home: today's Quiz harian and the streak.
/// Hidden while there is no login, and for mechanics while no question is
/// published yet.
class QuizHomeCard extends StatefulWidget {
  const QuizHomeCard({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizHomeCard> createState() => _QuizHomeCardState();
}

class _QuizHomeCardState extends State<QuizHomeCard> {
  late final http.Client _client = widget.client ?? http.Client();
  QuizHome? _home = QuizApi.lastHome;
  bool _offline = false;

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
    final store = StoreScope.read(context);
    if (store.session == null) return;
    try {
      final home = await QuizApi(store, _client).home();
      if (mounted) {
        setState(() {
          _home = home;
          _offline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final home = _home;
    final admin = store.session?.admin ?? false;
    if (store.session == null || home == null) return const SizedBox.shrink();
    if (home.questions == 0 && !admin) return const SizedBox.shrink();

    final now = DateTime.now();
    // A quiz day ends at 04.00; from 18.00 the card warns.
    final end = DateTime(now.year, now.month, now.day, 4).add(Duration(days: now.hour >= 4 ? 1 : 0));
    final hoursLeft = end.difference(now).inMinutes / 60;
    final yesterday = _shift(home.day, -1);
    final freeze = !home.done && home.streak > 0 && home.lastDaily != null && home.lastDaily != yesterday;

    late FlameLook look;
    late String title;
    late Widget sub;
    var cta = 'Mulai';
    VoidCallback onTap = () => _play(context);
    final muted = TextStyle(fontSize: 12, color: AppColors.muted);
    if (home.questions == 0) {
      look = FlameLook.off;
      title = 'Quiz harian';
      sub = Text('Belum ada soal terbit', style: muted);
      cta = 'Kelola';
      onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizAdminScreen()));
    } else if (home.done) {
      look = FlameLook.done;
      title = 'Streak ${home.streak} hari';
      sub = Text('Quiz hari ini selesai', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.green));
      cta = 'Lihat';
      onTap = () => _hub(context);
    } else if (home.daily == 'lanjutkan') {
      look = FlameLook.today;
      title = 'Lanjutkan quiz';
      sub = Text('Belum selesai', style: muted);
      cta = 'Lanjutkan';
    } else if (freeze) {
      look = FlameLook.freeze;
      title = 'Jaga streakmu';
      sub = Text('Libur streak terpakai', style: muted);
    } else if (home.streak > 0 && hoursLeft <= 10) {
      look = FlameLook.today;
      title = 'Jaga streakmu';
      final h = hoursLeft < 1 ? 'kurang dari 1 jam' : '${hoursLeft.floor()} jam';
      sub = Text('Berakhir $h lagi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amber));
    } else {
      look = home.streak > 0 ? FlameLook.today : FlameLook.off;
      title = home.streak > 0 ? 'Quiz harian' : 'Mulai streak baru';
      sub = Text('10 soal · sekitar 4 menit', style: muted);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            StreakRing(streak: home.streak, look: look),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  if (_offline)
                    Row(
                      children: [
                        AppIcon(AppGlyph.cloudOff, size: 14, color: AppColors.amber),
                        const SizedBox(width: 4),
                        Flexible(child: Text('Quiz butuh internet', style: TextStyle(fontSize: 12, color: AppColors.amber))),
                      ],
                    )
                  else
                    sub,
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(cta, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
            Icon(Icons.chevron_right, size: 20, color: AppColors.navy),
          ],
        ),
      ),
    );
  }

  void _play(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizPlayScreen()));

  void _hub(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizHubScreen()));
}

/// "2026-11-06" moved by [days].
String _shift(String day, int days) {
  final d = DateTime.tryParse('${day}T00:00:00Z');
  if (d == null) return '';
  return d.add(Duration(days: days)).toIso8601String().substring(0, 10);
}
