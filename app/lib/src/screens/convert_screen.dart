import 'package:flutter/material.dart';

import '../theme.dart';
import '../units.dart';
import 'shell.dart';

Future<void> openConvert(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConvertScreen()));

/// Konversi Satuan: pressure and torque, worked out on the phone as the
/// number is typed.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final _text = TextEditingController();
  UnitKind _kind = pressure;
  late UnitDef _from;
  late UnitDef _to;

  /// Which side's unit list is open: 'from', 'to' or none.
  String? _picking;

  @override
  void initState() {
    super.initState();
    final last = StoreScope.read(context).lastConvert;
    _kind = last == null ? pressure : unitKind(last.kind);
    _from = _kind.unit(last?.from ?? _kind.from);
    _to = _kind.unit(last?.to ?? _kind.to);
    if (_from == _to) _to = _kind.unit(_kind.to == _from.symbol ? _kind.from : _kind.to);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set({UnitKind? kind, UnitDef? from, UnitDef? to}) {
    setState(() {
      if (kind != null && kind != _kind) {
        _kind = kind;
        _from = kind.unit(kind.from);
        _to = kind.unit(kind.to);
      }
      // Picking the unit on the other side swaps the two.
      if (from != null) {
        if (from == _to) _to = _from;
        _from = from;
      }
      if (to != null) {
        if (to == _from) _from = _to;
        _to = to;
      }
      _picking = null;
    });
    StoreScope.read(context).setLastConvert(_kind.id, _from.symbol, _to.symbol);
  }

  @override
  Widget build(BuildContext context) {
    final value = parseNumber(_text.text);
    double? valueIn(UnitDef u) => value == null ? null : convertUnit(value, _from, u);
    return Scaffold(
      appBar: AppBar(title: const Text('Konversi Satuan')),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                for (final kind in unitKinds) ...[
                  if (kind != unitKinds.first) const SizedBox(width: 8),
                  Expanded(child: _KindTab(kind: kind, selected: kind == _kind, onTap: () => _set(kind: kind))),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _Card(
                  color: AppColors.surface,
                  label: 'Dari',
                  labelColor: AppColors.muted,
                  value: TextField(
                    key: const Key('convert-input'),
                    controller: _text,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.ink),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(color: AppColors.faint),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                  ),
                  unit: _UnitButton(
                    key: const Key('convert-from'),
                    symbol: _from.symbol,
                    background: AppColors.navySoft,
                    foreground: AppColors.navy,
                    tooltip: 'Pilih satuan asal',
                    onTap: () => setState(() => _picking = _picking == 'from' ? null : 'from'),
                  ),
                  choices: _picking == 'from'
                      ? _Choices(kind: _kind, selected: _from, dark: false, onPick: (u) => _set(from: u))
                      : null,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Material(
                    color: AppColors.orange,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _set(from: _to, to: _from),
                      child: const Tooltip(
                        message: 'Tukar satuan',
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.swap_vert, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Card(
                  color: const Color(0xFF1E3A64),
                  label: 'Ke',
                  labelColor: const Color(0xFFC9D3E3),
                  value: Text(
                    formatValue(valueIn(_to)),
                    key: const Key('convert-result'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  unit: _UnitButton(
                    key: const Key('convert-to'),
                    symbol: _to.symbol,
                    background: AppColors.orange,
                    foreground: const Color(0xFF1F2328),
                    tooltip: 'Pilih satuan tujuan',
                    onTap: () => setState(() => _picking = _picking == 'to' ? null : 'to'),
                  ),
                  note: '1 ${_from.symbol} = ${formatValue(convertUnit(1, _from, _to))} ${_to.symbol}',
                  choices: _picking == 'to'
                      ? _Choices(kind: _kind, selected: _to, dark: true, onPick: (u) => _set(to: u))
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                  child: Text(
                    'SEMUA SATUAN',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, u) in _kind.units.where((u) => u != _from).indexed)
                        InkWell(
                          onTap: () => _set(to: u),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: u == _to ? AppColors.orangeSoft : null,
                              border: i == 0 ? null : Border(top: BorderSide(color: AppColors.divider)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 74,
                                  child: Text(
                                    u.symbol,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
                                  ),
                                ),
                                Expanded(
                                  child: Text(u.name, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                ),
                                Text(
                                  formatValue(valueIn(u)),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

class _KindTab extends StatelessWidget {
  const _KindTab({required this.kind, required this.selected, required this.onTap});

  final UnitKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              kind.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Dari or Ke card: a label, the number on the left and its unit on the
/// right, and the unit list under them while it is open.
class _Card extends StatelessWidget {
  const _Card({
    required this.color,
    required this.label,
    required this.labelColor,
    required this.value,
    required this.unit,
    this.note,
    this.choices,
  });

  final Color color;
  final String label;
  final Color labelColor;
  final Widget value;
  final Widget unit;
  final String? note;
  final Widget? choices;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: const Color(0x33101828),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: labelColor)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: value),
                const SizedBox(width: 10),
                unit,
              ],
            ),
            if (note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(note, style: TextStyle(fontSize: 11.5, color: labelColor)),
              ),
            if (choices case final choices?) ...[const SizedBox(height: 10), choices],
          ],
        ),
      ),
    );
  }
}

class _UnitButton extends StatelessWidget {
  const _UnitButton({
    super.key,
    required this.symbol,
    required this.background,
    required this.foreground,
    required this.tooltip,
    required this.onTap,
  });

  final String symbol;
  final Color background;
  final Color foreground;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(symbol, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: foreground)),
                Icon(Icons.expand_more, size: 20, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The units of the kind as chips, inside the Dari (light) or Ke (dark) card.
class _Choices extends StatelessWidget {
  const _Choices({required this.kind, required this.selected, required this.dark, required this.onPick});

  final UnitKind kind;
  final UnitDef selected;
  final bool dark;
  final ValueChanged<UnitDef> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dark ? const Color(0xFF3A5582) : AppColors.divider)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final u in kind.units)
            _Chip(
              label: u.symbol,
              selected: u == selected,
              dark: dark,
              onTap: () => onPick(u),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.dark, required this.onTap});

  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? (dark ? AppColors.orange : AppColors.navy)
        : (dark ? const Color(0xFF2B4A78) : AppColors.surface);
    final foreground = selected ? (dark ? const Color(0xFF1F2328) : Colors.white) : (dark ? Colors.white : AppColors.inkSoft);
    final border = selected ? background : (dark ? const Color(0xFF3A5582) : AppColors.border);
    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: foreground),
          ),
        ),
      ),
    );
  }
}
