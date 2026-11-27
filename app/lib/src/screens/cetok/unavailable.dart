import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../theme.dart';
import '../home_screen.dart' show titleCase;

/// Cetok Online for a section that has none yet (no entry in the server's
/// ai-worker/cetok.json): a road barrier in front of a web page and one line.
class CetokUnavailableScreen extends StatelessWidget {
  const CetokUnavailableScreen({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.navyFill,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: const Text(
            'Cetok Online',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RoadworkPicture(size: 136),
                const SizedBox(height: 20),
                Text(
                  'Fitur sedang dalam tahap pengembangan',
                  key: const Key('cetok-unavailable'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Section ${titleCase(section)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A web page behind a road barrier: navy lines, orange barrier stripes,
/// on a soft circle (120 x 120 grid).
class RoadworkPicture extends StatelessWidget {
  const RoadworkPicture({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RoadworkPainter(AppColors.navy, AppColors.orange, AppColors.navySoft, AppColors.surface),
    ),
  );
}

class _RoadworkPainter extends CustomPainter {
  _RoadworkPainter(this.line, this.accent, this.soft, this.board);

  final Color line, accent, soft, board;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 120);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = line;
    canvas.drawCircle(const Offset(60, 60), 56, Paint()..color = soft);
    // The web page.
    canvas.drawPath(parseSvgPathData('M78 76H28a4 4 0 0 1-4-4V30a4 4 0 0 1 4-4h56a4 4 0 0 1 4 4v24M24 36h64'), stroke);
    for (final x in [30.0, 35.0, 40.0]) {
      canvas.drawCircle(Offset(x, 31), 1.4, fill);
    }
    final thin = Paint.from(stroke)..strokeWidth = 2;
    canvas.drawRRect(RRect.fromLTRBR(30, 41, 64, 47, const Radius.circular(2)), thin);
    canvas.drawRRect(RRect.fromLTRBR(68, 41, 82, 47, const Radius.circular(2)), thin);
    // The barrier: lamps, board with orange stripes, legs.
    canvas.drawPath(parseSvgPathData('M54 66v-6M92 66v-6'), stroke);
    canvas.drawCircle(const Offset(54, 56), 4.5, fill);
    canvas.drawCircle(const Offset(92, 56), 4.5, fill);
    final boardRect = RRect.fromLTRBR(44, 66, 102, 79, const Radius.circular(2));
    canvas.drawRRect(boardRect, Paint()..color = board);
    canvas.save();
    canvas.clipRRect(boardRect);
    final stripe = Paint()..color = accent;
    for (var x = 44.0; x < 110; x += 16) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 79)
          ..lineTo(x + 8, 66)
          ..lineTo(x + 15, 66)
          ..lineTo(x + 7, 79)
          ..close(),
        stripe,
      );
    }
    canvas.restore();
    canvas.drawRRect(boardRect, stroke);
    canvas.drawPath(parseSvgPathData('M54 79l-5 17M92 79l5 17M44 96h14M90 96h14'), stroke);
  }

  @override
  bool shouldRepaint(_RoadworkPainter old) =>
      old.line != line || old.accent != accent || old.soft != soft || old.board != board;
}
