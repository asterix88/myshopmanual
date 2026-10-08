import 'package:flutter/material.dart';

import '../models.dart';

/// The folder picture for a machine kind: the PC2000 for excavators and the
/// D375 for bulldozers (the unit pictures in assets/units), a plain folder
/// for anything else.
class MachineIcon extends StatelessWidget {
  const MachineIcon(this.machine, {super.key, this.width = 96});

  final Machine machine;
  final double width;

  static const _pictures = {Machine.excavator: 'assets/units/pc2000.png', Machine.bulldozer: 'assets/units/d375.png'};

  @override
  Widget build(BuildContext context) {
    final picture = _pictures[machine];
    return SizedBox(
      width: width,
      height: width * 2 / 3,
      child: picture != null ? Image.asset(picture, fit: BoxFit.contain) : CustomPaint(painter: _FolderPainter()),
    );
  }
}

class _FolderPainter extends CustomPainter {
  static final _body = Paint()..color = const Color(0xFFF08A1C);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 120 x 80 grid.
    canvas.scale(size.width / 120, size.height / 80);
    _other(canvas);
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
  bool shouldRepaint(_FolderPainter old) => false;
}
