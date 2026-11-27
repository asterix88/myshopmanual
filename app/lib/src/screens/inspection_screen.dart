/// Daily Inspection Monitoring. This file holds the screen itself (loading,
/// filters, the list layout); its pieces are part files under `inspection/`:
///
/// - `header.dart`         navy header, section tabs, model filter button
/// - `finding_list.dart`   unit cards, finding rows, status/age, model sheet
/// - `finding_sheet.dart`  one finding's detail sheet (fill Action to close)
/// - `add_screen.dart`     "+ Temuan": adding new findings
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../inspection.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'shell.dart';

part 'inspection/add_screen.dart';
part 'inspection/finding_list.dart';
part 'inspection/finding_sheet.dart';
part 'inspection/header.dart';

Future<void> openInspection(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InspectionScreen()));

/// The navy of the header, the same in light and dark mode (as on Home).
const _headerNavy = AppColors.header;
const _headerSoft = AppColors.headerMuted;

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
    final status = result.action.isEmpty ? 'OPEN' : 'CLOSED';
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
          message: all.isEmpty ? 'Tambahkan dengan tombol + Temuan' : 'Coba kata lain atau hapus filter model',
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
          // One frame per unit: all its findings together.
          for (final u in _byUnit(g.value))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _UnitCard(unit: u.key, rows: u.value, today: today, flash: _flash, onTap: (r) => _openRow(data, r)),
            ),
        ],
      ],
    );
  }
}
