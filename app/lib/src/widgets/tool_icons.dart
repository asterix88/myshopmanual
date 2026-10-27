import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Home tool icons, drawn here rather than taken from an icon set so
/// they look like MyManual's own: white strokes with one orange part, on a
/// navy square. Both are drawn on a 24 x 24 grid.
class ToolIcon extends StatelessWidget {
  const ToolIcon.gauge({super.key, this.size = 48}) : _painter = const _GaugePainter();
  const ToolIcon.partSearch({super.key, this.size = 48}) : _painter = const _PartSearchPainter();

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

/// Cetok Online: a magnifying glass over an orange hex nut, for finding a
/// part in stock.
class _PartSearchPainter extends CustomPainter {
  const _PartSearchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final lens = Offset(10.5 * u, 10.5 * u);
    final nut = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i;
      final p = lens + Offset(math.cos(a), math.sin(a)) * 3.4 * u;
      i == 0 ? nut.moveTo(p.dx, p.dy) : nut.lineTo(p.dx, p.dy);
    }
    nut.close();
    canvas.drawPath(nut, Paint()..color = _orange);
    canvas.drawCircle(lens, 1.2 * u, Paint()..color = _navy);
    canvas.drawCircle(lens, 6.6 * u, _stroke(u, 2.2, Colors.white));
    canvas.drawLine(Offset(15.4 * u, 15.4 * u), Offset(20.2 * u, 20.2 * u), _stroke(u, 3, Colors.white));
  }

  @override
  bool shouldRepaint(_PartSearchPainter oldDelegate) => false;
}
