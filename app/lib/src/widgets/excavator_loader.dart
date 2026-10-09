import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Loading animation: a PC210-style excavator digging, lifting and dumping
/// in a loop. Used instead of the spinning circle while data comes from the
/// server.
class ExcavatorLoader extends StatefulWidget {
  const ExcavatorLoader({super.key, this.label, this.width = 96});

  final String? label;
  final double width;

  /// Off in widget tests, where an endless animation would never settle.
  static bool animate = true;

  @override
  State<ExcavatorLoader> createState() => _ExcavatorLoaderState();
}

class _ExcavatorLoaderState extends State<ExcavatorLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
    value: .5,
  );

  @override
  void initState() {
    super.initState();
    if (ExcavatorLoader.animate) _cycle.repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          height: widget.width * ExcavatorPainter.height / ExcavatorPainter.width,
          child: RepaintBoundary(
            child: CustomPaint(painter: ExcavatorPainter(_cycle, dark: AppColors.dark)),
          ),
        ),
        if (widget.label case final label?) ...[
          const SizedBox(height: 10),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      ],
    );
  }
}

/// One pose of the digging cycle: boom and arm angles from horizontal
/// (degrees, up is positive) and the bucket's angle relative to the arm.
typedef Pose = ({double t, double boom, double arm, double bucket});

const List<Pose> _poses = [
  (t: 0.00, boom: 18, arm: -100, bucket: 10), // reach out, teeth down
  (t: 0.28, boom: 14, arm: -115, bucket: -55), // dig: arm and bucket curl in
  (t: 0.48, boom: 46, arm: -78, bucket: -92), // lift the load
  (t: 0.62, boom: 42, arm: -45, bucket: -125), // reach over the pile
  (t: 0.76, boom: 40, arm: -40, bucket: 60), // dump
  (t: 1.00, boom: 18, arm: -100, bucket: 10), // back to the start
];

class ExcavatorPainter extends CustomPainter {
  ExcavatorPainter(this.cycle, {this.dark = false}) : super(repaint: cycle);

  final Animation<double> cycle;
  final bool dark;

  static const double width = 220;
  static const double height = 130;
  static const double _ground = 122;
  static const Offset _boomFoot = Offset(108, 80);
  static const double _boomLength = 66;
  static const double _armLength = 46;

  static const _yellow = Color(0xFFF2B300);
  static const _yellowDark = Color(0xFFC98F00);
  // Steel parts get lighter at night so they stand out from the dark page.
  Color get _steel => Color(dark ? 0xFF6A717A : 0xFF3B4046);
  static const _rod = Color(0xFFC9CDD2);
  static const _glass = Color(0xFF8FB6D9);
  static const _dirt = Color(0xFF8A5A2B);

  static double _ease(double x) => x < .5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;

  static Pose poseAt(double t) {
    for (var i = 0; i < _poses.length - 1; i++) {
      final a = _poses[i], b = _poses[i + 1];
      if (t <= b.t) {
        final k = _ease((t - a.t) / (b.t - a.t));
        double lerp(double x, double y) => x + (y - x) * k;
        return (t: t, boom: lerp(a.boom, b.boom), arm: lerp(a.arm, b.arm), bucket: lerp(a.bucket, b.bucket));
      }
    }
    return _poses.last;
  }

  static Offset _along(Offset from, double degrees, double length) {
    final r = degrees * math.pi / 180;
    return from + Offset(math.cos(r) * length, -math.sin(r) * length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / width;
    canvas.save();
    canvas.scale(s);
    final t = cycle.value;
    final pose = poseAt(t);
    // A slight engine shake keeps the machine alive between moves.
    final shake = math.sin(t * math.pi * 2 * 14) * .35;

    _paintGround(canvas, t);
    _paintTracks(canvas);

    canvas.save();
    canvas.translate(0, shake);
    final boomTip = _along(_boomFoot, pose.boom, _boomLength);
    final armTip = _along(boomTip, pose.arm, _armLength);
    _paintHouse(canvas, t);
    _paintBoomArm(canvas, pose, boomTip, armTip);
    _paintBucket(canvas, pose, armTip);
    _paintCab(canvas);
    canvas.restore();

    _paintFallingDirt(canvas, t, armTip);
    canvas.restore();
  }

  void _paintGround(Canvas canvas, double t) {
    final line = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: dark ? .22 : .12)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(8, _ground), const Offset(width - 8, _ground), line);
    // The pile the bucket dumps onto grows a little after each dump.
    final grow = t > .78 ? math.min(1.0, (t - .78) / .12) : 0.0;
    final pile = Paint()..color = _dirt.withValues(alpha: .9);
    canvas.drawPath(
      Path()
        ..moveTo(176, _ground)
        ..quadraticBezierTo(194, _ground - 16 - 3 * grow, 212, _ground)
        ..close(),
      pile,
    );
  }

  void _paintTracks(Canvas canvas) {
    final track = RRect.fromLTRBR(26, 102, 134, _ground, const Radius.circular(10));
    canvas.drawRRect(track, Paint()..color = _steel);
    canvas.drawRRect(
      track.deflate(4),
      Paint()..color = dark ? const Color(0xFF8A9199) : const Color(0xFF5E646B),
    );
    final roller = Paint()..color = _steel;
    for (final x in [38.0, 122.0]) {
      canvas.drawCircle(Offset(x, 112), 6, roller);
      canvas.drawCircle(Offset(x, 112), 2.2, Paint()..color = _rod);
    }
    for (final x in [58.0, 74.0, 90.0, 106.0]) {
      canvas.drawCircle(Offset(x, 114), 3.4, roller);
    }
    canvas.drawRect(const Rect.fromLTRB(52, 96, 108, 102), Paint()..color = _steel);
  }

  void _paintHouse(Canvas canvas, double t) {
    // Counterweight at the back, engine hood, then the yellow upper body.
    canvas.drawRRect(
      RRect.fromLTRBR(18, 70, 50, 96, const Radius.circular(7)),
      Paint()..color = _yellowDark,
    );
    final body = Path()
      ..moveTo(26, 96)
      ..lineTo(26, 70)
      ..quadraticBezierTo(28, 64, 36, 64)
      ..lineTo(104, 64)
      ..lineTo(112, 96)
      ..close();
    canvas.drawPath(body, Paint()..color = _yellow);
    canvas.drawLine(const Offset(30, 80), const Offset(84, 80), Paint()
      ..color = _yellowDark
      ..strokeWidth = 1.5);
    canvas.drawRect(const Rect.fromLTRB(26, 92, 112, 96), Paint()..color = _steel.withValues(alpha: .85));
    // Exhaust stack with puffs while the engine works hardest (lifting).
    canvas.drawRect(const Rect.fromLTRB(44, 56, 48, 64), Paint()..color = _steel);
    final puffs = Paint()..color = (dark ? Colors.white : const Color(0xFF6B7178)).withValues(alpha: .0);
    for (var i = 0; i < 3; i++) {
      final p = (t * 3 + i / 3) % 1;
      final strength = (t > .28 && t < .62) ? 1.0 : .35;
      puffs.color = (dark ? Colors.white : const Color(0xFF6B7178)).withValues(alpha: (1 - p) * (dark ? .4 : .28) * strength);
      canvas.drawCircle(Offset(46 - p * 8, 52 - p * 18), 2.5 + p * 4, puffs);
    }
  }

  void _paintCylinder(Canvas canvas, Offset from, Offset to) {
    final barrel = from + (to - from) * .58;
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = _rod
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      from,
      barrel,
      Paint()
        ..color = _steel
        ..strokeWidth = 4.6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintBoomArm(Canvas canvas, Pose pose, Offset boomTip, Offset armTip) {
    final boomMid = Offset.lerp(_boomFoot, boomTip, .55)!;
    // The boom's banana bend: push the middle up, away from the ground.
    final normal = _along(Offset.zero, pose.boom + 90, 1);
    final bend = boomMid + normal * 9;

    // Boom cylinder from the house to under the boom.
    _paintCylinder(canvas, const Offset(112, 92), boomMid - normal * 3);

    final yellowStroke = Paint()
      ..color = _yellow
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(_boomFoot.dx, _boomFoot.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, boomTip.dx, boomTip.dy),
      yellowStroke..strokeWidth = 11,
    );
    canvas.drawPath(
      Path()
        ..moveTo(_boomFoot.dx, _boomFoot.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, boomTip.dx, boomTip.dy),
      Paint()
        ..color = _yellowDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Arm cylinder sits on top of the boom and pushes the arm's back end.
    final armBack = _along(boomTip, pose.arm + 180, 10);
    _paintCylinder(canvas, bend + normal * 4, armBack + normal * 2);

    canvas.drawLine(
      armBack,
      armTip,
      Paint()
        ..color = _yellow
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    for (final p in [_boomFoot, boomTip]) {
      canvas.drawCircle(p, 3, Paint()..color = _steel);
      canvas.drawCircle(p, 1.3, Paint()..color = _rod);
    }
  }

  void _paintBucket(Canvas canvas, Pose pose, Offset armTip) {
    canvas.save();
    canvas.translate(armTip.dx, armTip.dy);
    canvas.rotate(-(pose.arm + pose.bucket) * math.pi / 180);
    // Local frame: +x runs from the pin to the teeth, the opening faces +y.
    final shell = Path()
      ..moveTo(-2, 4)
      ..lineTo(-2, -4)
      ..quadraticBezierTo(14, -14, 23, 2)
      ..lineTo(23, 9)
      ..lineTo(13, 9)
      ..close();
    canvas.drawPath(shell, Paint()..color = _steel);
    canvas.drawPath(
      Path()
        ..moveTo(21, 6)
        ..lineTo(28, 12)
        ..lineTo(19, 10)
        ..close(),
      Paint()..color = _rod,
    );
    // A load of dirt while the bucket is curled and full.
    final t = pose.t;
    if (t > .2 && t < .76) {
      final fill = t < .3 ? (t - .2) / .1 : (t > .7 ? (.76 - t) / .06 : 1.0);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(11, 8), width: 18, height: 9 * fill),
        Paint()..color = _dirt,
      );
    }
    canvas.restore();
    canvas.drawCircle(armTip, 2.6, Paint()..color = _rod);
  }

  void _paintFallingDirt(Canvas canvas, double t, Offset armTip) {
    if (t < .7 || t > .9) return;
    final k = (t - .7) / .2;
    final dirt = Paint()..color = _dirt;
    for (var i = 0; i < 6; i++) {
      final dx = (i - 2.5) * 2.8;
      final fall = k * (_ground - armTip.dy) * (0.7 + (i % 3) * .15);
      final y = armTip.dy + 10 + fall;
      if (y > _ground - 6) continue;
      canvas.drawCircle(Offset(armTip.dx + 4 + dx, y), 1.8 + (i % 2) * .6, dirt);
    }
  }

  void _paintCab(Canvas canvas) {
    final cab = Path()
      ..moveTo(84, 92)
      ..lineTo(84, 44)
      ..quadraticBezierTo(84, 40, 88, 40)
      ..lineTo(104, 40)
      ..lineTo(112, 60)
      ..lineTo(112, 92)
      ..close();
    canvas.drawPath(cab, Paint()..color = _yellow);
    final window = Path()
      ..moveTo(88, 62)
      ..lineTo(88, 45)
      ..lineTo(102, 45)
      ..lineTo(108, 61)
      ..close();
    canvas.drawPath(window, Paint()..color = _glass);
    canvas.drawLine(
      const Offset(97, 45),
      const Offset(97, 62),
      Paint()
        ..color = _yellow
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(cab, Paint()
      ..color = _yellowDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(ExcavatorPainter oldDelegate) => oldDelegate.dark != dark;
}
