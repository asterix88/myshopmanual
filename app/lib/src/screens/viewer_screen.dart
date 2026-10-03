import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../search.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Opens a downloaded manual, optionally at [page] and with [query] highlighted.
Future<void> openViewer(BuildContext context, ManualFile file, {int? page, String? query}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ViewerScreen(fileKey: file.key, initialPage: page, initialQuery: query),
  ));
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.fileKey, this.initialPage, this.initialQuery});

  final String fileKey;
  final int? initialPage;
  final String? initialQuery;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  bool _searching = false;
  int _page = 1;
  int _pageCount = 0;
  List<TocEntry> _toc = const [];
  List<PdfOutlineNode> _outline = const [];

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage ?? 1;
    final query = widget.initialQuery?.trim();
    if (query != null && query.isNotEmpty) {
      _searching = true;
      _searchField.text = query;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_toc.isEmpty) {
      final manual = StoreScope.read(context).localManual(widget.fileKey);
      if (manual != null) _toc = loadToc(StoreScope.read(context).indexPath(manual.file));
    }
  }

  @override
  void dispose() {
    _searcher.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  String? _sectionFor(int page) {
    String? best;
    for (final entry in _toc) {
      if (entry.page > page) break;
      best = entry.title;
    }
    return best;
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    setState(() => _pageCount = document.pages.length);
    document.loadOutline().then((outline) {
      if (mounted) setState(() => _outline = outline);
    });
    final query = _searchField.text.trim();
    if (query.isNotEmpty) {
      // Opened from "Cari": stay on the page from the search result, but
      // highlight every match so next/previous work right away.
      _searcher.startTextSearch(query, goToFirstMatch: widget.initialPage == null, searchImmediately: true);
    }
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() => _page = page);
    StoreScope.read(context).setLastRead(widget.fileKey, page, section: _sectionFor(page));
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchField.clear();
      _searcher.resetTextSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final manual = store.localManual(widget.fileKey);
    if (manual == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.picture_as_pdf_outlined, title: 'File ini belum ada di HP'),
      );
    }
    final file = manual.file;
    final bookmarked = store.isBookmarked(file.key, _page);
    final section = _sectionFor(_page);

    return Scaffold(
      backgroundColor: const Color(0xFFE4E6EA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            Text(
              '${manual.unitName} · ${file.type.label}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cari di file ini',
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.search_off : Icons.search),
          ),
          IconButton(
            tooltip: bookmarked ? 'Hapus tanda halaman ini' : 'Tandai halaman ini',
            onPressed: () => store.toggleBookmark(file.key, _page),
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: bookmarked ? AppColors.orange : null),
          ),
          IconButton(
            tooltip: 'Penanda',
            onPressed: () => _showBookmarks(file),
            icon: const Icon(Icons.toc),
          ),
        ],
        bottom: _searching ? _searchBar() : null,
      ),
      body: PdfViewer.file(
        store.pdfPath(file),
        controller: _controller,
        initialPageNumber: widget.initialPage ?? 1,
        params: PdfViewerParams(
          backgroundColor: const Color(0xFFE4E6EA),
          margin: 8,
          onViewerReady: _onViewerReady,
          onPageChanged: _onPageChanged,
          pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
              const Center(child: CircularProgressIndicator()),
        ),
      ),
      bottomNavigationBar: _pageCount == 0
          ? null
          : _PageBar(
              page: _page,
              pageCount: _pageCount,
              section: section,
              onJump: (page) => _controller.goToPage(pageNumber: page),
            ),
    );
  }

  PreferredSizeWidget _searchBar() {
    final matches = _searcher.matches.length;
    final current = _searcher.currentIndex;
    final status = _searcher.isSearching
        ? (matches == 0 ? 'mencari…' : '${(current ?? 0) + 1}/$matches+')
        : _searchField.text.trim().isEmpty
            ? ''
            : matches == 0
                ? 'tidak ada'
                : '${(current ?? 0) + 1}/$matches';
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchField,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onChanged: (text) => _searcher.startTextSearch(text.trim()),
                onSubmitted: (text) => _searcher.startTextSearch(text.trim(), searchImmediately: true),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF4F5F7),
                  hintText: 'Cari kata di file ini',
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.muted),
                  suffixText: status,
                  suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Hasil sebelumnya',
              onPressed: matches == 0 ? null : _searcher.goToPrevMatch,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Hasil berikutnya',
              onPressed: matches == 0 ? null : _searcher.goToNextMatch,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookmarks(ManualFile file) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      builder: (sheetContext) => _BookmarksSheet(
        fileKey: file.key,
        outline: _outline,
        currentPage: _page,
        sectionFor: _sectionFor,
        onGo: (dest, page) {
          Navigator.pop(sheetContext);
          if (dest != null) {
            _controller.goToDest(dest);
          } else if (page != null) {
            _controller.goToPage(pageNumber: page);
          }
        },
      ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({required this.page, required this.pageCount, required this.section, required this.onJump});

  final int page;
  final int pageCount;
  final String? section;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      section ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  InkWell(
                    onTap: () => _askPage(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text('$page / $pageCount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: page.clamp(1, pageCount).toDouble(),
                  min: 1,
                  max: pageCount.toDouble(),
                  activeColor: AppColors.navy,
                  inactiveColor: AppColors.divider,
                  onChanged: (v) => onJump(v.round()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _askPage(BuildContext context) async {
    final controller = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ke halaman'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – $pageCount'),
          onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Buka'),
          ),
        ],
      ),
    );
    if (page != null) onJump(page.clamp(1, pageCount));
  }
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.fileKey,
    required this.outline,
    required this.currentPage,
    required this.sectionFor,
    required this.onGo,
  });

  final String fileKey;
  final List<PdfOutlineNode> outline;
  final int currentPage;
  final String? Function(int page) sectionFor;
  final void Function(PdfDest? dest, int? page) onGo;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  int _tab = 0;
  final Set<PdfOutlineNode> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mine = store.bookmarks[widget.fileKey] ?? const <int>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Penanda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('Daftar isi bawaan dari file PDF', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: 0, label: Text('Dari file')),
                ButtonSegment(value: 1, label: Text('Tanda saya (${mine.length})')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _tab == 0 ? _outlineList(scrollController) : _myList(scrollController, mine),
          ),
        ],
      ),
    );
  }

  Widget _outlineList(ScrollController scrollController) {
    if (widget.outline.isEmpty) {
      return const EmptyState(icon: Icons.toc, title: 'File ini tidak punya daftar isi bawaan');
    }
    final rows = <(PdfOutlineNode, int)>[];
    void walk(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        rows.add((node, depth));
        if (_expanded.contains(node)) walk(node.children, depth + 1);
      }
    }

    walk(widget.outline, 0);
    final currentSection = widget.sectionFor(widget.currentPage);
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final (node, depth) = rows[i];
        final isCurrent = node.title.trim() == currentSection && node.dest?.pageNumber != null &&
            node.dest!.pageNumber <= widget.currentPage;
        return Material(
          color: isCurrent ? AppColors.navySoft : AppColors.surface,
          child: InkWell(
            onTap: () => widget.onGo(node.dest, null),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: EdgeInsets.only(left: 8.0 + depth * 18, right: 4),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        node.title.trim(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: depth == 0 || isCurrent ? FontWeight.w600 : FontWeight.w400,
                          color: isCurrent ? AppColors.navyDark : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                  if (node.dest != null)
                    Text('${node.dest!.pageNumber}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (node.children.isNotEmpty)
                    IconButton(
                      tooltip: _expanded.contains(node) ? 'Tutup' : 'Buka',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        if (!_expanded.remove(node)) _expanded.add(node);
                      }),
                      icon: Icon(_expanded.contains(node) ? Icons.expand_less : Icons.expand_more, size: 20),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _myList(ScrollController scrollController, List<int> pages) {
    if (pages.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_border,
        title: 'Belum ada tanda',
        message: 'Ketuk ikon pita di atas untuk menandai halaman yang sering dibuka.',
      );
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        for (final page in pages)
          AppCard(
            onTap: () => widget.onGo(null, page),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.bookmark, color: AppColors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.sectionFor(page) ?? 'Halaman $page',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                Text('hlm $page', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
      ].expand((w) => [w, const SizedBox(height: 8)]).toList(),
    );
  }
}
