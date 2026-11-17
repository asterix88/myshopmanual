import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:sqlite3/sqlite3.dart';

/// Page sizes of a manual, known before PDFium has measured its pages.
///
/// PDFium measures pages one by one after opening (online, only as they
/// scroll in); until then pdfrx gives every page the size of page 1. In a
/// manual mixing portrait and landscape pages the layout then changes again
/// and again while it opens, and the page being read jumps and flashes
/// white. With the sizes known up front the layout is right from the start.
///
/// Sizes come from the manual's index (`meta.page_sizes`, written by
/// tools/build_packages.py) or, for an index made before that, from what
/// this phone measured the last time the manual was open.
///
/// Both are stored as runs `[count, width, height]`; width 0 means unknown.
class PageSizes {
  PageSizes(this.sizes);

  final List<Size?> sizes;

  Size? operator [](int index) => index >= 0 && index < sizes.length ? sizes[index] : null;

  bool get isComplete => sizes.every((s) => s != null);

  static PageSizes? fromRuns(Object? runs) {
    if (runs is! List) return null;
    final sizes = <Size?>[];
    for (final run in runs) {
      if (run is! List || run.length != 3) return null;
      final [count, width, height] = run;
      if (count is! num || width is! num || height is! num) return null;
      final size = width > 0 && height > 0 ? Size(width.toDouble(), height.toDouble()) : null;
      for (var i = 0; i < count; i++) {
        sizes.add(size);
      }
    }
    return sizes.isEmpty ? null : PageSizes(sizes);
  }

  List<List<num>> toRuns() {
    final runs = <List<num>>[];
    for (final size in sizes) {
      final w = size == null ? 0 : (size.width * 10).round() / 10;
      final h = size == null ? 0 : (size.height * 10).round() / 10;
      if (runs.isNotEmpty && runs.last[1] == w && runs.last[2] == h) {
        runs.last[0] = runs.last[0] + 1;
      } else {
        runs.add([1, w, h]);
      }
    }
    return runs;
  }

  /// The sizes in [indexPath]'s meta table; null for an older index.
  static PageSizes? fromIndex(String indexPath) {
    try {
      final db = sqlite3.open(indexPath, mode: OpenMode.readOnly);
      try {
        final rows = db.select("SELECT value FROM meta WHERE key = 'page_sizes'");
        return rows.isEmpty ? null : fromRuns(jsonDecode(rows.first['value'] as String));
      } finally {
        db.close();
      }
    } on Object {
      return null;
    }
  }

  /// Sizes this phone measured before, saved by [save].
  static PageSizes? fromFile(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? fromRuns(jsonDecode(file.readAsStringSync())) : null;
    } on Object {
      return null;
    }
  }

  /// Saves the sizes measured now, keeping ones measured before that are not
  /// measured this time (online, only the pages scrolled past are).
  static void save(String path, List<Size?> measured) {
    try {
      final old = fromFile(path);
      final merged = [
        for (var i = 0; i < measured.length; i++) measured[i] ?? (old != null && old.sizes.length == measured.length ? old[i] : null),
      ];
      if (merged.every((s) => s == null)) return;
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(PageSizes(merged).toRuns()));
    } on Object {
      // Only a speed-up for next time.
    }
  }
}
