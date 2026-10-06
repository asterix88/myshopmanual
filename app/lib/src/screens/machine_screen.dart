import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/machine_icon.dart';
import '../widgets/unit_icon.dart';
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
              style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w400),
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
        // The rows share the whole page, so a folder with a few units has no
        // empty space under the list; many units scroll at a minimum height.
        child: LayoutBuilder(
          builder: (context, constraints) {
            const minRowHeight = 76.0;
            final rowHeight = units.isEmpty
                ? minRowHeight
                : (constraints.maxHeight / units.length).clamp(minRowHeight, 140.0).toDouble();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Container(
                  color: AppColors.surface,
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: units.isEmpty
                      ? const EmptyState(icon: Icons.folder_off_outlined, title: 'Belum ada model unit di folder ini')
                      : Column(
                          children: [
                            for (final (i, unit) in units.indexed)
                              UnitRow(unit: unit, store: store, showDivider: i > 0, height: rowHeight),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class UnitRow extends StatelessWidget {
  const UnitRow({
    super.key,
    required this.unit,
    required this.store,
    required this.showDivider,
    this.height = 76,
  });

  final Unit unit;
  final AppStore store;
  final bool showDivider;
  final double height;

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
            if (onPhone > 0) '$onPhone dari ${files.length} file di HP',
          ].join(' · ');
    return Column(
      children: [
        if (showDivider) const Divider(height: 1, indent: 100),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UnitScreen(unitId: unit.id)),
          ),
          child: Container(
            height: showDivider ? height - 1 : height,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                UnitIcon(unitId: unit.id),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUpdate ? AppColors.update : AppColors.muted,
                            fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.faint),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
