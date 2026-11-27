import 'dart:async';
import 'dart:math' as math;

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

// The streak flame on a 100 x 120 grid, base at y 118: four flat layers
// (red-orange, orange, yellow, cream), as in the approved mockup v5.
final _flameOuter = parseSvgPathData(
    'M50 118C27 118 12 103 12 82C12 66 19 55 28 46C28 54 30 59 34 62C36 50 40 40 47 32C55 23 58 12 52 2C66 8 76 18 79 32C80 38 79 44 75 50C83 58 88 69 88 82C88 103 73 118 50 118Z');
final _flameMid = parseSvgPathData(
    'M50 118C33 118 20 106 20 89C20 79 24 71 30 65C32 72 36 76 41 78C42 64 47 52 55 40C60 54 70 64 74 75C77 82 79 87 79 92C79 107 67 118 50 118Z');
final _flameCore = parseSvgPathData(
    'M50 118C40 118 33 111 33 103C33 97 36 93 40 90C41 95 43 97 46 98C47 91 50 85 52 78C55 86 59 90 62 95C64 92 65 90 65 87C68 92 68 97 68 103C68 111 60 118 50 118Z');
final _flameHeart = parseSvgPathData(
    'M50 118C45 118 42 115 42 111C42 108 44 105 46 103C47 106 48 107 49 107C50 103 52 100 54 98C55 102 57 104 58 107C59 111 56 118 50 118Z');
final _spark = parseSvgPathData('M0 -6C1.5 -3 3 -1 3 1.5A3 3 0 0 1 -3 1.5C-3 -1 -1.5 -3 0 -6Z');

enum FlameLook {
  /// In colour: a day done.
  done,

  /// Grey: a day missed.
  off,

  /// Faint: a day still to come.
  later,

  /// Dashed orange outline: today, not done yet.
  today,

  /// Grey with a snowflake: the streak freeze kept the streak.
  freeze,
}

/// The streak flame. [live] makes its layers flicker, each at its own pace.
class Flame extends StatefulWidget {
  const Flame({super.key, this.size = 16, this.look = FlameLook.done, this.onDark = false, this.live = false});

  /// Height; the width is 5/6 of it.
  final double size;
  final FlameLook look;

  /// On the navy header the greys are see-through whites.
  final bool onDark;
  final bool live;

  /// Tests turn the flicker off, so pumpAndSettle can finish.
  static bool animate = true;

  @override
  State<Flame> createState() => _FlameState();
}

class _FlameState extends State<Flame> with SingleTickerProviderStateMixin {
  AnimationController? _flicker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Flame old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want = widget.live && widget.look == FlameLook.done && Flame.animate;
    if (want && _flicker == null) {
      _flicker = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))..repeat();
    } else if (!want && _flicker != null) {
      _flicker!.dispose();
      _flicker = null;
    }
  }

  @override
  void dispose() {
    _flicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.size * 100 / 120, widget.size);
    final flicker = _flicker;
    // Greys for a dark background: the navy header, or any card in dark mode.
    final onDark = widget.onDark || AppColors.dark;
    if (flicker == null) {
      return CustomPaint(size: size, painter: _FlamePainter(widget.look, onDark, widget.size, AppColors.navy, 0));
    }
    return AnimatedBuilder(
      animation: flicker,
      builder: (_, _) => CustomPaint(
        size: size,
        painter: _FlamePainter(widget.look, onDark, widget.size, AppColors.navy, flicker.value),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.look, this.onDark, this.height, this.navy, this.t);

  final FlameLook look;
  final bool onDark;
  final double height;
  final Color navy;

  /// Flicker time, 0..1 over one loop.
  final double t;

  static const _lit = [Color(0xFFFF5126), Color(0xFFFF9A33), Color(0xFFFFD447), Color(0xFFFFF3C4)];
  static const _greyLight = [Color(0xFFC3C8CF), Color(0xFFD3D7DD), Color(0xFFE1E4E8), Color(0xFFEEF0F2)];
  static const _greyDark = [Color(0xFF6E7A8E), Color(0xFF8A95A7), Color(0xFFA6AFBD), Color(0xFFC2C9D3)];

  /// Squash-and-stretch about the flame's base, [beats] times per loop.
  void _sway(Canvas canvas, int beats, double amount, double phase) {
    if (t == 0) return;
    final a = math.sin((t * beats + phase) * 2 * math.pi);
    canvas
      ..translate(50, 118)
      ..scale(1 - a * amount * .6, 1 + a * amount)
      ..transform((Matrix4.identity()..setEntry(0, 1, a * amount * .4)).storage)
      ..translate(-50, -118);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.height / 120);
    final fill = Paint()..style = PaintingStyle.fill;
    switch (look) {
      case FlameLook.today:
        fill.color = const Color(0xFFF08A1C).withValues(alpha: onDark ? .12 : .08);
        canvas.drawPath(_flameOuter, fill);
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFFF08A1C);
        canvas.drawPath(dashPath(_flameOuter, dashArray: CircularIntervalList([10.0, 8.0])), edge);
      case FlameLook.later:
        fill.color = onDark ? const Color(0x1AFFFFFF) : const Color(0xFFE7E9EC);
        canvas.drawPath(_flameOuter, fill);
      case FlameLook.done || FlameLook.off || FlameLook.freeze:
        final colors = look == FlameLook.done ? _lit : (onDark ? _greyDark : _greyLight);
        canvas.save();
        _sway(canvas, 2, .025, 0);
        canvas.drawPath(_flameOuter, fill..color = colors[0]);
        if (look == FlameLook.done && height >= 40) {
          for (final (x, y, s, r) in const [(33.0, 22.0, 1.1, -15.0), (84.0, 30.0, .95, 12.0), (22.0, 40.0, .85, -20.0)]) {
            canvas
              ..save()
              ..translate(x, y)
              ..rotate(r * math.pi / 180)
              ..scale(s)
              ..drawPath(_spark, fill)
              ..restore();
          }
        }
        canvas.save();
        _sway(canvas, 3, .035, .3);
        canvas.drawPath(_flameMid, fill..color = colors[1]);
        canvas.save();
        _sway(canvas, 4, .05, .6);
        canvas
          ..drawPath(_flameCore, fill..color = colors[2])
          ..drawPath(_flameHeart, fill..color = colors[3])
          ..restore()
          ..restore()
          ..restore();
        if (look == FlameLook.freeze) {
          final snow = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..color = onDark ? const Color(0xFF9DB6DA) : navy;
          canvas
            ..drawLine(const Offset(50, 72), const Offset(50, 108), snow)
            ..drawLine(const Offset(34.4, 81), const Offset(65.6, 99), snow)
            ..drawLine(const Offset(65.6, 81), const Offset(34.4, 99), snow);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.look != look || old.onDark != onDark || old.t != t || old.height != height || old.navy != navy;
}

/// The seven days Monday..Sunday of the week holding quiz day [day]
/// ("2026-11-06"), each a flame: done inside the streak that ends on
/// [lastDaily], today dashed, missed grey, days to come faint. [lightUp]
/// makes today's flame pop in (the streak just went up).
class StreakWeek extends StatelessWidget {
  const StreakWeek({
    super.key,
    required this.day,
    required this.lastDaily,
    required this.streak,
    this.onDark = false,
    this.size = 28,
    this.lightUp = false,
  });

  final String day;
  final String? lastDaily;
  final int streak;
  final bool onDark;
  final double size;
  final bool lightUp;

  static const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.tryParse('${day}T00:00:00Z') ?? DateTime.now().toUtc();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final last = lastDaily == null ? null : DateTime.tryParse('${lastDaily}T00:00:00Z');
    final first = last?.subtract(Duration(days: streak - 1));
    FlameLook lookOf(DateTime d) {
      if (d.isAfter(today)) return FlameLook.later;
      if (last != null && first != null && !d.isBefore(first) && !d.isAfter(last) && streak > 0) return FlameLook.done;
      if (d == today) return FlameLook.today;
      return FlameLook.off;
    }

    final muted = onDark ? const Color(0xB3FFFFFF) : AppColors.muted;
    final strong = onDark ? Colors.white : AppColors.ink;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final d = monday.add(Duration(days: i));
            final isToday = d == today;
            Widget flame = Flame(size: size, look: lookOf(d), onDark: onDark);
            if (isToday && lightUp) flame = PopIn(delay: const Duration(milliseconds: 900), child: flame);
            return Column(
              children: [
                flame,
                const SizedBox(height: 4),
                Text(
                  days[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                    color: isToday ? strong : muted,
                  ),
                ),
              ],
            );
          }),
      ],
    );
  }
}

/// Grows its child in with a small overshoot, once.
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _wait = Timer(widget.delay, () {
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, child) => Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: .3 + .7 * _a.value, alignment: Alignment.bottomCenter, child: child),
        ),
        child: widget.child,
      );
}

/// A round badge with the flame and the streak number in a navy pill
/// (Home card).
class StreakRing extends StatelessWidget {
  const StreakRing({super.key, required this.streak, required this.look});

  final int streak;
  final FlameLook look;

  @override
  Widget build(BuildContext context) {
    final lit = look == FlameLook.done || look == FlameLook.today;
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: lit ? AppColors.orangeSoft : AppColors.background),
            child: Flame(size: 34, look: lit ? FlameLook.done : look, live: look == FlameLook.done),
          ),
          Positioned(
            right: -4,
            bottom: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.navyFill,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: Text('$streak', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
            ),
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
