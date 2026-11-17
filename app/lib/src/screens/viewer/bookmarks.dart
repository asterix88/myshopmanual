part of '../viewer_screen.dart';

// The bookmarks sheet (the PDF's own bookmarks plus the user's pages).

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.fileKey,
    required this.outline,
    required this.currentPage,
    required this.sectionFor,
    required this.onGo,
  });

  final String fileKey;
  final ValueListenable<List<PdfOutlineNode>?> outline;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Penanda', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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

  Widget _outlineList(ScrollController scrollController) => ValueListenableBuilder(
        valueListenable: widget.outline,
        builder: (context, outline, _) => outline == null
            ? const Center(child: ExcavatorLoader(label: 'Memuat daftar isi…'))
            : _outlineRows(outline, scrollController),
      );

  Widget _outlineRows(List<PdfOutlineNode> outline, ScrollController scrollController) {
    if (outline.isEmpty) {
      return const EmptyState(icon: Icons.toc, title: 'File ini tidak punya daftar isi bawaan');
    }
    final rows = <(PdfOutlineNode, int)>[];
    void walk(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        rows.add((node, depth));
        if (_expanded.contains(node)) walk(node.children, depth + 1);
      }
    }

    walk(outline, 0);
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
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
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
                    Text('${node.dest!.pageNumber}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                Icon(Icons.bookmark, color: AppColors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.sectionFor(page) ?? 'Halaman $page',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                Text('hlm $page', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
      ].expand((w) => [w, const SizedBox(height: 8)]).toList(),
    );
  }
}

/// The index's bookmark rows as a tree: an entry's children are the deeper
/// entries that follow it.
/// The index's bookmark rows as a tree: an entry's children are the deeper
/// entries that follow it.
List<PdfOutlineNode> outlineFromToc(List<TocEntry> toc) {
  List<PdfOutlineNode> level(int from, int end) {
    final nodes = <PdfOutlineNode>[];
    var i = from;
    while (i < end) {
      var next = i + 1;
      while (next < end && toc[next].level > toc[i].level) {
        next++;
      }
      nodes.add(PdfOutlineNode(
        title: toc[i].title,
        dest: PdfDest(toc[i].page, PdfDestCommand.fit, null),
        children: level(i + 1, next),
      ));
      i = next;
    }
    return nodes;
  }

  return level(0, toc.length);
}
