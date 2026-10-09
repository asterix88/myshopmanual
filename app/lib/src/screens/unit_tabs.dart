import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../page_image.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/unit_icon.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Shared by the Spek and Servis tabs: a unit picked from the side menu (the
/// same unit on both tabs), and tabs along the top.
class UnitTabsPage extends StatelessWidget {
  const UnitTabsPage({
    super.key,
    required this.units,
    required this.unit,
    required this.tabs,
    required this.views,
    this.empty,
  });

  final List<Unit> units;
  final Unit? unit;
  final List<(IconData?, String)> tabs;
  final List<Widget> views;

  /// Shown instead of the tabs when there are none (or no unit).
  final Widget? empty;

  /// The unit the Spek and Servis tabs show: the one picked last, else the
  /// unit of the manual read last, else the first.
  static Unit? current(AppStore store, List<Unit> units) {
    final chosen = units.where((u) => u.id == store.pickedUnitId).firstOrNull;
    if (chosen != null) return chosen;
    final lastUnit = store.lastRead == null ? null : store.fileByKey(store.lastRead!.fileKey)?.unitId;
    return units.where((u) => u.id == lastUnit).firstOrNull ?? units.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unit = this.unit;
    final showTabs = unit != null && tabs.isNotEmpty;
    final page = Scaffold(
      drawer: UnitDrawer(
        units: units,
        current: unit?.id,
        onPick: (u) {
          store.pickUnit(u.id);
          Navigator.of(context).pop();
        },
      ),
      body: Builder(
        builder: (context) => Column(
          children: [
            Material(
              color: AppColors.surface,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(4, 10, 12, showTabs ? 0 : 10),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Pilih unit',
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                          if (unit != null)
                            Flexible(
                              child: InkWell(
                                key: const Key('spek-unit'),
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => Scaffold.of(context).openDrawer(),
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
                                              style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w700,
                                                height: 1.15,
                                              ),
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
                    if (showTabs)
                      TabBar(
                        isScrollable: tabs.length > 4,
                        tabAlignment: tabs.length > 4 ? TabAlignment.start : null,
                        labelColor: AppColors.navy,
                        unselectedLabelColor: AppColors.muted,
                        indicatorColor: AppColors.orange,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: AppColors.line,
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        tabs: [
                          for (final (icon, label) in tabs)
                            icon == null
                                ? Tab(height: 48, text: label)
                                : Tab(height: 58, icon: Icon(icon, size: 20), text: label),
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
                  : showTabs
                  ? TabBarView(children: views)
                  : empty ?? const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    return DefaultTabController(
      // A unit with other tabs (Servis intervals) starts a fresh controller.
      key: ValueKey('${unit?.id}/${tabs.length}'),
      length: tabs.length,
      child: page,
    );
  }
}

/// EXCAVATOR -> Excavator.
String _capitalized(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

/// One row on a Spek or Servis tab. A [heading] row is drawn as a label
/// above the rows that follow it.
typedef PageRow = ({String title, ManualFile? file, int page, int? at, bool heading});

/// The rows of one tab; [onOpen] opens a row's page.
class PageRowList extends StatelessWidget {
  const PageRowList({
    super.key,
    required this.rows,
    required this.onOpen,
    this.hint,
    this.emptyTitle,
    this.after = const [],
  });

  final List<PageRow> rows;
  final ValueChanged<PageRow> onOpen;
  final String? hint;
  final String? emptyTitle;

  /// Shown below the rows (the Torsi tab's component groups).
  final List<Widget> after;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && after.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: emptyTitle ?? 'Tidak ditemukan di bookmark manual unit ini',
        message: 'Coba cari di tab Cari.',
      );
    }
    final hint = this.hint;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: rows.length + (hint == null ? 0 : 1) + after.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final afterAt = i - rows.length - (hint == null ? 0 : 1);
        if (afterAt >= 0) return after[afterAt];
        if (hint != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(hint, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          );
        }
        final row = rows[i - (hint == null ? 0 : 1)];
        final file = row.file;
        if (row.heading) {
          return InkWell(
            onTap: () => onOpen(row),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.orangeText,
                      ),
                    ),
                  ),
                  Text('hlm ${row.page}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          );
        }
        return AppCard(
          onTap: () => onOpen(row),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const PageThumb(),
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
                    if (file != null) ...[const SizedBox(height: 5), Pill.docType(file.type)],
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

/// Opens [row] from the unit's spek.pdf when it is on the phone, else the
/// page in the full manual.
void openPageRow(BuildContext context, Unit unit, PageRow row) {
  final store = StoreScope.read(context);
  final path = store.readySpecPath(unit);
  final at = row.at;
  if (path != null && at != null) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpecViewerScreen(
          path: path,
          page: at,
          title: row.title,
          unitName: unit.name,
          file: row.file,
          sourcePage: row.page,
        ),
      ),
    );
  } else if (row.file != null) {
    openViewer(context, row.file!, page: row.page);
  }
}

/// A small drawing of a manual page with a table on it.
class PageThumb extends StatelessWidget {
  const PageThumb({super.key});

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
              decoration: BoxDecoration(
                border: Border.all(color: grey),
                borderRadius: BorderRadius.circular(2),
              ),
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

class UnitDrawer extends StatelessWidget {
  const UnitDrawer({super.key, required this.units, required this.current, required this.onPick});

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
    required this.unitName,
    required this.file,
    required this.sourcePage,
  });

  final String path;
  final int page;
  final String title;
  final String unitName;

  /// The full manual the page came from, and its page there.
  final ManualFile? file;
  final int sourcePage;

  @override
  State<SpecViewerScreen> createState() => _SpecViewerScreenState();
}

class _SpecViewerScreenState extends State<SpecViewerScreen> {
  final _controller = PdfViewerController();

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

  void _askAi() {
    final file = widget.file;
    final where = file == null ? '' : ' (${file.title} hlm ${widget.sourcePage})';
    StoreScope.read(context).askAi('Jelaskan isi halaman "${widget.title}"$where untuk unit ${widget.unitName}.');
    Navigator.of(context).popUntil((route) => route.isFirst);
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
        controller: _controller,
        initialPageNumber: widget.page,
        params: PdfViewerParams(
          backgroundColor: AppColors.viewerBackground,
          margin: 8,
          sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(maxScale: 16),
          viewerOverlayBuilder: (context, size, handleLinkTap) => [pageScrollThumb(_controller)],
        ),
      ),
      bottomNavigationBar: Container(
        color: AppColors.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                if (file != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () => openViewer(context, file, page: widget.sourcePage),
                      // One line on a narrow phone.
                      child: const Text('Manual lengkap', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _askAi,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Tanya nyel AI'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row inside a [GroupCard].
typedef GroupItem = ({String title, String? subtitle, VoidCallback onTap});

/// A group on the Torsi tab (Standard tightening torque, or one of the shop
/// manual's own sections such as "Undercarriage and frame"): a header that
/// opens and closes the list of its rows.
class GroupCard extends StatefulWidget {
  const GroupCard({super.key, required this.title, required this.items, this.open = false});

  final String title;
  final List<GroupItem> items;
  final bool open;

  @override
  State<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<GroupCard> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              color: _open ? AppColors.field : null,
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  // Title and count take all the room left of the arrow, so
                  // the arrow lines up on every card whatever the title length.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                          child: Text('${widget.items.length}', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                ],
              ),
            ),
          ),
          if (_open)
            for (final item in widget.items) GroupItemTile(item: item),
        ],
      ),
    );
  }
}

/// One row of a [GroupCard], with a line above it; [ItemCard] shows one on
/// its own.
class GroupItemTile extends StatelessWidget {
  const GroupItemTile({super.key, required this.item, this.line = true});

  final GroupItem item;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      child: Container(
        decoration: BoxDecoration(
          border: line ? Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (item.subtitle case final sub?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

/// A single [GroupItem] as its own card, lined up with the [GroupCard]s.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item});

  final GroupItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: GroupItemTile(item: item, line: false),
    );
  }
}
