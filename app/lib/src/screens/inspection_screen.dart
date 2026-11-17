import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../inspection.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

Future<void> openInspection(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionScreen()));

/// The navy of the header, the same in light and dark mode (as on Home).
const _headerNavy = Color(0xFF1E3A64);
const _headerSoft = Color(0xFFC9D3E3);

/// "12/11/2026 9:10:00" -> "12/11 09:10".
String shortUpdate(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/\d{4}(?:\s+(\d{1,2}):(\d{2}))?').firstMatch(s.trim());
  if (m == null) return s;
  final day = '${m[1]!.padLeft(2, '0')}/${m[2]!.padLeft(2, '0')}';
  return m[3] == null ? day : '$day ${m[3]!.padLeft(2, '0')}:${m[4]}';
}

/// Uppercase as it is typed, like the sheet.
class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Daily Inspection Monitoring: the findings of the NRP's section, with
/// ACTION filled in from the phone and new findings added to the sheet.
class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final _search = TextEditingController();
  String? _section;
  String? _model;
  String? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).inspection.open();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  List<String> _sections(Inspection data) {
    if (data.sections.isNotEmpty) return data.sections;
    final s = StoreScope.read(context).session;
    final mine = [for (final x in s?.sections ?? const <String>[]) if (inspectionSections.contains(x.toUpperCase())) x.toUpperCase()];
    return (s?.admin ?? false) ? inspectionSections : (mine.isEmpty ? const ['TRACK'] : mine);
  }

  void _flashRow(String id) {
    _flashTimer?.cancel();
    setState(() => _flash = id);
    _flashTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _toast(String text, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
      action: undo == null ? null : SnackBarAction(label: 'Urungkan', onPressed: undo),
    ));
  }

  Future<void> _openRow(Inspection data, InspectionRow row) async {
    final before = row.action;
    final result = await showModalBottomSheet<_Saved>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _FindingSheet(row: row, inspection: data),
    );
    if (result == null || !mounted) return;
    final status = result.action.isEmpty ? 'OPEN' : 'CLOSE';
    _flashRow(row.id);
    final note = result.sent ? '' : ' · belum terkirim';
    final text = before.isNotEmpty && result.action.isNotEmpty ? '${row.unit} action disimpan$note' : '${row.unit} $status$note';
    _toast(text, undo: () async {
      try {
        await data.setAction(row, before);
      } on InspectionException catch (e) {
        if (mounted) showError(context, e);
      }
    });
  }

  Future<void> _openFilter(List<InspectionRow> rows) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModelSheet(rows: rows, current: _model),
    );
    if (picked == null || !mounted) return;
    setState(() => _model = picked.isEmpty ? null : picked);
  }

  Future<void> _add(Inspection data, String section) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AddInspectionScreen(section: section)),
    );
    if (message != null && mounted) {
      setState(() {
        _model = null;
        _search.clear();
      });
      _toast(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = StoreScope.of(context).inspection;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final sections = _sections(data);
        final section = sections.contains(_section) ? _section! : sections.first;
        final tab = data.tabs[section];
        final all = tab?.rows ?? const <InspectionRow>[];
        final q = _search.text.trim().toUpperCase();
        final qKey = inspectionUnitKey(q);
        final shown = [
          for (final r in all)
            if ((_model == null || r.model == _model) &&
                (q.isEmpty || (qKey.isNotEmpty && inspectionUnitKey(r.unit).contains(qKey)) || r.problem.toUpperCase().contains(q)))
              r,
        ];
        final updated = tab == null || tab.updated.isEmpty ? '' : ' · Update ${shortUpdate(tab.updated)}';
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _Header(
                subtitle: '$section$updated',
                sheetUrl: data.sheetUrl,
                sections: sections,
                section: section,
                openCounts: {
                  for (final s in sections) s: (data.tabs[s]?.rows ?? const <InspectionRow>[]).where((r) => !r.closed).length,
                },
                onSection: (s) => setState(() {
                  _section = s;
                  _model = null;
                }),
                search: _search,
                onSearch: () => setState(() {}),
              ),
              if (data.healthProblem != null) _Bar(text: 'Admin: ${data.healthProblem}', danger: true),
              if (data.pendingCount > 0)
                _Bar(text: '${data.pendingCount} update belum terkirim', icon: Icons.wifi_off_rounded)
              else if (data.error != null && data.tabs.isNotEmpty)
                _Bar(text: data.error!, icon: Icons.wifi_off_rounded),
              if (data.refused != null)
                _Bar(
                  text: 'Tidak tersimpan: ${data.refused}',
                  danger: true,
                  onClose: () => setState(() => data.refused = null),
                ),
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _ModelButton(
                        label: _model ?? 'Semua',
                        active: _model != null,
                        onTap: () => _openFilter(all),
                      ),
                      if (_model != null)
                        TextButton(
                          onPressed: () => setState(() => _model = null),
                          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                          child: const Text('Hapus filter', style: TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: data.refresh,
                  child: _body(data, section, all, shown),
                ),
              ),
            ],
          ),
          floatingActionButton: data.tabs.isEmpty
              ? null
              : FloatingActionButton.extended(
                  key: const Key('inspection-add'),
                  onPressed: () => _add(data, section),
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add, size: 22),
                  label: const Text('Temuan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
        );
      },
    );
  }

  Widget _body(Inspection data, String section, List<InspectionRow> all, List<InspectionRow> shown) {
    if (data.tabs.isEmpty) {
      if (data.loading || (data.error == null && data.fetched == null)) {
        return ListView(children: const [SizedBox(height: 120), Center(child: ExcavatorLoader())]);
      }
      return ListView(children: [
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Data belum bisa dibuka',
          message: data.error,
          action: FilledButton(onPressed: data.refresh, child: const Text('Coba lagi')),
        ),
      ]);
    }
    if (shown.isEmpty) {
      return ListView(children: [
        EmptyState(
          icon: Icons.fact_check_outlined,
          title: all.isEmpty ? 'Belum ada temuan ${sectionLabel(section)}' : 'Tidak ada yang cocok',
          message: all.isEmpty ? 'Tambahkan dengan tombol + Temuan.' : 'Coba kata lain atau hapus filter model.',
        ),
      ]);
    }
    // Under a small heading per model, in the list's order.
    final groups = <String, List<InspectionRow>>{};
    for (final r in shown) {
      groups.putIfAbsent(r.model.isEmpty ? '-' : r.model, () => []).add(r);
    }
    final today = DateTime.now();
    return ListView(
      key: const Key('inspection-list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(g.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.6)),
                const SizedBox(width: 8),
                Text(_summary(g.value), style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          for (final r in g.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FindingCard(
                row: r,
                today: today,
                flash: _flash == r.id,
                onTap: () => _openRow(data, r),
              ),
            ),
        ],
      ],
    );
  }
}

String _summary(List<InspectionRow> rows) {
  final open = rows.where((r) => !r.closed).length;
  return '$open open · ${rows.length - open} close';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitle,
    required this.sheetUrl,
    required this.sections,
    required this.section,
    required this.openCounts,
    required this.onSection,
    required this.search,
    required this.onSearch,
  });

  final String subtitle;
  final String sheetUrl;
  final List<String> sections;
  final String section;
  final Map<String, int> openCounts;
  final ValueChanged<String> onSection;
  final TextEditingController search;
  final VoidCallback onSearch;

  Future<void> _openSheet(BuildContext context) async {
    if (sheetUrl.isEmpty) return;
    final ok = await launchUrl(Uri.parse(sheetUrl), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showError(context, 'Spreadsheet tidak bisa dibuka di HP ini.');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _headerNavy,
      padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: Colors.white,
                tooltip: 'Kembali',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Inspection Monitoring',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    Text(subtitle, style: const TextStyle(color: _headerSoft, fontSize: 12)),
                  ],
                ),
              ),
              if (sheetUrl.isNotEmpty)
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: const Key('inspection-sheet-link'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openSheet(context),
                    child: const SizedBox(
                      height: 32,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(8, 0, 10, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Sheet', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            SizedBox(width: 4),
                            Icon(Icons.north_east_rounded, size: 14, color: Color(0xFFF08A1C)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (sections.length > 1) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    for (final s in sections)
                      Expanded(
                        child: GestureDetector(
                          key: Key('inspection-tab-$s'),
                          onTap: () => onSection(s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: s == section ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: sectionLabel(s)),
                                TextSpan(
                                  text: '  ${openCounts[s] ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: s == section ? const Color(0xFFB42318) : _headerSoft,
                                  ),
                                ),
                              ]),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: s == section ? _headerNavy : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 20, color: Color(0xFF6B7178)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('inspection-search'),
                      controller: search,
                      onChanged: (_) => onSearch(),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1F2328)),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        filled: false,
                        hintText: 'Cari kode unit / temuan',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA3A8AF)),
                      ),
                    ),
                  ),
                  if (search.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        search.clear();
                        onSearch();
                      },
                      child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF6B7178)),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.text, this.icon, this.danger = false, this.onClose});

  final String text;
  final IconData? icon;
  final bool danger;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.danger : AppColors.amber;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? AppColors.danger.withValues(alpha: 0.1) : AppColors.amberSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.error_outline_rounded, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: fg))),
          if (onClose != null)
            GestureDetector(onTap: onClose, child: Icon(Icons.close_rounded, size: 16, color: fg)),
        ],
      ),
    );
  }
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.ink;
    return Material(
      color: active ? AppColors.navy : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? AppColors.navy : AppColors.border),
      ),
      child: InkWell(
        key: const Key('inspection-model-filter'),
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list_rounded, size: 18, color: fg),
                const SizedBox(width: 6),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Model: '),
                    TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  style: TextStyle(fontSize: 13, color: fg),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// OPEN (red) or CLOSE (green), as the sheet's STATUS says.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.closed});

  final bool closed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: closed ? AppColors.greenSoft : AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          closed ? 'CLOSE' : 'OPEN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: closed ? AppColors.green : AppColors.danger,
          ),
        ),
      );
}

String _who(InspectionRow r) {
  final first = r.inspector.split(RegExp(r'\s+')).first;
  return r.inspector.contains(' ') ? '$first dkk' : first;
}

String _ageText(int d) => d <= 0 ? 'Hari ini' : '$d hr';

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.row, required this.today, required this.flash, required this.onTap});

  final InspectionRow row;
  final DateTime today;
  final bool flash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final age = row.ageOn(today);
    final old = age != null && age > 30;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow,
        color: flash ? AppColors.greenSoft : AppColors.surface,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('finding-${row.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.unit,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: row.closed ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                    ),
                    if (!row.closed && age != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: old ? AppColors.amberSoft : AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _ageText(age),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: old ? AppColors.amber : AppColors.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    StatusPill(closed: row.closed),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  row.problem,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: row.closed ? AppColors.muted : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${row.date.length >= 5 ? row.date.substring(0, 5) : row.date} · HM ${row.hm} · ${_who(row)}',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (row.closed) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text('ACTION',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.green)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(row.action, style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.ink))),
                      ],
                    ),
                  ),
                ],
                if (row.pending) ...[
                  const SizedBox(height: 4),
                  Text('Belum terkirim', style: TextStyle(fontSize: 12, color: AppColors.amber)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The model filter: one row per model of the section, with its counts.
class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.rows, required this.current});

  final List<InspectionRow> rows;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final byModel = <String, List<InspectionRow>>{};
    for (final r in rows) {
      byModel.putIfAbsent(r.model, () => []).add(r);
    }
    final models = byModel.keys.toList()..sort(naturalCompare);
    Widget option(String value, String label, String sub) {
      final on = (current ?? '') == value;
      return InkWell(
        key: Key('model-option-${value.isEmpty ? 'semua' : value}'),
        onTap: () => Navigator.of(context).pop(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    Text(sub, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(
                on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? AppColors.navy : AppColors.faint,
              ),
            ],
          ),
        ),
      );
    }

    return _SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Model unit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  option('', 'Semua', _summary(rows)),
                  for (final m in models) option(m, m.isEmpty ? '-' : m, _summary(byModel[m]!)),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}

/// White sheet with rounded top and a grab handle.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.onDragDown});

  final Widget child;
  final VoidCallback? onDragDown;

  @override
  Widget build(BuildContext context) {
    final handle = Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Center(
        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) (onDragDown ?? () => Navigator.of(context).maybePop())();
            },
            child: handle,
          ),
          child,
        ],
      ),
    );
  }
}

class _Saved {
  const _Saved(this.action, this.sent);

  final String action;
  final bool sent;
}

/// A finding's details and its ACTION; saving it makes the finding CLOSE.
class _FindingSheet extends StatefulWidget {
  const _FindingSheet({required this.row, required this.inspection});

  final InspectionRow row;
  final Inspection inspection;

  @override
  State<_FindingSheet> createState() => _FindingSheetState();
}

class _FindingSheetState extends State<_FindingSheet> {
  late final _action = TextEditingController(text: widget.row.action);
  bool _saving = false;

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  bool get _dirty => _action.text.trim() != widget.row.action.trim();

  Future<void> _close() async {
    if (_dirty) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Buang isian Action?'),
          content: const Text('Tulisan yang belum disimpan akan hilang.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut isi')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buang')),
          ],
        ),
      );
      if (drop != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final text = _action.text.trim().toUpperCase();
    setState(() => _saving = true);
    try {
      final sent = await widget.inspection.setAction(widget.row, text);
      if (mounted) Navigator.of(context).pop(_Saved(text, sent));
    } on InspectionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final age = r.ageOn(DateTime.now());
    final found = [r.date, if (r.hm.isNotEmpty) 'HM ${r.hm}', if (age != null) '$age hari'].join(' · ');
    final canSave = !_saving && _dirty && (r.closed || _action.text.trim().isNotEmpty);
    Widget info(String label, String value, {bool first = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: AppColors.divider))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.muted))),
              Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.ink))),
            ],
          ),
        );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: _SheetFrame(
          onDragDown: _close,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + (keyboard > 0 ? 0 : MediaQuery.paddingOf(context).bottom)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.unit} · ${r.model}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    ),
                    StatusPill(closed: r.closed),
                  ],
                ),
                const SizedBox(height: 4),
                Text(r.problem, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35, color: AppColors.ink)),
                const SizedBox(height: 12),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: keyboard > 0
                      ? Text(
                          '${_who(r)} / ${r.leader} · ${r.date}',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        )
                      : Container(
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              info('Inspector', r.inspector, first: true),
                              info('Leader', r.leader),
                              info('Ditemukan', found),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Text('ACTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('inspection-action'),
                  controller: _action,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_Upper()],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Cth: done, replace saat service',
                    hintStyle: TextStyle(color: AppColors.faint, fontSize: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    key: const Key('inspection-save-action'),
                    onPressed: canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(r.closed ? 'Simpan perubahan' : 'Simpan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

/// "+ Temuan": new findings of one unit, one sheet row per problem.
class AddInspectionScreen extends StatefulWidget {
  const AddInspectionScreen({super.key, required this.section});

  final String section;

  @override
  State<AddInspectionScreen> createState() => _AddInspectionScreenState();
}

class _AddInspectionScreenState extends State<AddInspectionScreen> {
  final _unit = TextEditingController();
  final _model = TextEditingController();
  final _hm = TextEditingController();
  final _leader = TextEditingController();
  final _problems = [TextEditingController()];
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_unit, _model, _hm, _leader, ..._problems]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _touched =>
      [_unit, _model, _hm, _leader, ..._problems].any((c) => c.text.trim().isNotEmpty);

  Future<bool> _confirmLeave() async {
    if (!_touched) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buang temuan ini?'),
        content: const Text('Isian yang belum disimpan akan hilang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut isi')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buang')),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(Inspection data, String model) async {
    setState(() => _saving = true);
    final problems = [for (final c in _problems) c.text.trim()];
    final unit = _unit.text.trim().toUpperCase();
    try {
      final sent = await data.add(
        section: widget.section,
        unit: data.popIndex[inspectionUnitKey(unit)]?.unit ?? unit,
        model: model,
        hm: _hm.text,
        date: _date,
        leader: _leader.text,
        problems: problems,
      );
      if (!mounted) return;
      Navigator.of(context).pop('${problems.length} temuan baru · $unit${sent ? '' : ' · belum terkirim'}');
    } on InspectionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, e);
    }
  }

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.faint, fontSize: 14),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted)),
      );

  Widget _note(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: color ?? AppColors.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final data = store.inspection;
    final section = widget.section;
    final tab = data.tabs[section];
    final key = inspectionUnitKey(_unit.text);
    final hit = key.isEmpty ? null : data.popIndex[key];
    final other = hit != null && hit.section.isNotEmpty && hit.section != section ? hit.section : '';
    final locked = hit != null && other.isEmpty;
    final hits = key.isEmpty || hit != null
        ? const <PopUnit>[]
        : [for (final u in data.pop) if (u.section == section && inspectionUnitKey(u.unit).contains(key)) u].take(5).toList();
    final unknown = key.isNotEmpty && hit == null && hits.isEmpty;
    final model = locked ? hit.model : _model.text.trim().toUpperCase();
    final last = key.isEmpty ? null : lastHm(tab, hit?.unit ?? _unit.text);
    final inspector = data.inspector.isNotEmpty
        ? data.inspector
        : (store.session?.name ?? '').trim().toUpperCase().split(RegExp(r'\s+')).first;
    final leaders = tab?.leaders ?? const <String>[];
    final hmOk = RegExp(r'^\d+([.,]\d+)?$').hasMatch(_hm.text.trim());
    final filled = _problems.every((c) => c.text.trim().isNotEmpty);
    final ok = !_saving && key.isNotEmpty && other.isEmpty && model.isNotEmpty && hmOk && _leader.text.trim().isNotEmpty && filled;
    void changed(_) => setState(() {});

    Widget card(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        );

    return PopScope(
      canPop: !_touched || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Temuan baru'),
              Text(
                'Masuk ke sheet Inspection ${sectionLabel(section)} Open 2026',
                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            card([
              _label('CODE UNIT'),
              TextField(
                key: const Key('add-unit'),
                controller: _unit,
                inputFormatters: [_Upper()],
                textCapitalization: TextCapitalization.characters,
                onChanged: changed,
                decoration: _box('Cth: ${unitExamples[section] ?? ''}'),
              ),
              if (hits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final u in hits)
                        ActionChip(
                          key: Key('unit-hit-${u.unit}'),
                          label: Text('${u.unit} · ${u.model}', style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() {
                            _unit.text = u.unit;
                            _unit.selection = TextSelection.collapsed(offset: u.unit.length);
                          }),
                        ),
                    ],
                  ),
                ),
              if (unknown) _note('Belum ada di POP UNIT, isi model unit manual', color: AppColors.amber),
              if (other.isNotEmpty) _note('Unit ini milik section ${sectionLabel(other)}', color: AppColors.danger),
              const SizedBox(height: 14),
              _label('MODEL UNIT'),
              locked
                  ? Container(
                      key: const Key('add-model-locked'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
                      child: Text(hit.model, style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
                    )
                  : TextField(
                      key: const Key('add-model'),
                      controller: _model,
                      inputFormatters: [_Upper()],
                      textCapitalization: TextCapitalization.characters,
                      onChanged: changed,
                      decoration: _box(key.isEmpty ? 'Terisi otomatis dari POP UNIT' : 'Cth: PC210-10M0'),
                    ),
              if (locked) _note('Terisi dari POP UNIT'),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('HM'),
                        TextField(
                          key: const Key('add-hm'),
                          controller: _hm,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: changed,
                          decoration: _box(last ?? 'Cth: 10615'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('DATE'),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: _box(''),
                            child: Row(
                              children: [
                                Expanded(child: Text(sheetDate(_date), style: const TextStyle(fontSize: 14))),
                                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (last != null) _note('HM terakhir di sheet: $last'),
            ]),
            card([
              _label('NAME INSPECTOR'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
                child: Text(inspector, style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
              ),
              const SizedBox(height: 14),
              _label('NAME LEADER'),
              TextField(
                key: const Key('add-leader'),
                controller: _leader,
                inputFormatters: [_Upper()],
                textCapitalization: TextCapitalization.characters,
                onChanged: changed,
                decoration: _box(leaders.isEmpty ? 'Nama group leader' : 'Cth: ${leaders.first}'),
              ),
              if (leaders.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in leaders)
                        ChoiceChip(
                          key: Key('leader-$l'),
                          label: Text(l, style: const TextStyle(fontSize: 12)),
                          selected: _leader.text.trim() == l,
                          onSelected: (_) => setState(() {
                            _leader.text = l;
                            _leader.selection = TextSelection.collapsed(offset: l.length);
                          }),
                        ),
                    ],
                  ),
                ),
            ]),
            for (var i = 0; i < _problems.length; i++)
              card([
                Row(
                  children: [
                    Expanded(child: _label('PROBLEM')),
                    if (_problems.length > 1)
                      GestureDetector(
                        onTap: () => setState(() => _problems.removeAt(i).dispose()),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('Hapus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger)),
                        ),
                      ),
                  ],
                ),
                TextField(
                  key: Key('add-problem-$i'),
                  controller: _problems[i],
                  minLines: 2,
                  maxLines: 4,
                  inputFormatters: [_Upper()],
                  textCapitalization: TextCapitalization.characters,
                  onChanged: changed,
                  decoration: _box('Cth: hose ppc fatigue'),
                ),
              ]),
            OutlinedButton.icon(
              key: const Key('add-more-problem'),
              onPressed: () => setState(() => _problems.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah problem di unit ini'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('add-save'),
                onPressed: ok ? () => _save(data, model) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text('Simpan ${_problems.length} temuan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
