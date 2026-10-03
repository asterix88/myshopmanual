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
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onOpenSearch: () => setState(() => _tab = 1)),
          const SearchScreen(),
          const ChatScreen(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        current: _tab,
        onSelect: (i) => setState(() => _tab = i),
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFE6E8EB))),
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
    final color = active ? AppColors.navy : const Color(0xFF8A9097);
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
