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

/// A page drawn for a "gambar" quiz question: every word covered in white,
/// so the drawing keeps its callout numbers but the legend ("3. Main relief
/// valve") does not give the answer away. [image] is the whole page; the
/// question's picture is a part of it ([autoCrop], or the admin's own box).
class QuizPage {
  QuizPage(this.image, this.rgba, this.numbers, {this.labels = const [], this.sharp});

  /// Draws a part of the page again at a size that stays sharp when zoomed,
  /// with [QuizMark]s on it; null in tests, where [png] cuts it from [image].
  final Future<Uint8List> Function(ui.Rect crop, List<QuizMark> marks)? sharp;

  final ui.Image image;

  /// [image]'s pixels, RGBA, for finding the drawings.
  final Uint8List rgba;

  /// The callout numbers left on the page and where they are, in pixels.
  final List<({String text, ui.Rect box})> numbers;

  /// Short part names placed on a photo or drawing ("PSV", "TVC valve"), in
  /// reading order, so the first is A; in pixels.
  final List<({String text, ui.Rect box})> labels;

  int get width => image.width;
  int get height => image.height;

  /// On a labelled photo: every label as a letter box, the one [target]
  /// names (the right answer) marked as asked. Empty when [target] is not
  /// one of the labels (a numbered drawing).
  List<QuizMark> marksFor(String? target) {
    final asked = labelIndex(labels.map((l) => l.text).toList(), target);
    if (asked == null) return const [];
    return [
      for (final (i, l) in labels.take(26).indexed) (box: l.box, letter: String.fromCharCode(65 + i), asked: i == asked),
    ];
  }

  /// The question's picture: [crop] (in [image]'s pixels) of the page as a
  /// PNG, drawn again from the manual so a small drawing stays sharp.
  Future<Uint8List> png(ui.Rect crop, {List<QuizMark> marks = const []}) async {
    final sharp = this.sharp;
    if (sharp != null) return sharp(crop, marks);
    final r = crop.intersect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    final w = math.max(1, r.width.round());
    final h = math.max(1, r.height.round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawImageRect(image, r, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
    paintQuizMarks(canvas, marks, 1, r.topLeft);
    final part = await recorder.endRecording().toImage(w, h);
    final ByteData? data;
    try {
      data = await part.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      part.dispose();
    }
    if (data == null) throw StateError('quiz picture could not be encoded');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// The drawing that holds [target]: a callout number, or a label's name
  /// ([autoCrop]).
  ui.Rect autoCropFor(String? target) {
    final asked = labelIndex(labels.map((l) => l.text).toList(), target);
    return autoCrop(rgba, width, height, [
      if (asked != null) labels[asked].box,
      for (final n in numbers) if (target != null && n.text == target) n.box,
    ]);
  }

  void dispose() => image.dispose();
}

/// A label of a photo shown as a letter: [box] in the page picture's pixels.
typedef QuizMark = ({ui.Rect box, String letter, bool asked});

/// Which of [labels] [target] names, ignoring case and spacing; null when
/// none does.
int? labelIndex(List<String> labels, String? target) {
  if (target == null || RegExp(r'^\d+$').hasMatch(target.trim())) return null;
  String flat(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final want = flat(target);
  if (want.isEmpty) return null;
  final i = labels.indexWhere((l) => flat(l) == want);
  return i < 0 ? null : i;
}

/// Draws [marks] (scaled by [k], less [origin]): a white box with a navy
/// border and the letter; the asked one's letter in orange.
void paintQuizMarks(ui.Canvas canvas, List<QuizMark> marks, double k, ui.Offset origin) {
  const navy = ui.Color(0xFF1E3A64);
  const orange = ui.Color(0xFFF08A1C);
  for (final m in marks) {
    final r = ui.Rect.fromLTRB(
        m.box.left * k - origin.dx, m.box.top * k - origin.dy, m.box.right * k - origin.dx, m.box.bottom * k - origin.dy);
    // At least a square big enough for the letter.
    final side = math.max(r.height, 18 * k);
    final box = ui.Rect.fromCenter(center: r.center, width: math.max(r.width, side), height: side);
    canvas.drawRect(box, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    canvas.drawRect(
      box,
      ui.Paint()
        ..color = m.asked ? orange : navy
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, side * 0.08),
    );
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: side * 0.68))
      ..pushStyle(ui.TextStyle(
        color: m.asked ? orange : navy,
        fontWeight: ui.FontWeight.w700,
        fontFamily: 'Poppins',
        fontSize: side * 0.68,
      ))
      ..addText(m.letter);
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: box.width));
    canvas.drawParagraph(paragraph, ui.Offset(box.left, box.center.dy - paragraph.height / 2));
  }
}

/// Draws [page] of [file] for quiz pictures (see [QuizPage]).
/// [open] replaces opening [file] (tests).
Future<QuizPage> renderQuizPage(AppStore store, ManualFile file, int page,
        {double longest = 1600, Future<PdfDocument> Function()? open}) =>
    _oneAtATime(() async {
      Diagnostics.log('quiz picture ${file.key} p$page');
      PdfDocument? document;
      try {
        document = await (open?.call() ?? _open(store, file));
        final pdfPage = await _loadPage(document, page);
        final scale = longest / math.max(pdfPage.width, pdfPage.height);
        final width = (pdfPage.width * scale).round();
        final height = (pdfPage.height * scale).round();
        // fullWidth/fullHeight say how big the whole page is drawn; without
        // them PDFium draws it at 1 pixel per point in the corner, and the
        // word boxes (scaled) land on the drawing.
        final rendered = await pdfPage.render(
          width: width,
          height: height,
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xffffffff,
        );
        if (rendered == null) throw StateError('page $page could not be drawn');
        final ui.Image picture;
        try {
          picture = await rendered.createImage();
        } finally {
          rendered.dispose();
        }
        final text = await pdfPage.loadText();
        ui.Rect toPixels(PdfRect r) => ui.Rect.fromLTRB(
            r.left * scale - 2, (pdfPage.height - r.top) * scale - 2, r.right * scale + 2, (pdfPage.height - r.bottom) * scale + 2);
        final parts = quizPageText(text?.fullText ?? '', text?.charRects ?? const []);
        final labels = quizLabels(text?.fullText ?? '', text?.charRects ?? const []);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..drawImage(picture, ui.Offset.zero, ui.Paint());
        picture.dispose();
        final white = ui.Paint()..color = const ui.Color(0xffffffff);
        for (final r in parts.cover) {
          canvas.drawRect(toPixels(r), white);
        }
        final covered = await recorder.endRecording().toImage(width, height);
        final data = await covered.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) {
          covered.dispose();
          throw StateError('page $page could not be read');
        }
        final pdfWidth = pdfPage.width;
        final pdfHeight = pdfPage.height;
        return QuizPage(
          covered,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          [for (final n in parts.numbers) (text: n.text, box: toPixels(n.box))],
          labels: [for (final l in labels) (text: l.text, box: toPixels(l.box))],
          sharp: (crop, marks) =>
              _sharpQuizPicture(store, file, page, crop, scale, pdfWidth, pdfHeight, parts.cover, marks, open: open),
        );
      } finally {
        await document?.dispose();
      }
    });

/// [crop] of a quiz page (pixels at [scale]) drawn again so its longest side
/// is about [longest] pixels, with the same words covered.
Future<Uint8List> _sharpQuizPicture(AppStore store, ManualFile file, int page, ui.Rect crop, double scale,
        double pdfWidth, double pdfHeight, List<PdfRect> cover, List<QuizMark> marks,
        {double longest = 1400, Future<PdfDocument> Function()? open}) =>
    _oneAtATime(() async {
      PdfDocument? document;
      try {
        document = await (open?.call() ?? _open(store, file));
        final pdfPage = await _loadPage(document, page);
        // Points of the page in the crop; never smaller than the first drawing.
        final points = math.max(crop.width, crop.height) / scale;
        final s = math.min(math.max(scale, longest / points), scale * 4);
        final x = (crop.left / scale * s).round();
        final y = (crop.top / scale * s).round();
        final width = math.max(1, (crop.width / scale * s).round());
        final height = math.max(1, (crop.height / scale * s).round());
        final rendered = await pdfPage.render(
          x: x,
          y: y,
          width: width,
          height: height,
          fullWidth: pdfWidth * s,
          fullHeight: pdfHeight * s,
          backgroundColor: 0xffffffff,
        );
        if (rendered == null) throw StateError('page $page could not be drawn');
        final ui.Image picture;
        try {
          picture = await rendered.createImage();
        } finally {
          rendered.dispose();
        }
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..drawImage(picture, ui.Offset.zero, ui.Paint());
        picture.dispose();
        final white = ui.Paint()..color = const ui.Color(0xffffffff);
        for (final r in cover) {
          canvas.drawRect(
            ui.Rect.fromLTRB(r.left * s - x - 2, (pdfHeight - r.top) * s - y - 2, r.right * s - x + 2,
                (pdfHeight - r.bottom) * s - y + 2),
            white,
          );
        }
        paintQuizMarks(canvas, marks, s / scale, ui.Offset(x.toDouble(), y.toDouble()));
        final out = await recorder.endRecording().toImage(width, height);
        final ByteData? data;
        try {
          data = await out.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          out.dispose();
        }
        if (data == null) throw StateError('quiz picture could not be encoded');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        await document?.dispose();
      }
    });

/// The words of a page grouped into labels: words next to each other on a
/// line, or on lines right under each other ("TVC output" / "pressure"),
/// are one label. Only short groups (up to 6 words) count as labels, in
/// reading order: top to bottom, rows left to right.
List<({String text, PdfRect box})> quizLabels(String text, List<PdfRect> rects) {
  final n = math.min(text.length, rects.length);
  final words = <({String text, PdfRect box})>[];
  var start = -1;
  void close(int end) {
    if (start < 0) return;
    var b = rects[start];
    for (var i = start + 1; i < end; i++) {
      final r = rects[i];
      b = PdfRect(math.min(b.left, r.left), math.max(b.top, r.top), math.max(b.right, r.right), math.min(b.bottom, r.bottom));
    }
    if (b.top - b.bottom > 0) words.add((text: text.substring(start, end), box: b));
    start = -1;
  }

  for (var i = 0; i < n; i++) {
    if (text[i].trim().isEmpty) {
      close(i);
    } else if (start < 0) {
      start = i;
    }
  }
  close(n);

  // Union-find over the words.
  final parent = List<int>.generate(words.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  bool near(PdfRect a, PdfRect b) {
    final h = math.max(a.top - a.bottom, b.top - b.bottom);
    final overlapY = math.min(a.top, b.top) - math.max(a.bottom, b.bottom);
    final gapX = math.max(a.left, b.left) - math.min(a.right, b.right);
    if (overlapY > 0.5 * math.min(a.top - a.bottom, b.top - b.bottom)) return gapX < 0.9 * h; // same line
    final gapY = math.max(a.bottom, b.bottom) - math.min(a.top, b.top);
    // Lines under each other: char boxes are tight, so a short word under a
    // tall one ("Control" / "pump") leaves almost a full line height.
    return gapY < 1.0 * h && gapX < 0.3 * h;
  }

  for (var i = 0; i < words.length; i++) {
    for (var j = i + 1; j < words.length; j++) {
      if (near(words[i].box, words[j].box)) parent[find(i)] = find(j);
    }
  }
  final groups = <int, List<({String text, PdfRect box})>>{};
  for (var i = 0; i < words.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(words[i]);
  }
  final labels = <({String text, PdfRect box})>[];
  for (final g in groups.values) {
    if (g.length > 6) continue;
    // Lines top to bottom (PDF y grows upward), words left to right.
    final h = g.map((w) => w.box.top - w.box.bottom).reduce(math.max);
    g.sort((a, b) {
      final dy = b.box.top - a.box.top;
      return dy.abs() > h * 0.5 ? dy.sign.toInt() : a.box.left.compareTo(b.box.left);
    });
    var box = g.first.box;
    for (final w in g.skip(1)) {
      box = PdfRect(math.min(box.left, w.box.left), math.max(box.top, w.box.top), math.max(box.right, w.box.right),
          math.min(box.bottom, w.box.bottom));
    }
    final label = g.map((w) => w.text).join(' ');
    if (label.length <= 40 && RegExp(r'[A-Za-z]').hasMatch(label)) labels.add((text: label, box: box));
  }
  // Reading order: rows from the top (a row = labels whose tops are within
  // two label heights), left to right in a row.
  labels.sort((a, b) => b.box.top.compareTo(a.box.top));
  final ordered = <({String text, PdfRect box})>[];
  var row = <({String text, PdfRect box})>[];
  for (final l in labels) {
    if (row.isNotEmpty) {
      final h = row.first.box.top - row.first.box.bottom;
      if (row.first.box.top - l.box.top > 2 * h) {
        ordered.addAll(row..sort((a, b) => a.box.left.compareTo(b.box.left)));
        row = [];
      }
    }
    row.add(l);
  }
  ordered.addAll(row..sort((a, b) => a.box.left.compareTo(b.box.left)));
  return ordered;
}

/// What a picture question shows: the callout number it asks about, or on
/// a labelled photo the right answer's label.
String? quizPictureTarget(String prompt, List<String> choices, int answer) =>
    calloutOf(prompt) ?? (answer >= 0 && answer < choices.length ? choices[answer] : null);

/// The callout number a picture question asks about: "komponen nomor 3".
String? calloutOf(String prompt) =>
    (RegExp(r'nomor\s*\(?(\d{1,3})\b', caseSensitive: false).firstMatch(prompt) ??
            RegExp(r'\((\d{1,3})\)').firstMatch(prompt))
        ?.group(1);

/// What to cover on a quiz picture and which callout numbers stay. Every run
/// of characters with a letter in it is covered. A number alone ("3", "12.",
/// "(35)") stays as a callout, unless it sits on a line with words: then it
/// belongs to the legend ("3. Main relief valve") and is covered too.
({List<PdfRect> cover, List<({String text, PdfRect box})> numbers}) quizPageText(String text, List<PdfRect> rects) {
  final letter = RegExp(r'[A-Za-z]');
  final n = math.min(text.length, rects.length);
  final tokens = <({int start, int end, int line, bool word})>[];
  var line = 0;
  var start = -1;
  void close(int end) {
    if (start < 0) return;
    tokens.add((start: start, end: end, line: line, word: letter.hasMatch(text.substring(start, end))));
    start = -1;
  }

  for (var i = 0; i < n; i++) {
    final c = text[i];
    if (c.trim().isEmpty) {
      close(i);
      if (c == '\n' || c == '\r') line++;
    } else if (start < 0) {
      start = i;
    }
  }
  close(n);

  PdfRect box(int from, int to) {
    var b = rects[from];
    for (var i = from + 1; i < to; i++) {
      final r = rects[i];
      b = PdfRect(math.min(b.left, r.left), math.max(b.top, r.top), math.max(b.right, r.right), math.min(b.bottom, r.bottom));
    }
    return b;
  }

  final cover = <PdfRect>[];
  final numbers = <({String text, PdfRect box})>[];
  for (final (i, t) in tokens.indexed) {
    final onWordLine = (i > 0 && tokens[i - 1].line == t.line && tokens[i - 1].word) ||
        (i + 1 < tokens.length && tokens[i + 1].line == t.line && tokens[i + 1].word);
    if (t.word || onWordLine) {
      cover.add(box(t.start, t.end));
    } else {
      final digits = RegExp(r'\d+').firstMatch(text.substring(t.start, t.end))?.group(0);
      if (digits != null) numbers.add((text: digits, box: box(t.start, t.end)));
    }
  }
  return (cover: cover, numbers: numbers);
}

/// The boxes [quizPageText] covers.
List<PdfRect> wordsToCover(String text, List<PdfRect> rects) => quizPageText(text, rects).cover;

/// The part of a covered page that is one drawing: the page is cut at white
/// gaps, first into bands, then each band into columns, until the part
/// holding [targets] (the asked callout) stops changing. Without a target the
/// biggest drawing wins. A small margin is kept around it.
ui.Rect autoCrop(Uint8List rgba, int width, int height, List<ui.Rect> targets) {
  bool ink(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] < 215 || rgba[i + 1] < 215 || rgba[i + 2] < 215;
  }

  final longest = math.max(width, height);
  final gap = math.max(8, (longest * 0.012).round());

  // Runs of rows (or columns) with ink inside [r], split at white gaps.
  List<(int, int)> runs(ui.Rect r, bool rows) {
    final from = (rows ? r.top : r.left).floor();
    final to = (rows ? r.bottom : r.right).ceil();
    final out = <(int, int)>[];
    int? runStart;
    var lastInk = -1 << 30;
    for (var a = from; a < to; a++) {
      var any = false;
      if (rows) {
        for (var x = r.left.floor(); x < r.right.ceil(); x += 2) {
          if (ink(x, a)) {
            any = true;
            break;
          }
        }
      } else {
        for (var y = r.top.floor(); y < r.bottom.ceil(); y += 2) {
          if (ink(a, y)) {
            any = true;
            break;
          }
        }
      }
      if (!any) continue;
      if (runStart != null && a - lastInk > gap) {
        out.add((runStart, lastInk + 1));
        runStart = null;
      }
      runStart ??= a;
      lastInk = a;
    }
    if (runStart != null) out.add((runStart, lastInk + 1));
    return out;
  }

  int inkIn(ui.Rect r) {
    var count = 0;
    for (var y = r.top.floor(); y < r.bottom.ceil(); y += 4) {
      for (var x = r.left.floor(); x < r.right.ceil(); x += 4) {
        if (ink(x, y)) count++;
      }
    }
    return count;
  }

  final page = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final target = targets.isEmpty ? null : targets.first;
  var current = page;
  for (var step = 0; step < 6; step++) {
    final rows = step.isEven;
    final parts = [
      for (final (a, b) in runs(current, rows))
        rows
            ? ui.Rect.fromLTRB(current.left, a.toDouble(), current.right, b.toDouble())
            : ui.Rect.fromLTRB(a.toDouble(), current.top, b.toDouble(), current.bottom),
    ];
    if (parts.isEmpty) return page;
    ui.Rect pick;
    if (target != null) {
      final c = target.center;
      double distance(ui.Rect r) {
        final dx = c.dx < r.left ? r.left - c.dx : (c.dx > r.right ? c.dx - r.right : 0.0);
        final dy = c.dy < r.top ? r.top - c.dy : (c.dy > r.bottom ? c.dy - r.bottom : 0.0);
        return dx + dy;
      }

      pick = parts.reduce((a, b) => distance(b) < distance(a) ? b : a);
    } else {
      pick = parts.reduce((a, b) => inkIn(b) > inkIn(a) ? b : a);
    }
    if (step > 0 && pick == current) break;
    current = pick;
  }
  final margin = longest * 0.02;
  return current.inflate(margin).intersect(page);
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
