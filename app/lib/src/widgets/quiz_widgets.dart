import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme.dart';

/// The 10 Quiz avatars (assets/avatars/avatar_0..9.png): mechanics in the
/// blue shirt and orange vest, each with another face (mockup v20).
const avatarNames = [
  'Senyum lebar', 'Kedip', 'Tertawa', 'Santai', 'Kaget',
  'Kalem', 'Penasaran', 'Iseng', 'Semangat', 'Senior',
];

/// The order on "Ganti avatar".
const avatarOrder = [3, 7, 0, 5, 9, 2, 6, 1, 8, 4];

class QuizAvatar extends StatelessWidget {
  const QuizAvatar(this.index, {super.key, this.size = 40});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/avatars/avatar_${index.clamp(0, 9)}.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: avatarNames[index.clamp(0, 9)],
      ),
    );
  }
}

final _flamePath = parseSvgPathData('M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2.5 1.5-4 2.5-5 .3 1.6 1 2.5 2 3 .5-3 .5-5.5.5-8z');

enum FlameLook {
  /// Orange gradient: a day done.
  done,

  /// Grey: a day missed or not yet.
  off,

  /// Grey with a dashed orange edge: today, not done yet.
  today,

  /// Grey with a snowflake: the streak freeze kept the streak.
  freeze,
}

/// The streak flame, drawn from the mockup's path.
class Flame extends StatelessWidget {
  const Flame({super.key, this.size = 16, this.look = FlameLook.done, this.onDark = false});

  final double size;
  final FlameLook look;

  /// On the navy header the grey is a see-through white.
  final bool onDark;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * .8, size), painter: _FlamePainter(look, onDark, AppColors.border, AppColors.navy));
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.look, this.onDark, this.grey, this.navy);

  final FlameLook look;
  final bool onDark;
  final Color grey;
  final Color navy;

  @override
  void paint(Canvas canvas, Size size) {
    // The flame sits in x 6..18, y 2.5..18.5 of its 24 grid.
    final scale = size.height / 16;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-6, -2.5);
    final rect = const Rect.fromLTWH(6, 2.5, 12, 16);
    final off = onDark ? const Color(0x38FFFFFF) : grey;
    final fill = Paint()..style = PaintingStyle.fill;
    if (look == FlameLook.done) {
      fill.shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xFFE25B12), Color(0xFFF08A1C), Color(0xFFFFC56B)],
        stops: [0, .6, 1],
      ).createShader(rect);
    } else {
      fill.color = off;
    }
    canvas.drawPath(_flamePath, fill);
    if (look == FlameLook.today) {
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFF08A1C);
      canvas.drawPath(dashPath(_flamePath, dashArray: CircularIntervalList([2.0, 2.0])), edge);
    }
    if (look == FlameLook.freeze) {
      final snow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = onDark ? const Color(0xFF9DB6DA) : navy;
      canvas.drawPath(parseSvgPathData('M12 10.5v6M9.4 12l5.2 3M14.6 12l-5.2 3'), snow);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.look != look || old.onDark != onDark || old.grey != grey;
}

/// A round badge with the flame and the streak number (Home card).
class StreakRing extends StatelessWidget {
  const StreakRing({super.key, required this.streak, required this.look});

  final int streak;
  final FlameLook look;

  @override
  Widget build(BuildContext context) {
    final lit = look == FlameLook.done;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? AppColors.orangeSoft : AppColors.background,
        border: Border.all(
          color: switch (look) {
            FlameLook.done => AppColors.orange,
            FlameLook.today => AppColors.orange.withValues(alpha: .5),
            FlameLook.freeze => AppColors.navy.withValues(alpha: .4),
            FlameLook.off => AppColors.border,
          },
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flame(size: 16, look: look == FlameLook.today ? FlameLook.done : look),
          Text(
            '$streak',
            style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// A small label with a line arrow: up green, down red.
class RankChange extends StatelessWidget {
  const RankChange(this.change, {super.key});

  final int change;

  @override
  Widget build(BuildContext context) {
    final up = change > 0;
    final color = up ? AppColors.green : AppColors.danger;
    return Semantics(
      label: '${up ? 'Naik' : 'Turun'} ${change.abs()} peringkat',
      excludeSemantics: true,
      child: Container(
        height: 18,
        padding: const EdgeInsets.fromLTRB(3, 0, 6, 0),
        decoration: BoxDecoration(
          color: up ? AppColors.greenSoft : AppColors.danger.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: color),
            Text('${change.abs()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// A grey placeholder bar while something loads (no empty spinner).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(radius)),
      );
}
