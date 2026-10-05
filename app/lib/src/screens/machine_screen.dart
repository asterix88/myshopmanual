import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/machine_icon.dart';
import 'shell.dart';
import 'unit_screen.dart';

/// One machine folder (EXCAVATOR, BULLDOZER): the unit models inside it.
class MachineScreen extends StatelessWidget {
  const MachineScreen({super.key, required this.machine});

  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = store.units.where((u) => u.machine == machine).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(machine.label),
            Text(
              '${units.length} model unit',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MachineIcon(machine, width: 54),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.only(top: 10, bottom: 24),
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: units.isEmpty
                  ? const EmptyState(icon: Icons.folder_off_outlined, title: 'Belum ada model unit di folder ini')
                  : Column(
                      children: [
                        for (final (i, unit) in units.indexed)
                          UnitRow(unit: unit, store: store, showDivider: i > 0),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnitRow extends StatelessWidget {
  const UnitRow({super.key, required this.unit, required this.store, required this.showDivider});

  final Unit unit;
  final AppStore store;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final files = store.filesOf(unit);
    final onPhone = files.where((f) => store.isDownloaded(f.key)).length;
    final keys = {for (final f in files) f.key};
    final hasUpdate = store.unseenUpdates.any((u) => keys.contains(u.file.key));
    final subtitle = hasUpdate
        ? 'Ada update manual'
        : [
            if (unit.kind.isNotEmpty) unit.kind,
            onPhone == 0 ? 'belum ada file di HP' : '$onPhone dari ${files.length} file di HP',
          ].join(' · ');
    return Column(
      children: [
        if (showDivider) const Divider(indent: 72),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UnitScreen(unitId: unit.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(
                    _shortCode(unit),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.orangeText),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUpdate ? const Color(0xFFC2410C) : AppColors.muted,
                          fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF9AA0A6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _shortCode(Unit unit) {
    final code = unit.id.split(RegExp(r'[-_ ]')).first.toUpperCase();
    return code.length > 5 ? code.substring(0, 5) : code;
  }
}
