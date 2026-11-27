/// Statistik tab Manual: which manuals are opened most.
library;

import 'package:flutter/material.dart';

import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import 'format.dart';
import 'widgets.dart';

class ManualTab extends StatelessWidget {
  const ManualTab({super.key, required this.data, required this.onManual});

  final StatsOverview data;
  final ValueChanged<String> onManual;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final top = data.manuals.fold(1, (a, m) => m.n > a ? m.n : a);
    final unitTop = data.units.fold(1, (a, u) => u.n > a ? u.n : a);
    return ListView(
      padding: statsListPadding,
      children: [
        const StatsCaps('Paling sering dibuka'),
        if (data.manuals.isEmpty)
          const NoneYet('Belum ada manual dibuka')
        else
          CardRows([
            for (final m in data.manuals)
              InkWell(
                onTap: () => onManual(m.file),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      ManualIcon(unit: m.unit, title: m.title),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(m.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Text('${m.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            StatsBar(m.n / top),
                            const SizedBox(height: 5),
                            Text(
                              '${unitLine(store, m.unit, shared: m.shared)} · ${m.people} orang',
                              style: TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ]),
        if (data.units.isNotEmpty) ...[
          const StatsCaps('Per unit'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              children: [
                for (final u in data.units)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(unitName(store, u.unit),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        Expanded(child: StatsBar(u.n / unitTop)),
                        SizedBox(
                          width: 40,
                          child: Text('${u.n}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
