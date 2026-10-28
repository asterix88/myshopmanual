import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../search.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/rise.dart';
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
                    const Text('Cari', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _field,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => _schedule(),
                      onSubmitted: (text) {
                        store.addRecentSearch(text);
                        _run();
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.background,
                        hintText: 'Part number, kode error, komponen',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: AppIcon(AppGlyph.search, size: 20, color: AppColors.muted),
                        ),
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
              SliverToBoxAdapter(child: _start(store))
            else if (result.hits.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(icon: Icons.search_off, title: 'Tidak ada hasil untuk "$_query"'),
              )
            else
              ..._resultSlivers(result),
            // Room to scroll the last results out from under the bottom bar.
            SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }

  /// Before typing: the last searches, one tap to search again.
  Widget _start(AppStore store) {
    final recent = store.recentSearches;
    final files = store.catalog.files.length;
    final onPhone = store.local.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('TERAKHIR DICARI',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.muted)),
            ),
            AppCard(
              child: Column(
                children: [
                  for (final (i, q) in recent.indexed)
                    Rise(
                      key: ValueKey('recent-$q'),
                      delay: Rise.stagger(i),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                _field.text = q;
                                store.addRecentSearch(q);
                                _run();
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                                child: Row(
                                  children: [
                                    AppIcon(AppGlyph.clock, size: 18, color: AppColors.muted),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(q,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Hapus dari riwayat',
                            onPressed: () => store.removeRecentSearch(q),
                            icon: Icon(Icons.close, size: 18, color: AppColors.faint),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                children: [
                  DocTile(AppGlyph.search, size: 56),
                  const SizedBox(height: 12),
                  const Text('Cari di semua manual', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (files > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
              child: Text(
                onPhone > 0 ? '$files manual, $onPhone tersimpan di HP' : '$files manual',
                textAlign: recent.isEmpty ? TextAlign.center : TextAlign.start,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
        ],
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
          final count = result.pageCounts[key] ?? hits.length;
          final first = hits.first;
          // One card per file: it opens at the best hit with the words
          // searched inside, where < | > walks through every hit in the file.
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: InkWell(
                onTap: () {
                  store.addRecentSearch(_query);
                  openViewer(context, file, page: first.page, query: _query);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(
                        children: [
                          DocTile(docGlyph(file), size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(store.unitNameOf(file),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                        color: AppColors.muted)),
                                Text(file.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (first.section != null)
                                  Text(
                                    first.section!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                const SizedBox(height: 2),
                                HighlightedSnippet(first.snippet),
                                const SizedBox(height: 6),
                                Text(
                                  '$count halaman ditemukan',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  }
}
