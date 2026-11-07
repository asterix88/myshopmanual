import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../page_image.dart';
import '../quiz.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

/// "Atur gambar": the admin moves and resizes a box over the question's page
/// (words already covered) to choose the drawing the mechanic sees. It opens
/// on the automatic choice.
class QuizCropScreen extends StatefulWidget {
  const QuizCropScreen({super.key, required this.api, required this.file, required this.question, this.page});

  final QuizApi api;
  final ManualFile file;
  final QuizQuestion question;

  /// The drawn page, for tests; drawn from the manual when null.
  final Future<QuizPage> Function()? page;

  @override
  State<QuizCropScreen> createState() => _QuizCropScreenState();
}

enum _Grip { move, topLeft, topRight, bottomLeft, bottomRight }

class _QuizCropScreenState extends State<QuizCropScreen> {
  QuizPage? _page;
  Object? _error;
  Rect? _crop;
  Rect? _auto;
  _Grip? _grip;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draw();
  }

  Future<void> _draw() async {
    try {
      final page = await (widget.page?.call() ??
          renderQuizPage(StoreScope.read(context), widget.file, widget.question.page));
      if (!mounted) {
        page.dispose();
        return;
      }
      final auto = page.autoCropFor(calloutOf(widget.question.prompt));
      setState(() {
        _page = page;
        _auto = auto;
        _crop = auto;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _page?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final page = _page;
    final crop = _crop;
    if (page == null || crop == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.uploadImage(widget.question.id, await page.png(crop));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      backgroundColor: AppColors.viewerBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Atur gambar'),
            Text('${widget.file.title} · hal. ${widget.question.page}',
                style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: page == null
          ? Center(
              child: _error == null
                  ? const ExcavatorLoader()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Halaman tidak bisa digambar. Coba lagi saat ada sinyal.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: LayoutBuilder(builder: (context, box) {
                final scale = math.min(box.maxWidth / page.width, box.maxHeight / page.height);
                final size = Size(page.width * scale, page.height * scale);
                return Center(
                  child: SizedBox.fromSize(
                    size: size,
                    child: GestureDetector(
                      onPanStart: (d) => _grip = _gripAt(d.localPosition / scale, 28 / scale),
                      onPanUpdate: (d) => _drag(d.delta / scale),
                      onPanEnd: (_) => _grip = null,
                      child: Stack(fit: StackFit.expand, children: [
                        RawImage(image: page.image, fit: BoxFit.fill),
                        CustomPaint(painter: _CropPainter(_crop!, scale, AppColors.navy)),
                      ]),
                    ),
                  ),
                );
              }),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Geser kotak atau sudutnya.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: page == null || _saving || _crop == _auto ? null : () => setState(() => _crop = _auto),
                      child: const Text('Otomatis'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: page == null || _saving ? null : _save,
                      child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _Grip? _gripAt(Offset p, double reach) {
    final r = _crop!;
    final corners = {
      _Grip.topLeft: r.topLeft,
      _Grip.topRight: r.topRight,
      _Grip.bottomLeft: r.bottomLeft,
      _Grip.bottomRight: r.bottomRight,
    };
    for (final MapEntry(key: grip, value: c) in corners.entries) {
      if ((c - p).distance <= reach) return grip;
    }
    return r.contains(p) ? _Grip.move : null;
  }

  void _drag(Offset d) {
    final grip = _grip;
    final page = _page;
    var r = _crop;
    if (grip == null || page == null || r == null) return;
    final w = page.width.toDouble();
    final h = page.height.toDouble();
    final least = math.max(w, h) * 0.06;
    switch (grip) {
      case _Grip.move:
        final dx = d.dx.clamp(-r.left, w - r.right);
        final dy = d.dy.clamp(-r.top, h - r.bottom);
        r = r.shift(Offset(dx, dy));
      case _Grip.topLeft:
        r = Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - least), (r.top + d.dy).clamp(0, r.bottom - least), r.right, r.bottom);
      case _Grip.topRight:
        r = Rect.fromLTRB(r.left, (r.top + d.dy).clamp(0, r.bottom - least), (r.right + d.dx).clamp(r.left + least, w), r.bottom);
      case _Grip.bottomLeft:
        r = Rect.fromLTRB((r.left + d.dx).clamp(0, r.right - least), r.top, r.right, (r.bottom + d.dy).clamp(r.top + least, h));
      case _Grip.bottomRight:
        r = Rect.fromLTRB(r.left, r.top, (r.right + d.dx).clamp(r.left + least, w), (r.bottom + d.dy).clamp(r.top + least, h));
    }
    setState(() => _crop = r);
  }
}

/// Dims the page outside the crop box and draws the box with its corners.
class _CropPainter extends CustomPainter {
  _CropPainter(this.crop, this.scale, this.color);

  final Rect crop;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(crop.left * scale, crop.top * scale, crop.right * scale, crop.bottom * scale);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(outside, Paint()..color = const Color(0x59000000));
    canvas.drawRect(r, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final grip = Paint()..color = color;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 8, grip);
      canvas.drawCircle(c, 8, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop || old.scale != scale || old.color != color;
}
