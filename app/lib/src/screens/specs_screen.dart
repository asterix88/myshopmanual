import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../page_image.dart';
import '../specs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/unit_icon.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// The Spek tab: one unit at a time (picked from the side menu), with its
/// bolt torque, capacity and standard value pages under three tabs. Pages
/// open from the unit's spek.pdf on the phone; units whose catalog has no
/// spek.pdf yet fall back to the manuals' bookmarks and open the manual.
class SpecsScreen extends StatefulWidget {
  const SpecsScreen({super.key});

  @override
  State<SpecsScreen> createState() => _SpecsScreenState();
}

/// One row on a tab.
typedef _Row = ({String title, ManualFile? file, int page, int? at});

class _SpecsScreenState extends State<SpecsScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String? _unitId;

  /// Bookmark matches for a unit without spek.pdf, per section.
  List<List<SpecPage>>? _fallback;
  String? _fallbackFor;
  int _session = 0;

  static const _tabs = [
    (Icons.build_outlined, 'Torsi'),
    (Icons.water_drop_outlined, 'Kapasitas'),
    (Icons.speed, 'Nilai standar'),
  ];

  List<Unit> _units() {
    final store = StoreScope.read(context);
    return [
      for (final u in store.units)
        if (u.spec != null || store.filesOf(u).any((f) => f.searchable)) u,
    ];
  }

  Unit? _current(List<Unit> units) {
    final store = StoreScope.read(context);
    final chosen = units.where((u) => u.id == _unitId).firstOrNull;
    if (chosen != null) return chosen;
    final lastUnit = store.lastRead == null ? null : store.fileByKey(store.lastRead!.fileKey)?.unitId;
    return units.where((u) => u.id == lastUnit).firstOrNull ?? units.firstOrNull;
  }

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

  List<List<_Row>>? _rows(Unit unit) {
    final store = StoreScope.read(context);
    final spec = unit.spec;
    if (spec != null) {
      return [
        for (var i = 0; i < _tabs.length; i++)
          [
            for (final e in spec.pages)
              if (e.section == i)
                (title: e.title, file: store.fileByKey('${unit.id}/${e.fileId}'), page: e.page, at: e.at),
          ],
      ];
    }
    final fallback = _fallback;
    if (fallback == null || _fallbackFor != unit.id) return null;
    return [
      for (var i = 0; i < _tabs.length; i++)
        [
          if (i < fallback.length)
            for (final e in fallback[i]) (title: e.title, file: store.fileByKey(e.fileKey), page: e.page, at: null),
        ],
    ];
  }

  void _open(Unit unit, _Row row) {
    final store = StoreScope.read(context);
    final path = store.readySpecPath(unit);
    final at = row.at;
    if (path != null && at != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SpecViewerScreen(path: path, page: at, title: row.title, file: row.file, sourcePage: row.page),
      ));
    } else if (row.file != null) {
      openViewer(context, row.file!, page: row.page);
    }
  }

  @override
  Widget build(BuildContext context) {
    StoreScope.of(context);
    final units = _units();
    final unit = _current(units);
    if (unit != null && unit.spec == null) _loadFallback(unit);
    final rows = unit == null ? null : _rows(unit);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        key: _scaffold,
        drawer: _UnitDrawer(
          units: units,
          current: unit?.id,
          onPick: (u) {
            setState(() => _unitId = u.id);
            Navigator.of(context).pop();
          },
        ),
        body: Column(
          children: [
            Material(
              color: AppColors.surface,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Pilih unit',
                            onPressed: () => _scaffold.currentState?.openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                          if (unit != null)
                            Flexible(
                              child: InkWell(
                                key: const Key('spek-unit'),
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _scaffold.currentState?.openDrawer(),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      UnitIcon(unitId: unit.id, width: 48, height: 40),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _capitalized(unit.machine.label),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.muted,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            Text(
                                              unit.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down, color: AppColors.muted),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TabBar(
                      labelColor: AppColors.navy,
                      unselectedLabelColor: AppColors.muted,
                      indicatorColor: AppColors.orange,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: AppColors.line,
                      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      tabs: [
                        for (final (icon, label) in _tabs) Tab(height: 58, icon: Icon(icon, size: 20), text: label),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: unit == null
                  ? const EmptyState(
                      icon: Icons.cloud_download_outlined,
                      title: 'Belum ada manual',
                      message: 'Sambungkan ke internet sebentar agar daftar manual diambil.',
                    )
                  : rows == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            for (final list in rows) _SpecList(unit: unit, rows: list, onOpen: (r) => _open(unit, r)),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EXCAVATOR -> Excavator.
String _capitalized(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

class _SpecList extends StatelessWidget {
  const _SpecList({required this.unit, required this.rows, required this.onOpen});

  final Unit unit;
  final List<_Row> rows;
  final ValueChanged<_Row> onOpen;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Tidak ditemukan di bookmark manual unit ini',
        message: 'Coba cari di tab Cari.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: rows.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${rows.length} halaman dari bookmark manual ${unit.name}',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          );
        }
        final row = rows[i - 1];
        final file = row.file;
        return AppCard(
          onTap: () => onOpen(row),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const _PageThumb(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 3),
                    Text(
                      [?file?.title, 'hlm ${row.page}'].join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    if (file != null) ...[
                      const SizedBox(height: 5),
                      Pill.docType(file.type),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.faint),
            ],
          ),
        );
      },
    );
  }
}

/// A small drawing of a manual page with a table on it.
class _PageThumb extends StatelessWidget {
  const _PageThumb();

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFFC9CED6);
    Widget bar(double widthFactor, {Color color = grey, double height = 3}) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        );
    return Container(
      width: 50,
      height: 66,
      padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(0.7, color: const Color(0xFF1E3A64), height: 4),
          const SizedBox(height: 4),
          bar(1),
          const SizedBox(height: 4),
          bar(0.8),
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: grey), borderRadius: BorderRadius.circular(2)),
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFE3E6EA))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitDrawer extends StatelessWidget {
  const _UnitDrawer({required this.units, required this.current, required this.onPick});

  final List<Unit> units;
  final String? current;
  final ValueChanged<Unit> onPick;

  @override
  Widget build(BuildContext context) {
    final groups = <Machine, List<Unit>>{};
    for (final u in units) {
      groups.putIfAbsent(u.machine, () => []).add(u);
    }
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
              child: Text('Pilih unit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            for (final machine in Machine.values)
              if (groups[machine] case final list?) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                  child: Text(
                    machine.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.orangeText,
                    ),
                  ),
                ),
                for (final u in list)
                  Material(
                    color: u.id == current ? AppColors.navySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onPick(u),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            UnitIcon(unitId: u.id, width: 52, height: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                u.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: u.id == current ? AppColors.navy : AppColors.ink,
                                ),
                              ),
                            ),
                            if (u.id == current) Icon(Icons.check, color: AppColors.navy, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

/// Shows a unit's spek.pdf from the phone, opened at one entry's page.
class SpecViewerScreen extends StatefulWidget {
  const SpecViewerScreen({
    super.key,
    required this.path,
    required this.page,
    required this.title,
    required this.file,
    required this.sourcePage,
  });

  final String path;
  final int page;
  final String title;

  /// The full manual the page came from, and its page there.
  final ManualFile? file;
  final int sourcePage;

  @override
  State<SpecViewerScreen> createState() => _SpecViewerScreenState();
}

class _SpecViewerScreenState extends State<SpecViewerScreen> {
  /// PDFium has one worker: the AI's page drawing waits while this is open.
  late final void Function() _resumeServerDrawing;

  @override
  void initState() {
    super.initState();
    _resumeServerDrawing = pauseServerDrawing();
  }

  @override
  void dispose() {
    _resumeServerDrawing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return Scaffold(
      backgroundColor: AppColors.viewerBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            Text(
              [?file?.title, 'hlm ${widget.sourcePage}'].join(' · '),
              style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: PdfViewer.file(
        widget.path,
        initialPageNumber: widget.page,
        params: PdfViewerParams(
          backgroundColor: AppColors.viewerBackground,
          margin: 8,
          sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(maxScale: 16),
        ),
      ),
      bottomNavigationBar: file == null
          ? null
          : Container(
              color: AppColors.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: OutlinedButton.icon(
                    onPressed: () => openViewer(context, file, page: widget.sourcePage),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Buka manual lengkap'),
                  ),
                ),
              ),
            ),
    );
  }
}
