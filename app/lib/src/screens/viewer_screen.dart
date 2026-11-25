/// The PDF viewer. This file holds the screen itself: opening the manual
/// (downloaded or online), the app bar, page changes, last-read and the
/// bookmarks button. The rest is split into `viewer/` (part files, so they
/// share the screen's private state):
///
/// - `search.dart`     find in this manual, hit highlighting, search bar
/// - `torque.dart`     yellow torque marks and their bar
/// - `page_bar.dart`   page number box and the Nyel AI button
/// - `bookmarks.dart`  the bookmarks sheet
/// - `layout.dart`     page layout that keeps the reading position steady
library;

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
import '../page_sizes.dart';
import '../remote_pdf.dart';
import '../search.dart';
import '../specs.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import 'chat_screen.dart';
import 'quiz_admin_screen.dart';
import 'shell.dart';

part 'viewer/bookmarks.dart';
part 'viewer/layout.dart';
part 'viewer/page_bar.dart';
part 'viewer/search.dart';
part 'viewer/torque.dart';

/// Opens a manual, optionally at [page] and with [query] highlighted. A
/// downloaded manual opens from the phone; any other is read from the server.
/// With [torque] the torque values of a component's remove & install
/// chapter are marked.
Future<void> openViewer(BuildContext context, ManualFile file, {int? page, String? query, TorqueScan? torque}) {
  Diagnostics.log('open ${file.key} p${page ?? 1}');
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ViewerScreen(fileKey: file.key, initialPage: page, initialQuery: query, torque: torque),
    ),
  );
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
      unawaited(
        RemotePdf.prune(
          Directory(store.pdfBlockRoot),
          maxBytes: 400 << 20,
          keep: dir,
        ).catchError((Object e) => Diagnostics.log('prune pdf pieces: $e')),
      );
    }
    if (manual != null) _toc = loadToc(store.indexPath(manual.file));
    if (_file != null) {
      final index = store.readyIndexPath(_file!);
      _knownSizes =
          (index == null ? null : PageSizes.fromIndex(index)) ?? PageSizes.fromFile(store.pageSizeCachePath(_file!));
      Diagnostics.log('page sizes: ${_knownSizes == null ? 'unknown' : '${_knownSizes!.sizes.length} known'}');
    }
  }

  /// The pages' sizes before PDFium has measured them; null when neither the
  /// index nor an earlier visit has them. See [PageSizes].
  PageSizes? _knownSizes;

  /// Keeps the sizes PDFium measured, for a manual whose index has none, so
  /// the next opening lays the pages out right from the start.
  void _savePageSizes() {
    final document = _document;
    final file = _file;
    if (document == null || file == null || (_knownSizes?.isComplete ?? false)) return;
    PageSizes.save(_store.pageSizeCachePath(file), [
      for (final page in document.pages)
        page.isLoaded && page.width > 0 && page.height > 0 ? Size(page.width, page.height) : null,
    ]);
  }

  /// Pages for the AI are not drawn from the server while a manual is open
  /// here: they share PDFium's one worker, and this page comes first.
  late void Function() _resumeServerDrawing;

  /// [setState] for the search and torque parts under viewer/ (extensions
  /// may not call it directly: it is protected).
  void _update(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    if (_fullScreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _savePageSizes();
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
    // pdfrx opens a page lower than the screen (landscape) centered.
    final initialPage = widget.initialPage ?? 1;
    if (initialPage > 1) _jumpTo(initialPage);
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

  /// Jumps straight to the page, without a slide. Online, an animated jump
  /// paints every page it passes, and the viewer fetches each of those from
  /// the server before the page asked for. And while page sizes are still
  /// being learned, a slide under way would be cut short where it was.
  /// The page's top goes to the top of the screen; pdfrx would center a page
  /// lower than the screen, such as a landscape page, between its neighbours.
  Future<void> _jumpTo(int page) =>
      _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.topCenter, duration: Duration.zero);

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

    final full = _fullScreen;
    return PopScope(
      // Back first leaves full screen, like Xodo.
      canPop: !full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setFullScreen(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.viewerBackground,
        appBar: full
            ? null
            : AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                    Text(
                      [
                        store.unitNameOf(file),
                        if (file.type != DocType.other) file.type.label,
                        if (_online) 'online',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
                actions: [
                  if (store.session?.managesQuiz ?? false)
                    IconButton(
                      tooltip: 'Buat soal quiz dari halaman ini',
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => QuizGenerateSheet(file: file, page: _page),
                      ),
                      icon: AppIcon(AppGlyph.quiz, color: AppColors.ink, size: 22),
                    ),
                  IconButton(
                    tooltip: 'Cari di file ini',
                    onPressed: _toggleSearch,
                    icon: _searching
                        ? const Icon(Icons.search_off)
                        : AppIcon(AppGlyph.search, color: AppColors.ink, size: 22),
                  ),
                  IconButton(
                    tooltip: bookmarked ? 'Hapus tanda halaman ini' : 'Tandai halaman ini',
                    onPressed: () => store.toggleBookmark(file.key, _page),
                    icon: AppIcon(
                      bookmarked ? AppGlyph.bookmarkOn : AppGlyph.bookmark,
                      color: AppColors.ink,
                      accent: AppColors.orange,
                      size: 22,
                    ),
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
            // On the left: the Nyel AI button has the right corner.
            if (full)
              // Full screen keeps only the Nyel AI button.
              const Positioned(left: 0, top: 0, child: SizedBox.shrink())
            else if (_searching && _matchCount > 0)
              Positioned(left: 16, bottom: 24, child: _matchPill())
            else if (!_searching && (_torque?.isNotEmpty ?? false))
              Positioned(
                left: 16,
                bottom: 24,
                child: _matchPill(prev: _prevTorque, next: _nextTorque),
              ),
            Positioned(right: 16, bottom: 16, child: _AiButton(onPressed: () => _askAi(file))),
          ],
        ),
        bottomNavigationBar: _pageCount == 0 || full
            ? null
            : _PageBar(page: _page, pageCount: _pageCount, section: section, onJump: _jumpTo),
      ),
    );
  }

  /// Full screen: a tap on the page hides the bars (also Android's status
  /// and navigation bars), leaving only the pages and the Nyel AI button;
  /// another tap, or back, brings them back. Like Xodo.
  bool _fullScreen = false;

  void _setFullScreen(bool on) {
    if (on == _fullScreen || !mounted) return;
    setState(() => _fullScreen = on);
    SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  bool _onTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails details) {
    // While typing a search the tap only closes the keyboard.
    if (details.type == PdfViewerGeneralTapType.tap && !_searchFocus.hasFocus) _setFullScreen(!_fullScreen);
    return false;
  }

  /// Opens Nyel AI over the viewer with the page shown now attached, so the
  /// mechanic can ask "terjemahkan halaman ini"; back returns here.
  Future<void> _askAi(ManualFile file) async {
    // The chat covers the viewer, which then draws nothing: the AI may draw
    // pages of online manuals meanwhile.
    _resumeServerDrawing();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(file: file, page: _page),
      ),
    );
    if (mounted) _resumeServerDrawing = pauseServerDrawing();
  }

  /// Built once: the viewer re-lays out whenever its params change.
  late final PdfViewerParams _viewerParams = PdfViewerParams(
    backgroundColor: AppColors.viewerBackground,
    margin: 8,
    layoutPages: _fitWidthLayout,
    sizeDelegateProvider: const _SteadySizeDelegateProvider(),
    // Read online, measuring all pages up front would fetch most of the
    // file before the first page shows, so measure pages as they scroll in.
    behaviorControlParams: PdfViewerBehaviorControlParams(loadPageDimensionsOnDemand: _online),
    onViewerReady: _onViewerReady,
    onPageChanged: _onPageChanged,
    viewerOverlayBuilder: (context, size, handleLinkTap) => [if (!_fullScreen) pageScrollThumb(_controller)],
    onGeneralTap: _onTap,
    pagePaintCallbacks: [_paintHits, _paintTorque],
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

  /// Pages one under the other, each as wide as the column with its own
  /// height, like Xodo: a landscape page takes only its own (low) height, so
  /// several of them fit on the screen.
  ///
  /// Sizes known beforehand ([_knownSizes]) come first: then the layout is
  /// final from the start and nothing moves while PDFium measures the pages.
  /// Otherwise a page not measured yet keeps the estimate pdfrx gives it
  /// (the size of page 1).
  PdfPageLayout _fitWidthLayout(List<PdfPage> pages, PdfViewerParams params) {
    const width = 600.0;
    final margin = params.margin;
    final known = _knownSizes;
    final rects = <Rect>[];
    var y = margin;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final size = known?[i] ?? (page.width > 0 && page.height > 0 ? Size(page.width, page.height) : null);
      final height = size != null ? width * size.height / size.width : width * 1.4142;
      rects.add(Rect.fromLTWH(margin, y, width, height));
      y += height + margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(width + margin * 2, y));
  }

  /// The match shown when searching without an index.
  int _fallbackAt = 0;
  bool _fallbackJump = false;

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
            _controller.goToDest(dest, duration: Duration.zero);
          } else if (page != null) {
            _jumpTo(page);
          }
        },
      ),
    );
  }
}
