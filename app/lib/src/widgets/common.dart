import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// White rounded card used for every grouped list, like the company app.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      shadowColor: const Color(0x14101828),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.background, required this.foreground});

  /// The type label of a manual; other documents get none.
  static Widget docType(DocType type) => switch (type) {
        DocType.shopManual =>
          Pill('SHOP MANUAL', background: AppColors.blueSoft, foreground: AppColors.blue),
        DocType.omm => Pill('OMM', background: AppColors.orangeSoft, foreground: AppColors.orangeText),
        DocType.partsbook =>
          Pill('PARTBOOK', background: AppColors.greenSoft, foreground: AppColors.green),
        DocType.other => const SizedBox.shrink(),
      };

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: foreground),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Text with the search matches (wrapped in \u0001…\u0002) highlighted.
class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet(this.snippet, {super.key, this.maxLines = 3});

  final String snippet;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final parts = snippet.split('\u0001');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i == 0) {
        spans.add(TextSpan(text: part));
        continue;
      }
      final end = part.indexOf('\u0002');
      if (end < 0) {
        spans.add(TextSpan(text: part));
        continue;
      }
      spans.add(TextSpan(
        text: part.substring(0, end),
        style: const TextStyle(backgroundColor: AppColors.highlight, fontWeight: FontWeight.w600),
      ));
      spans.add(TextSpan(text: part.substring(end + 1)));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF3A3F45)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

void showError(BuildContext context, Object error) {
  final text = switch (error) {
    final Exception e => e.toString().replaceFirst(RegExp(r'^\w+Exception:?\s*'), ''),
    _ => '$error',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $text')));
}
