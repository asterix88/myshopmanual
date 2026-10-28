import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'service_screen.dart';
import 'specs_screen.dart';

/// Makes the [AppStore] available below it and rebuilds dependents on change.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// Read without subscribing to changes (for event handlers).
  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

/// Bottom navigation: Home, Cari, nyel AI (raised, in the middle), Standar,
/// Servis.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.entrance = false});

  /// Slide Home in (after the opening animation or the introduction).
  final bool entrance;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _aiAsks = 0;
  final _pages = PageController();

  /// A swipe that went past the end of a page's own sub-tabs (Standar,
  /// Servis), carried on by the tab pages.
  Drag? _carried;

  static const chatTab = 2;

  @override
  void dispose() {
    _carried?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _select(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _pages.animateToPage(tab, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  /// Sideways swipes on a page's own tabs move those first; at their first
  /// or last tab the swipe moves on to the next or previous main tab.
  bool _onPageScroll(ScrollNotification n) {
    if (n.depth == 0 || n.metrics.axis != Axis.horizontal || !_pages.hasClients) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      final d = n.dragDetails!;
      _carried ??= _pages.position.drag(
        DragStartDetails(globalPosition: d.globalPosition, localPosition: d.localPosition),
        () => _carried = null,
      );
      _carried?.update(d);
    } else if (n is ScrollEndNotification && _carried != null) {
      _carried?.end(n.dragDetails ?? DragEndDetails(primaryVelocity: 0));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.aiAsks != _aiAsks) {
      // "Tanya nyel AI" on a page: show the chat with the question in it.
      _aiAsks = store.aiAsks;
      _tab = chatTab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(chatTab);
      });
    }
    final pages = [
      HomeScreen(onOpenSearch: () => _select(1), entrance: widget.entrance),
      const SearchScreen(),
      const ChatScreen(),
      const SpecsScreen(),
      const ServiceScreen(),
    ];
    return PopScope(
      // Back on another tab goes to Home first; on Home it closes the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        // Pages run on under the bar, so the space beside the raised nyel AI
        // button shows the page instead of an empty band. They keep their
        // last rows clear of it with MediaQuery's bottom padding.
        extendBody: true,
        // Swipe left or right to move between the tabs; the page follows the
        // finger and the bar's orange line follows the page.
        body: NotificationListener<ScrollNotification>(
          onNotification: _onPageScroll,
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _tab = i),
            children: [
              for (final (i, page) in pages.indexed)
                // Each tab keeps its scroll position and typed search; only
                // the shown one runs its animations.
                _KeepAlive(child: TickerMode(enabled: i == _tab, child: page)),
            ],
          ),
        ),
        bottomNavigationBar: _NavBar(pages: _pages, current: _tab, onSelect: _select),
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.pages, required this.current, required this.onSelect});

  /// The tab pages, followed by the orange line while they slide.
  final PageController pages;
  final int current;
  final ValueChanged<int> onSelect;

  static const _items = [
    (AppGlyph.home, 'Home'),
    (AppGlyph.search, 'Cari'),
    (AppGlyph.nyel, 'nyel AI'),
    (AppGlyph.standar, 'Standar'),
    (AppGlyph.servis, 'Servis'),
  ];

  /// How far the nyel AI button rises above the bar.
  static const _rise = 24.0;
  static const _barHeight = 66.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: _barHeight + _rise + bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barHeight + bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: const [BoxShadow(color: Color(0x1F101828), blurRadius: 16, offset: Offset(0, -2))],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            top: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == current,
                      button: true,
                      label: _items[i].$2,
                      excludeSemantics: true,
                      child: i == _HomeShellState.chatTab
                          ? _AiButton(item: _items[i], active: i == current, onTap: () => onSelect(i))
                          : InkWell(
                              onTap: () => onSelect(i),
                              child: SizedBox(
                                height: _barHeight,
                                child: Center(child: _NavItem(item: _items[i], active: i == current)),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          // An orange line under the current tab's name; it slides along
          // with the pages, mid-swipe too.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 3,
            height: 3,
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, box) => AnimatedBuilder(
                  animation: pages,
                  builder: (context, _) {
                    final page = pages.hasClients && pages.position.haveDimensions
                        ? (pages.page ?? current.toDouble())
                        : current.toDouble();
                    final slot = box.maxWidth / _items.length;
                    return Stack(
                      children: [
                        Positioned(
                          left: (page.clamp(0, _items.length - 1) + 0.5) * slot - 14,
                          width: 28,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.orange,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The raised round nyel AI button in the middle of the bar.
class _AiButton extends StatelessWidget {
  const _AiButton({required this.item, required this.active, required this.onTap});

  final (AppGlyph, String) item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x29101828), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: const Center(child: AppIcon(AppGlyph.nyel, color: Colors.white, size: 28)),
          ),
          const SizedBox(height: 2),
          Text(
            item.$2,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.orangeText,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.active});

  final (AppGlyph, String) item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.navy : AppColors.tabInactive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(item.$1, color: color, size: 22),
          const SizedBox(height: 1),
          Text(
            item.$2,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
