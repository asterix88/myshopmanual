import 'package:flutter/material.dart';

import '../models.dart';
import '../specs.dart';
import 'shell.dart';
import 'unit_tabs.dart';

/// The Spek tab: one unit at a time (picked from the side menu), with its
/// bolt torque, capacity and standard value pages under three tabs. Pages
/// open from the unit's spek.pdf on the phone; units whose catalog has no
/// spek.pdf yet fall back to the manuals' bookmarks and open the manual.
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
    final rows = unit == null ? null : _rows(unit);
    return UnitTabsPage(
      units: units,
      unit: unit,
      tabs: _tabs,
      views: [
        for (final list in rows ?? List.filled(_tabs.length, const <PageRow>[]))
          rows == null
              ? const Center(child: CircularProgressIndicator())
              : PageRowList(
                  rows: list,
                  hint: '${list.length} halaman dari bookmark manual ${unit!.name}',
                  onOpen: (r) => openPageRow(context, unit, r),
                ),
      ],
    );
  }
}
