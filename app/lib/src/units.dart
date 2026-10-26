/// Pressure and torque units for the Konversi Satuan screen. Each unit is a
/// factor to its kind's base unit (kPa for pressure, N·m for torque), from
/// the exact definitions: 1 kgf = 9.80665 N, 1 lb = 0.45359237 kg,
/// 1 inch = 25.4 mm.
library;

class UnitDef {
  const UnitDef(this.symbol, this.name, this.factor);

  final String symbol;
  final String name;

  /// How many base units one of this unit is.
  final double factor;
}

class UnitKind {
  const UnitKind({
    required this.id,
    required this.label,
    required this.units,
    required this.from,
    required this.to,
  });

  final String id;
  final String label;
  final List<UnitDef> units;

  /// The pair shown when the kind is first opened.
  final String from;
  final String to;

  UnitDef unit(String symbol) => units.firstWhere((u) => u.symbol == symbol, orElse: () => units.first);
}

const pressure = UnitKind(
  id: 'tekanan',
  label: 'Tekanan',
  from: 'psi',
  to: 'kg/cm²',
  units: [
    UnitDef('kg/cm²', 'kilogram-force/cm²', 98.0665),
    UnitDef('psi', 'pound/inch²', 6.894757293168361),
    UnitDef('bar', 'bar', 100),
    UnitDef('MPa', 'megapascal', 1000),
    UnitDef('kPa', 'kilopascal', 1),
    UnitDef('atm', 'atmosfer', 101.325),
    UnitDef('mmHg', 'milimeter raksa', 0.133322387415),
  ],
);

/// lb·ft and lb·in are the pound-force units of torque wrenches (lbf·ft).
const torque = UnitKind(
  id: 'torsi',
  label: 'Torsi',
  from: 'N·m',
  to: 'kgf·m',
  units: [
    UnitDef('N·m', 'newton meter', 1),
    UnitDef('kgf·m', 'kgm', 9.80665),
    UnitDef('kgf·cm', 'kgcm', 0.0980665),
    UnitDef('lb·ft', 'pound-foot (lbf·ft)', 1.3558179483314004),
    UnitDef('lb·in', 'pound-inch (lbf·in)', 0.1129848290276167),
  ],
);

const unitKinds = [pressure, torque];

UnitKind unitKind(String id) => unitKinds.firstWhere((k) => k.id == id, orElse: () => pressure);

double convertUnit(double value, UnitDef from, UnitDef to) => value * from.factor / to.factor;

/// The number typed in the box: a dot or a comma for decimals, spaces ignored.
double? parseNumber(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Four significant digits with a decimal dot, as the manuals write them
/// (350.1, 0.07031); 10 000 and up as a whole number with spaced thousands.
String formatValue(double? x) {
  if (x == null || !x.isFinite) return '–';
  if (x == 0) return '0';
  if (x.abs() >= 10000) {
    final whole = x.round().abs().toString();
    final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return x < 0 ? '-$grouped' : grouped;
  }
  final p = x.toStringAsPrecision(4);
  if (p.contains('e')) return x.toStringAsExponential(2);
  // 350.10 -> 350.1, 72.00 -> 72
  return p.contains('.') ? p.replaceFirst(RegExp(r'\.?0+$'), '') : p;
}
