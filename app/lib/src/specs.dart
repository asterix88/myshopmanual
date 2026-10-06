import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

/// A group on the Spek tab and the bookmark titles that belong to it.
/// Komatsu and CAT manuals name these pages consistently, so their own
/// bookmarks find them without anyone typing the numbers into the app: the
/// mechanic always reads the value on the manual page itself.
class SpecSection {
  const SpecSection(this.title, this.pattern);

  final String title;
  final RegExp pattern;
}

final specSections = [
  SpecSection('Torsi baut', RegExp(r'tightening torque|torque (table|chart|spec)', caseSensitive: false)),
  SpecSection(
    'Kapasitas oli & cairan',
    RegExp(
      r'(fuel|coolant|lubricant|oil)s?[^/]*capacit|capacit[^/]*(fuel|coolant|lubricant|oil|refill)|refill capacit'
      r'|table of fuel|fuel, coolant and lubricants',
      caseSensitive: false,
    ),
  ),
  SpecSection(
    'Nilai standar & tekanan',
    RegExp(
      r'standard value|relief (valve|pressure)[^/]*(test|adjust|measur)|pressure[^/]*(test|adjust|setting)'
      r'|testing and adjusting.*pressure',
      caseSensitive: false,
    ),
  ),
];

/// One bookmark of a manual that belongs to a spec section.
typedef SpecPage = ({String fileKey, String title, int page});

/// Bookmarks of the given manuals ({fileKey: path to .sqlite index}) that
/// match each of [specSections], in manual order; same title and page are
/// listed once. Runs on a background isolate.
Future<List<List<SpecPage>>> findSpecPages(Map<String, String> indexes) =>
    Isolate.run(() => findSpecPagesSync(indexes));

List<List<SpecPage>> findSpecPagesSync(Map<String, String> indexes) {
  final result = [for (final _ in specSections) <SpecPage>[]];
  for (final entry in indexes.entries) {
    try {
      final db = sqlite3.open(entry.value, mode: OpenMode.readOnly);
      try {
        final seen = <String>{};
        for (final row in db.select('SELECT title, page FROM toc ORDER BY seq')) {
          final title = (row['title'] as String).replaceAll(RegExp(r'\s+'), ' ').trim();
          final page = row['page'] as int;
          for (final (i, section) in specSections.indexed) {
            if (section.pattern.hasMatch(title) && seen.add('$i|${title.toLowerCase()}|$page')) {
              result[i].add((fileKey: entry.key, title: title, page: page));
            }
          }
        }
      } finally {
        db.close();
      }
    } on SqliteException {
      // An unreadable index just adds nothing.
    }
  }
  return result;
}
