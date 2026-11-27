part of '../viewer_screen.dart';

/// Find in this manual: running the search, jumping between hits, painting
/// them, and the search bar with its hit counter.
extension _ViewerSearch on _ViewerScreenState {
  void _onSearchChanged() {
    final matches = _searcher?.matches ?? const [];
    if (_fallbackJump && matches.isNotEmpty) {
      _fallbackJump = false;
      _jumpTo(matches.first.pageNumber);
    }
    if (mounted) _update(() {});
  }

  /// Searches when the mechanic presses search on the keyboard (not while
  /// typing). Uses the manual's index: every page at once, also online.
  Future<void> _runSearch(String text, {int? fromPage}) async {
    final query = text.trim();
    final run = ++_searchRun;
    _clearHits();
    if (query.isEmpty) {
      _update(() {});
      return;
    }
    final file = _file!;
    if (!file.searchable) {
      _update(() => _searchStatus = 'teks tidak terbaca');
      return;
    }
    _update(() => _searchStatus = 'mencari…');
    final local = _store.localManual(file.key);
    String? index = local == null ? null : _store.indexPath(local.file);
    if (index == null || !File(index).existsSync()) {
      final got = await _store.aiIndexes(
        where: (f) => f.key == file.key,
        onStatus: (_) {
          if (mounted && run == _searchRun) _update(() => _searchStatus = 'mengambil indeks…');
        },
      );
      index = got[file.key];
    }
    if (!mounted || run != _searchRun) return;
    if (index == null) {
      // No index (offline before it was ever fetched): search the pages
      // the viewer has loaded instead.
      Diagnostics.log('search "$query": no index, searching loaded pages');
      _update(() => _searchStatus = '');
      // Its own going to a match zooms in on the word; only turn pages.
      _fallbackAt = 0;
      _fallbackJump = fromPage == null;
      _searcher?.startTextSearch(query, goToFirstMatch: false, searchImmediately: true);
      return;
    }
    final hits = await searchPagesInIndex(index, query);
    if (!mounted || run != _searchRun) return;
    Diagnostics.log('search "$query": ${hits.length} pages');
    _update(() {
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
    unawaited(_goToHit(at, scroll: fromPage == null || hits.every((h) => h.page != fromPage)));
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
    _update(() => _hitAt = at);
    final (page, _) = _hitPosition(at);
    // Only turn to the page and keep the zoom (Anas: no zooming in on the
    // word); the current match is marked orange on the page.
    if (scroll && page != _page) await _jumpTo(page);
    if (!mounted || run != _searchRun || _hitAt != at) return;
    await _loadPageHits(page);
  }

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
      if (mounted && run == _searchRun) _update(() => _pageHits[pageNumber] = ranges);
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

  void _toggleSearch() {
    _update(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchField.clear();
      _searchRun++;
      _clearHits();
    }
  }

  /// Matches found: by the index, or by pdfrx on loaded pages when there is
  /// no index.
  int get _matchCount => _hits != null ? _hitTotal : _searcher?.matches.length ?? 0;

  int get _matchAt => _hits != null ? _hitAt : _fallbackAt;

  void _stepFallback(int by) {
    final matches = _searcher?.matches ?? const [];
    if (matches.isEmpty) return;
    _update(() => _fallbackAt = (_fallbackAt + by + matches.length) % matches.length);
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
              _update(_clearHits);
            }
          },
          onSubmitted: _runSearch,
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
        color: AppColors.navyFill,
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
}
