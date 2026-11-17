part of '../store.dart';

/// The bell: what changed on the server since the user last looked.
extension AppStoreUpdates on AppStore {
  /// Changes on the server since the user last looked (only meaningful once
  /// the catalog was fetched at least once).
  List<ManualUpdate> get updates =>
      computeUpdates(remote: catalog, local: local, seenKeys: seenKeys);

  /// Updates the user has not looked at yet: what the bell counts.
  List<ManualUpdate> get unseenUpdates => [
        for (final u in updates)
          if (!seenKeys.contains(u.seenKey)) u,
      ];

  /// What the update list shows, newest first: changes still pending and
  /// the ones already seen, until the bin clears them.
  List<ManualUpdate> get listedUpdates {
    final listed = <String>{};
    return [
      for (final u in [...updates, ...updateLog])
        if (!dismissedUpdates.contains(u.seenKey) && listed.add(u.seenKey)) u,
    ];
  }

  /// Not looked at yet: marked on the update list.
  bool isUnseen(ManualUpdate update) => !seenKeys.contains(update.seenKey);

  /// Adds [pending] updates not logged yet to the front of [updateLog].
  bool _remember(List<ManualUpdate> pending) {
    final logged = {for (final u in updateLog) u.seenKey};
    final fresh = [for (final u in pending) if (!logged.contains(u.seenKey)) u];
    if (fresh.isEmpty) return false;
    updateLog = [...fresh, ...updateLog].take(200).toList();
    return true;
  }

  /// Empties the update list (the bin on it); manuals on the phone stay.
  void clearUpdates() {
    dismissedUpdates.addAll(listedUpdates.map((u) => u.seenKey));
    markUpdatesSeen();
    _scheduleSave();
    _changed();
  }

  void markUpdatesSeen() {
    final before = seenKeys.length;
    final pending = updates;
    final logged = _remember(pending);
    seenKeys.addAll(catalog.files.map((f) => f.key));
    seenKeys.addAll(pending.map((u) => u.seenKey));
    if (seenKeys.length != before || logged) {
      _scheduleSave();
      _changed();
    }
  }

  /// Opening a unit counts as seeing its updates: its badges and its part
  /// of the bell's count go; the update list keeps them.
  void markUnitUpdatesSeen(String unitId) {
    final pending = [for (final u in unseenUpdates) if (u.file.unitId == unitId) u];
    if (pending.isEmpty) return;
    _remember(pending);
    seenKeys.addAll(pending.map((u) => u.seenKey));
    _scheduleSave();
    _changed();
  }
}
