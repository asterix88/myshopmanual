import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../quiz.dart';
import '../quiz_reminders.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/quiz_widgets.dart';
import '../widgets/unit_icon.dart';
import 'quiz_admin_screen.dart';
import 'quiz_screen.dart';
import 'shell.dart';

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
        trailing: (store.session?.admin ?? false)
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

/// Quiz per unit: the units with published questions, and how much of each
/// is mastered.
class QuizUnitsScreen extends StatefulWidget {
  const QuizUnitsScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<QuizUnitsScreen> createState() => _QuizUnitsScreenState();
}

class _QuizUnitsScreenState extends State<QuizUnitsScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  List<QuizUnit>? _units;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final units = await QuizApi(StoreScope.read(context), _client).units();
      if (mounted) setState(() => _units = units);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = _units;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Quiz per unit'),
      body: units == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Gagal memuat unit',
                  message: 'Periksa koneksi internet.',
                  action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
                ))
          : units.isEmpty
              ? const EmptyState(icon: Icons.quiz_outlined, title: 'Belum ada soal per unit', message: 'Soal baru sedang disiapkan.')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppCard(
                      child: Column(
                        children: [
                          for (final (i, u) in units.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => QuizPlayScreen(unit: u.unit)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Row(
                                  children: [
                                    UnitIcon(unitId: u.unit, width: 56, height: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(store.unitById(u.unit)?.name ?? u.unit,
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(3),
                                            child: LinearProgressIndicator(
                                              value: u.total == 0 ? 0 : (u.seen / u.total).clamp(0, 1),
                                              minHeight: 6,
                                              color: AppColors.navy,
                                              backgroundColor: AppColors.line,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text('${u.seen} dari ${u.total} soal',
                                                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                              ),
                                              Text(
                                                '${u.total == 0 ? 0 : (u.seen * 100 / u.total).round().clamp(0, 100)}%',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.chevron_right, color: AppColors.muted),
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

/// The department's board this week or month: podium for the top three,
/// then the rest, with the mechanic's own row (tap it to change avatar).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.client});

  final http.Client? client;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final QuizApi _api = QuizApi(StoreScope.read(context), _client);
  bool _month = false;
  final _boards = <bool, Board>{};
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    final month = _month;
    try {
      final board = await _api.leaderboard(month: month);
      if (mounted) {
        setState(() {
          _boards[month] = board;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _changeAvatar(int current) async {
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => AvatarPickerScreen(current: current)),
    );
    if (picked == null || picked == current || !mounted) return;
    try {
      await _api.setAvatar(picked);
      QuizApi.changed.value++;
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _boards[_month];
    final dept = StoreScope.of(context).session?.department ?? '';
    final now = DateTime.now();
    const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    final left = 7 - now.weekday;
    final periodLabel = _month ? months[now.month - 1] : (left == 0 ? 'Selesai hari ini' : 'Selesai $left hari lagi');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: QuizBar(
        title: 'Leaderboard',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(periodLabel, style: const TextStyle(fontSize: 11, color: Color(0xD9FFFFFF))),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
          children: [
            Container(
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: [
                  if (dept.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        [titleCaseWords(dept), if ((board?.count ?? 0) > 0) '${board!.count} mekanik'].join(' · '),
                        style: const TextStyle(fontSize: 12, color: Color(0xBFFFFFFF)),
                      ),
                    ),
                  _PeriodTabs(
                    month: _month,
                    onChanged: (m) {
                      setState(() => _month = m);
                      if (!_boards.containsKey(m)) _load();
                    },
                  ),
                  const SizedBox(height: 8),
                  if (board != null && board.rows.isNotEmpty) _Podium(rows: board.rows.take(3).toList(), onMe: _changeAvatar),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            if (board == null && _error != null)
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Gagal memuat leaderboard',
                message: 'Periksa koneksi internet.',
                action: FilledButton(onPressed: _load, child: const Text('Coba lagi')),
              )
            else if (board == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (board.rows.isEmpty)
              const EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'Belum ada XP periode ini',
                message: 'Selesaikan satu quiz',
              )
            else ...[
              if (board.me != null) _Race(board: board),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppCard(
                  child: Column(
                    children: [
                      for (final r in [
                        ...board.rows.skip(3),
                        if (board.me != null && board.me!.rank > board.rows.length) board.me!,
                      ])
                        _BoardRowTile(row: r, onMe: _changeAvatar),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.month, required this.onChanged});

  final bool month;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) => Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: month == value ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: month == value ? AppColors.navy : Colors.white,
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [tab('Minggu ini', false), tab('Bulan ini', true)]),
    );
  }
}

/// Gold, silver and bronze: light, middle and dark of each metal.
const _metals = [
  [Color(0xFFFFE08A), Color(0xFFF5A623), Color(0xFFC9700E)],
  [Color(0xFFF4F6F9), Color(0xFFC3CBD6), Color(0xFF8C97A6)],
  [Color(0xFFF2C9A2), Color(0xFFC98A5A), Color(0xFF8E5530)],
];

LinearGradient _metal(int i) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _metals[i],
      stops: const [0, .55, 1],
    );

class _Podium extends StatelessWidget {
  const _Podium({required this.rows, required this.onMe});

  final List<BoardRow> rows;
  final ValueChanged<int> onMe;

  @override
  Widget build(BuildContext context) {
    // Second, first, third, as on a podium; a place nobody has yet stays
    // as an empty step, so the podium keeps its shape.
    const order = [1, 0, 2];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.6),
                  radius: .6,
                  colors: [const Color(0xFFFFD68C).withValues(alpha: .16), const Color(0x00FFD68C)],
                ),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final i in order)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: i < rows.length ? _PodiumPlace(row: rows[i], place: i, onMe: onMe) : _EmptyPlace(place: i),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({required this.row, required this.place, required this.onMe});

  final BoardRow row;
  final int place;
  final ValueChanged<int> onMe;

  @override
  Widget build(BuildContext context) {
    final size = place == 0 ? 64.0 : 52.0;
    final height = [86.0, 66.0, 54.0][place];
    Widget avatar = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _metal(place),
        boxShadow: const [BoxShadow(color: Color(0x59050E1E), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: QuizAvatar(row.avatar, size: size - 6),
    );
    if (row.me) {
      avatar = GestureDetector(onTap: () => onMe(row.avatar), child: avatar);
    }
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            avatar,
            Positioned(
              bottom: -9,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: _metal(place),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.navy, width: 2),
                ),
                child: Text(
                  '${place + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: place == 1 ? const Color(0xFF1E3A64) : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          constraints: BoxConstraints(minHeight: height + 20),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: place == 0 ? .22 : .15), Colors.white.withValues(alpha: .04)],
            ),
            border: Border(top: BorderSide(color: _metals[place][1], width: 3)),
          ),
          child: Stack(
            children: [
              Positioned(
                right: 2,
                bottom: -4,
                child: Text(
                  '${place + 1}',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, height: 1, color: Color(0x12FFFFFF)),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      row.me ? '${_firstName(row.name)} (kamu)' : _shortName(row.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${row.xp}', style: TextStyle(fontSize: place == 0 ? 17 : 15, fontWeight: FontWeight.w700)),
                        const TextSpan(text: ' XP', style: TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
                      ]),
                      style: const TextStyle(color: Colors.white),
                    ),
                    _SectionStreak(row: row, color: const Color(0xBFFFFFFF), center: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0x47050E1E),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
          ),
        ),
      ],
    );
  }
}

/// A podium step nobody has reached yet this period.
class _EmptyPlace extends StatelessWidget {
  const _EmptyPlace({required this.place});

  final int place;

  @override
  Widget build(BuildContext context) {
    final size = place == 0 ? 64.0 : 52.0;
    final height = [86.0, 66.0, 54.0][place];
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .06),
            border: Border.all(color: Colors.white.withValues(alpha: .18), width: 2),
          ),
          child: Text(
            '${place + 1}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0x59FFFFFF)),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: height + 20,
          width: double.infinity,
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            color: Colors.white.withValues(alpha: .05),
          ),
          child: const Text('Belum ada', style: TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
        ),
        Container(
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0x2E050E1E),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
          ),
        ),
      ],
    );
  }
}

String _firstName(String name) => titleCaseWords(name.split(' ').first);

/// "Rahmat Suryadi" -> "Rahmat S."
String _shortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return titleCaseWords(name);
  return '${titleCaseWords(parts.first)} ${parts[1][0].toUpperCase()}.';
}

/// At the top: how far ahead of second place.
String _lead(Board board) {
  final second = board.rows.where((r) => r.rank == 2).firstOrNull;
  final me = board.me;
  if (second == null || me == null) return 'Satu-satunya di papan';
  return '${me.xp - second.xp} XP di atas posisi 2';
}

/// How far to the next place.
class _Race extends StatelessWidget {
  const _Race({required this.board});

  final Board board;

  @override
  Widget build(BuildContext context) {
    final me = board.me!;
    final above = board.rows.where((r) => r.rank == me.rank - 1).firstOrNull;
    final gap = above == null ? 0 : above.xp - me.xp + 1;
    return Transform.translate(
      offset: const Offset(0, -4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navySoft, shape: BoxShape.circle),
                    child: Text(
                      '${me.rank}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          above == null ? 'Kamu di puncak' : '$gap XP lagi ke ${me.rank <= 4 ? 'podium' : 'posisi ${above.rank}'}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          above == null ? _lead(board) : 'Sekitar ${(gap / 10).ceil()} jawaban benar',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizUnitsScreen())),
                    child: const Text('Quiz unit', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              if (above != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: above.xp == 0 ? 0 : (me.xp / above.xp).clamp(0, 1),
                    minHeight: 8,
                    color: AppColors.orange,
                    backgroundColor: AppColors.line,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kamu ${me.xp}', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    Text('${above.rank}. ${_shortName(above.name)} ${above.xp}', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardRowTile extends StatelessWidget {
  const _BoardRowTile({required this.row, required this.onMe});

  final BoardRow row;
  final ValueChanged<int> onMe;

  @override
  Widget build(BuildContext context) {
    final avatar = row.me
        ? Semantics(
            button: true,
            label: 'Ganti avatar',
            child: GestureDetector(
              onTap: () => onMe(row.avatar),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.navy, width: 2)),
                    child: QuizAvatar(row.avatar, size: 38),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.orangeSoft, width: 2),
                      ),
                      child: const Center(child: AppIcon(AppGlyph.pencil, size: 9, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          )
        : QuizAvatar(row.avatar, size: 40);
    return Container(
      color: row.me ? AppColors.orangeSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${row.rank}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted)),
          ),
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.me ? '${titleCaseWords(row.name)} (kamu)' : titleCaseWords(row.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: row.me ? FontWeight.w600 : FontWeight.w500),
                      ),
                    ),
                    if (row.change != 0) ...[const SizedBox(width: 6), RankChange(row.change)],
                  ],
                ),
                _SectionStreak(row: row, color: AppColors.muted),
              ],
            ),
          ),
          Text('${row.xp}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
        ],
      ),
    );
  }
}

/// "Ganti avatar": the 10 avatars; Simpan returns the chosen one.
class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({super.key, required this.current});

  final int current;

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  late int _picked = widget.current;

  @override
  Widget build(BuildContext context) {
    final session = StoreScope.of(context).session;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const QuizBar(title: 'Ganti avatar'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: QuizAvatar(_picked, size: 96)),
          const SizedBox(height: 6),
          Text(titleCaseWords(session?.name ?? ''), textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (session != null && session.sections.isNotEmpty)
            Text(session.sections.join(', '), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          const SectionLabel('Pilih avatar'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              children: [
                for (final k in avatarOrder)
                  Semantics(
                    button: true,
                    selected: k == _picked,
                    label: avatarNames[k],
                    child: GestureDetector(
                      onTap: () => setState(() => _picked = k),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: k == _picked ? AppColors.navy : Colors.transparent, width: 2.5),
                          ),
                          child: QuizAvatar(k, size: 52),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Simpan')),
          ),
        ],
      ),
    );
  }
}

/// "Pengingat" on the Quiz page: each mechanic sets their own reminders.
class QuizReminderSettings extends StatefulWidget {
  const QuizReminderSettings({super.key, required this.home});

  final QuizHome home;

  @override
  State<QuizReminderSettings> createState() => _QuizReminderSettingsState();
}

class _QuizReminderSettingsState extends State<QuizReminderSettings> {
  late ReminderSettings _settings = QuizReminders.load(StoreScope.read(context).root);

  static const _times = [(5, 0), (5, 30), (6, 0), (6, 30), (7, 0), (7, 30), (12, 0), (16, 0)];

  Future<void> _set(ReminderSettings settings) async {
    setState(() => _settings = settings);
    final root = StoreScope.read(context).root;
    await QuizReminders.save(root, settings);
    await QuizReminders.sync(root, QuizApi.lastHome ?? widget.home);
  }

  /// "Jam pengingat": the usual times in equal boxes, or any time.
  Future<void> _chooseTime() async {
    final s = _settings;
    final picked = await showModalBottomSheet<(int, int)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Jam pengingat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
                children: [
                  for (final (h, m) in _times)
                    _TimeBox(
                      label: ReminderSettings(hour: h, minute: m).time,
                      selected: s.hour == h && s.minute == m,
                      onTap: () => Navigator.pop(context, (h, m)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, (-1, -1)),
                  child: const Text('Jam lain'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.$1 >= 0) return _set(_settings.copyWith(hour: picked.$1, minute: picked.$2));
    final other = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
      helpText: 'Jam pengingat',
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (other != null) await _set(_settings.copyWith(hour: other.hour, minute: other.minute));
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final muted = TextStyle(fontSize: 12, color: AppColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Caps('Pengingat'),
        AppCard(
          child: Column(
            children: [
              _SwitchRow(
                title: 'Pengingat harian',
                subtitle: Text('Setiap hari', style: muted),
                time: s.daily
                    ? Material(
                        color: AppColors.navySoft,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _chooseTime,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.time,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.navy,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 18, color: AppColors.navy),
                              ],
                            ),
                          ),
                        ),
                      )
                    : null,
                value: s.daily,
                onChanged: (v) => _set(s.copyWith(daily: v)),
              ),
              Divider(height: 1, color: AppColors.divider),
              _SwitchRow(
                title: 'Peringatan streak',
                subtitle: Text('20.00 jika belum quiz', style: muted),
                value: s.streak,
                onChanged: (v) => _set(s.copyWith(streak: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.navy : AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selected ? AppColors.navy : AppColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

class _Caps extends StatelessWidget {
  const _Caps(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: AppColors.muted),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged, this.time});

  final String title;
  final Widget subtitle;
  final Widget? time;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
          if (time != null) ...[time!, const SizedBox(width: 4)],
          Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: AppColors.navy),
        ],
      ),
    ),
  );
}

/// "TRACK 🔥6": the section, and the streak when one stands.
class _SectionStreak extends StatelessWidget {
  const _SectionStreak({required this.row, required this.color, this.center = false});

  final BoardRow row;
  final Color color;
  final bool center;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
    children: [
      Flexible(
        child: Text(
          row.section.split(',').first.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, letterSpacing: .3, color: color),
        ),
      ),
      if (row.streak > 0) ...[
        const SizedBox(width: 8),
        const Flame(size: 12),
        const SizedBox(width: 2),
        Text('${row.streak}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    ],
  );
}
