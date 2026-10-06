import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'unit_tabs.dart';

/// The Servis tab: the unit's maintenance schedule, one tab per interval
/// (HM 250, HM 500, ...) listing the service items under it, with the
/// schedule chart on top. Pages open from the unit's spek.pdf.
class ServiceScreen extends StatelessWidget {
  const ServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final units = [
      for (final u in store.units)
        if (u.spec != null || store.filesOf(u).isNotEmpty) u,
    ];
    final unit = UnitTabsPage.current(store, units);
    final service = unit?.spec?.service ?? const <ServicePage>[];
    final hours = {for (final e in service) if (e.hours > 0) e.hours}.toList()..sort();
    PageRow row(ServicePage e) => (
          title: e.title,
          file: store.fileByKey('${unit!.id}/${e.fileId}'),
          page: e.page,
          at: e.at,
          heading: !e.item && e.hours > 0,
        );
    final charts = [for (final e in service) if (e.hours == 0) row(e)];
    return UnitTabsPage(
      units: units,
      unit: unit,
      tabs: [for (final h in hours) (null, 'HM $h')],
      views: [
        for (final h in hours)
          PageRowList(
            rows: [...charts, for (final e in service) if (e.hours == h) row(e)],
            onOpen: (r) => openPageRow(context, unit!, r),
          ),
      ],
      empty: const EmptyState(
        icon: Icons.event_note_outlined,
        title: 'Jadwal servis unit ini belum ada',
        message: 'Muncul setelah manual unit ini diperbarui di server.',
      ),
    );
  }
}
