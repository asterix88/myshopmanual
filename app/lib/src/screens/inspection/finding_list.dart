part of '../inspection_screen.dart';

// The list of findings: one card per unit, its finding rows, status pill, age and the model filter sheet.

/// [rows] split by unit code, keeping their order.
List<MapEntry<String, List<InspectionRow>>> _byUnit(List<InspectionRow> rows) {
  final units = <String, List<InspectionRow>>{};
  for (final r in rows) {
    units.putIfAbsent(r.unit, () => []).add(r);
  }
  return units.entries.toList();
}

String _summary(List<InspectionRow> rows) {
  final open = rows.where((r) => !r.closed).length;
  return '$open open · ${rows.length - open} close';
}

/// OPEN (red) or CLOSE (green), as the sheet's STATUS says.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.closed});

  final bool closed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: closed ? AppColors.greenSoft : AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          closed ? 'CLOSED' : 'OPEN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: closed ? AppColors.green : AppColors.danger,
          ),
        ),
      );
}

String _who(InspectionRow r) {
  final first = r.inspector.split(RegExp(r'\s+')).first;
  return r.inspector.contains(' ') ? '$first dkk' : first;
}

String _ageText(int d) => d <= 0 ? 'Hari ini' : '$d hari';

/// An open finding's age: quiet grey text, red with a dot only past 30 days
/// (mockup v22 D1).
class _AgeText extends StatelessWidget {
  const _AgeText({required this.age});

  final int? age;

  @override
  Widget build(BuildContext context) {
    final a = age;
    if (a == null) return const SizedBox.shrink();
    final late = a > 30;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (late) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(
          _ageText(a),
          style: TextStyle(
            fontSize: 12,
            fontWeight: late ? FontWeight.w600 : FontWeight.w400,
            color: late ? AppColors.danger : AppColors.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// A closed finding: green check and CLOSED.
class _ClosedMark extends StatelessWidget {
  const _ClosedMark();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 16, color: AppColors.green),
          const SizedBox(width: 4),
          Text('CLOSED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.green)),
        ],
      );
}

/// One unit's findings in one card: the unit code and its counts on top,
/// then a row per finding.
class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.unit, required this.rows, required this.today, required this.flash, required this.onTap});

  final String unit;
  final List<InspectionRow> rows;
  final DateTime today;
  final String? flash;
  final ValueChanged<InspectionRow> onTap;

  @override
  Widget build(BuildContext context) {
    final open = rows.where((r) => !r.closed).length;
    final closed = rows.length - open;
    return Container(
      key: Key('unit-$unit'),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: cardShadow, color: AppColors.surface),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    unit,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: open == 0 ? AppColors.muted : AppColors.navy),
                  ),
                ),
                Text('$open open${closed > 0 ? ' · $closed close' : ''}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          for (final r in rows) _FindingRow(row: r, today: today, flash: flash == r.id, onTap: () => onTap(r)),
        ],
      ),
    );
  }
}

/// One finding inside a [_UnitCard].
class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.row, required this.today, required this.flash, required this.onTap});

  final InspectionRow row;
  final DateTime today;
  final bool flash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final age = row.ageOn(today);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: flash ? AppColors.greenSoft : AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('finding-${row.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.problem,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: row.closed ? AppColors.muted : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${row.date.length >= 5 ? row.date.substring(0, 5) : row.date} · HM ${row.hm} · ${_who(row)}',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      if (row.closed) ...[
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'ACTION  ',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.green),
                              ),
                              TextSpan(text: row.action),
                            ],
                          ),
                          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.ink),
                        ),
                      ],
                      if (row.pending) ...[
                        const SizedBox(height: 4),
                        Text('Belum terkirim', style: TextStyle(fontSize: 12, color: AppColors.amber)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: row.closed ? const _ClosedMark() : _AgeText(age: age),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The model filter: one row per model of the section, with its counts.
class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.rows, required this.current});

  final List<InspectionRow> rows;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final byModel = <String, List<InspectionRow>>{};
    for (final r in rows) {
      byModel.putIfAbsent(r.model, () => []).add(r);
    }
    final models = byModel.keys.toList()..sort(naturalCompare);
    Widget option(String value, String label, String sub) {
      final on = (current ?? '') == value;
      return InkWell(
        key: Key('model-option-${value.isEmpty ? 'semua' : value}'),
        onTap: () => Navigator.of(context).pop(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    Text(sub, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(
                on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? AppColors.navy : AppColors.faint,
              ),
            ],
          ),
        ),
      );
    }

    return _SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Model unit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  option('', 'Semua', _summary(rows)),
                  for (final m in models) option(m, m.isEmpty ? '-' : m, _summary(byModel[m]!)),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}
