import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

/// One page that matched a search, read from a manual's .sqlite index
/// (built by tools/build_packages.py: tables meta, toc, pages FTS5).
class SearchHit {
  const SearchHit({
    required this.fileKey,
    required this.page,
    required this.rank,
    required this.section,
    required this.snippet,
  });

  final String fileKey;
  final int page;
  final double rank;
  final String? section;

  /// Snippet text with matches wrapped in [matchStart]/[matchEnd].
  final String snippet;

  static const matchStart = '\u0001';
  static const matchEnd = '\u0002';
}

class SearchResult {
  const SearchResult({required this.hits, required this.pageCounts});

  /// Best hits across all files, best first.
  final List<SearchHit> hits;

  /// Number of matching pages per file key (can exceed the hits returned).
  final Map<String, int> pageCounts;

  int get totalPages => pageCounts.values.fold(0, (a, b) => a + b);
}

/// Turns what the mechanic typed into an FTS5 query: every word must match,
/// and the last word also matches as a prefix so results show while typing.
String toFtsQuery(String text) {
  final words = text
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll('"', ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final terms = [for (final w in words.take(words.length - 1)) '"$w"', '"${words.last}"*'];
  return terms.join(' ');
}

const _searchSql = '''
SELECT page, bm25(pages) AS rank,
       snippet(pages, 1, char(1), char(2), '…', 14) AS snip,
       (SELECT title FROM toc WHERE toc.page <= pages.page
        ORDER BY toc.page DESC, toc.seq DESC LIMIT 1) AS section
FROM pages
WHERE pages MATCH ?
ORDER BY rank
LIMIT ?
''';

/// Searches the given index files ({fileKey: path to .sqlite}).
///
/// Runs on a background isolate so typing stays smooth.
Future<SearchResult> searchIndexes(
  Map<String, String> indexes,
  String text, {
  int limitPerFile = 30,
}) {
  final query = toFtsQuery(text);
  if (query.isEmpty || indexes.isEmpty) {
    return Future.value(const SearchResult(hits: [], pageCounts: {}));
  }
  return Isolate.run(() => searchIndexesSync(indexes, query, limitPerFile: limitPerFile));
}

SearchResult searchIndexesSync(Map<String, String> indexes, String ftsQuery, {int limitPerFile = 30}) {
  final hits = <SearchHit>[];
  final counts = <String, int>{};
  for (final entry in indexes.entries) {
    final db = sqlite3.open(entry.value, mode: OpenMode.readOnly);
    try {
      for (final row in db.select(_searchSql, [ftsQuery, limitPerFile])) {
        hits.add(SearchHit(
          fileKey: entry.key,
          page: row['page'] as int,
          rank: (row['rank'] as num).toDouble(),
          section: row['section'] as String?,
          snippet: (row['snip'] as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
        ));
      }
      final count = db.select('SELECT count(*) AS n FROM pages WHERE pages MATCH ?', [ftsQuery]);
      final n = count.first['n'] as int;
      if (n > 0) counts[entry.key] = n;
    } on SqliteException {
      // A malformed query (e.g. only punctuation) simply matches nothing.
    } finally {
      db.close();
    }
  }
  hits.sort((a, b) => a.rank.compareTo(b.rank));
  return SearchResult(hits: hits, pageCounts: counts);
}

typedef TocEntry = ({int level, String title, int page});

/// The PDF's bookmarks as stored in its index, in document order. Used to
/// name the section of a page without parsing the PDF again.
List<TocEntry> loadToc(String indexPath) {
  try {
    final db = sqlite3.open(indexPath, mode: OpenMode.readOnly);
    try {
      return [
        for (final row in db.select('SELECT level, title, page FROM toc ORDER BY seq'))
          (level: row['level'] as int, title: row['title'] as String, page: row['page'] as int),
      ];
    } finally {
      db.close();
    }
  } on SqliteException {
    return const [];
  }
}
