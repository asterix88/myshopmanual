/// The Stok tab: search, unit chips, location filter and the stock list.
library;

import 'package:flutter/material.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../../widgets/excavator_loader.dart';
import '../../widgets/rise.dart';
import 'style.dart';
import 'widgets.dart';

/// The stock list: search, unit chips and a location filter.
class StockTab extends StatefulWidget {
  const StockTab({super.key, required this.cetok, required this.focusSearch, required this.onOpen});

  final Cetok cetok;
  final bool focusSearch;
  final ValueChanged<CetokPart> onOpen;

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
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
          child: CetokSearchBox(
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
                  child: CetokChip(
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
                duration: cetokMotion,
                curve: cetokCurve,
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
                : '${cetok.error!} Yang tampil stok terakhir${cetok.updated == null ? '' : ' (${stockTime(cetok.updated!)})'}.',
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
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                              ),
                              const SizedBox(height: 4),
                              if (cetok.parts.isNotEmpty)
                                Text(
                                  query.isNotEmpty
                                      ? 'Tidak ada part number atau nama yang cocok dengan "$query"'
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
                    // A new filter starts at the top; the cards show at once.
                    key: ValueKey('$_unit|$_location'),
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => PartCard(
                      key: ValueKey(rows[i].id),
                      part: rows[i],
                      highlight: query,
                      onTap: () => widget.onOpen(rows[i]),
                    ),
                  ),
          ),
        ),
      ],
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
      child: Pressable(
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
              child: Text('Lokasi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CetokSearchBox(controller: _query, hint: 'Cari lokasi', onChanged: () => setState(() {})),
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
                                    fontSize: 13,
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
