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

/// Remove & install chapters: their pages carry a component's mounting bolt
/// torques. "Removal and installation of track roller assembly" (Komatsu) or
/// "Track Roller - Remove and Install" (CAT). Same rules as the pipeline.
final _partTitles = [
  RegExp(
    r'^(?:removal\s+(?:and|&)\s+installation|remove\s+(?:and|&)\s+install|removing\s+and\s+installing)'
    r'\s+(?:of\s+)?(?:the\s+)?(?<name>.+)$',
    caseSensitive: false,
  ),
  RegExp(r'^(?<name>.+?)\s*[-–]\s*remove\s+(?:and|&)\s+install\b.*$', caseSensitive: false),
];

const maxPartPages = 12;

/// 'Removal and installation of track roller assembly' -> 'Track roller'.
String? partName(String title) {
  for (final pattern in _partTitles) {
    final m = pattern.firstMatch(title);
    if (m == null) continue;
    var name = m.namedGroup('name')!.trim();
    name = name.replaceAll(RegExp(r'^[ .:]+|[ .:]+$'), '');
    name = name.replaceFirst(RegExp(r'\s+(assembly|assy)$', caseSensitive: false), '').trim();
    return name.isEmpty ? null : name[0].toUpperCase() + name.substring(1);
  }
  return null;
}

/// One remove & install chapter found in a manual's bookmarks.
typedef PartPage = ({String fileKey, String group, String title, int page, int count});

/// The remove & install chapters of [toc] (one manual), each under the title
/// of the bookmark one level up, once per group and component.
List<PartPage> partPages(String fileKey, List<({int level, String title, int page})> toc) {
  final found = <PartPage>[];
  final seen = <String>{};
  for (var i = 0; i < toc.length; i++) {
    final (:level, :title, :page) = toc[i];
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final name = partName(clean);
    if (name == null) continue;
    var group = '';
    for (var j = i - 1; j >= 0; j--) {
      if (toc[j].level < level) {
        group = toc[j].title.replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r'^[\d\s.\-]+(?=[A-Za-z])'), '');
        break;
      }
    }
    if (!seen.add('${group.toLowerCase()}|${name.toLowerCase()}')) continue;
    var last = page + maxPartPages - 1;
    for (final next in toc.skip(i + 1)) {
      if (next.level <= level && next.page > page) {
        last = next.page - 1;
        break;
      }
    }
    found.add((fileKey: fileKey, group: group, title: name, page: page, count: last.clamp(page, page + maxPartPages - 1) - page + 1));
  }
  return found;
}

/// [partPages] of the given manuals ({fileKey: path to .sqlite index}), on
/// a background isolate.
Future<List<PartPage>> findPartPages(Map<String, String> indexes) => Isolate.run(() {
      final found = <PartPage>[];
      for (final entry in indexes.entries) {
        try {
          final db = sqlite3.open(entry.value, mode: OpenMode.readOnly);
          try {
            final toc = [
              for (final row in db.select('SELECT level, title, page FROM toc ORDER BY seq'))
                (level: row['level'] as int, title: row['title'] as String, page: row['page'] as int),
            ];
            found.addAll(partPages(entry.key, toc));
          } finally {
            db.close();
          }
        } on SqliteException {
          // An unreadable index just adds nothing.
        }
      }
      return found;
    });
