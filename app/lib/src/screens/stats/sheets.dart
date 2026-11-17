/// Bottom sheets opened from the Statistik tabs.
library;

import 'package:flutter/material.dart';

import '../../models.dart';
import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/app_icons.dart';
import '../shell.dart';
import '../viewer_screen.dart';
import 'format.dart';
import 'widgets.dart';

class ManualSheet extends StatelessWidget {
  const ManualSheet({super.key, required this.load, required this.filter, required this.onPerson});

  final Future<ManualStats> load;
  final StatsFilter filter;
  final ValueChanged<String> onPerson;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return LoadingSheet<ManualStats>(
      load: load,
      show: (context, m) {
        final section = store.unitById(m.unit)?.section;
        final chapterTop = m.chapters.fold(1, (a, c) => c.n > a ? c.n : a);
        final file = store.fileByKey(m.file);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                ManualIcon(unit: m.unit, title: m.title, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(
                        [
                          unitName(store, m.unit),
                          section == null ? null : (section == sharedSection ? 'Semua section' : section),
                          filter.periodLabel,
                        ].whereType<String>().join(' · '),
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            StatsTiles([('${m.opens}×', 'Dibuka'), ('${m.people}', 'Orang'), ('${m.downloads}', 'Diunduh')]),
            if (m.chapters.isNotEmpty) ...[
              const StatsCaps('Bab paling sering dilihat'),
              for (final c in m.chapters)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(c.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ),
                          Text('${c.n}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      StatsBar(c.n / chapterTop),
                    ],
                  ),
                ),
            ],
            if (m.readers.isNotEmpty) ...[
              const StatsCaps('Paling sering membuka'),
              for (final r in m.readers)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onPerson(r.nrp),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        InitialsAvatar(r.name, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Text('${r.n}×', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
            ],
            if (file != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  openViewer(context, file);
                },
                child: const Text('Buka manual'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class AnswerSheet extends StatefulWidget {
  const AnswerSheet({super.key, required this.load, required this.onPerson});

  final Future<AnswerStats> load;
  final ValueChanged<String> onPerson;

  @override
  State<AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<AnswerSheet> {
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return LoadingSheet<AnswerStats>(
      load: widget.load,
      show: (context, a) {
        final q = a.question;
        final meta = [
          q.sections.join(', '),
          if (q.unit.isNotEmpty) unitName(store, q.unit),
          whenLabel(q.at),
        ].where((s) => s.isNotEmpty);
        final (IconData icon, Color color, String rated) = switch (a.rating) {
          'good' => (Icons.thumb_up_alt_outlined, AppColors.green, 'Dinilai membantu'),
          'bad' => (Icons.thumb_down_alt_outlined, AppColors.danger, 'Dinilai salah'),
          _ => (Icons.remove_circle_outline, AppColors.faint, 'Belum dinilai'),
        };
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(q.question, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => widget.onPerson(q.nrp),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: q.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy)),
                TextSpan(text: ' · ${meta.join(' · ')}'),
              ]), style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            const StatsCaps('Jawaban nyel AI'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.answer.isEmpty ? '–' : a.answer,
                    maxLines: _full ? null : 5,
                    overflow: _full ? null : TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSoft),
                  ),
                  if (a.sources.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in a.sources)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(AppGlyph.shopManual, size: 14),
                                const SizedBox(width: 4),
                                Text(s, style: TextStyle(fontSize: 11, color: AppColors.navy)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$rated${a.topic.isEmpty ? '' : ' · topik ${a.topic}'}',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            if (!_full && a.answer.length > 200)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _full = true),
                  child: const Text('Lihat jawaban lengkap'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SearchSheet extends StatelessWidget {
  const SearchSheet({super.key, required this.load, required this.onHandled, this.showSection = true});

  final Future<SearchStats> load;
  final Future<void> Function() onHandled;
  final bool showSection;

  @override
  Widget build(BuildContext context) => LoadingSheet<SearchStats>(
        load: load,
        show: (context, s) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(s.query, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('0 hasil di semua manual',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amber)),
            const SizedBox(height: 14),
            StatsTiles([('${s.n}×', 'Dicari'), ('${s.people}', 'Orang')]),
            const StatsCaps('Yang mencari'),
            for (final w in s.who)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    InitialsAvatar(w.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (showSection)
                            Text(w.sections.join(', '), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Text(whenLabel(w.at), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onHandled, child: const Text('Tandai sudah ditangani')),
          ],
        ),
      );
}
