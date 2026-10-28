import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The MyManual logo drawn in code: an orange torque arrow around a navy
/// nut. [arcTurn] turns the arrow (radians) and [nutScale] grows the nut, so
/// the splash can tighten the nut. Same shapes as assets/images/logo.png,
/// on a 100 x 100 grid.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 92, this.arcTurn = 0, this.nutScale = 1});

  final double size;
  final double arcTurn;
  final double nutScale;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(arcTurn: arcTurn, nutScale: nutScale),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.arcTurn, required this.nutScale});

  final double arcTurn;
  final double nutScale;

  static const orange = Color(0xFFF08A1C);
  static const navy = Color(0xFF1E3A64);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    const center = Offset(50, 50);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(arcTurn);
    canvas.translate(-center.dx, -center.dy);
    // From -48° clockwise round to 226°, leaving the gap at the top left.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 30),
      -48 * math.pi / 180,
      274 * math.pi / 180,
      false,
      Paint()
        ..color = orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.5
        ..strokeCap = StrokeCap.round,
    );
    final head = Path()
      ..moveTo(21.5, 20.5)
      ..lineTo(37.8, 20.1)
      ..lineTo(36.8, 36.3)
      ..close();
    canvas.drawPath(head, Paint()..color = orange);
    canvas.drawPath(
      head,
      Paint()
        ..color = orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (nutScale <= 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(nutScale);
    canvas.translate(-center.dx, -center.dy);
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = (-90 + 60 * i) * math.pi / 180;
      final p = center + Offset(math.cos(a), math.sin(a)) * 16;
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();
    canvas.drawPath(
      hex,
      Paint()
        ..color = navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    final nut = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(hex, Offset.zero)
      ..addOval(Rect.fromCircle(center: center, radius: 6));
    canvas.drawPath(nut, Paint()..color = navy);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.arcTurn != arcTurn || old.nutScale != nutScale;
}
