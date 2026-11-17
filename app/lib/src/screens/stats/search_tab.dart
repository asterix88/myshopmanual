/// Statistik tab Cari: what the mechanics search for.
library;

import 'package:flutter/material.dart';

import '../../stats.dart';
import '../../theme.dart';
import 'widgets.dart';

class SearchTab extends StatelessWidget {
  const SearchTab({super.key, required this.data, required this.onMissing});

  final StatsOverview data;
  final ValueChanged<String> onMissing;

  @override
  Widget build(BuildContext context) {
    final top = data.searches.fold(1, (a, s) => s.n > a ? s.n : a);
    return ListView(
      padding: statsListPadding,
      children: [
        const StatsCaps('Paling dicari'),
        if (data.searches.isEmpty)
          const NoneYet('Belum ada pencarian.')
        else
          CardRows([
            for (final s in data.searches)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text('${s.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    StatsBar(s.n / top),
                  ],
                ),
              ),
          ]),
        StatsCaps('Tidak ketemu', trailing: Text('0 hasil', style: TextStyle(fontSize: 11, color: AppColors.muted))),
        if (data.missing.isEmpty)
          const NoneYet('Semua pencarian ketemu di manual.')
        else
          CardRows([
            for (final s in data.missing)
              InkWell(
                onTap: () => onMissing(s.query),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text('${s.n}× · ${s.people} orang', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
          ]),
      ],
    );
  }
}
