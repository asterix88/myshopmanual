/// Statistik tab Pengguna: who uses the app and who does not yet.
library;

import 'package:flutter/material.dart';

import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'format.dart';
import 'widgets.dart';

class PeopleTab extends StatelessWidget {
  const PeopleTab({super.key, required this.data, required this.onPerson, required this.onInactive, this.showSection = true});

  final StatsOverview data;
  final ValueChanged<String> onPerson;
  final VoidCallback onInactive;
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: statsListPadding,
      children: [
        const StatsCaps('Aktif per section'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            children: [
              for (final s in data.perSection)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(s.section, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      if (s.hasManual) ...[
                        Expanded(child: StatsBar(s.total == 0 ? 0 : s.active / s.total)),
                        SizedBox(
                          width: 52,
                          child: Text('${s.active}/${s.total}',
                              textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                        ),
                      ] else
                        Expanded(
                          child: Text('belum ada manual',
                              textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        StatsCaps(
          'Paling aktif',
          trailing: data.inactive.isEmpty
              ? null
              : InkWell(
                  onTap: onInactive,
                  child: Text(
                    '${data.inactive.length} belum aktif',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ),
        ),
        if (data.people.isEmpty)
          const NoneYet('Belum ada yang memakai aplikasi.')
        else
          CardRows([
            for (final p in data.people)
              InkWell(
                onTap: () => onPerson(p.nrp),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      InitialsAvatar(p.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(showSection ? '${p.nrp} · ${p.sections.join(', ')}' : p.nrp,
                                style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${p.manuals} manual · ${p.ai} AI', style: const TextStyle(fontSize: 12)),
                          Text(whenLabel(p.last), style: TextStyle(fontSize: 11, color: AppColors.faint)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}
