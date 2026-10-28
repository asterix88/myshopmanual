import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Home tool icons, drawn here rather than taken from an icon set so
/// they look like MyManual's own: white strokes with one orange part, on a
/// navy square. Both are drawn on a 24 x 24 grid.
class ToolIcon extends StatelessWidget {
  const ToolIcon.gauge({super.key, this.size = 48}) : _painter = const _GaugePainter();
  const ToolIcon.box({super.key, this.size = 48}) : _painter = const _BoxPainter();

  final double size;
  final CustomPainter _painter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFF1E3A64), borderRadius: BorderRadius.circular(size * 0.29)),
      alignment: Alignment.center,
      child: CustomPaint(size: Size.square(size * 0.56), painter: _painter),
    );
  }
}

const _orange = Color(0xFFF08A1C);
const _navy = Color(0xFF1E3A64);

Paint _stroke(double unit, double width, Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width * unit
  ..strokeCap = StrokeCap.round;

/// Konversi: a pressure gauge dial with an orange needle.
class _GaugePainter extends CustomPainter {
  const _GaugePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    // The dial fills the upper part of the grid: grow it and centre it.
    canvas.translate(-1.8 * u, -3.12 * u);
    canvas.scale(1.15);
    final hub = Offset(12 * u, 16 * u);
    canvas.drawArc(Rect.fromCircle(center: hub, radius: 7.5 * u), math.pi, math.pi, false, _stroke(u, 2, Colors.white));
    for (final a in [math.pi * 1.25, math.pi * 1.5, math.pi * 1.75]) {
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(hub + dir * 4.6 * u, hub + dir * 5.6 * u, _stroke(u, 1.4, Colors.white));
    }
    canvas.drawLine(hub, Offset(16 * u, 11 * u), _stroke(u, 2.2, _orange));
    canvas.drawCircle(hub, 1.8 * u, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) => false;
}

/// Cetok Online: a parts box with an orange tag, for the parts stock.
class _BoxPainter extends CustomPainter {
  const _BoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final line = _stroke(u, 1.8, Colors.white)..strokeJoin = StrokeJoin.round;
    final box = Path()
      ..moveTo(4 * u, 8 * u)
      ..lineTo(12 * u, 3.5 * u)
      ..lineTo(20 * u, 8 * u)
      ..lineTo(20 * u, 16.5 * u)
      ..lineTo(12 * u, 21 * u)
      ..lineTo(4 * u, 16.5 * u)
      ..close();
    final edges = Path()
      ..moveTo(4 * u, 8 * u)
      ..lineTo(12 * u, 12.5 * u)
      ..lineTo(20 * u, 8 * u)
      ..moveTo(12 * u, 12.5 * u)
      ..lineTo(12 * u, 21 * u);
    canvas.drawPath(box, line);
    canvas.drawPath(edges, line);
    final tag = Offset(17.5 * u, 17 * u);
    canvas.drawCircle(tag, 3.2 * u, Paint()..color = _navy);
    canvas.drawCircle(tag, 3.2 * u, _stroke(u, 1.8, _orange));
  }

  @override
  bool shouldRepaint(_BoxPainter oldDelegate) => false;
}
