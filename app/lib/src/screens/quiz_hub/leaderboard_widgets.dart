/// Pieces of the Leaderboard: podium, the "kejar" card, rows and the
/// section streak badge.
library;

import 'package:flutter/material.dart';

import '../../quiz.dart';
import '../../theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/quiz_widgets.dart';
import '../quiz_hub_screen.dart';

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

class Podium extends StatelessWidget {
  const Podium({super.key, required this.rows, required this.onMe});

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
                    color: place == 1 ? AppColors.header : Colors.white,
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
class RaceCard extends StatelessWidget {
  const RaceCard({super.key, required this.board});

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

class BoardRowTile extends StatelessWidget {
  const BoardRowTile({super.key, required this.row, required this.onMe});

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
