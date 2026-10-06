import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Side view of an excavator or a bulldozer, drawn in the app's navy and
/// orange so the folders read at a glance without image assets.
class MachineIcon extends StatelessWidget {
  const MachineIcon(this.machine, {super.key, this.width = 96});

  final Machine machine;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 2 / 3,
      child: CustomPaint(painter: _MachinePainter(machine)),
    );
  }
}

class _MachinePainter extends CustomPainter {
  _MachinePainter(this.machine);

  final Machine machine;

  static final _body = Paint()..color = const Color(0xFFF08A1C);
  static final _dark = Paint()..color = const Color(0xFF1E3A64);
  static final _glass = Paint()..color = const Color(0xFFDDE6F3);
  static final _wheel = Paint()..color = const Color(0xFF8FA3C0);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 120 x 80 grid.
    canvas.scale(size.width / 120, size.height / 80);
    switch (machine) {
      case Machine.excavator:
        _excavator(canvas);
      case Machine.bulldozer:
        _bulldozer(canvas);
      case Machine.other:
        _other(canvas);
    }
  }

  void _track(Canvas canvas, Rect rect) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)), _dark);
    final r = rect.height * 0.26;
    final y = rect.center.dy;
    final count = (rect.width / (rect.height * 0.9)).floor();
    final step = (rect.width - rect.height) / (count - 1);
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(rect.left + rect.height / 2 + step * i, y), r, _wheel);
    }
  }

  void _excavator(Canvas canvas) {
    _track(canvas, const Rect.fromLTWH(10, 60, 62, 14));
    // Swing frame between track and house.
    canvas.drawRect(const Rect.fromLTWH(30, 55, 24, 6), _dark);
    // House with counterweight.
    canvas.drawRRect(RRect.fromLTRBR(12, 38, 66, 56, const Radius.circular(4)), _body);
    // Cab.
    canvas.drawRRect(RRect.fromLTRBR(44, 20, 66, 42, const Radius.circular(4)), _body);
    canvas.drawRRect(RRect.fromLTRBR(48, 24, 62, 34, const Radius.circular(2)), _glass);
    // Boom and arm.
    final boom = Paint()
      ..color = AppColors.orange
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(64, 46), const Offset(88, 14), boom);
    canvas.drawLine(const Offset(88, 14), const Offset(104, 42), boom..strokeWidth = 5.5);
    // Bucket.
    final bucket = Path()
      ..moveTo(98, 40)
      ..lineTo(112, 42)
      ..lineTo(108, 58)
      ..quadraticBezierTo(98, 58, 95, 48)
      ..close();
    canvas.drawPath(bucket, _dark);
  }

  void _bulldozer(Canvas canvas) {
    _track(canvas, const Rect.fromLTWH(12, 56, 72, 18));
    // Engine body and cab.
    canvas.drawRRect(RRect.fromLTRBR(20, 38, 78, 58, const Radius.circular(4)), _body);
    canvas.drawRRect(RRect.fromLTRBR(24, 16, 52, 40, const Radius.circular(4)), _body);
    canvas.drawRRect(RRect.fromLTRBR(28, 20, 48, 32, const Radius.circular(2)), _glass);
    // Exhaust stack.
    canvas.drawRRect(RRect.fromLTRBR(62, 26, 66, 40, const Radius.circular(1.5)), _dark);
    // Push arm and blade.
    canvas.drawLine(
      const Offset(76, 52),
      const Offset(94, 58),
      Paint()
        ..color = AppColors.navy
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final blade = Path()
      ..moveTo(92, 30)
      ..lineTo(101, 30)
      ..quadraticBezierTo(96, 52, 104, 74)
      ..lineTo(93, 74)
      ..quadraticBezierTo(88, 52, 92, 30)
      ..close();
    canvas.drawPath(blade, _dark);
    // Ripper at the back.
    canvas.drawLine(
      const Offset(14, 54),
      const Offset(6, 72),
      Paint()
        ..color = AppColors.navy
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _other(Canvas canvas) {
    // A plain folder for units that are neither.
    final folder = Path()
      ..moveTo(22, 20)
      ..lineTo(50, 20)
      ..lineTo(58, 28)
      ..lineTo(98, 28)
      ..quadraticBezierTo(102, 28, 102, 32)
      ..lineTo(102, 66)
      ..quadraticBezierTo(102, 70, 98, 70)
      ..lineTo(22, 70)
      ..quadraticBezierTo(18, 70, 18, 66)
      ..lineTo(18, 24)
      ..quadraticBezierTo(18, 20, 22, 20)
      ..close();
    canvas.drawPath(folder, _body);
  }

  @override
  bool shouldRepaint(_MachinePainter old) => old.machine != machine;
}
