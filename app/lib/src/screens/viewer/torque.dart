part of '../viewer_screen.dart';

/// Yellow torque marks: finding torque lines on the opened chapter, painting
/// them, and the 'N angka torsi ditandai' bar.
extension _ViewerTorque on _ViewerScreenState {
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
        _update(() => _torque = [...found]);
        _goToTorque(0);
      } else if (found.isNotEmpty) {
        _update(() => _torque = [...found]);
      }
    }
    if (mounted) _update(() => _torque = found);
  }

  void _goToTorque(int at) {
    final torque = _torque;
    if (torque == null || at >= torque.length) return;
    _update(() => _torqueAt = at);
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
                                : 'Torsi tidak terbaca, cek dokumen',
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
}
