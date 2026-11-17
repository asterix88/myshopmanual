/// Text helpers for the Statistik screens: month names, "kemarin",
/// initials, unit names and the WhatsApp text of the inactive list.
library;

import '../../models.dart';
import '../../stats.dart';
import '../../store.dart';

String twoDigits(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// "Oktober 2026".
String monthLabel(DateTime m) => '${_months[m.month - 1]} ${m.year}';

/// "10.42" today, "kemarin", "3 hari lalu", or a date.
String whenLabel(DateTime? t, {DateTime? now}) {
  if (t == null) return '–';
  now ??= DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return '${twoDigits(t.hour)}.${twoDigits(t.minute)}';
  if (days == 1) return 'kemarin';
  if (days < 30) return '$days hari lalu';
  return '${t.day}/${t.month}/${t.year}';
}

/// "hari ini", "kemarin", "N hari lalu".
String daysAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '–';
  now ??= DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  return days <= 0 ? 'hari ini' : days == 1 ? 'kemarin' : '$days hari lalu';
}

String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return (words.length == 1 ? words.first.substring(0, words.first.length.clamp(0, 2)) : '${words[0][0]}${words[1][0]}')
      .toUpperCase();
}

String unitName(AppStore store, String unit) => store.unitById(unit)?.name ?? unit;

/// The unit's name, or "Semua section" for a manual every section reads.
String unitLine(AppStore store, String unit, {bool? shared}) =>
    (shared ?? store.unitById(unit)?.section == sharedSection) ? 'Semua section' : unitName(store, unit);

/// The "belum aktif" list as text for WhatsApp, by section.
String inactiveText(List<InactiveRow> people, List<String> order, Map<String, List<InactiveRow>> groups) {
  final b = StringBuffer('Belum aktif di MyManual (${people.length} orang)\n');
  for (final section in order) {
    b.write('\n*$section* (${groups[section]!.length})\n');
    for (final (i, p) in groups[section]!.indexed) {
      final note = p.never || p.last == null ? 'belum pernah login' : 'terakhir ${daysAgo(p.last)}';
      b.write('${i + 1}. ${p.name} (${p.nrp}) - $note${p.oldApp && !p.never ? ', app lama' : ''}\n');
    }
  }
  return b.toString().trimRight();
}
