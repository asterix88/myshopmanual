import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'diagnostics.dart';
import 'models.dart';
import 'store.dart';

/// Parts of a page the AI can ask for. A quarter is a bit more than half of
/// each side, so a line crossing the middle shows in both neighbours.
const pageRegions = ['full', 'top-left', 'top-right', 'bottom-left', 'bottom-right'];

/// Drawing pages takes a lot of memory on big manuals, so one page is drawn
/// at a time and its manual is closed again before the next.
Future<void> _queue = Future.value();

Future<T> _oneAtATime<T>(Future<T> Function() work) {
  final result = _queue.then((_) => work());
  _queue = result.then((_) {}, onError: (_) {});
  return result;
}

/// Renders [page] (1-based) of [file], or one quarter of it, as a PNG for the
/// AI to look at: from the phone when the manual is downloaded, otherwise
/// only that page's part of the PDF is fetched from the server. The longest
/// side is about [longest] pixels, so a quarter shows the drawing twice as
/// large as the full page does.
Future<Uint8List> renderPageImage(AppStore store, ManualFile file, int page, String region,
        {double longest = 1600}) =>
    _oneAtATime(() async {
      Diagnostics.log('draw ${file.key} p$page $region');
      PdfDocument? document;
      try {
        document = await _open(store, file);
        final png = await _render(await _loadPage(document, page), region, longest);
        Diagnostics.log('drawn ${png.length ~/ 1024} KB');
        return png;
      } on Object catch (e) {
        Diagnostics.log('not drawn: $e');
        rethrow;
      } finally {
        await document?.dispose();
      }
    });

/// Page [page] with its real size. A manual read from the server is opened
/// without measuring all its pages (that alone fetches most of a big shop
/// manual), so only this page is measured.
Future<PdfPage> _loadPage(PdfDocument document, int page) async {
  if (!document.pages[page - 1].isLoaded) {
    await document.loadPagesProgressively(
      startPageNumber: page,
      loadUnitDuration: Duration.zero,
      onPageLoadProgress: (_, _, _) => !document.pages[page - 1].isLoaded,
    );
  }
  return document.pages[page - 1];
}

Future<Uint8List> _render(PdfPage pdfPage, String region, double longest) async {
  final (left, top, part) = switch (region) {
    'top-left' => (0.0, 0.0, 0.55),
    'top-right' => (0.45, 0.0, 0.55),
    'bottom-left' => (0.0, 0.45, 0.55),
    'bottom-right' => (0.45, 0.45, 0.55),
    _ => (0.0, 0.0, 1.0),
  };
  // Very large colour sheets can make a big PNG; try smaller until it fits
  // comfortably in one request.
  for (final size in [longest, longest * 0.75, longest * 0.56]) {
    final scale = size / (part * (pdfPage.width > pdfPage.height ? pdfPage.width : pdfPage.height));
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
    if (image == null) throw StateError('page ${pdfPage.pageNumber} could not be drawn');
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
    if (data == null) throw StateError('page ${pdfPage.pageNumber} could not be encoded');
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (png.length <= 1500000 || size < longest * 0.6) return png;
  }
  throw StateError('unreachable');
}

/// A small picture of [page] for showing under an AI answer, drawn once and
/// kept on the phone, so the chat does not keep big manuals open.
Future<File> pageThumbnail(AppStore store, ManualFile file, int page) async {
  final target = File(store.pageThumbPath(file, page));
  if (await target.exists()) return target;
  final png = await renderPageImage(store, file, page, 'full', longest: 900);
  await target.parent.create(recursive: true);
  final part = File('${target.path}.part');
  await part.writeAsBytes(png);
  return part.rename(target.path);
}

/// Pages of [file] that are much larger than its usual page: the fold-out
/// drawing sheets of a schematic or a shop manual. Knowing them lets the AI
/// go straight to the drawing instead of paging through covers and tables.
Future<List<int>> findLargeSheets(AppStore store, ManualFile file) => _oneAtATime(() async {
      // Measuring every page of a manual on the server means fetching most
      // of it; the hint is only worth that for manuals on the phone.
      if (!store.isDownloaded(file.key)) return const <int>[];
      final document = await _open(store, file);
      try {
        final areas = [for (final p in document.pages) p.width * p.height];
        if (areas.isEmpty) return const <int>[];
        final sorted = [...areas]..sort();
        final usual = sorted[sorted.length ~/ 2];
        return [
          for (final (i, area) in areas.indexed)
            if (area >= usual * 2.5) i + 1,
        ];
      } finally {
        await document.dispose();
      }
    });

/// Opens [file]: from the phone when it is downloaded, otherwise piece by
/// piece from the server. The server pieces are kept here, in memory, and
/// not in the PDF viewer's cache file: the viewer may have the same manual
/// open, and two readers of one cache file corrupt it (blank pages, then a
/// crash inside PDFium).
Future<PdfDocument> _open(AppStore store, ManualFile file) {
  if (store.isDownloaded(file.key)) return PdfDocument.openFile(store.pdfPath(file));
  final key = '${file.key}@${file.pdf.sha256}';
  if (_remoteKey != key) {
    _remoteKey = key;
    _remoteBlocks.clear();
  }
  final size = file.pdf.size;
  // Pages are drawn by the same PDFium worker the PDF viewer uses, which
  // waits while a page is being fetched. So give up after a minute, and at
  // once while the user has a manual open (see [pauseServerDrawing]).
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  Future<Uint8List> block(int id) async {
    if (_viewersOpen > 0 || DateTime.now().isAfter(deadline)) {
      throw const HttpException('drawing from the server paused');
    }
    // Most recently used last, so the oldest piece is dropped first.
    final cached = _remoteBlocks.remove(id);
    if (cached != null) return _remoteBlocks[id] = cached;
    final start = id * _blockSize;
    // A piece still on its way when a manual is opened is not waited for.
    final fetch = store.fetchPdfRange(file, start, math.min(start + _blockSize, size));
    final data = await Future.any<Uint8List?>([fetch, _viewerOpened.future.then((_) => null)]);
    if (data == null) {
      fetch.ignore();
      throw const HttpException('drawing from the server paused');
    }
    _remoteBlocks[id] = data;
    while (_remoteBlocks.length > _maxBlocks) {
      _remoteBlocks.remove(_remoteBlocks.keys.first);
    }
    return data;
  }

  return PdfDocument.openCustom(
    read: (buffer, position, length) async {
      var done = 0;
      while (done < length && position + done < size) {
        final at = position + done;
        final data = await block(at ~/ _blockSize);
        final offset = at % _blockSize;
        final n = math.min(length - done, data.length - offset);
        buffer.setRange(done, done + n, data, offset);
        done += n;
      }
      return done;
    },
    fileSize: size,
    sourceName: 'ai:$key',
    useProgressiveLoading: true,
  );
}

/// Manuals open in the PDF viewer; while there is one, pages are not drawn
/// from the server, so the viewer never waits behind the AI.
int _viewersOpen = 0;
var _viewerOpened = Completer<void>();

/// Called by the PDF viewer while it is open; returns the function to call
/// when it closes.
void Function() pauseServerDrawing() {
  _viewersOpen++;
  _viewerOpened.complete();
  _viewerOpened = Completer<void>();
  var done = false;
  return () {
    if (done) return;
    done = true;
    _viewersOpen--;
  };
}

/// The manual whose server pieces are in [_remoteBlocks]. Pages are drawn
/// one at a time, so one manual's pieces are enough: the next page of the
/// same manual reuses its table of contents instead of fetching it again.
String? _remoteKey;
final _remoteBlocks = <int, Uint8List>{};
const _blockSize = 256 * 1024;
const _maxBlocks = 96; // 24 MB
