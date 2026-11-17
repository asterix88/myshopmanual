/// Full pages opened from Statistik: one person, and the inactive list.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shell.dart';
import 'ai_tab.dart';
import 'format.dart';
import 'widgets.dart';

class PersonPage extends StatelessWidget {
  const PersonPage({super.key, required this.api, required this.filter, required this.nrp, required this.onQuestion});

  final StatsApi api;
  final StatsFilter filter;
  final String nrp;
  final ValueChanged<int> onQuestion;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengguna'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      body: LoadingSheet<PersonStats>(
        load: api.person(filter, nrp),
        show: (context, p) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      InitialsAvatar(p.name.isEmpty ? nrp : p.name, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name.isEmpty ? nrp : p.name,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            Text('${p.nrp} · ${p.sections.join(', ')}',
                                style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text('Terakhir aktif ${whenLabel(p.last)}',
                                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                VersionTag(p.app.isEmpty ? 'app lama' : 'App ${p.app}', warn: p.app.isEmpty),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  StatsTiles([
                    ('${p.manualsOpened}', 'Manual dibuka'),
                    ('${p.ai}', 'Tanya nyel AI'),
                    ('${p.searches}', 'Pencarian'),
                  ]),
                ],
              ),
            ),
            const StatsCaps('Manual yang dibuka'),
            if (p.manuals.isEmpty)
              const NoneYet('Belum membuka manual.')
            else
              CardRows([
                for (final m in p.manuals)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        ManualIcon(unit: m.unit, title: m.title, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(unitLine(store, m.unit), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        Text('${m.n}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ]),
            const StatsCaps('Pertanyaan terakhir'),
            if (p.questions.isEmpty)
              const NoneYet('Belum bertanya ke nyel AI.')
            else
              CardRows([
                for (final q in p.questions) QuestionTile(q, showName: false, onTap: () => onQuestion(q.id)),
              ]),
          ],
        ),
      ),
    );
  }
}

class InactivePage extends StatelessWidget {
  const InactivePage({super.key, required this.people, required this.sections, this.title = 'belum aktif'});

  final List<InactiveRow> people;
  final List<String> sections;
  final String title;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<InactiveRow>>{};
    for (final p in people) {
      groups.putIfAbsent(p.sections.firstOrNull ?? defaultSection, () => []).add(p);
    }
    final order = [
      ...sections.where(groups.containsKey),
      ...groups.keys.where((s) => !sections.contains(s)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${people.length} $title'),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
        actions: [
          IconButton(
            tooltip: 'Salin daftar',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inactiveText(people, order, groups)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daftar disalin')));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: statsListPadding,
        children: [
          for (final section in order) ...[
            StatsCaps('$section · ${groups[section]!.length}'),
            CardRows([
              for (final p in groups[section]!)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Row(
                    children: [
                      InitialsAvatar(p.name, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(p.nrp, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p.never || p.last == null ? 'Belum pernah login' : 'Terakhir ${daysAgo(p.last)}',
                            style: TextStyle(fontSize: 11, color: p.never ? AppColors.amber : AppColors.muted),
                          ),
                          if (p.oldApp && !p.never) ...[
                            const SizedBox(height: 3),
                            const VersionTag('app lama', warn: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
