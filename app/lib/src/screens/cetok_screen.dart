/// The Cetok Online screen: navy header with the Stok / Ambil / Transfer /
/// Input switch. Each tab lives in its own file under `cetok/`:
///
/// - `stock_tab.dart`    Stok: search, unit chips, location filter, list
/// - `part_sheet.dart`   a part's details with Ambil / Transfer / Partsbook
/// - `take_form.dart`    Ambil
/// - `move_form.dart`    Transfer
/// - `add_form.dart`     Input
/// - `form_widgets.dart` pieces the three forms share
/// - `widgets.dart`      pieces every tab shares (chip, search box, PartCard)
/// - `style.dart`        motion, colours, text-field look, small helpers
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cetok.dart';
import '../theme.dart';
import 'cetok/add_form.dart';
import 'cetok/move_form.dart';
import 'cetok/part_sheet.dart';
import 'cetok/stock_tab.dart';
import 'cetok/style.dart';
import 'cetok/take_form.dart';
import 'cetok/unavailable.dart';
import 'shell.dart';

/// Opens Cetok Online of the section in use; with [search] the search box
/// gets the keyboard. A section without its own Cetok yet gets
/// "Fitur sedang dalam tahap pengembangan".
Future<void> openCetok(BuildContext context, {bool search = false}) {
  final store = StoreScope.read(context);
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => store.cetokSite == null
          ? CetokUnavailableScreen(section: store.cetokSection)
          : CetokScreen(focusSearch: search),
    ),
  );
}

/// Cetok Online inside MyManual: Stok (look up and open a part), Ambil,
/// Transfer and Input, using the same database functions as the website.
class CetokScreen extends StatefulWidget {
  const CetokScreen({super.key, this.focusSearch = false});

  final bool focusSearch;

  @override
  State<CetokScreen> createState() => _CetokScreenState();
}

class _CetokScreenState extends State<CetokScreen> {
  int _tab = 0;
  int _spins = 0;

  /// The part picked in Ambil and Transfer; a part's details fill them in.
  final _takePart = ValueNotifier<CetokPart?>(null);
  final _movePart = ValueNotifier<CetokPart?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).cetok.open();
    });
  }

  @override
  void dispose() {
    _takePart.dispose();
    _movePart.dispose();
    super.dispose();
  }

  void _go(int tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
  }

  void _openPart(CetokPart part) => showPartSheet(
        context,
        part,
        onTake: (p) {
          _takePart.value = p;
          _go(1);
        },
        onMove: (p) {
          _movePart.value = p;
          _go(2);
        },
      );

  @override
  Widget build(BuildContext context) {
    final cetok = StoreScope.of(context).cetok;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListenableBuilder(
        listenable: cetok,
        // The tabs are made here so each change of the stock rebuilds them.
        builder: (context, _) => Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _Header(
                cetok: cetok,
                tab: _tab,
                onTab: _go,
                spins: _spins,
                onRefresh: () {
                  setState(() => _spins++);
                  cetok.refresh();
                },
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _TabEntrance(
                      active: _tab == 0,
                      child: StockTab(cetok: cetok, focusSearch: widget.focusSearch, onOpen: _openPart),
                    ),
                    _TabEntrance(active: _tab == 1, child: TakeForm(cetok: cetok, choice: _takePart)),
                    _TabEntrance(active: _tab == 2, child: MoveForm(cetok: cetok, choice: _movePart)),
                    _TabEntrance(active: _tab == 3, child: AddForm(cetok: cetok)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.cetok,
    required this.tab,
    required this.onTab,
    required this.spins,
    required this.onRefresh,
  });

  final Cetok cetok;
  final int tab;
  final ValueChanged<int> onTab;
  final int spins;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 6, 8, 16),
      decoration: const BoxDecoration(
        color: cetokNavy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Kembali',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cetok Online',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                    Text(
                      cetok.loading
                          ? 'Memperbarui stok…'
                          : cetok.updated == null
                              ? 'Stok part gudang'
                              : 'Diperbarui ${stockTime(cetok.updated!)}',
                      style: const TextStyle(fontSize: 12, color: cetokNavySoft),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Perbarui stok',
                onPressed: cetok.loading ? null : onRefresh,
                icon: AnimatedRotation(
                  turns: spins.toDouble(),
                  duration: const Duration(milliseconds: 600),
                  curve: cetokCurve,
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _Segments(index: tab, onTap: onTab),
          ),
        ],
      ),
    );
  }
}

/// Stok / Ambil / Transfer / Input, with a white pill that slides to the
/// chosen one.
class _Segments extends StatelessWidget {
  const _Segments({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.inventory_2_outlined, 'Stok'),
    (Icons.outbox_outlined, 'Ambil'),
    (Icons.swap_horiz, 'Transfer'),
    (Icons.add_box_outlined, 'Input'),
  ];
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - _gap * (_items.length - 1)) / _items.length;
          return SizedBox(
            height: 44,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: cetokMotion,
                  curve: cetokCurve,
                  left: index * (w + _gap),
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox(
                        width: w,
                        child: _Segment(
                          key: Key('cetok-tab-$i'),
                          icon: _items[i].$1,
                          label: _items[i].$2,
                          selected: i == index,
                          onTap: () => onTap(i),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: selected ? cetokNavy : cetokNavySoft),
          duration: cetokMotion,
          builder: (context, color, _) => Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays a short slide-in each time its tab is opened.
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: cetokMotion, value: 1);
  late final _a = CurvedAnimation(parent: _c, curve: cetokCurve);

  @override
  void didUpdateWidget(_TabEntrance old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(_a),
          child: widget.child,
        ),
      );
}
