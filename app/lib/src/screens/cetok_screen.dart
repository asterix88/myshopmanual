import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cetok.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/excavator_loader.dart';
import '../widgets/rise.dart';
import 'partsbook_search_screen.dart';
import 'shell.dart';

/// Opens Cetok Online; with [search] the search box gets the keyboard.
Future<void> openCetok(BuildContext context, {bool search = false}) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CetokScreen(focusSearch: search)),
    );

/// How long the screen's moves take, and their easing.
const _motion = Duration(milliseconds: 300);
const _curve = Curves.easeOutCubic;

/// The navy of the header, the same in light and dark mode (as on Home).
const _headerNavy = Color(0xFF1E3A64);
const _headerSoft = Color(0xFFC9D3E3);

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
                      child: _StockTab(cetok: cetok, focusSearch: widget.focusSearch, onOpen: _openPart),
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
        color: _headerNavy,
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                    Text(
                      cetok.loading
                          ? 'Memperbarui stok…'
                          : cetok.updated == null
                              ? 'Stok part gudang'
                              : 'Diperbarui ${_time(cetok.updated!)}',
                      style: const TextStyle(fontSize: 11.5, color: _headerSoft),
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
                  curve: _curve,
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
                  duration: _motion,
                  curve: _curve,
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
          tween: ColorTween(end: selected ? _headerNavy : _headerSoft),
          duration: _motion,
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
                    Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
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
  late final _c = AnimationController(vsync: this, duration: _motion, value: 1);
  late final _a = CurvedAnimation(parent: _c, curve: _curve);

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

/// Shrinks a little while pressed.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child});

  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      );
}

String _time(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
  return '${t.day}/${t.month} $hm';
}

// ---------------------------------------------------------------------------
// Stok

/// The stock list: search, unit chips and a location filter.
class _StockTab extends StatefulWidget {
  const _StockTab({required this.cetok, required this.focusSearch, required this.onOpen});

  final Cetok cetok;
  final bool focusSearch;
  final ValueChanged<CetokPart> onOpen;

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  final _query = TextEditingController();
  String? _unit;
  String? _location;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _inUnit(CetokPart p) => _unit == null || p.unit == _unit;

  List<CetokPart> get _rows => [
        for (final p in widget.cetok.parts)
          if (_inUnit(p) &&
              p.matches(_query.text) &&
              (_location == null || p.loc.toLowerCase() == _location!.toLowerCase()))
            p,
      ];

  Future<void> _pickLocation() async {
    final counts = <String, (String, int)>{};
    var total = 0;
    for (final p in widget.cetok.parts) {
      if (!_inUnit(p)) continue;
      total++;
      if (p.loc.isEmpty) continue;
      final key = p.loc.toLowerCase();
      final (name, n) = counts[key] ?? (p.loc, 0);
      counts[key] = (name, n + 1);
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _LocationSheet(
        total: total,
        counts: [for (final c in counts.values) c]..sort((a, b) => a.$1.compareTo(b.$1)),
        current: _location,
      ),
    );
    if (picked != null && mounted) setState(() => _location = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final rows = _rows;
    final query = _query.text.trim();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: _SearchBox(
            controller: _query,
            autofocus: widget.focusSearch,
            hint: 'Cari part number atau nama part',
            onChanged: () => setState(() {}),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final unit in [null, ...cetok.units])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: unit ?? 'Semua',
                    selected: _unit == unit,
                    onTap: () => setState(() => _unit = unit),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text('${rows.length} part', style: TextStyle(fontSize: 12, color: AppColors.muted))),
              Flexible(
                flex: 3,
                child: _LocationButton(
                  label: _location ?? 'Semua lokasi',
                  active: _location != null,
                  onTap: _pickLocation,
                ),
              ),
              AnimatedSize(
                duration: _motion,
                curve: _curve,
                child: _location == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _RoundButton(
                          tooltip: 'Hapus filter lokasi',
                          icon: Icons.close,
                          onTap: () => setState(() => _location = null),
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (cetok.error != null)
          _Notice(
            text: cetok.parts.isEmpty
                ? cetok.error!
                : '${cetok.error!} Yang tampil stok terakhir${cetok.updated == null ? '' : ' (${_time(cetok.updated!)})'}.',
            onRetry: cetok.refresh,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: cetok.refresh,
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      if (cetok.parts.isEmpty && cetok.loading)
                        const ExcavatorLoader(label: 'Memuat stok…')
                      else
                        Rise(
                          key: ValueKey('empty|$_unit|$_location|$query'),
                          child: Column(
                            children: [
                              Text(
                                cetok.parts.isEmpty ? 'Belum ada data stok' : 'Tidak ada part',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                              ),
                              const SizedBox(height: 4),
                              if (cetok.parts.isNotEmpty)
                                Text(
                                  query.isNotEmpty
                                      ? 'Tidak ada part number atau nama yang cocok dengan "$query".'
                                      : 'Coba ganti unit atau lokasi',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                            ],
                          ),
                        ),
                    ],
                  )
                : ListView.separated(
                    // A new filter plays the cards' entrance again.
                    key: ValueKey('$_unit|$_location'),
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => Rise(
                      key: ValueKey(rows[i].id),
                      delay: Rise.stagger(i),
                      child: PartCard(part: rows[i], highlight: query, onTap: () => widget.onOpen(rows[i])),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.hint, required this.onChanged, this.autofocus = false});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: (_) => onChanged(),
      style: TextStyle(fontSize: 13.5, color: AppColors.ink),
      decoration: _input(hint).copyWith(
        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.muted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    );
  }
}

/// A round chip: navy when chosen.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.small = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final height = small ? 30.0 : 34.0;
    return _Pressable(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: height,
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : (small ? AppColors.navySoft : AppColors.surface),
          border: Border.all(color: selected ? AppColors.navy : (small ? AppColors.navySoft : AppColors.border)),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 11.5 : 12.5,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : (small ? AppColors.navy : AppColors.ink),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.ink;
    return Align(
      alignment: Alignment.centerRight,
      child: _Pressable(
        child: AnimatedContainer(
          key: const Key('cetok-location'),
          duration: const Duration(milliseconds: 220),
          height: 34,
          decoration: BoxDecoration(
            color: active ? AppColors.navy : AppColors.surface,
            border: Border.all(color: active ? AppColors.navy : AppColors.border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: fg),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down, size: 18, color: fg),
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 16, color: AppColors.inkSoft)),
        ),
      ),
    );
  }
}

/// Picks a location; slides down to close. Pops '' for every location.
class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.total, required this.counts, required this.current});

  final int total;
  final List<(String, int)> counts;
  final String? current;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final rows = [
      if (q.isEmpty) ('', 'Semua lokasi', widget.total),
      for (final (name, n) in widget.counts)
        if (name.toLowerCase().contains(q)) (name, name, n),
    ];
    final current = widget.current?.toLowerCase() ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (context, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Lokasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SearchBox(controller: _query, hint: 'Cari lokasi', onChanged: () => setState(() {})),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final (value, label, n) = rows[i];
                  final on = value.toLowerCase() == current;
                  return Rise(
                    key: ValueKey('loc-$value'),
                    delay: Rise.stagger(i, step: 25),
                    child: Material(
                      color: on ? AppColors.navySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, value),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 50),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                                    color: on ? AppColors.navy : AppColors.ink,
                                  ),
                                ),
                              ),
                              Text('$n part', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              const SizedBox(width: 8),
                              AnimatedOpacity(
                                opacity: on ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(Icons.check, size: 18, color: AppColors.navy),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.greySoft,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.inkSoft))),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

Color _statusColor(String? status) => switch (status) {
      'RFU' => AppColors.green,
      'NOT RFU' => AppColors.danger,
      _ => AppColors.muted,
    };

/// RFU / NOT RFU / no status as a coloured dot and word.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 11});

  final String? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status ?? 'Tanpa status', style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// A quantity with "pcs"; red when none is left.
class _Qty extends StatelessWidget {
  const _Qty(this.qty, {this.size = 22});

  final int qty;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$qty',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: qty <= 0 ? AppColors.danger : AppColors.ink,
          ),
        ),
        const SizedBox(width: 3),
        Text('pcs', style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}

/// One stock row: part number(s), name and qty, then status, location and
/// unit under a thin line.
class PartCard extends StatelessWidget {
  const PartCard({super.key, required this.part, this.highlight = '', this.onTap});

  final CetokPart part;
  final String highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in part.numbers)
                      Text.rich(
                        _marked(n, highlight),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                      ),
                    const SizedBox(height: 2),
                    Text.rich(
                      _marked(part.desc, highlight),
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Qty(part.qty),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusDot(part.status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  part.loc.isEmpty ? '–' : part.loc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ),
              const SizedBox(width: 8),
              Text(part.unit, style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          if (part.remarks != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(8)),
                  child: Text('Ket: ${part.remarks}', style: TextStyle(fontSize: 11, color: AppColors.orangeText)),
                ),
              ),
            ),
        ],
      ),
    );
    return onTap == null ? card : _Pressable(child: card);
  }
}

TextSpan _marked(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return TextSpan(text: text);
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var at = 0;
  while (true) {
    final found = lower.indexOf(q, at);
    if (found < 0) break;
    if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
    spans.add(TextSpan(
      text: text.substring(found, found + q.length),
      style: TextStyle(backgroundColor: AppColors.highlight, color: const Color(0xFF1F2328)),
    ));
    at = found + q.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

// ---------------------------------------------------------------------------
// Detail

/// A part's details with what can be done with it: Ambil, Transfer, and
/// finding it in the Partsbooks. Slide it down to close.
Future<void> showPartSheet(
  BuildContext context,
  CetokPart part, {
  required ValueChanged<CetokPart> onTake,
  required ValueChanged<CetokPart> onMove,
}) {
  final empty = part.qty <= 0;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PART NUMBER',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.muted)),
            const SizedBox(height: 2),
            for (final n in part.numbers)
              SelectableText(n, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.navy)),
            Text(part.desc, style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Fact('Stok', _Qty(part.qty, size: 18))),
                const SizedBox(width: 8),
                Expanded(child: _Fact('Status', StatusDot(part.status, size: 14))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Fact('Lokasi', Text(part.loc.isEmpty ? '–' : part.loc))),
                const SizedBox(width: 8),
                Expanded(child: _Fact('Unit', Text(part.unit))),
              ],
            ),
            if (part.remarks != null) ...[
              const SizedBox(height: 8),
              _Fact('Keterangan', Text(part.remarks!)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _BigButton(
                    label: 'Ambil',
                    icon: Icons.outbox_outlined,
                    color: AppColors.orange,
                    onPressed: empty
                        ? null
                        : () {
                            Navigator.pop(sheet);
                            onTake(part);
                          },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigButton(
                    label: 'Transfer',
                    icon: Icons.swap_horiz,
                    color: _headerNavy,
                    onPressed: empty
                        ? null
                        : () {
                            Navigator.pop(sheet);
                            onMove(part);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.navy,
                side: BorderSide(color: AppColors.navy, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                Navigator.pop(sheet);
                openInPartsbook(context, part);
              },
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Buka di Partsbook'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
            child: value,
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.icon, required this.color, required this.onPressed});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.greySoft,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Forms

InputDecoration _input(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.5, color: AppColors.faint, fontWeight: FontWeight.w400),
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.navy, width: 1.5),
      ),
    );

const _upper = TextCapitalization.characters;

/// An upper-case text field.
class _Field extends StatelessWidget {
  const _Field({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textCapitalization: _upper,
        onChanged: (_) => onChanged(),
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
        decoration: _input(hint),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.muted)),
      );
}

/// A form above a sticky button.
class _FormPage extends StatelessWidget {
  const _FormPage({required this.fields, required this.cta});

  final List<Widget> fields;
  final Widget cta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: cta,
        ),
      ],
    );
  }
}

/// The form's button: grey with what is still missing, coloured with what it
/// will do once everything is filled in.
class _Cta extends StatelessWidget {
  const _Cta({super.key, required this.label, required this.color, required this.ready, required this.busy, required this.onPressed});

  final String label;
  final Color color;
  final bool ready;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = ready && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: _Pressable(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 52,
          decoration: BoxDecoration(
            color: ready ? color : AppColors.greySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          label,
                          key: ValueKey(label),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ready ? Colors.white : AppColors.muted,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required List<(String, String)> rows,
  required String yes,
  required Color color,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  for (final (k, v) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 96, child: Text(k, style: TextStyle(fontSize: 12.5, color: AppColors.muted))),
                          Expanded(
                            child: Text(v,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(sheet, false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(sheet, true),
                    child: Text(yes),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

int _qtyOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

/// A whole-number quantity between − and +; it can also be typed.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.controller, required this.onChanged, this.max = 99999});

  final TextEditingController controller;
  final VoidCallback onChanged;
  final int max;

  void _step(int by) {
    final next = (_qtyOf(controller) + by).clamp(1, max < 1 ? 1 : max);
    HapticFeedback.selectionClick();
    controller.text = '$next';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final qty = _qtyOf(controller);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kurangi',
            onPressed: qty > 1 ? () => _step(-1) : null,
            icon: Icon(Icons.remove, color: AppColors.navy),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) => onChanged(),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
          IconButton(
            tooltip: 'Tambah',
            onPressed: qty < max ? () => _step(1) : null,
            icon: Icon(Icons.add, color: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

/// RFU / NOT RFU with a pill that slides to the chosen one.
class _StatusChoice extends StatelessWidget {
  const _StatusChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = ['RFU', 'NOT RFU'];

  @override
  Widget build(BuildContext context) {
    final index = _options.indexOf(value).clamp(0, 1);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = (box.maxWidth - 4) / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: _motion,
                curve: _curve,
                left: index * (w + 4),
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [BoxShadow(color: Color(0x1F101828), blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    SizedBox(
                      width: w,
                      child: InkWell(
                        key: Key('status-${_options[i]}'),
                        borderRadius: BorderRadius.circular(9),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(_options[i]);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: _motion,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: i == index ? _statusColor(_options[i]) : AppColors.muted,
                            ),
                            child: Text(_options[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Location chips under a location field: the stock's locations.
class _LocationChips extends StatelessWidget {
  const _LocationChips({required this.cetok, required this.controller, required this.onChanged, this.except = ''});

  final Cetok cetok;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String except;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().toLowerCase();
    final options = [
      for (final l in cetok.locations)
        if (l.toLowerCase() != except.toLowerCase() && (typed.isEmpty || l.toLowerCase().contains(typed) || l.toLowerCase() == typed)) l,
    ].take(8);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in options)
            _Chip(
              label: l,
              small: true,
              selected: l.toLowerCase() == typed,
              onTap: () {
                controller.text = l;
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

/// Finds a stock row by part number or name, the results right below.
class _PartPicker extends StatefulWidget {
  const _PartPicker({super.key, required this.cetok, required this.onPicked});

  final Cetok cetok;
  final ValueChanged<CetokPart> onPicked;

  @override
  State<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends State<_PartPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final found = q.isEmpty ? const <CetokPart>[] : widget.cetok.parts.where((p) => p.matches(q)).take(30).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBox(controller: _query, hint: 'Ketik part number atau nama part', onChanged: () => setState(() {})),
        const SizedBox(height: 10),
        if (q.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Ketik untuk mencari dari ${widget.cetok.parts.length} part',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          )
        else if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('Tidak ada part yang cocok dengan "$q".', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          )
        else
          for (var i = 0; i < found.length; i++)
            Rise(
              key: ValueKey('pick-${found[i].id}'),
              delay: Rise.stagger(i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Opacity(
                  opacity: found[i].qty <= 0 ? 0.5 : 1,
                  child: PartCard(
                    part: found[i],
                    highlight: q,
                    onTap: found[i].qty <= 0
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            widget.onPicked(found[i]);
                          },
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _PickedPart extends StatelessWidget {
  const _PickedPart({super.key, required this.part, required this.onChange});

  final CetokPart part;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.pn, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(part.desc, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                const SizedBox(height: 4),
                Text(
                  [if (part.loc.isNotEmpty) part.loc, part.status ?? 'Tanpa status', part.unit].join(' · '),
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text('${part.qty}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: part.qty <= 0 ? AppColors.danger : AppColors.ink)),
              Text('stok', style: TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
          TextButton(onPressed: onChange, child: const Text('Ganti')),
        ],
      ),
    );
  }
}

/// The picker until a part is chosen, then the part with "Ganti".
class _PartSlot extends StatelessWidget {
  const _PartSlot({required this.cetok, required this.part, required this.choice});

  final Cetok cetok;
  final CetokPart? part;
  final ValueNotifier<CetokPart?> choice;

  @override
  Widget build(BuildContext context) {
    final p = part;
    return AnimatedSwitcher(
      duration: _motion,
      switchInCurve: _curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: p == null
          ? _PartPicker(key: const ValueKey('picker'), cetok: cetok, onPicked: (picked) => choice.value = picked)
          : _PickedPart(key: ValueKey('picked-${p.id}'), part: p, onChange: () => choice.value = null),
    );
  }
}

/// The picked part as it is in the latest stock list.
CetokPart? _fresh(Cetok cetok, CetokPart? picked) {
  if (picked == null) return null;
  for (final p in cetok.parts) {
    if (p.id == picked.id) return p;
  }
  return picked;
}

/// Fills in the name last used once the saved stock list has been read.
void _fillName(TextEditingController name, Cetok cetok) {
  if (name.text.isEmpty && cetok.name.isNotEmpty) name.text = cetok.name;
}

String _from(CetokPart p) => '${p.loc.isEmpty ? '–' : p.loc} (${p.status ?? 'tanpa status'})';

/// Ambil: takes stock out (ambil_barang).
class TakeForm extends StatefulWidget {
  const TakeForm({super.key, required this.cetok, required this.choice});

  final Cetok cetok;
  final ValueNotifier<CetokPart?> choice;

  @override
  State<TakeForm> createState() => _TakeFormState();
}

class _TakeFormState extends State<TakeForm> {
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.choice.addListener(_picked);
    widget.cetok.addListener(_syncName);
  }

  @override
  void dispose() {
    widget.choice.removeListener(_picked);
    widget.cetok.removeListener(_syncName);
    for (final c in [_qty, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _picked() => setState(() => _qty.text = '1');

  void _syncName() => _fillName(_name, widget.cetok);

  Future<void> _save(CetokPart part, int qty) async {
    final note = _note.text.trim().toUpperCase();
    final ok = await _confirm(
      context,
      title: 'Ambil $qty pcs?',
      rows: [
        ('Part', '${part.pn} ${part.desc}'),
        ('Dari', _from(part)),
        ('Sisa stok', '${part.qty} → ${part.qty - qty} pcs'),
        ('Keperluan', note),
      ],
      yes: 'Ya, ambil',
      color: AppColors.orange,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.take(part, qty: qty, note: _note.text, name: _name.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast(context, 'Tersimpan: ambil $qty pcs ${part.pn}');
      _note.clear();
      widget.choice.value = null;
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final part = _fresh(cetok, widget.choice.value);
    final qty = _qtyOf(_qty);
    final label = part == null
        ? 'Pilih part'
        : qty <= 0
            ? 'Isi jumlah'
            : qty > part.qty
                ? 'Stok tidak cukup'
                : _note.text.trim().isEmpty
                    ? 'Isi keperluan'
                    : _name.text.trim().isEmpty
                        ? 'Isi nama pengambil'
                        : 'Ambil $qty pcs';
    final ready = label.startsWith('Ambil ');
    void changed() => setState(() {});
    return _FormPage(
      fields: [
        const _Label('PART'),
        _PartSlot(cetok: cetok, part: part, choice: widget.choice),
        if (part != null)
          Rise(
            key: ValueKey('take-${part.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                const _Label('JUMLAH'),
                _Stepper(controller: _qty, max: part.qty, onChanged: changed),
                const SizedBox(height: 6),
                Text(
                  qty > 0 && qty <= part.qty ? 'Sisa stok ${part.qty} → ${part.qty - qty} pcs' : 'Stok ${part.qty} pcs',
                  style: TextStyle(fontSize: 12, color: qty > part.qty ? AppColors.danger : AppColors.muted),
                ),
                const SizedBox(height: 18),
                const _Label('KEPERLUAN'),
                _Field(controller: _note, hint: 'cth: PERBAIKAN UNIT E5138', onChanged: changed),
                if (cetok.recentNotes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Terakhir', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        for (final n in cetok.recentNotes)
                          _Chip(
                            label: n,
                            small: true,
                            selected: _note.text.trim().toUpperCase() == n,
                            onTap: () {
                              _note.text = n;
                              changed();
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                const _Label('NAMA PENGAMBIL'),
                _Field(controller: _name, hint: 'Nama kamu', onChanged: changed),
              ],
            ),
          ),
      ],
      cta: _Cta(
        key: const Key('cetok-take-cta'),
        label: label,
        color: AppColors.orange,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(part!, qty),
      ),
    );
  }
}

/// Transfer: moves stock to another location and/or status (transfer_stok).
class MoveForm extends StatefulWidget {
  const MoveForm({super.key, required this.cetok, required this.choice});

  final Cetok cetok;
  final ValueNotifier<CetokPart?> choice;

  @override
  State<MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends State<MoveForm> {
  final _qty = TextEditingController(text: '1');
  final _location = TextEditingController();
  late String _status = widget.choice.value?.status ?? 'RFU';
  final _note = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.choice.addListener(_picked);
    widget.cetok.addListener(_syncName);
  }

  @override
  void dispose() {
    widget.choice.removeListener(_picked);
    widget.cetok.removeListener(_syncName);
    for (final c in [_qty, _location, _note, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncName() => _fillName(_name, widget.cetok);

  void _picked() => setState(() {
        _qty.text = '1';
        _location.clear();
        _status = widget.choice.value?.status ?? 'RFU';
      });

  Future<void> _save(CetokPart part, int qty) async {
    final location = _location.text.trim().toUpperCase();
    final ok = await _confirm(
      context,
      title: 'Transfer $qty pcs?',
      rows: [
        ('Part', '${part.pn} ${part.desc}'),
        ('Dari', _from(part)),
        ('Ke', '$location ($_status)'),
        ('Sisa di asal', '${part.qty - qty} pcs'),
      ],
      yes: 'Ya, transfer',
      color: _headerNavy,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.move(part, qty: qty, location: location, status: _status, note: _note.text, name: _name.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast(context, '$qty pcs ${part.pn} dipindah ke $location ($_status)');
      _note.clear();
      widget.choice.value = null;
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final part = _fresh(cetok, widget.choice.value);
    final qty = _qtyOf(_qty);
    final location = _location.text.trim();
    final label = part == null
        ? 'Pilih part'
        : qty <= 0
            ? 'Isi jumlah'
            : qty > part.qty
                ? 'Stok tidak cukup'
                : location.isEmpty
                    ? 'Isi lokasi tujuan'
                    : location.toLowerCase() == part.loc.toLowerCase() && _status == (part.status ?? '')
                        ? 'Tujuan sama dengan asal'
                        : _name.text.trim().isEmpty
                            ? 'Isi nama'
                            : 'Transfer $qty pcs';
    final ready = label.startsWith('Transfer ');
    void changed() => setState(() {});
    return _FormPage(
      fields: [
        const _Label('PART'),
        _PartSlot(cetok: cetok, part: part, choice: widget.choice),
        if (part != null)
          Rise(
            key: ValueKey('move-${part.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                const _Label('JUMLAH'),
                Row(
                  children: [
                    Expanded(child: _Stepper(controller: _qty, max: part.qty, onChanged: changed)),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: BorderSide(color: AppColors.border, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _qty.text = '${part.qty}';
                          changed();
                        },
                        child: const Text('Semua'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _Label('DARI → KE'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.navy, width: 2.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dari', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                                Text(_from(part),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: 2, height: 16, color: AppColors.border),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Text('Ke', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _Field(
                        key: const Key('cetok-move-location'),
                        controller: _location,
                        hint: 'Ketik atau pilih lokasi',
                        onChanged: changed,
                      ),
                      _LocationChips(cetok: cetok, controller: _location, onChanged: changed, except: part.loc),
                      const SizedBox(height: 12),
                      _StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('KETERANGAN (OPSIONAL)'),
                _Field(controller: _note, hint: 'cth: PINDAH KE GUDANG', onChanged: changed),
                const SizedBox(height: 18),
                const _Label('NAMA'),
                _Field(controller: _name, hint: 'Nama kamu', onChanged: changed),
              ],
            ),
          ),
      ],
      cta: _Cta(
        key: const Key('cetok-move-cta'),
        label: label,
        color: _headerNavy,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(part!, qty),
      ),
    );
  }
}

/// Input: adds stock (input_barang). A part number already in stock fills
/// in its name and unit, so its quantity is added to that row.
class AddForm extends StatefulWidget {
  const AddForm({super.key, required this.cetok});

  final Cetok cetok;

  @override
  State<AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<AddForm> {
  String _unit = Cetok.unitModels.first;
  final _pn = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _qty = TextEditingController(text: '1');
  String _status = 'RFU';
  final _remarks = TextEditingController();
  late final _name = TextEditingController(text: widget.cetok.name);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.cetok.addListener(_syncName);
  }

  void _syncName() => _fillName(_name, widget.cetok);

  @override
  void dispose() {
    widget.cetok.removeListener(_syncName);
    for (final c in [_pn, _desc, _location, _qty, _remarks, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The stock row with exactly this part number, if any.
  CetokPart? get _known {
    final pn = _pn.text.trim().toUpperCase();
    if (pn.isEmpty) return null;
    for (final p in widget.cetok.parts) {
      if (p.pn.toUpperCase() == pn || p.numbers.any((n) => n.toUpperCase() == pn)) return p;
    }
    return null;
  }

  void _fillFrom(CetokPart p) {
    _desc.text = p.desc;
    if (Cetok.unitModels.contains(p.unit)) _unit = p.unit;
  }

  void _pnChanged() {
    final known = _known;
    setState(() {
      if (known != null) _fillFrom(known);
    });
  }

  Future<void> _save(int qty) async {
    final pn = _pn.text.trim().toUpperCase();
    final location = _location.text.trim().toUpperCase();
    final ok = await _confirm(
      context,
      title: 'Input $qty pcs?',
      rows: [
        ('Part', pn),
        ('Nama part', _desc.text.trim().toUpperCase()),
        ('Unit', _unit),
        ('Lokasi', '${location.isEmpty ? 'tanpa lokasi' : location} ($_status)'),
      ],
      yes: 'Ya, simpan',
      color: AppColors.green,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.cetok.add(
        unit: _unit,
        pn: _pn.text,
        desc: _desc.text,
        location: _location.text,
        qty: qty,
        status: _status,
        remarks: _remarks.text,
        name: _name.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast(context, 'Tersimpan: $qty pcs $pn di $_unit ($_status)');
      setState(() {
        _pn.clear();
        _desc.clear();
        _location.clear();
        _qty.text = '1';
        _status = 'RFU';
        _remarks.clear();
      });
    } on CetokException catch (e) {
      if (mounted) _toast(context, 'Gagal: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cetok = widget.cetok;
    final known = _known;
    final q = _pn.text.trim();
    final similar = known != null || q.length < 3
        ? const <CetokPart>[]
        : cetok.parts.where((p) => p.matches(q)).take(3).toList();
    final qty = _qtyOf(_qty);
    final label = _pn.text.trim().isEmpty
        ? 'Isi part number'
        : _desc.text.trim().isEmpty
            ? 'Isi nama part'
            : qty <= 0
                ? 'Isi jumlah'
                : _name.text.trim().isEmpty
                    ? 'Isi nama penginput'
                    : 'Simpan $qty pcs';
    final ready = label.startsWith('Simpan ');
    void changed() => setState(() {});
    return _FormPage(
      fields: [
        const _Label('UNIT'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in Cetok.unitModels)
              _Chip(label: u, selected: _unit == u, onTap: () => setState(() => _unit = u)),
          ],
        ),
        const SizedBox(height: 18),
        const _Label('PART NUMBER'),
        _Field(key: const Key('cetok-add-pn'), controller: _pn, hint: 'cth: 07000-12010', onChanged: _pnChanged),
        AnimatedSize(
          duration: _motion,
          curve: _curve,
          alignment: Alignment.topCenter,
          child: known != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: AppColors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sudah ada: ${known.qty} pcs di ${known.loc.isEmpty ? '–' : known.loc}. Nama part diisi otomatis.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.green),
                        ),
                      ),
                    ],
                  ),
                )
              : similar.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          for (final p in similar)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(p.pn, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${p.desc} · ${p.unit} · ${p.qty} pcs'),
                              trailing: const Text('Pakai'),
                              onTap: () {
                                _pn.text = p.pn;
                                setState(() => _fillFrom(p));
                              },
                            ),
                        ],
                      ),
                    ),
        ),
        const SizedBox(height: 18),
        const _Label('NAMA PART'),
        _Field(controller: _desc, hint: 'cth: O-RING', onChanged: changed),
        const SizedBox(height: 18),
        const _Label('LOKASI'),
        _Field(controller: _location, hint: 'Ketik atau pilih lokasi', onChanged: changed),
        _LocationChips(cetok: cetok, controller: _location, onChanged: changed),
        const SizedBox(height: 18),
        const _Label('JUMLAH'),
        _Stepper(controller: _qty, onChanged: changed),
        const SizedBox(height: 18),
        const _Label('STATUS'),
        _StatusChoice(value: _status, onChanged: (s) => setState(() => _status = s)),
        const SizedBox(height: 18),
        const _Label('KETERANGAN (OPSIONAL)'),
        _Field(controller: _remarks, hint: 'cth: NEW, BEKAS UNIT E5138', onChanged: changed),
        const SizedBox(height: 18),
        const _Label('NAMA PENGINPUT'),
        _Field(controller: _name, hint: 'Nama kamu', onChanged: changed),
      ],
      cta: _Cta(
        key: const Key('cetok-add-cta'),
        label: label,
        color: AppColors.green,
        ready: ready,
        busy: _busy,
        onPressed: () => _save(qty),
      ),
    );
  }
}
