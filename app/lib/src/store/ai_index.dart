part of '../store.dart';

/// Search indexes for Nyel AI: every manual's small index is fetched in
/// the background (never the PDF) and kept in sync with the server.
extension AppStoreAiIndexes on AppStore {
  /// Progress of [fetchAllAiIndexes] while it runs: indexes ready of total,
  /// and bytes received of the bytes it has to fetch.
  AiIndexProgress? get aiIndexProgress => _aiIndexRun;

  /// Fetches every missing search index for Nyel AI (indexes only, never
  /// PDFs), a few at a time, and deletes cached indexes of manuals no longer
  /// on the server. A failed index is skipped; after several failures in a
  /// row (offline) it stops and tries again on the next refresh.
  Future<void> fetchAllAiIndexes() async {
    if (_aiIndexRun != null) return;
    final files = [for (final f in catalog.files) if (f.searchable) f];
    final missing = [for (final f in files) if (_readyAiIndex(f) == null) f];
    final run = _aiIndexRun = AiIndexProgress(
      total: files.length,
      ready: files.length - missing.length,
      totalBytes: missing.fold(0, (s, f) => s + f.index.size),
    );
    _changed();
    var failuresInARow = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < missing.length && failuresInARow < 3) {
        final file = missing[next++];
        final got = await aiIndexes(where: (f) => f.key == file.key);
        if (got.isEmpty) {
          failuresInARow++;
        } else {
          failuresInARow = 0;
          run.ready++;
        }
        run.doneBytes += file.index.size;
        _changed();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
      if (failuresInARow < 3) await _deleteStaleAiIndexes();
    } finally {
      _aiIndexRun = null;
      _changed();
    }
  }

  Future<void> _deleteStaleAiIndexes() async {
    final keep = {for (final f in catalog.files) cachedIndexPath(f)};
    final dir = Directory(p.join(_root.path, 'index-cache'));
    if (!await dir.exists()) return;
    await for (final entry in dir.list(recursive: true)) {
      if (entry is File && entry.path.endsWith('.sqlite') && !keep.contains(entry.path)) await entry.delete();
    }
  }

  String cachedIndexPath(ManualFile f) =>
      p.join(_root.path, 'index-cache', f.unitId, '${f.id}-${f.index.sha256.substring(0, 12)}.sqlite');

  /// Search indexes for Nyel AI over every manual on the server, by file
  /// key: a downloaded manual uses its own index; for any other only the small
  /// index is fetched (not the PDF) and kept. [where] narrows the manuals, so
  /// a question about one unit only fetches that unit's indexes. A manual
  /// whose index can't be fetched (offline) is left out.
  ///
  /// With [fetch] false nothing is downloaded: only indexes already on the
  /// phone are returned.
  Future<Map<String, String>> aiIndexes({
    bool Function(ManualFile file)? where,
    void Function(String status)? onStatus,
    bool fetch = true,
  }) async {
    final result = <String, String>{};
    for (final file in catalog.files.followedBy(local.values.map((m) => m.file))) {
      if (!file.searchable || result.containsKey(file.key) || !(where?.call(file) ?? true)) continue;
      final ready = _readyAiIndex(file);
      if (ready != null) {
        result[file.key] = ready;
        continue;
      }
      if (!fetch) continue;
      final target = cachedIndexPath(file);
      onStatus?.call('Mengambil indeks ${unitNameOf(file)} · ${file.type.label}…');
      // The background fetch and a question may want the same index at
      // once; they share one download.
      final download = _aiIndexFetches[file.key] ??=
          _fetchAiIndex(file, target).whenComplete(() {
            // A block body: returning the removed future would await itself.
            _aiIndexFetches.remove(file.key);
          });
      try {
        await download;
      } on Exception {
        continue;
      }
      result[file.key] = target;
    }
    return result;
  }

  /// The index of [file] if it is on the phone already (downloaded with
  /// the manual, or fetched for Nyel AI), else null.
  String? readyIndexPath(ManualFile file) => _readyAiIndex(file);

  /// Where the page sizes measured while [file] was open are kept (for
  /// indexes made before they had the sizes; see PageSizes).
  String pageSizeCachePath(ManualFile file) =>
      p.join(_root.path, 'page-sizes', file.unitId, '${file.id}-${file.pdf.sha256.substring(0, 12)}.json');

  /// The index of [file] if it is on the phone already, else null.
  String? _readyAiIndex(ManualFile file) {
    if (isDownloaded(file.key)) return indexPath(file);
    final cached = cachedIndexPath(file);
    return File(cached).existsSync() ? cached : null;
  }

  Future<void> _fetchAiIndex(ManualFile file, String target) async {
    final dir = Directory(p.dirname(target));
    if (await dir.exists()) {
      // Older versions of this manual's index.
      final old = RegExp('^${RegExp.escape(file.id)}-[0-9a-f]{12}\\.sqlite\$');
      await for (final entry in dir.list()) {
        if (old.hasMatch(p.basename(entry.path))) await entry.delete();
      }
    }
    final progress = DownloadProgress(file.index.size);
    final run = _aiIndexRun;
    run?._inFlight.add(progress);
    try {
      await _fetch(file.index, target, progress);
    } finally {
      run?._inFlight.remove(progress);
    }
    await File('$target.part').rename(target);
    await _deleteIfExists(File('$target.part.sha'));
  }

  /// Search indexes for the Cari tab, by file key: every manual whose index
  /// is on the phone, downloaded or not (the small indexes of the others are
  /// fetched in the background for Nyel AI).
  Map<String, String> searchableIndexes({DocType? type}) => {
        for (final file in catalog.files.followedBy(local.values.map((m) => m.file)))
          if (file.searchable && (type == null || file.type == type))
            file.key: ?_readyAiIndex(file),
      };
}
