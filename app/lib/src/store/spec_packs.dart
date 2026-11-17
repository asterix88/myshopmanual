part of '../store.dart';

/// Per-unit spek.pdf packs used by the Standar and Servis tabs.
extension AppStoreSpecPacks on AppStore {
  /// Where a unit's spek.pdf is kept; the version is in the name so an
  /// update fetches it afresh.
  String specPath(Unit unit, SpecPack spec) =>
      p.join(_root.path, 'spek', '${unit.id}-${spec.file.sha256.substring(0, 12)}.pdf');

  /// The unit's spek.pdf if it is on the phone.
  String? readySpecPath(Unit unit) {
    final spec = unit.spec;
    if (spec == null) return null;
    final path = specPath(unit, spec);
    return File(path).existsSync() ? path : null;
  }

  /// Fetches the spek.pdf of every unit that lacks it (they are small) and
  /// deletes old versions, so the Spek tab opens its pages without signal.
  /// Stops at the first failure (offline) and tries again on the next refresh.
  Future<void> fetchSpecPacks() async {
    if (_fetchingSpecs) return;
    _fetchingSpecs = true;
    try {
      for (final unit in catalog.units) {
        final spec = unit.spec;
        if (spec == null || readySpecPath(unit) != null) continue;
        final target = specPath(unit, spec);
        try {
          await _fetch(spec.file, target, DownloadProgress(spec.file.size));
        } on Exception catch (e) {
          debugPrint('spek ${unit.id} failed: $e');
          return;
        }
        await File('$target.part').rename(target);
        await _deleteIfExists(File('$target.part.sha'));
        _changed();
      }
      final keep = {
        for (final u in catalog.units)
          if (u.spec != null) specPath(u, u.spec!),
      };
      final dir = Directory(p.join(_root.path, 'spek'));
      if (await dir.exists()) {
        await for (final entry in dir.list()) {
          if (entry is File && entry.path.endsWith('.pdf') && !keep.contains(entry.path)) await entry.delete();
        }
      }
    } finally {
      _fetchingSpecs = false;
    }
  }
}
