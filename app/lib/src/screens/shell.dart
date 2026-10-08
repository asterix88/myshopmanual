import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
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

/// Bottom navigation: Home, Cari, Nyel AI (raised, in the middle), Spek,
/// Servis.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _aiAsks = 0;

  static const chatTab = 2;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.aiAsks != _aiAsks) {
      // "Tanya Nyel AI" on a page: show the chat with the question in it.
      _aiAsks = store.aiAsks;
      _tab = chatTab;
    }
    return PopScope(
      // Back on another tab goes to Home first; on Home it closes the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (final (i, page) in [
              HomeScreen(onOpenSearch: () => setState(() => _tab = 1)),
              const SearchScreen(),
              const ChatScreen(),
              const SpecsScreen(),
              const ServiceScreen(),
            ].indexed)
              _TabPage(active: i == _tab, child: page),
          ],
        ),
        bottomNavigationBar: _NavBar(
          current: _tab,
          onSelect: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

/// Keeps every tab alive (scroll position, typed search) and cross-fades
/// between them with a short rise, instead of swapping instantly.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: _duration,
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: active ? Offset.zero : const Offset(0, 0.015),
            duration: _duration,
            curve: Curves.easeOutCubic,
            // Only the page's own animations pause; the fade above must keep
            // running, or a tab being left stays drawn over the new one.
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.search, Icons.search, 'Cari'),
    (Icons.auto_awesome, Icons.auto_awesome, 'Nyel AI'),
    (Icons.fact_check_outlined, Icons.fact_check, 'Spek'),
    (Icons.event_note_outlined, Icons.event_note, 'Servis'),
  ];

  /// How far the Nyel AI button rises above the bar.
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
                      label: _items[i].$3,
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
        ],
      ),
    );
  }
}

/// The raised round Nyel AI button in the middle of the bar.
class _AiButton extends StatelessWidget {
  const _AiButton({required this.item, required this.active, required this.onTap});

  final (IconData, IconData, String) item;
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
              boxShadow: const [BoxShadow(color: Color(0x40F08A1C), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 2),
          Text(
            item.$3,
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

  final (IconData, IconData, String) item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.navy : AppColors.tabInactive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.navySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? item.$2 : item.$1, color: color, size: 22),
          const SizedBox(height: 1),
          Text(
            item.$3,
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
