import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../diagnostics.dart';
import '../models.dart';
import '../page_image.dart';
import '../search.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Opens a manual, optionally at [page] and with [query] highlighted. A
/// downloaded manual opens from the phone; any other is read from the server.
/// With [torquePages] (first, last) the torque values on those pages are
/// marked, as on a component's remove & install chapter.
Future<void> openViewer(BuildContext context, ManualFile file, {int? page, String? query, (int, int)? torquePages}) {
  Diagnostics.log('open ${file.key} p${page ?? 1}');
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ViewerScreen(fileKey: file.key, initialPage: page, initialQuery: query, torquePages: torquePages),
  ));
}

/// A torque value as manuals print it: "824 – 1,030 Nm {84 – 105 kgm}",
/// "98 N·m", "70 lb ft".
final torqueValue = RegExp(
  r'\d[\d.,]*\s*(?:[-–~]\s*\d[\d.,]*\s*)?(?:N\s*[·.•]?\s*m|kgf?\s*[·.•]?\s*m|lbf?\s*[·.•]?\s*ft)(?![a-z])',
  caseSensitive: false,
);

/// A line with only a bare range like "5 to 50 Nm": a torque wrench in the
/// tools table, not a tightening torque.
final _toolRange = RegExp(r'^[\d.,]+\s*(?:to|[-–~])\s*[\d.,]+\s*N\s*[·.•]?\s*m$', caseSensitive: false);

/// The lines of [text] holding a torque value, as (start, end) indexes;
/// each line once, a very long line only around the value.
List<(int, int)> torqueLines(String text) {
  final found = <(int, int)>[];
  for (final m in torqueValue.allMatches(text)) {
    var start = text.lastIndexOf('\n', m.start) + 1;
    var end = text.indexOf('\n', m.end);
    if (end < 0) end = text.length;
    if (end - start > 160) (start, end) = (m.start, m.end);
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    if (found.isNotEmpty && found.last.$2 >= start) continue;
    if (_toolRange.hasMatch(text.substring(start, end))) continue;
    found.add((start, end));
  }
  return found;
}

/// A handle on the right edge that shows the page number; dragging it
/// scrolls through the whole document fast.
Widget pageScrollThumb(PdfViewerController controller) => PdfViewerScrollThumb(
      controller: controller,
      orientation: ScrollbarOrientation.right,
      thumbSize: const Size(46, 30),
      margin: 0,
      thumbBuilder: (context, size, page, controller) => Container(
        key: const Key('page-thumb'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
          boxShadow: const [BoxShadow(color: Color(0x33101828), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Text(
          page == null ? '' : '$page',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.fileKey, this.initialPage, this.initialQuery, this.torquePages});

  final String fileKey;
  final int? initialPage;
  final String? initialQuery;

  /// Pages (first, last) whose torque values are marked.
  final (int, int)? torquePages;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  /// pdfrx only allows a searcher once the document is loaded, so it is
  /// created in [_onViewerReady].
  PdfTextSearcher? _searcher;
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  bool _searching = false;

  /// Torque lines marked on [ViewerScreen.torquePages], in page order;
  /// null while they are being read.
  List<PdfPageTextRange>? _torque;
  int _torqueAt = -1;
  int _page = 1;
  int _pageCount = 0;
  Timer? _saveTimer;
  late AppStore _store;
  List<TocEntry> _toc = const [];
  List<PdfOutlineNode> _outline = const [];

  /// Chosen once when the screen opens, so a download finishing while
  /// reading does not reload the document.
  ManualFile? _file;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage ?? 1;
    _resumeServerDrawing = pauseServerDrawing();
    final query = widget.initialQuery?.trim();
    if (query != null && query.isNotEmpty) {
      _searching = true;
      _searchField.text = query;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = StoreScope.read(context);
    if (_file != null) return;
    final store = _store;
    final manual = store.localManual(widget.fileKey);
    _file = manual?.file ?? store.catalog.file(widget.fileKey);
    _online = manual == null;
    if (manual != null) _toc = loadToc(store.indexPath(manual.file));
  }

  /// Pages for the AI are not drawn from the server while a manual is open
  /// here: they share PDFium's one worker, and this page comes first.
  late final void Function() _resumeServerDrawing;

  @override
  void dispose() {
    _resumeServerDrawing();
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveLastRead();
    }
    _searcher?.dispose();
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
    Diagnostics.log('viewer ready, ${document.pages.length} pages');
    _searcher ??= PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    setState(() => _pageCount = document.pages.length);
    document.loadOutline().then((outline) {
      if (!mounted) return;
      setState(() {
        _outline = outline;
        // Read online there is no search index, so name sections from the
        // PDF's own bookmarks instead.
        if (_toc.isEmpty) _toc = _tocFromOutline(outline);
      });
    });
    if (widget.torquePages != null) _markTorque(document);
    final query = _searchField.text.trim();
    if (query.isNotEmpty) {
      // Opened from "Cari": stay on the page from the search result, but
      // highlight every match so next/previous work right away.
      _searcher!.startTextSearch(query, goToFirstMatch: widget.initialPage == null, searchImmediately: true);
    }
  }

  Future<void> _markTorque(PdfDocument document) async {
    final (first, last) = widget.torquePages!;
    final found = <PdfPageTextRange>[];
    for (var n = first; n <= last && n <= document.pages.length; n++) {
      try {
        // An online manual loads its pages progressively; reading a page
        // before it has loaded returns no text, so wait for it.
        final page = await document.pages[n - 1].waitForLoaded(timeout: const Duration(seconds: 40));
        if (page == null) {
          Diagnostics.log('torque p$n: not loaded');
          continue;
        }
        final text = await page.loadStructuredText();
        for (final (start, end) in torqueLines(text.fullText)) {
          found.add(PdfPageTextRange(pageText: text, start: start, end: end));
        }
      } catch (e) {
        Diagnostics.log('torque p$n: $e');
      }
      if (!mounted) return;
    }
    setState(() => _torque = found);
  }

  void _nextTorque() {
    final torque = _torque;
    if (torque == null || torque.isEmpty) return;
    setState(() => _torqueAt = (_torqueAt + 1) % torque.length);
    final range = torque[_torqueAt];
    _controller.goToRectInsidePage(pageNumber: range.pageNumber, rect: range.bounds, anchor: PdfPageAnchor.center);
  }

  void _paintTorque(Canvas canvas, Rect pageRect, PdfPage page) {
    final torque = _torque;
    if (torque == null) return;
    for (final (i, range) in torque.indexed) {
      if (range.pageNumber != page.pageNumber) continue;
      final rect = range.bounds
          .toRect(page: page, scaledPageSize: pageRect.size)
          .translate(pageRect.left, pageRect.top)
          .inflate(1.5);
      canvas.drawRect(
        rect,
        Paint()..color = (i == _torqueAt ? const Color(0xFFF08A1C) : const Color(0xFFFFD500)).withAlpha(110),
      );
    }
  }

  PreferredSizeWidget _torqueBar() {
    final torque = _torque;
    final count = torque?.length ?? 0;
    return PreferredSize(
      preferredSize: const Size.fromHeight(46),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          height: 38,
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(19)),
          child: Row(
            children: [
              if (torque != null && count > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFFD500), borderRadius: BorderRadius.circular(8)),
                  child: Text('$count',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B2333))),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  torque == null
                      ? 'Mencari angka torsi…'
                      : count == 0
                          ? 'Angka torsi tidak ditemukan di bagian ini'
                          : 'angka torsi ditandai',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ),
              if (count > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  onPressed: _nextTorque,
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('berikutnya'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static List<TocEntry> _tocFromOutline(List<PdfOutlineNode> outline) {
    final entries = <TocEntry>[];
    void walk(List<PdfOutlineNode> nodes, int level) {
      for (final node in nodes) {
        final page = node.dest?.pageNumber;
        if (page != null) entries.add((level: level, title: node.title.trim(), page: page));
        walk(node.children, level + 1);
      }
    }

    walk(outline, 1);
    // Sections are looked up in page order.
    entries.sort((a, b) => a.page.compareTo(b.page));
    return entries;
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() => _page = page);
    // Saving notifies every screen in the stack, so wait until scrolling
    // settles instead of saving on each page that flies past.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveLastRead);
  }

  void _saveLastRead() {
    _saveTimer = null;
    _store.setLastRead(widget.fileKey, _page, section: _sectionFor(_page));
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchField.clear();
      _searcher?.resetTextSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final file = _file;
    if (file == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.picture_as_pdf_outlined, title: 'File ini tidak ditemukan'),
      );
    }
    final bookmarked = store.isBookmarked(file.key, _page);
    final section = _sectionFor(_page);

    return Scaffold(
      backgroundColor: AppColors.viewerBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            Text(
              [store.unitNameOf(file), file.type.label, if (_online) 'online'].join(' · '),
              style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
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
        bottom: _searching
            ? _searchBar()
            : widget.torquePages != null
                ? _torqueBar()
                : null,
      ),
      body: _online
          ? PdfViewer.uri(
              store.pdfUri(file),
              // Fetch only the parts of the PDF being viewed, so a 130 MB
              // manual opens in seconds instead of downloading in full.
              preferRangeAccess: true,
              timeout: const Duration(seconds: 30),
              controller: _controller,
              initialPageNumber: widget.initialPage ?? 1,
              params: _viewerParams,
            )
          : PdfViewer.file(
              store.pdfPath(file),
              controller: _controller,
              initialPageNumber: widget.initialPage ?? 1,
              params: _viewerParams,
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

  /// Built once: the viewer re-lays out whenever its params change.
  late final PdfViewerParams _viewerParams = PdfViewerParams(
        backgroundColor: AppColors.viewerBackground,
        margin: 8,
        layoutPages: _fixedSlotLayout,
        sizeDelegateProvider: const _FixedSlotSizeDelegateProvider(),
        // Read online, measuring all pages up front would fetch most of the
        // file before the first page shows, so measure pages as they scroll in.
        behaviorControlParams: PdfViewerBehaviorControlParams(loadPageDimensionsOnDemand: _online),
        onViewerReady: _onViewerReady,
        onPageChanged: _onPageChanged,
        viewerOverlayBuilder: (context, size, handleLinkTap) => [pageScrollThumb(_controller)],
        pagePaintCallbacks: [
          (canvas, pageRect, page) => _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page),
          _paintTorque,
        ],
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_online) ...[
                const SizedBox(height: 14),
                Text('Membuka dari server…', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ],
          ),
        ),
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          Diagnostics.log('viewer error: $error');
          return EmptyState(
          icon: _online ? Icons.cloud_off : Icons.error_outline,
          title: _online ? 'Gagal membuka file secara online' : 'File tidak bisa dibuka',
          message: _online
              ? 'Periksa sinyal, atau unduh file ini supaya bisa dibuka tanpa internet.'
              : 'Coba hapus lalu unduh ulang file ini.',
          );
        },
      );

  /// Every page gets a slot of the same size (A4 portrait at a fixed width)
  /// and is fitted inside it, centered. Page positions then never depend on
  /// page sizes, which pdfrx only learns page by page after opening (and,
  /// online, only as pages scroll in). So nothing shifts or shrinks while
  /// scrolling, and a bookmark lands on the page it names.
  static PdfPageLayout _fixedSlotLayout(List<PdfPage> pages, PdfViewerParams params) {
    const slotWidth = 600.0;
    const slotHeight = slotWidth * 1.4142;
    final margin = params.margin;
    final rects = <Rect>[];
    var y = margin;
    for (final page in pages) {
      final scale = page.width > 0 && page.height > 0
          ? math.min(slotWidth / page.width, slotHeight / page.height)
          : 1.0;
      final width = page.width > 0 ? page.width * scale : slotWidth;
      final height = page.height > 0 ? page.height * scale : slotHeight;
      rects.add(Rect.fromLTWH(margin + (slotWidth - width) / 2, y + (slotHeight - height) / 2, width, height));
      y += slotHeight + margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(slotWidth + margin * 2, y));
  }

  PreferredSizeWidget _searchBar() {
    final searcher = _searcher;
    final matches = searcher?.matches.length ?? 0;
    final current = searcher?.currentIndex;
    final String status;
    if (searcher == null || _searchField.text.trim().isEmpty) {
      status = '';
    } else if (searcher.isSearching) {
      status = matches == 0 ? 'mencari…' : '${(current ?? 0) + 1}/$matches+';
    } else {
      status = matches == 0 ? 'tidak ada' : '${(current ?? 0) + 1}/$matches';
    }
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
                onChanged: (text) => _searcher?.startTextSearch(text.trim()),
                onSubmitted: (text) => _searcher?.startTextSearch(text.trim(), searchImmediately: true),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.field,
                  // Online, only pages already shown have been measured and can be searched.
                  hintText: _online ? 'Cari di halaman yang sudah dimuat' : 'Cari kata di file ini',
                  prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
                  suffixText: status,
                  suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Hasil sebelumnya',
              onPressed: matches == 0 ? null : searcher!.goToPrevMatch,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Hasil berikutnya',
              onPressed: matches == 0 ? null : searcher!.goToNextMatch,
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
          if (dest != null && _online) {
            // Online, the page may not be measured yet, so a position inside
            // it would be off; open the page from its top instead.
            _controller.goToPage(pageNumber: dest.pageNumber);
          } else if (dest != null) {
            _controller.goToDest(dest);
          } else if (page != null) {
            _controller.goToPage(pageNumber: page);
          }
        },
      ),
    );
  }
}

/// The section being read and a page number box: type a page and press
/// enter to go there.
class _PageBar extends StatefulWidget {
  const _PageBar({required this.page, required this.pageCount, required this.section, required this.onJump});

  final int page;
  final int pageCount;
  final String? section;
  final ValueChanged<int> onJump;

  @override
  State<_PageBar> createState() => _PageBarState();
}

class _PageBarState extends State<_PageBar> {
  late final _field = TextEditingController(text: '${widget.page}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Leaving the box without pressing enter shows the current page again.
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _field.selection = TextSelection(baseOffset: 0, extentOffset: _field.text.length);
      } else {
        _field.text = '${widget.page}';
      }
    });
  }

  @override
  void didUpdateWidget(_PageBar old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.page != widget.page) _field.text = '${widget.page}';
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String text) {
    final page = int.tryParse(text.trim());
    _focus.unfocus();
    if (page == null) return;
    widget.onJump(page.clamp(1, widget.pageCount));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.section ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              const SizedBox(width: 10),
              Text('Hlm', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(width: 6),
              SizedBox(
                width: 64,
                child: TextField(
                  key: const Key('page-input'),
                  controller: _field,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: _go,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.field,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Text(' / ${widget.pageCount}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
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
          Padding(
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

/// pdfrx's default sizing, except when only page sizes change.
///
/// pdfrx learns real page sizes after opening (offline, all pages in the
/// background for a while; online, as pages scroll in). Each time it re-runs
/// the layout and, by default, moves the view to "keep" the old position,
/// which cancels a bookmark jump still under way and lands somewhere else.
/// With [_ViewerScreenState._fixedSlotLayout] every page keeps its slot, so the
/// current position is already right and the view is left alone.
class _FixedSlotSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const _FixedSlotSizeDelegateProvider();

  // A fold-out page is drawn at about half its size to fit its slot, so
  // allow twice pdfrx's default zoom to keep its diagrams just as sharp.
  static const _legacy = PdfViewerSizeDelegateProviderLegacy(maxScale: 16);

  @override
  PdfViewerSizeDelegate create() => _FixedSlotSizeDelegate(_legacy.create());

  @override
  bool operator ==(Object other) => other is _FixedSlotSizeDelegateProvider;

  @override
  int get hashCode => (_FixedSlotSizeDelegateProvider).hashCode;
}

class _FixedSlotSizeDelegate implements PdfViewerSizeDelegate {
  _FixedSlotSizeDelegate(this._inner);

  final PdfViewerSizeDelegate _inner;

  @override
  void init(PdfViewerController controller) => _inner.init(controller);

  @override
  void dispose() => _inner.dispose();

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) => _inner.calculateMetrics(
    viewSize: viewSize,
    layout: layout,
    pageNumber: pageNumber,
    pageMargin: pageMargin,
    boundaryMargin: boundaryMargin,
  );

  @override
  double get onePassRenderingScaleThreshold => _inner.onePassRenderingScaleThreshold;

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) => _inner.onLayoutInitialized(
    state: state,
    initialPageNumber: initialPageNumber,
    coverScale: coverScale,
    alternativeFitScale: alternativeFitScale,
    layout: layout,
    document: document,
  );

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    if (!isViewSizeChanged) return;
    _inner.onLayoutUpdate(
      oldState: oldState,
      newState: newState,
      currentZoom: currentZoom,
      oldVisibleRect: oldVisibleRect,
      anchorPageNumber: anchorPageNumber,
      isLayoutChanged: isLayoutChanged,
      isViewSizeChanged: isViewSizeChanged,
    );
  }
}
