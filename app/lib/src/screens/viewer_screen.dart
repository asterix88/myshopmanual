import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../diagnostics.dart';
import '../models.dart';
import '../page_image.dart';
import '../remote_pdf.dart';
import '../search.dart';
import '../specs.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'chat_screen.dart';
import 'shell.dart';

/// Opens a manual, optionally at [page] and with [query] highlighted. A
/// downloaded manual opens from the phone; any other is read from the server.
/// With [torque] the torque values of a component's remove & install
/// chapter are marked.
Future<void> openViewer(BuildContext context, ManualFile file, {int? page, String? query, TorqueScan? torque}) {
  Diagnostics.log('open ${file.key} p${page ?? 1}');
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ViewerScreen(fileKey: file.key, initialPage: page, initialQuery: query, torque: torque),
  ));
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
  const ViewerScreen({super.key, required this.fileKey, this.initialPage, this.initialQuery, this.torque});

  final String fileKey;
  final int? initialPage;
  final String? initialQuery;

  /// The chapter whose torque values are marked.
  final TorqueScan? torque;

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

  /// Pages matching the search, read from the manual's index, so a manual
  /// read online is searched in full without fetching its pages; null
  /// before a search, or when there is no index (then [_searcher] is used).
  List<PageMatch>? _hits;
  int _hitTotal = 0;

  /// The match shown, counted over the whole manual.
  int _hitAt = 0;
  String _searchStatus = '';
  RegExp? _hitPattern;

  /// Increases with every search, so a slower earlier one is ignored.
  int _searchRun = 0;

  /// Matches drawn on each page, read from the page's text once it loads.
  final Map<int, List<PdfPageTextRange>> _pageHits = {};
  final Set<int> _pageHitsLoading = {};
  PdfDocument? _document;

  /// Torque lines marked on [ViewerScreen.torque], in page order;
  /// null while they are being read.
  List<PdfPageTextRange>? _torque;
  int _torqueAt = -1;
  int _page = 1;
  int _pageCount = 0;
  Timer? _saveTimer;
  late AppStore _store;
  List<TocEntry> _toc = const [];
  /// The bookmarks; null while they are still being read.
  final _outline = ValueNotifier<List<PdfOutlineNode>?>(null);

  /// Chosen once when the screen opens, so a download finishing while
  /// reading does not reload the document.
  ManualFile? _file;
  bool _online = false;
  RemotePdf? _remote;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage ?? 1;
    _resumeServerDrawing = pauseServerDrawing();
    // Known beforehand: no torque value in the chapter, or no text to find
    // one in (a scanned manual). Say so without waiting for the document.
    final marks = widget.torque?.marks;
    if (widget.torque != null && (marks == null || marks.isEmpty)) _torque = const [];
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
    if (_file != null) store.usage.opened(_file!);
    _online = manual == null;
    if (_online) {
      final dir = Directory(store.pdfBlockDir(_file!));
      _remote = RemotePdf(
        size: _file!.pdf.size,
        dir: dir,
        fetch: (start, end) => store.fetchPdfRange(_file!, start, end),
      );
      unawaited(RemotePdf.prune(Directory(store.pdfBlockRoot), maxBytes: 400 << 20, keep: dir)
          .catchError((Object e) => Diagnostics.log('prune pdf pieces: $e')));
    }
    if (manual != null) _toc = loadToc(store.indexPath(manual.file));
  }

  /// Pages for the AI are not drawn from the server while a manual is open
  /// here: they share PDFium's one worker, and this page comes first.
  late void Function() _resumeServerDrawing;

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
    _outline.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final matches = _searcher?.matches ?? const [];
    if (_fallbackJump && matches.isNotEmpty) {
      _fallbackJump = false;
      _jumpTo(matches.first.pageNumber);
    }
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
    _document = document;
    _searcher ??= PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    setState(() => _pageCount = document.pages.length);
    if (_online && _file!.searchable) {
      _loadOnlineToc();
    } else {
      document.loadOutline().then((outline) {
        if (!mounted) return;
        _outline.value = outline;
        setState(() {
          if (_toc.isEmpty) _toc = _tocFromOutline(outline);
        });
      });
    }
    if (widget.torque != null) _markTorque(document);
    final query = _searchField.text.trim();
    if (query.isNotEmpty) {
      // Opened from "Cari": stay on the page from the search result, but
      // highlight every match so next/previous work right away.
      _runSearch(query, fromPage: widget.initialPage);
    }
  }

  /// Searches when the mechanic presses search on the keyboard (not while
  /// typing). Uses the manual's index: every page at once, also online.
  Future<void> _runSearch(String text, {int? fromPage}) async {
    final query = text.trim();
    final run = ++_searchRun;
    _clearHits();
    if (query.isEmpty) {
      setState(() {});
      return;
    }
    final file = _file!;
    if (!file.searchable) {
      setState(() => _searchStatus = 'teks tidak terbaca');
      return;
    }
    setState(() => _searchStatus = 'mencari…');
    final local = _store.localManual(file.key);
    String? index = local == null ? null : _store.indexPath(local.file);
    if (index == null || !File(index).existsSync()) {
      final got = await _store.aiIndexes(
        where: (f) => f.key == file.key,
        onStatus: (_) {
          if (mounted && run == _searchRun) setState(() => _searchStatus = 'mengambil indeks…');
        },
      );
      index = got[file.key];
    }
    if (!mounted || run != _searchRun) return;
    if (index == null) {
      // No index (offline before it was ever fetched): search the pages
      // the viewer has loaded instead.
      Diagnostics.log('search "$query": no index, searching loaded pages');
      setState(() => _searchStatus = '');
      // Its own going to a match zooms in on the word; only turn pages.
      _fallbackAt = 0;
      _fallbackJump = fromPage == null;
      _searcher?.startTextSearch(query, goToFirstMatch: false, searchImmediately: true);
      return;
    }
    final hits = await searchPagesInIndex(index, query);
    if (!mounted || run != _searchRun) return;
    Diagnostics.log('search "$query": ${hits.length} pages');
    setState(() {
      _hits = hits;
      _hitPattern = queryPattern(query);
      _hitTotal = hits.fold(0, (sum, h) => sum + h.count);
      _searchStatus = hits.isEmpty ? 'tidak ada' : '';
    });
    if (hits.isEmpty) return;
    var at = 0;
    if (fromPage != null) {
      // Start at the first match on or after the page opened from "Cari".
      for (final h in hits) {
        if (h.page >= fromPage) break;
        at += h.count;
      }
      if (at >= _hitTotal) at = 0;
    }
    _goToHit(at, scroll: fromPage == null || hits.every((h) => h.page != fromPage));
  }

  void _clearHits() {
    _searcher?.resetTextSearch();
    _fallbackJump = false;
    _hits = null;
    _hitTotal = 0;
    _hitAt = 0;
    _hitPattern = null;
    _searchStatus = '';
    _pageHits.clear();
    _pageHitsLoading.clear();
  }

  /// The page of match [at] and which match on that page it is.
  (int page, int nth) _hitPosition(int at) {
    var left = at;
    for (final h in _hits!) {
      if (left < h.count) return (h.page, left);
      left -= h.count;
    }
    return (_hits!.last.page, 0);
  }

  Future<void> _goToHit(int at, {bool scroll = true}) async {
    final hits = _hits;
    if (hits == null || hits.isEmpty) return;
    final run = _searchRun;
    setState(() => _hitAt = at);
    final (page, _) = _hitPosition(at);
    // Only turn to the page and keep the zoom (Anas: no zooming in on the
    // word); the current match is marked orange on the page.
    if (scroll && page != _page) await _jumpTo(page);
    if (!mounted || run != _searchRun || _hitAt != at) return;
    await _loadPageHits(page);
  }

  /// Online, an animated jump paints every page it passes, and the viewer
  /// fetches each of those from the server before the page asked for. So
  /// jump straight there; offline the short slide is kept.
  Future<void> _jumpTo(int page) =>
      _controller.goToPage(pageNumber: page, duration: _online ? Duration.zero : const Duration(milliseconds: 200));

  void _nextHit() => _goToHit((_hitAt + 1) % _hitTotal);

  void _prevHit() => _goToHit((_hitAt - 1 + _hitTotal) % _hitTotal);

  /// Finds the matches in a page's text so they can be marked. Online the
  /// page is fetched first; that is one page, not the whole manual.
  Future<List<PdfPageTextRange>> _loadPageHits(int pageNumber) async {
    final cached = _pageHits[pageNumber];
    if (cached != null) return cached;
    final document = _document;
    final pattern = _hitPattern;
    if (document == null || pattern == null || pageNumber > document.pages.length) return const [];
    if (!_pageHitsLoading.add(pageNumber)) return const [];
    final run = _searchRun;
    try {
      final watch = Stopwatch()..start();
      bool loaded(int n) => document.pages[n - 1].isLoaded;
      // Load the match's page first: anything else read now would make it
      // wait, since PDFium does one thing at a time.
      if (!loaded(pageNumber)) {
        unawaited(
          document
              .loadPagesProgressively(
                  startPageNumber: pageNumber,
                  onPageLoadProgress: (_, _, _) => mounted && run == _searchRun && !loaded(pageNumber))
              .catchError((Object e) => Diagnostics.log('search load p$pageNumber: $e')),
        );
      }
      final page = await document.pages[pageNumber - 1].waitForLoaded(timeout: const Duration(seconds: 30));
      if (page == null) return const [];
      final text = await page.loadStructuredText();
      final ranges = [
        for (final m in pattern.allMatches(text.fullText))
          PdfPageTextRange(pageText: text, start: m.start, end: m.end),
      ];
      if (_online) Diagnostics.log('search p$pageNumber ready in ${watch.elapsedMilliseconds} ms');
      // Then 4 pages either side of it, outward from it, so scrolling on
      // from the match finds them ready.
      final first = math.max(1, pageNumber - 4);
      final last = math.min(document.pages.length, pageNumber + 4);
      bool waiting() =>
          mounted && run == _searchRun && [for (var n = first; n <= last; n++) n].any((n) => !loaded(n));
      if (waiting()) {
        unawaited(
          document
              .loadPagesProgressively(startPageNumber: pageNumber, onPageLoadProgress: (_, _, _) => waiting())
              .catchError((Object e) => Diagnostics.log('search load around p$pageNumber: $e')),
        );
      }
      if (mounted && run == _searchRun) setState(() => _pageHits[pageNumber] = ranges);
      return ranges;
    } catch (e) {
      Diagnostics.log('search p$pageNumber: $e');
      return const [];
    } finally {
      if (run == _searchRun) _pageHitsLoading.remove(pageNumber);
    }
  }

  void _paintHits(Canvas canvas, Rect pageRect, PdfPage page) {
    final hits = _hits;
    if (hits == null) {
      _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
      return;
    }
    final ranges = _pageHits[page.pageNumber];
    if (ranges == null) {
      // A matching page scrolled into view: read its matches to mark them.
      if (hits.any((h) => h.page == page.pageNumber) && page.isLoaded) {
        scheduleMicrotask(() => _loadPageHits(page.pageNumber));
      }
      return;
    }
    final (currentPage, nth) = _hitPosition(_hitAt);
    for (final (i, range) in ranges.indexed) {
      final rect = range.bounds
          .toRect(page: page, scaledPageSize: pageRect.size)
          .translate(pageRect.left, pageRect.top)
          .inflate(1.5);
      final current = page.pageNumber == currentPage && i == nth;
      canvas.drawRect(
        rect,
        Paint()..color = (current ? const Color(0xFFF08A1C) : const Color(0xFFFFD500)).withAlpha(current ? 140 : 110),
      );
    }
  }

  Future<void> _markTorque(PdfDocument document) async {
    final marks = widget.torque!.marks;
    if (marks == null || marks.isEmpty) return;
    final found = <PdfPageTextRange>[];
    final wanted = [for (final n in marks) if (n <= document.pages.length) n];
    final watch = Stopwatch()..start();
    // Only the pages the pipeline found torque values on, one at a time like
    // a search hit: each is loaded on its own (PDFium does one thing at a
    // time, so loading the pages around it first would make it wait), and
    // the first marks show as soon as their page is in.
    for (final n in wanted) {
      bool loaded() => document.pages[n - 1].isLoaded;
      if (!loaded()) {
        unawaited(
          document
              .loadPagesProgressively(startPageNumber: n, onPageLoadProgress: (_, _, _) => mounted && !loaded())
              .catchError((Object e) => Diagnostics.log('torque load p$n: $e')),
        );
      }
      try {
        // Reading a page before it has loaded returns no text, so wait for it.
        final page = await document.pages[n - 1].waitForLoaded(timeout: const Duration(seconds: 40));
        if (!mounted) return;
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
      if (found.isNotEmpty && _torque == null) {
        // Show the first marks right away and go to them; later pages add more.
        if (_online) Diagnostics.log('torque p$n ready in ${watch.elapsedMilliseconds} ms');
        setState(() => _torque = [...found]);
        _goToTorque(0);
      } else if (found.isNotEmpty) {
        setState(() => _torque = [...found]);
      }
    }
    if (mounted) setState(() => _torque = found);
  }

  void _goToTorque(int at) {
    final torque = _torque;
    if (torque == null || at >= torque.length) return;
    setState(() => _torqueAt = at);
    // Like a search hit: turn to the page and keep the zoom; the current
    // value is marked orange.
    final page = torque[at].pageNumber;
    if (page != _page) _jumpTo(page);
  }

  void _nextTorque() {
    final torque = _torque;
    if (torque == null || torque.isEmpty) return;
    _goToTorque((_torqueAt + 1) % torque.length);
  }

  void _prevTorque() {
    final torque = _torque;
    if (torque == null || torque.isEmpty) return;
    _goToTorque((_torqueAt - 1 + torque.length) % torque.length);
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
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(19)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                // Shrinks a long message to fit instead of cutting it off.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    torque == null
                        ? 'Mencari angka torsi…'
                        : count > 0
                            ? '$count angka torsi ditemukan'
                            : widget.torque!.marks?.isEmpty ?? false
                                ? 'Tidak ada standar torque khusus pada komponen ini'
                                : 'Torsi tidak terbaca, silakan langsung cek dokumen',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ),
              // Which value is marked orange, like the search's 3/18.
              if (count > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '${_torqueAt < 0 ? 1 : _torqueAt + 1}/$count',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Online, reading the PDF's bookmarks makes PDFium fetch every bookmark
  /// from the server one by one, and the pages wait behind it. The manual's
  /// index has the same bookmarks, so take them from there.
  Future<void> _loadOnlineToc() async {
    final file = _file!;
    var toc = const <TocEntry>[];
    try {
      final got = await _store.aiIndexes(where: (f) => f.key == file.key);
      final index = got[file.key];
      if (index != null) toc = await loadTocInBackground(index);
      Diagnostics.log('online toc: ${index == null ? 'no index' : '${toc.length} entries'}');
    } catch (e) {
      Diagnostics.log('online toc: $e');
    }
    if (!mounted) return;
    // Without an index (no signal when it was needed) there are no
    // bookmarks rather than a wait for PDFium to read them over the network.
    _outline.value = outlineFromToc(toc);
    setState(() => _toc = [...toc]..sort((a, b) => a.page.compareTo(b.page)));
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
    _countChapter();
  }

  String? _chapter;

  /// The top-level bookmark of the page the reader stopped on, counted once
  /// per visit for the usage statistics.
  void _countChapter() {
    if (_toc.isEmpty || _file == null) return;
    final top = _toc.map((e) => e.level).reduce((a, b) => a < b ? a : b);
    String? chapter;
    for (final entry in _toc) {
      if (entry.page > _page) break;
      if (entry.level == top) chapter = entry.title;
    }
    if (chapter == null || chapter == _chapter) return;
    _chapter = chapter;
    _store.usage.chapter(_file!, chapter);
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchField.clear();
      _searchRun++;
      _clearHits();
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
              [store.unitNameOf(file), if (file.type != DocType.other) file.type.label, if (_online) 'online'].join(' · '),
              style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cari di file ini',
            onPressed: _toggleSearch,
            icon: _searching ? const Icon(Icons.search_off) : AppIcon(AppGlyph.search, color: AppColors.ink, size: 22),
          ),
          IconButton(
            tooltip: bookmarked ? 'Hapus tanda halaman ini' : 'Tandai halaman ini',
            onPressed: () => store.toggleBookmark(file.key, _page),
            icon: AppIcon(bookmarked ? AppGlyph.bookmarkOn : AppGlyph.bookmark, color: AppColors.ink, accent: AppColors.orange, size: 22),
          ),
          IconButton(
            tooltip: 'Penanda',
            onPressed: () => _showBookmarks(file),
            icon: AppIcon(AppGlyph.contents, color: AppColors.ink, size: 22),
          ),
        ],
        bottom: _searching
            ? _searchBar()
            : widget.torque != null
                ? _torqueBar()
                : null,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _online
                ? PdfViewer.custom(
                    // Fetch only the parts of the PDF being viewed, in small
                    // pieces, so a 350 MB manual opens in seconds.
                    fileSize: file.pdf.size,
                    read: _remote!.read,
                    sourceName: 'remote:${file.key}@${file.pdf.sha256}',
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
          ),
          // On the left: the nyel AI button has the right corner.
          if (_searching && _matchCount > 0)
            Positioned(left: 16, bottom: 24, child: _matchPill())
          else if (!_searching && (_torque?.isNotEmpty ?? false))
            Positioned(left: 16, bottom: 24, child: _matchPill(prev: _prevTorque, next: _nextTorque)),
          Positioned(right: 16, bottom: 16, child: _AiButton(onPressed: () => _askAi(file))),
        ],
      ),
      bottomNavigationBar: _pageCount == 0
          ? null
          : _PageBar(
              page: _page,
              pageCount: _pageCount,
              section: section,
              onJump: _jumpTo,
            ),
    );
  }

  /// Opens nyel AI over the viewer with the page shown now attached, so the
  /// mechanic can ask "terjemahkan halaman ini"; back returns here.
  Future<void> _askAi(ManualFile file) async {
    // The chat covers the viewer, which then draws nothing: the AI may draw
    // pages of online manuals meanwhile.
    _resumeServerDrawing();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(file: file, page: _page)));
    if (mounted) _resumeServerDrawing = pauseServerDrawing();
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
          _paintHits,
          _paintTorque,
        ],
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
            Center(child: ExcavatorLoader(label: _online ? 'Loading material…' : null)),
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

  /// Matches found: by the index, or by pdfrx on loaded pages when there is
  /// no index.
  int get _matchCount => _hits != null ? _hitTotal : _searcher?.matches.length ?? 0;

  int get _matchAt => _hits != null ? _hitAt : _fallbackAt;

  /// The match shown when searching without an index.
  int _fallbackAt = 0;
  bool _fallbackJump = false;

  void _stepFallback(int by) {
    final matches = _searcher?.matches ?? const [];
    if (matches.isEmpty) return;
    setState(() => _fallbackAt = (_fallbackAt + by + matches.length) % matches.length);
    _jumpTo(matches[_fallbackAt].pageNumber);
  }

  PreferredSizeWidget _searchBar() {
    final searcher = _searcher;
    final count = _matchCount;
    final String status;
    if (count > 0) {
      status = '${_matchAt + 1}/$count${_hits == null && (searcher?.isSearching ?? false) ? '+' : ''}';
    } else if (_hits == null && searcher != null && searcher.isSearching) {
      status = 'mencari…';
    } else if (_hits == null && searcher != null && searcher.hasMatches == false && searcher.pattern != null) {
      status = 'tidak ada';
    } else {
      status = _searchStatus;
    }
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextField(
          key: const Key('viewer-search'),
          controller: _searchField,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          // Searching starts on the keyboard's search key, not while typing.
          onChanged: (text) {
            if (text.trim().isEmpty && (_hits != null || _searchStatus.isNotEmpty || _searcher?.pattern != null)) {
              _searchRun++;
              setState(_clearHits);
            }
          },
          onSubmitted: (text) => _runSearch(text),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.field,
            hintText: 'Ketik lalu tekan cari',
            prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
            suffixText: status,
            suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  /// Previous / next match, a dark pill at the bottom right like Xodo's.
  /// The Xodo-style < | > buttons: search matches, or with [prev] and
  /// [next] the torque values.
  Widget _matchPill({VoidCallback? prev, VoidCallback? next}) {
    final indexed = _hits != null;
    Widget half(IconData icon, String tooltip, VoidCallback onTap, BorderRadius radius) => Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(width: 56, height: 52, child: Icon(icon, color: Colors.white, size: 26)),
            ),
          ),
        );
    return Container(
      key: const Key('match-pill'),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x40101828), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          half(Icons.chevron_left, 'Hasil sebelumnya', prev ?? (indexed ? _prevHit : () => _stepFallback(-1)),
              const BorderRadius.horizontal(left: Radius.circular(26))),
          Container(width: 1, height: 52, color: const Color(0x55FFFFFF)),
          half(Icons.chevron_right, 'Hasil berikutnya', next ?? (indexed ? _nextHit : () => _stepFallback(1)),
              const BorderRadius.horizontal(right: Radius.circular(26))),
        ],
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
            _jumpTo(dest.pageNumber);
          } else if (dest != null) {
            _controller.goToDest(dest);
          } else if (page != null) {
            _jumpTo(page);
          }
        },
      ),
    );
  }
}

/// The section being read and a page number box: type a page and press
/// enter to go there.
/// The round nyel AI button over the page: the sparkle only, like the one
/// in the middle of the tab bar.
class _AiButton extends StatelessWidget {
  const _AiButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tanya nyel AI tentang halaman ini',
      child: Material(
        key: const Key('viewer-ai'),
        color: AppColors.orange,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x66101828),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Center(child: AppIcon(AppGlyph.nyel, color: Colors.white, size: 28)),
          ),
        ),
      ),
    );
  }
}

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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
              Text(' / ${widget.pageCount}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Penanda', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
