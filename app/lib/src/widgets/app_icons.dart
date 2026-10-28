import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../models.dart';
import '../theme.dart';

/// MyManual's own icons (see docs/panduan-desain.md): drawn on a 24 x 24
/// grid as navy lines with at most one orange part, so every screen uses
/// one icon style instead of a mix of icon sets.
class AppIcon extends StatelessWidget {
  const AppIcon(this.glyph, {super.key, this.size = 24, this.color, this.accent});

  final AppGlyph glyph;
  final double size;

  /// The lines; navy when not given.
  final Color? color;

  /// The one highlighted part; orange when not given. Pass [color] to draw
  /// the whole icon in one color (white on the orange nyel AI button).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final main = color ?? AppColors.navy;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(glyph, main, accent ?? (color == null ? AppColors.orange : main))),
    );
  }
}

/// One drawn part of an icon.
sealed class _Part {
  const _Part({this.width = 1.8, this.accent = false, this.fill = false});

  final double width;
  final bool accent;
  final bool fill;

  Path path();
}

class _P extends _Part {
  const _P(this.d, {super.width, super.accent, super.fill});

  final String d;

  @override
  Path path() => parseSvgPathData(d);
}

class _C extends _Part {
  const _C(this.x, this.y, this.r, {super.width, super.accent, super.fill});

  final double x, y, r;

  @override
  Path path() => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
}

class _R extends _Part {
  const _R(this.x, this.y, this.w, this.h, this.r, {this.turn = 0, super.width, super.accent});

  final double x, y, w, h, r;

  /// Degrees, around the rectangle's centre.
  final double turn;

  @override
  Path path() {
    final rect = Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));
    if (turn == 0) return rect;
    final c = Offset(x + w / 2, y + h / 2);
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(turn * math.pi / 180)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    return rect.transform(m.storage);
  }
}

/// The icons. Document types first, then menus and actions.
enum AppGlyph {
  shopManual([
    _P('M5 3.5h10.5l3.5 3.5v13.5H5z'),
    _P('M8.5 16.5l4.2-4.2M12 9.5a2.4 2.4 0 1 0 3.2 3.2l-1.6-.3-.3-1.6z', accent: true),
  ]),
  omm([
    _P('M12 6.5C10 5 7 4.5 3.5 5v13c3.5-.5 6.5 0 8.5 1.5 2-1.5 5-2 8.5-1.5V5c-3.5-.5-6.5 0-8.5 1.5zM12 6.5v13'),
    _P('M15 9.5h3M15 12.5h3', accent: true),
  ]),
  partsbook([
    _R(3.5, 3.5, 7, 7, 1.5),
    _R(13.5, 3.5, 7, 7, 1.5),
    _R(3.5, 13.5, 7, 7, 1.5),
    _C(17, 17, 3.5, accent: true),
  ]),
  systemOperation([
    _C(6, 6.5, 2.5),
    _C(18, 12, 2.5),
    _C(6, 17.5, 2.5),
    _P('M8.5 6.5h3.5a3 3 0 0 1 3 3M8.5 17.5h3.5a3 3 0 0 0 3-3', accent: true),
  ]),
  testing([
    _P('M4.5 16.5a7.5 7.5 0 1 1 15 0'),
    _P('M12 16.5l3.6-5', width: 2, accent: true),
    _C(12, 16.5, 1.6, fill: true),
    _P('M4 20h16'),
  ]),
  disassembly([
    _R(3.5, 9, 8, 10, 1.5),
    _R(13, 4.5, 7.5, 9, 1.5, turn: 12),
    _P('M13.5 17.5h6M17.5 15.5l2 2-2 2', accent: true),
  ]),
  troubleshooting([
    _P('M12 3.5l9 16H3z'),
    _P('M10 11.2a2 2 0 1 1 2.9 1.8c-.6.3-.9.8-.9 1.4', accent: true),
    _C(12, 17, 1.1, accent: true, fill: true),
  ]),
  diagram([
    _P('M3.5 7h3.2M8.5 8.8V17h5.2M15.5 15.2V7h5'),
    _C(8.5, 7, 1.8, accent: true),
    _C(15.5, 17, 1.8, accent: true),
  ]),
  engine([
    _P('M7 8.5h7l2 2h2.5v6H16l-2 2H8.5L6 16H3.5v-5H6z'),
    _P('M9 5.5h5M11.5 5.5v3M18.5 12h2v2.5h-2'),
    _P('M11.8 10.5l-1.6 3h2.6l-1.6 3', width: 1.7, accent: true),
  ]),
  general([
    _P('M5 3.5h9.5L19 8v12.5H5z'),
    _P('M14.5 3.5V8H19'),
    _C(12, 14.5, 2.2, accent: true),
    _P('M12 10.3v1.4M12 17.3v1.4M7.8 14.5h1.4M14.8 14.5h1.4M9 11.5l1 1M14 16.5l1 1M9 17.5l1-1M14 12.5l1-1',
        width: 1.6, accent: true),
  ]),

  home([_P('M4 10.5L12 4l8 6.5V20h-5.5v-5.5h-5V20H4z')]),
  search([_C(10.5, 10.5, 6), _P('M15 15l5 5', width: 2)]),
  // nyel AI: the hex nut of the MyManual logo inside a speech bubble.
  nyel([
    _P('M4 6.5a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v7a3 3 0 0 1-3 3h-6l-4.5 4v-4H7a3 3 0 0 1-3-3z', width: 1.9),
    _P('M12 6.6l2.7 1.55v3.1L12 12.8l-2.7-1.55v-3.1z', width: 1.7),
  ]),
  standar([
    _P('M4.5 16.5a7.5 7.5 0 1 1 15 0'),
    _P('M12 16.5l3.6-5', width: 2),
    _C(12, 16.5, 1.6, fill: true),
    _P('M4 20h16'),
  ]),
  servis([
    _R(3.5, 5, 17, 15, 2),
    _P('M3.5 9.5h17M8 3v4M16 3v4'),
    _P('M8.5 14.5l2.3 2.3 4.7-4.6'),
  ]),
  torque([
    _P('M5 19l8.5-8.5', width: 2),
    _P('M13 5.5a4 4 0 0 0 5.5 5.5l-2.3-.5-.6-2.4-2.4-.6z'),
  ]),
  oil([_P('M12 3.5c3 3.8 5.5 6.8 5.5 10a5.5 5.5 0 0 1-11 0c0-3.2 2.5-6.2 5.5-10z')]),
  gauge([
    _P('M4.5 16.5a7.5 7.5 0 1 1 15 0'),
    _P('M12 16.5l3.6-5', width: 2, accent: true),
    _C(12, 16.5, 1.6, fill: true),
  ]),
  bookmark([_P('M7 3.5h10v17l-5-3.8-5 3.8z')]),
  bookmarkOn([_P('M7 3.5h10v17l-5-3.8-5 3.8z', accent: true, fill: true)]),
  contents([
    _P('M9 6.5h11M9 12h11M9 17.5h11'),
    _C(4.8, 6.5, 1.3, fill: true),
    _C(4.8, 12, 1.3, fill: true),
    _C(4.8, 17.5, 1.3, fill: true),
  ]),
  bell([_P('M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2H4.5z'), _P('M10 20.5h4')]),
  trash([_P('M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10 11v5.5M14 11v5.5')]),
  clock([_C(12, 12, 8.5), _P('M12 7.5V12l3 2')]),
  info([_C(12, 12, 8.5), _P('M12 11v5.5'), _C(12, 7.8, 1.1, fill: true)]),
  thumbUp([
    _P('M7.5 10.5V20H4.5v-9.5zM7.5 11l3.6-6.5c1.4 0 2.4 1 2.1 2.6l-.7 3.4h5.6a1.8 1.8 0 0 1 1.8 2.1l-1.2 6.3a1.8 1.8 0 0 1-1.8 1.6H7.5',
        width: 1.7),
  ]),
  thumbDown([
    _P('M16.5 13.5V4h3v9.5zM16.5 13l-3.6 6.5c-1.4 0-2.4-1-2.1-2.6l.7-3.4H5.9a1.8 1.8 0 0 1-1.8-2.1l1.2-6.3A1.8 1.8 0 0 1 7.1 3.5h9.4',
        width: 1.7),
  ]),
  send([_P('M4.5 12L20 4.5 16 20l-4-6.5z'), _P('M12 13.5l8-9')]);

  const AppGlyph(this._parts);

  final List<_Part> _parts;
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color, this.accent);

  final AppGlyph glyph;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    for (final part in glyph._parts) {
      final paint = Paint()
        ..color = part.accent ? accent : color
        ..style = part.fill ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = part.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(part.path(), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color || old.accent != accent;
}

/// The icon of a manual, from its title first (CAT's SIS books and diagrams
/// have no type of their own), then from its type.
AppGlyph docGlyph(ManualFile file) => glyphForTitle(file.title) ?? switch (file.type) {
      DocType.shopManual => AppGlyph.shopManual,
      DocType.omm => AppGlyph.omm,
      DocType.partsbook => AppGlyph.partsbook,
      DocType.other => AppGlyph.general,
    };

AppGlyph? glyphForTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('troubleshoot')) return AppGlyph.troubleshooting;
  if (t.contains('testing') || t.contains('adjusting')) return AppGlyph.testing;
  if (t.contains('disassembly') || t.contains('assembly')) return AppGlyph.disassembly;
  if (t.contains('system operation')) return AppGlyph.systemOperation;
  if (t.contains('schematic') || t.contains('diagram') || t.contains('wiring')) return AppGlyph.diagram;
  if (t.contains('part') && (t.contains('book') || t.contains('catalog'))) return AppGlyph.partsbook;
  if (t.contains('operation') && t.contains('maintenance')) return AppGlyph.omm;
  if (t.contains('engine')) return AppGlyph.engine;
  if (t.contains('shop manual')) return AppGlyph.shopManual;
  return null;
}

/// A document icon on its light navy tile, as on the unit page.
class DocTile extends StatelessWidget {
  const DocTile(this.glyph, {super.key, this.size = 44, this.muted = false});

  final AppGlyph glyph;
  final double size;

  /// Grey, for a document that is not on the server yet.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: muted ? AppColors.greySoft : AppColors.navySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        glyph,
        size: size * 0.55,
        color: muted ? AppColors.faint : null,
        accent: muted ? AppColors.border : null,
      ),
    );
  }
}
