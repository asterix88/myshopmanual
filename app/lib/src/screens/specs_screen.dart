import 'package:flutter/material.dart';

import '../models.dart';
import '../specs.dart';
import 'shell.dart';
import 'viewer_screen.dart';
import 'unit_tabs.dart';

/// The Spek tab: one unit at a time (picked from the side menu), with its
/// bolt torque, capacity and standard value pages under three tabs. Pages
/// open from the unit's spek.pdf on the phone; units whose catalog has no
/// spek.pdf yet fall back to the manuals' bookmarks and open the manual.
/// Torsi also lists the shop manual's remove & install chapters by group;
/// they open in the manual with the torque lines marked.
class SpecsScreen extends StatefulWidget {
  const SpecsScreen({super.key});

  @override
  State<SpecsScreen> createState() => _SpecsScreenState();
}

class _SpecsScreenState extends State<SpecsScreen> {
  /// Bookmark matches for a unit without spek.pdf, per section.
  List<List<SpecPage>>? _fallback;
  String? _fallbackFor;
  int _session = 0;

  /// Remove & install chapters read from the manuals' bookmarks, for a
  /// unit whose catalog does not list them yet.
  List<PartPage>? _parts;
  String? _partsFor;
  int _partsSession = 0;

  static const _tabs = [
    (Icons.build_outlined, 'Torsi'),
    (Icons.water_drop_outlined, 'Kapasitas'),
    (Icons.speed, 'Nilai standar'),
  ];

  Future<void> _loadFallback(Unit unit) async {
    if (_fallbackFor == unit.id) return;
    final store = StoreScope.read(context);
    final session = ++_session;
    _fallbackFor = unit.id;
    _fallback = null;
    final indexes = await store.aiIndexes(where: (f) => f.unitId == unit.id, fetch: store.online == true);
    final pages = await findSpecPages(indexes);
    if (!mounted || session != _session) return;
    setState(() {
      _fallback = pages;
      // Indexes still on their way: look again on the next rebuild.
      if (indexes.isEmpty) _fallbackFor = null;
    });
  }

  Future<void> _loadParts(Unit unit) async {
    if (_partsFor == unit.id) return;
    final store = StoreScope.read(context);
    final session = ++_partsSession;
    _partsFor = unit.id;
    _parts = null;
    final indexes = await store.aiIndexes(
      where: (f) => f.unitId == unit.id && f.type != DocType.partsbook,
      fetch: store.online == true,
    );
    final parts = await findPartPages(indexes);
    if (!mounted || session != _partsSession) return;
    setState(() {
      _parts = parts;
      if (indexes.isEmpty) _partsFor = null;
    });
  }

  /// The unit's remove & install chapters: from the catalog (where
  /// spek-hapus.txt applies) or else from the manuals' bookmarks.
  List<PartPage> _partsOf(Unit unit) {
    final listed = unit.spec?.parts;
    if (listed != null) {
      return [
        for (final p in listed)
          (fileKey: '${unit.id}/${p.fileId}', group: p.group, title: p.title, page: p.page, count: p.count),
      ];
    }
    return _partsFor == unit.id ? _parts ?? const [] : const [];
  }

  void _openPart(PartPage part) {
    final file = StoreScope.read(context).fileByKey(part.fileKey);
    if (file == null) return;
    openViewer(context, file, page: part.page, torquePages: (part.page, part.page + part.count - 1));
  }

  List<Widget> _partGroups(List<PartPage> parts) {
    final groups = <String, List<PartPage>>{};
    for (final p in parts) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }
    return [
      for (final (i, MapEntry(key: group, value: list)) in groups.entries.indexed)
        PartGroupCard(
          key: ValueKey('part-group/$group'),
          title: group.isEmpty ? 'Lainnya' : group,
          parts: list,
          onOpen: _openPart,
          open: i == 0,
        ),
    ];
  }

  List<List<PageRow>>? _rows(Unit unit) {
    final store = StoreScope.read(context);
    final spec = unit.spec;
    if (spec != null) {
      return [
        for (var i = 0; i < _tabs.length; i++)
          [
            for (final e in spec.pages)
              if (e.section == i)
                (
                  title: e.title,
                  file: store.fileByKey('${unit.id}/${e.fileId}'),
                  page: e.page,
                  at: e.at,
                  heading: false,
                ),
          ],
      ];
    }
    final fallback = _fallback;
    if (fallback == null || _fallbackFor != unit.id) return null;
    return [
      for (var i = 0; i < _tabs.length; i++)
        [
          if (i < fallback.length)
            for (final e in fallback[i])
              (title: e.title, file: store.fileByKey(e.fileKey), page: e.page, at: null, heading: false),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = [
      for (final u in store.units)
        if (u.spec != null || store.filesOf(u).any((f) => f.searchable)) u,
    ];
    final unit = UnitTabsPage.current(store, units);
    if (unit != null && unit.spec == null) _loadFallback(unit);
    if (unit != null && unit.spec?.parts == null) _loadParts(unit);
    final rows = unit == null ? null : _rows(unit);
    final parts = unit == null ? const <PartPage>[] : _partsOf(unit);
    return UnitTabsPage(
      units: units,
      unit: unit,
      tabs: _tabs,
      views: [
        for (final (i, list) in (rows ?? List.filled(_tabs.length, const <PageRow>[])).indexed)
          rows == null
              ? const Center(child: CircularProgressIndicator())
              : PageRowList(
                  rows: list,
                  hint: '${list.length} halaman dari bookmark manual ${unit!.name}',
                  onOpen: (r) => openPageRow(context, unit, r),
                  // Torsi: the components' remove & install chapters follow.
                  after: i == 0 ? _partGroups(parts) : const [],
                ),
      ],
    );
  }
}
