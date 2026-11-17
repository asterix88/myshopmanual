part of '../viewer_screen.dart';

// Page layout that keeps the page being read in place while page sizes load.

/// pdfrx's default sizing, except that the view is moved only when the page
/// being read actually moved.
///
/// pdfrx learns real page sizes after opening (offline, all pages in the
/// background for a while; online, as pages scroll in) and re-runs the
/// layout each time. By default it then puts the view back on the page being
/// read, which also stops a fling. Most of these updates only change pages
/// below the screen, so they are left alone; when pages above changed size,
/// the page being read is kept where it is on the screen.
class _SteadySizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const _SteadySizeDelegateProvider();

  // Allow twice pdfrx's default zoom so the small print of fold-out
  // drawings still gets sharp.
  static const _legacy = PdfViewerSizeDelegateProviderLegacy(maxScale: 16);

  @override
  PdfViewerSizeDelegate create() => _SteadySizeDelegate(_legacy.create());

  @override
  bool operator ==(Object other) => other is _SteadySizeDelegateProvider;

  @override
  int get hashCode => (_SteadySizeDelegateProvider).hashCode;
}

class _SteadySizeDelegate implements PdfViewerSizeDelegate {
  _SteadySizeDelegate(this._inner);

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
    if (!isViewSizeChanged && !_readPageMoved(oldState.layout, newState.layout, anchorPageNumber)) return;
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

  /// Whether the page being read, or the one above it (whose bottom may be
  /// at the top of the screen), moved or changed size.
  static bool _readPageMoved(PdfPageLayout? oldLayout, PdfPageLayout? newLayout, int? pageNumber) {
    if (oldLayout == null || newLayout == null || pageNumber == null) return true;
    if (pageNumber > oldLayout.pageLayouts.length || pageNumber > newLayout.pageLayouts.length) return true;
    for (var i = math.max(0, pageNumber - 2); i < pageNumber; i++) {
      final before = oldLayout.pageLayouts[i];
      final after = newLayout.pageLayouts[i];
      if ((before.top - after.top).abs() > 0.5 || (before.height - after.height).abs() > 0.5) return true;
    }
    return false;
  }
}
