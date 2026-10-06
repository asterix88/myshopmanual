import 'package:flutter/material.dart';

import '../models.dart';
import '../specs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Quick links to a unit's spec pages (bolt torque, refill capacities,
/// standard values and pressures), found in the manuals' own bookmarks.
class SpecsScreen extends StatefulWidget {
  const SpecsScreen({super.key});

  @override
  State<SpecsScreen> createState() => _SpecsScreenState();
}

class _SpecsScreenState extends State<SpecsScreen> {
  String? _unitId;
  List<List<SpecPage>>? _pages;
  bool _loading = false;
  int _session = 0;
  int _indexCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    final units = _unitsWithIndexes();
    if (_unitId == null || !units.any((u) => u.id == _unitId)) {
      final lastUnit = store.lastRead == null ? null : store.fileByKey(store.lastRead!.fileKey)?.unitId;
      final pick = units.where((u) => u.id == lastUnit).firstOrNull ?? units.firstOrNull;
      if (pick != null) _select(pick.id);
    } else {
      // New indexes arrive in the background: refresh once they do.
      final count = store.searchableIndexes().length;
      if (count != _indexCount && !_loading) _select(_unitId!);
    }
  }

  List<Unit> _unitsWithIndexes() {
    final store = StoreScope.read(context);
    return [
      for (final u in store.units)
        if (store.filesOf(u).any((f) => f.searchable)) u,
    ];
  }

  Future<void> _select(String unitId) async {
    final store = StoreScope.read(context);
    final session = ++_session;
    setState(() {
      _unitId = unitId;
      _loading = true;
    });
    _indexCount = store.searchableIndexes().length;
    final indexes = await store.aiIndexes(where: (f) => f.unitId == unitId, fetch: store.online == true);
    final pages = indexes.isEmpty ? <List<SpecPage>>[] : await findSpecPages(indexes);
    if (!mounted || session != _session) return;
    setState(() {
      _pages = indexes.isEmpty ? null : pages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    StoreScope.of(context);
    final units = _unitsWithIndexes();
    final pages = _pages;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spek', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    Text(
                      'Halaman torsi, kapasitas dan nilai standar per unit',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final unit in units)
                          ChoiceChip(
                            label: Text(unit.name),
                            selected: _unitId == unit.id,
                            showCheckmark: false,
                            selectedColor: AppColors.navy,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _unitId == unit.id ? Colors.white : AppColors.inkSoft,
                              fontWeight: _unitId == unit.id ? FontWeight.w600 : FontWeight.w400,
                            ),
                            side: BorderSide(color: _unitId == unit.id ? AppColors.navy : AppColors.border),
                            shape: const StadiumBorder(),
                            onSelected: (_) => _select(unit.id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (units.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.cloud_download_outlined,
                  title: 'Belum ada manual',
                  message: 'Sambungkan ke internet sebentar agar daftar manual dan indeksnya diambil.',
                ),
              )
            else if (_loading && pages == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (pages == null)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Indeks manual unit ini belum ada',
                  message: 'Sambungkan ke internet sebentar: indeksnya diambil otomatis, '
                      'lalu halaman spek bisa dibuka tanpa sinyal.',
                ),
              )
            else
              SliverList.separated(
                itemCount: specSections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.fromLTRB(16, i == 0 ? 16 : 0, 16, 0),
                  child: _SectionCard(section: specSections[i], pages: i < pages.length ? pages[i] : const []),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.pages});

  final SpecSection section;
  final List<SpecPage> pages;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(section.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (pages.isEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                'Tidak ditemukan di bookmark manual unit ini. Coba cari di tab Cari.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
          for (final page in pages) ...[
            const Divider(),
            Builder(builder: (context) {
              final file = store.fileByKey(page.fileKey);
              return InkWell(
                onTap: file == null ? null : () => openViewer(context, file, page: page.page),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(page.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(
                              [
                                ?file?.title,
                                'hlm ${page.page}',
                                if (file != null && !store.isDownloaded(file.key)) 'perlu internet',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.faint),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
