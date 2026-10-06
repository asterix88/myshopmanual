import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';

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

/// Bottom navigation: Unit, Cari, Tanya AI.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          for (final (i, page) in [
            HomeScreen(onOpenSearch: () => setState(() => _tab = 1)),
            const SearchScreen(),
            const ChatScreen(),
          ].indexed)
            _TabPage(active: i == _tab, child: page),
        ],
      ),
      bottomNavigationBar: _NavBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
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
    (Icons.folder_outlined, Icons.folder, 'Unit'),
    (Icons.search, Icons.search, 'Cari'),
    (Icons.chat_bubble_outline, Icons.chat_bubble, 'Tanya AI'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == current,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: Center(child: _NavItem(item: _items[i], active: i == current)),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
