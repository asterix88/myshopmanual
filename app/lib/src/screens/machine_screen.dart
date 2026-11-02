import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rise.dart';
import '../widgets/unit_icon.dart';
import 'shell.dart';
import 'unit_screen.dart';

/// One Home folder (EXCAVATOR, BULLDOZER, HD, ...): the unit models inside it.
class MachineScreen extends StatelessWidget {
  const MachineScreen({super.key, required this.machine});

  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = store.homeUnits.where((u) => u.machine == machine).toList();
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
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: units.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [EmptyState(icon: Icons.folder_off_outlined, title: 'Belum ada model unit di folder ini')],
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, unit) in units.indexed) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Rise(delay: Rise.stagger(i, step: 50), child: UnitRow(unit: unit, store: store)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// One unit model as a card: its picture on a grey tile and its name.
class UnitRow extends StatelessWidget {
  const UnitRow({super.key, required this.unit, required this.store});

  final Unit unit;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final keys = {for (final f in store.filesOf(unit)) f.key};
    final hasUpdate = store.unseenUpdates.any((u) => keys.contains(u.file.key));
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UnitScreen(unitId: unit.id)),
      ),
      child: SizedBox(
        height: 96,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              PictureStage(child: UnitIcon(unitId: unit.id, width: 100, height: 56)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unit.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                    if (hasUpdate)
                      Text(
                        'Ada update manual',
                        style: TextStyle(fontSize: 12, color: AppColors.update, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}
