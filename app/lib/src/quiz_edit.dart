import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'page_image.dart';

/// A label on a quiz picture: the box its letter covers and the part name
/// it stands for, in the page picture's pixels. [words] are the words it was
/// made of (for "Pisah"); empty for a label the admin added.
class QuizLabel {
  const QuizLabel(this.box, this.text, [this.words = const []]);

  final ui.Rect box;
  final String text;
  final List<({String text, ui.Rect box})> words;

  QuizLabel moved(ui.Offset by) =>
      QuizLabel(box.shift(by), text, [for (final w in words) (text: w.text, box: w.box.shift(by))]);
}

/// What "Atur gambar" makes of a page: the part shown ([crop]), the labels
/// shown as letters, the white boxes over words ([covers]), which label the
/// question asks about ([ask]), the letters' size and the quarter turns.
/// All boxes are in the page picture's pixels; saved in PDF points, so the
/// same edit fits a page drawn at another size.
class QuizEdit {
  const QuizEdit({
    required this.crop,
    this.labels = const [],
    this.covers = const [],
    this.ask,
    this.size = 1,
    this.turns = 0,
  });

  final ui.Rect crop;
  final List<QuizLabel> labels;
  final List<ui.Rect> covers;

  /// Index in [labels] of the label the question asks about.
  final int? ask;

  /// Letter size, 1 = normal.
  final double size;

  /// Quarter turns clockwise of the finished picture.
  final int turns;

  /// The automatic choice: the drawing that holds [target], every word
  /// covered, and on a labelled photo ([labelled], or [target] is a label)
  /// the labels as letters.
  factory QuizEdit.auto(QuizPage page, String? target, {bool labelled = false}) {
    final ask = labelIndex(page.labels.map((l) => l.text).toList(), target);
    return QuizEdit(
      crop: page.autoCropFor(target),
      labels: ask != null || labelled ? [for (final l in page.labels) QuizLabel(l.box, l.text, l.words)] : const [],
      covers: page.covers,
      ask: ask,
    );
  }

  QuizEdit copyWith({
    ui.Rect? crop,
    List<QuizLabel>? labels,
    List<ui.Rect>? covers,
    int? Function()? ask,
    double? size,
    int? turns,
  }) =>
      QuizEdit(
        crop: crop ?? this.crop,
        labels: labels ?? this.labels,
        covers: covers ?? this.covers,
        ask: ask == null ? this.ask : ask(),
        size: size ?? this.size,
        turns: turns ?? this.turns,
      );

  /// Letter height in pixels: the same for every label, from the size of
  /// the picture.
  /// At least as high as the tallest label's frame, so every word stays
  /// covered.
  double get side => math.max(math.max(14.0, math.max(crop.width, crop.height) * 0.045) * size,
      labels.fold(0.0, (h, l) => math.max(h, quizLabelFrame(l.box).height)));

  /// Label indexes in reading order (the first is A); at most 26.
  List<int> get order => quizReadingOrder([for (final l in labels) l.box]).take(26).toList();

  /// The letter of label [i], or null past Z.
  String? letterOf(int i) {
    final at = order.indexOf(i);
    return at < 0 ? null : String.fromCharCode(65 + at);
  }

  /// The asked label's letter.
  String? get letter => ask == null ? null : letterOf(ask!);

  List<QuizMark> get marks => [
        for (final (at, i) in order.indexed)
          (box: labels[i].box, letter: String.fromCharCode(65 + at), asked: i == ask),
      ];

  /// The box drawn for label [i].
  ui.Rect markBox(int i) => quizMarkBox(labels[i].box, side);

  /// The finished picture.
  Future<Uint8List> png(QuizPage page) => page.png(crop, marks: marks, covers: covers, side: side, turns: turns);

  /// As kept on the server: boxes in points ([scale] pixels per point).
  Map<String, dynamic> toJson(double scale) {
    List<double> pts(ui.Rect r) => [for (final v in [r.left, r.top, r.right, r.bottom]) _round(v / scale)];
    return {
      'v': 1,
      'crop': pts(crop),
      'labels': [
        for (final l in labels)
          {
            'box': pts(l.box),
            'text': l.text,
            if (l.words.isNotEmpty) 'words': [for (final w in l.words) {'box': pts(w.box), 'text': w.text}],
          },
      ],
      'covers': [for (final c in covers) pts(c)],
      'ask': ask,
      'size': size,
      'turns': turns,
    };
  }

  /// Reads [toJson]; null when [j] is not an edit.
  static QuizEdit? fromJson(Object? j, double scale) {
    if (j is! Map || j['v'] != 1) return null;
    ui.Rect? rect(Object? v) {
      if (v is! List || v.length != 4 || v.any((x) => x is! num)) return null;
      final n = [for (final x in v) (x as num).toDouble() * scale];
      return ui.Rect.fromLTRB(n[0], n[1], n[2], n[3]);
    }

    final crop = rect(j['crop']);
    if (crop == null) return null;
    final labels = <QuizLabel>[];
    for (final l in j['labels'] as List? ?? const []) {
      if (l is! Map) continue;
      final box = rect(l['box']);
      if (box == null) continue;
      labels.add(QuizLabel(box, '${l['text'] ?? ''}', [
        for (final w in l['words'] as List? ?? const [])
          if (w is Map && rect(w['box']) != null) (text: '${w['text'] ?? ''}', box: rect(w['box'])!),
      ]));
    }
    final ask = (j['ask'] as num?)?.toInt();
    return QuizEdit(
      crop: crop,
      labels: labels,
      covers: [for (final c in j['covers'] as List? ?? const []) ?rect(c)],
      ask: ask != null && ask >= 0 && ask < labels.length ? ask : null,
      size: ((j['size'] as num?)?.toDouble() ?? 1).clamp(0.5, 2.0),
      turns: ((j['turns'] as num?)?.toInt() ?? 0) % 4,
    );
  }

  /// Same picture as [other].
  bool same(QuizEdit other) => jsonEncode(toJson(1)) == jsonEncode(other.toJson(1));

  // ---- Changes made in "Atur gambar" ----

  /// Labels [a] and [b] as one; its text reads top to bottom.
  QuizEdit merge(int a, int b) {
    if (a == b) return this;
    final first = quizReadingOrder([labels[a].box, labels[b].box]).first == 0 ? a : b;
    final second = first == a ? b : a;
    final one = QuizLabel(
      labels[a].box.expandToInclude(labels[b].box),
      '${labels[first].text} ${labels[second].text}'.trim(),
      [...labels[first].words, ...labels[second].words],
    );
    final keep = math.min(a, b);
    final drop = math.max(a, b);
    final next = [...labels]
      ..[keep] = one
      ..removeAt(drop);
    var asked = ask;
    if (asked == a || asked == b) {
      asked = keep;
    } else if (asked != null && asked > drop) {
      asked--;
    }
    return copyWith(labels: next, ask: () => asked);
  }

  /// Label [i] split into its lines, or its words when it is one line. The
  /// asked label goes to the part whose text is [target], if any.
  QuizEdit split(int i, String? target) {
    final parts = quizSplitWords(labels[i].words);
    if (parts.length < 2) return this;
    final next = [...labels]..replaceRange(i, i + 1, parts);
    int? asked = ask;
    if (asked == i) {
      final hit = labelIndex([for (final p in parts) p.text], target);
      asked = hit == null ? null : i + hit;
    } else if (asked != null && asked > i) {
      asked += parts.length - 1;
    }
    return copyWith(labels: next, ask: () => asked);
  }

  QuizEdit removeLabel(int i) {
    var asked = ask;
    if (asked == i) {
      asked = null;
    } else if (asked != null && asked > i) {
      asked--;
    }
    return copyWith(labels: [...labels]..removeAt(i), ask: () => asked);
  }
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// Indexes of [boxes] (pixels, y down) in reading order: rows from the top
/// (a row = boxes whose tops are within two box heights), left to right.
List<int> quizReadingOrder(List<ui.Rect> boxes) {
  final byTop = List<int>.generate(boxes.length, (i) => i)..sort((a, b) => boxes[a].top.compareTo(boxes[b].top));
  final ordered = <int>[];
  var row = <int>[];
  void flush() {
    row.sort((a, b) => boxes[a].left.compareTo(boxes[b].left));
    ordered.addAll(row);
    row = [];
  }

  for (final i in byTop) {
    if (row.isNotEmpty) {
      final first = boxes[row.first];
      if (boxes[i].top - first.top > 2 * first.height) flush();
    }
    row.add(i);
  }
  flush();
  return ordered;
}

/// [words] of one label as separate labels: one per line, or one per word
/// when they are all on one line.
List<QuizLabel> quizSplitWords(List<({String text, ui.Rect box})> words) {
  if (words.length < 2) return const [];
  final lines = <List<({String text, ui.Rect box})>>[];
  for (final w in [...words]..sort((a, b) => a.box.top.compareTo(b.box.top))) {
    final line = lines.isEmpty ? null : lines.last;
    final ref = line?.first.box;
    if (ref != null && (w.box.center.dy - ref.center.dy).abs() < math.max(ref.height, w.box.height) * 0.5) {
      line!.add(w);
    } else {
      lines.add([w]);
    }
  }
  final groups = lines.length > 1 ? lines : [for (final w in lines.single) [w]];
  return [
    for (final g in groups)
      () {
        g.sort((a, b) => a.box.left.compareTo(b.box.left));
        final box = g.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
        return QuizLabel(box, g.map((w) => w.text).join(' '), g);
      }(),
  ];
}
