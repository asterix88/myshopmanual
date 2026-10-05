import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'models.dart';
import 'store.dart';

/// Parts of a page the AI can ask for. A quarter is a bit more than half of
/// each side, so a line crossing the middle shows in both neighbours.
const pageRegions = ['full', 'top-left', 'top-right', 'bottom-left', 'bottom-right'];

/// Renders [page] (1-based) of [file], or one quarter of it, as a PNG for the
/// AI to look at: from the phone when the manual is downloaded, otherwise
/// only that page's part of the PDF is fetched from the server. The longest
/// side is about 1600 pixels, so a quarter shows the drawing twice as large
/// as the full page does.
Future<Uint8List> renderPageImage(AppStore store, ManualFile file, int page, String region) async {
  final document = store.isDownloaded(file.key)
      ? await PdfDocument.openFile(store.pdfPath(file))
      : await PdfDocument.openUri(store.pdfUri(file), preferRangeAccess: true);
  try {
    final pdfPage = document.pages[page - 1];
    final (left, top, part) = switch (region) {
      'top-left' => (0.0, 0.0, 0.55),
      'top-right' => (0.45, 0.0, 0.55),
      'bottom-left' => (0.0, 0.45, 0.55),
      'bottom-right' => (0.45, 0.45, 0.55),
      _ => (0.0, 0.0, 1.0),
    };
    // Very large colour sheets can make a big PNG; try smaller until it fits
    // comfortably in one request.
    for (final longest in const [1600.0, 1200.0, 900.0]) {
      final scale = longest / (part * (pdfPage.width > pdfPage.height ? pdfPage.width : pdfPage.height));
      final fullWidth = pdfPage.width * scale;
      final fullHeight = pdfPage.height * scale;
      final image = await pdfPage.render(
        x: (left * fullWidth).round(),
        y: (top * fullHeight).round(),
        width: (part * fullWidth).round(),
        height: (part * fullHeight).round(),
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xffffffff,
      );
      if (image == null) throw StateError('page $page could not be drawn');
      final ui.Image picture;
      try {
        picture = await image.createImage();
      } finally {
        image.dispose();
      }
      final ByteData? data;
      try {
        data = await picture.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        picture.dispose();
      }
      if (data == null) throw StateError('page $page could not be encoded');
      final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (png.length <= 1500000 || longest == 900.0) return png;
    }
    throw StateError('unreachable');
  } finally {
    await document.dispose();
  }
}
