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

/// Older manuals (D85) name the component alone, with REMOVAL and
/// INSTALLATION bookmarks under it.
final _partStep = RegExp(r'^(?:removal|installation|insyallation)$', caseSensitive: false);

const maxPartPages = 40;

/// 'Removal and installation of track roller assembly' -> 'Track roller'.
String? partName(String title) {
  for (final pattern in _partTitles) {
    final m = pattern.firstMatch(title);
    if (m == null) continue;
    return _cleanPartName(m.namedGroup('name')!);
  }
  return null;
}

/// 'SUPPLY PUMP ASSEMBLY (RIGHT BANK)' -> 'SUPPLY PUMP': one entry for both
/// banks, without "assembly".
String? _cleanPartName(String name) {
  name = name.trim().replaceAll(RegExp(r'^[ .:]+|[ .:]+$'), '');
  name = name.replaceAll(RegExp(r'\s*\((?:left|right)\s+bank\)', caseSensitive: false), '').trim();
  name = name.replaceFirst(RegExp(r'\s+(assembly|assy)$', caseSensitive: false), '').trim();
  return name.isEmpty ? null : name[0].toUpperCase() + name.substring(1);
}

/// A torque value as manuals print it: "824 – 1,030 Nm {84 – 105 kgm}",
/// "98 N·m", "70 lb ft".
final torqueValue = RegExp(
  r'\d[\d.,]*\s*(?:[-–~]\s*\d[\d.,]*\s*)?(?:N\s*[·.•]?\s*m|kgf?\s*[·.•]?\s*m|lbf?\s*[·.•]?\s*ft)(?![a-z])',
  caseSensitive: false,
);

/// A line with only a bare range like "5 to 50 Nm": a torque wrench in the
/// tools table, not a tightening torque.
final _toolRange = RegExp(r'^[\d.,]+\s*(?:to|[-–~])\s*[\d.,]+\s*N\s*[·.•]?\s*m$', caseSensitive: false);

/// The lines of [text] holding a torque value, as (start, end) indexes;
/// each line once, a very long line only around the value.
List<(int, int)> torqueLines(String text) {
  final found = <(int, int)>[];
  for (final m in torqueValue.allMatches(text)) {
    var start = text.lastIndexOf('\n', m.start) + 1;
    var end = text.indexOf('\n', m.end);
    if (end < 0) end = text.length;
    if (end - start > 160) (start, end) = (m.start, m.end);
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    if (found.isNotEmpty && found.last.$2 >= start) continue;
    if (_toolRange.hasMatch(text.substring(start, end))) continue;
    found.add((start, end));
  }
  return found;
}

/// One remove & install chapter found in a manual's bookmarks. [marks]
/// lists the pages holding a torque value; null when the manual has no text
/// to look in (scanned).
typedef PartPage = ({String fileKey, String group, String title, int page, int count, List<int>? marks});

/// A chapter whose torque values the viewer marks: pages [first]..[last],
/// torque values on [marks] (empty: the chapter has none; null: the manual
/// has no readable text).
typedef TorqueScan = ({int first, int last, List<int>? marks});

/// The remove & install chapters of [toc] (one manual), each under the title
/// of the bookmark one level up, once per group and component.
List<PartPage> partPages(
  String fileKey,
  List<({int level, String title, int page})> toc, {
  String? Function(int page)? textOf,
}) {
  final found = <PartPage>[];
  final seen = <String>{};
  for (var i = 0; i < toc.length; i++) {
    final (:level, :title, :page) = toc[i];
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    var name = partName(clean);
    if (name == null &&
        i + 1 < toc.length &&
        toc[i + 1].level == level + 1 &&
        _partStep.hasMatch(toc[i + 1].title.trim()) &&
        clean.isNotEmpty) {
      name = _cleanPartName(clean == clean.toUpperCase() ? clean[0] + clean.substring(1).toLowerCase() : clean);
    }
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
    last = last.clamp(page, page + maxPartPages - 1);
    // Torsi opens at the Installation part and marks torque from there on.
    final first = _installBookmark(toc, i, page, last) ?? (textOf == null ? null : installStart(textOf, page, last)) ?? page;
    found.add((
      fileKey: fileKey,
      group: group,
      title: name,
      page: first,
      count: last - first + 1,
      marks: textOf == null
          ? null
          : [
              for (var n = first; n <= last; n++)
                if (torqueLines(textOf(n) ?? '').isNotEmpty) n,
            ],
    ));
  }
  return found;
}

int? _installBookmark(List<({int level, String title, int page})> toc, int i, int first, int last) {
  final level = toc[i].level;
  for (final child in toc.skip(i + 1)) {
    if (child.level <= level) break;
    if (child.level == level + 1 &&
        RegExp(r'^ins[ty]allation$', caseSensitive: false).hasMatch(child.title.trim()) &&
        child.page >= first &&
        child.page <= last) {
      return child.page;
    }
  }
  return null;
}

// Same headings as INSTALL_* in tools/build_packages.py. Install steps alone
// don't count: removal steps say "Install the plug ..." too.
final _installHeading = RegExp(r'^(?:\d+[.)]?\s*)?installation:?$', caseSensitive: false);
final _installUpper = RegExp(r'^(?:INSTALL(?:ATION)?|METHOD FOR INSTALLING)(?: [A-Z0-9][A-Z0-9 ,()/&.\-]*)?$');
final _installReverse = RegExp(r'^carry out installation in the reverse order', caseSensitive: false);

/// First page of the Installation part of pages [first]..[last].
int? installStart(String? Function(int page) textOf, int first, int last) {
  for (var n = first; n <= last; n++) {
    for (var line in (textOf(n) ?? '').split('\n')) {
      line = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_installHeading.hasMatch(line) ||
          _installReverse.hasMatch(line) ||
          (line.length <= 80 && _installUpper.hasMatch(line))) {
        return n;
      }
    }
  }
  return null;
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
            // A scanned manual's index has no page text: its marks stay null.
            final texts = <int, String>{
              for (final row in db.select('SELECT CAST(page AS INTEGER) AS page, text FROM pages'))
                row['page'] as int: row['text'] as String,
            };
            found.addAll(partPages(entry.key, toc, textOf: texts.isEmpty ? null : (n) => texts[n]));
          } finally {
            db.close();
          }
        } on SqliteException {
          // An unreadable index just adds nothing.
        }
      }
      return found;
    });
