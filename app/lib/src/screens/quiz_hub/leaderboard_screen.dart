/// The Leaderboard page.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../quiz.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../quiz_hub_screen.dart';
import '../quiz_screen.dart';
import '../shell.dart';
import 'avatar_picker_screen.dart';
import 'leaderboard_widgets.dart';

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
              color: AppColors.navyFill,
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
                  if (board != null && board.rows.isNotEmpty) Podium(rows: board.rows.take(3).toList(), onMe: _changeAvatar),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            if (board == null && _error != null)
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Gagal memuat leaderboard',
                message: 'Periksa koneksi internet',
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
              if (board.me != null) RaceCard(board: board),
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
                        BoardRowTile(row: r, onMe: _changeAvatar),
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
