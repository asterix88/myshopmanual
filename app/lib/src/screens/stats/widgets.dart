/// Small pieces shared by the Statistik tabs, sheets and pages.
library;

import 'package:flutter/material.dart';

import '../../auth.dart';
import '../../stats.dart';
import '../../theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/excavator_loader.dart';
import '../../widgets/unit_icon.dart';
import 'format.dart';

class StatsCaps extends StatelessWidget {
  const StatsCaps(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.muted),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class StatsBar extends StatelessWidget {
  const StatsBar(this.fraction, {super.key});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.greySoft),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0,
                child: ColoredBox(color: AppColors.navy),
              ),
            ],
          ),
        ),
      );
}

class StatsNumber extends StatelessWidget {
  const StatsNumber({super.key, required this.value, required this.label, this.trend});

  final String value;
  final String label;

  /// Percent against the period before; null = nothing to compare with.
  final int? trend;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: value == '–' ? AppColors.faint : null),
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.muted)),
            if (trend case final t?)
              Text(
                '${t >= 0 ? '▲' : '▼'} ${t.abs()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t >= 0 ? AppColors.green : AppColors.danger,
                ),
              ),
          ],
        ),
      );
}

/// One line under the numbers that leads to what an admin can fix.
class StatsActionCard extends StatelessWidget {
  const StatsActionCard({super.key, required this.data, required this.onTap});

  final StatsOverview data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (data.missing.isNotEmpty) '${data.missing.length} kata tidak ketemu',
      if (data.bad > 0) '${data.bad} jawaban dinilai salah',
    ];
    return Material(
      color: AppColors.orangeSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Perlu tindakan  ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: parts.join(' · ')),
                  ]),
                  style: TextStyle(fontSize: 12, color: AppColors.ink),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppColors.orangeText),
            ],
          ),
        ),
      ),
    );
  }
}

class StatsSegmented extends StatelessWidget {
  const StatsSegmented({super.key, required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.greySoft, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: i == selected ? cardShadow : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                        color: i == selected ? AppColors.navy : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class StatsChip extends StatelessWidget {
  const StatsChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.navy : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      );
}

class StatsOfflineBar extends StatelessWidget {
  const StatsOfflineBar({super.key});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.amberSoft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.wifi_off, size: 18, color: AppColors.amber),
            const SizedBox(width: 10),
            Text('Koneksi terputus',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.amber)),
          ],
        ),
      );
}

class StatsEmpty extends StatelessWidget {
  const StatsEmpty({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.bar_chart_rounded, color: AppColors.navy, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Belum ada pemakaian', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(caption, style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      );
}

/// A line of muted text where a list has nothing yet.
class NoneYet extends StatelessWidget {
  const NoneYet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.muted)),
      );
}

/// Rows in one card, with thin lines between them.
class CardRows extends StatelessWidget {
  const CardRows(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: AppColors.divider),
              child,
            ],
          ],
        ),
      );
}

/// The unit's picture, or a document tile when there is none.
class ManualIcon extends StatelessWidget {
  const ManualIcon({super.key, required this.unit, required this.title, this.size = 40});

  final String unit;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (UnitIcon.pictures.contains(UnitIcon.modelCode(unit))) {
      return UnitIcon(unitId: unit, width: size * 1.3, height: size);
    }
    return SizedBox(
      width: size * 1.3,
      child: Center(child: DocTile(glyphForTitle(title) ?? AppGlyph.general, size: size)),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.navySoft, borderRadius: BorderRadius.circular(12)),
        child: Text(
          initials(name),
          style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: AppColors.navy),
        ),
      );
}

class StatsTiles extends StatelessWidget {
  const StatsTiles(this.items, {super.key});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final (i, (value, label)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
}

const statsListPadding = EdgeInsets.fromLTRB(16, 0, 16, 32);

/// A sheet that waits for [load], then shows [show].
class LoadingSheet<T> extends StatelessWidget {
  const LoadingSheet({super.key, required this.load, required this.show});

  final Future<T> load;
  final Widget Function(BuildContext context, T data) show;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: load,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return EmptyState(
              icon: Icons.wifi_off,
              title: e is AuthException ? e.message : 'Koneksi terputus',
            );
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: ExcavatorLoader(label: 'Memuat…')),
            );
          }
          return show(context, snap.data as T);
        },
      );
}

/// A small label: the app version, or "app lama" in amber.
class VersionTag extends StatelessWidget {
  const VersionTag(this.text, {super.key, this.warn = false, this.danger = false});

  final String text;
  final bool warn;

  /// Red instead of amber.
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: danger ? AppColors.danger.withValues(alpha: .12) : (warn ? AppColors.amberSoft : AppColors.greenSoft),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: danger ? AppColors.danger : (warn ? AppColors.amber : AppColors.green),
          ),
        ),
      );
}
