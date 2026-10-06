import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';
import 'viewer_screen.dart';

/// Search across every manual, downloaded or not, using each manual's index.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _field = TextEditingController();
  DocType? _type;
  SearchResult? _result;
  String _query = '';
  Timer? _debounce;
  int _session = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final query = _field.text.trim();
    final session = ++_session;
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _result = null;
      });
      return;
    }
    final indexes = StoreScope.read(context).searchableIndexes(type: _type);
    final result = await searchIndexes(indexes, query);
    if (!mounted || session != _session) return;
    setState(() {
      _query = query;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final result = _result;

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
                    const Text('Cari', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    Text(
                      'Di semua manual, termasuk yang belum diunduh',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _field,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => _schedule(),
                      onSubmitted: (_) => _run(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.background,
                        hintText: 'Contoh: hydraulic oil filter',
                        prefixIcon: Icon(Icons.search, color: AppColors.muted),
                        suffixIcon: _field.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Hapus',
                                onPressed: () {
                                  _field.clear();
                                  _run();
                                },
                                icon: const Icon(Icons.close),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in [null, DocType.shopManual, DocType.omm, DocType.partsbook])
                          ChoiceChip(
                            label: Text(type?.label ?? 'Semua'),
                            selected: _type == type,
                            showCheckmark: false,
                            selectedColor: AppColors.navy,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _type == type ? Colors.white : AppColors.inkSoft,
                              fontWeight: _type == type ? FontWeight.w600 : FontWeight.w400,
                            ),
                            side: BorderSide(color: _type == type ? AppColors.navy : AppColors.border),
                            shape: const StadiumBorder(),
                            onSelected: (_) {
                              setState(() => _type = type);
                              _run();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (store.searchableIndexes().isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.cloud_download_outlined,
                  title: 'Indeks pencarian belum ada',
                  message: 'Sambungkan ke internet sebentar: indeks semua manual diambil otomatis, '
                      'lalu pencarian bisa dipakai tanpa sinyal.',
                ),
              )
            else if (result == null)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.manage_search,
                  title: 'Ketik kata yang dicari',
                  message: 'Hasil muncul dari semua manual, lengkap dengan halamannya. '
                      'Manual yang belum diunduh dibuka lewat internet.',
                ),
              )
            else if (result.hits.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(icon: Icons.search_off, title: 'Tidak ada hasil untuk "$_query"'),
              )
            else
              ..._resultSlivers(result),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _resultSlivers(SearchResult result) {
    final store = StoreScope.read(context);
    // Group hits by file, files ordered by their best hit.
    final groups = <String, List<SearchHit>>{};
    for (final hit in result.hits) {
      groups.putIfAbsent(hit.fileKey, () => []).add(hit);
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            '${result.totalPages} halaman cocok di ${groups.length} file',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
      ),
      SliverList.separated(
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final key = groups.keys.elementAt(i);
          final hits = groups[key]!;
          final file = store.fileByKey(key);
          if (file == null) return const SizedBox.shrink();
          final downloaded = store.isDownloaded(key);
          final count = result.pageCounts[key] ?? hits.length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(file.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(
                                [
                                  store.unitNameOf(file),
                                  '$count halaman',
                                  if (!downloaded) 'belum diunduh, perlu internet',
                                ].join(' · '),
                                style: TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        Pill.docType(file.type),
                      ],
                    ),
                  ),
                  for (final hit in hits.take(5)) ...[
                    const Divider(),
                    InkWell(
                      onTap: () => openViewer(context, file, page: hit.page, query: _query),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    hit.section ?? 'Halaman ${hit.page}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('hlm ${hit.page}',
                                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            HighlightedSnippet(hit.snippet),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (hits.length > 5)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(
                        '+${count - 5} halaman lain. Buka file lalu pakai pencarian di dalamnya.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ];
  }
}
