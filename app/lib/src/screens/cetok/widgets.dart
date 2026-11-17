/// Small building blocks used by more than one Cetok Online tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'style.dart';

/// Shrinks a little while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
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

class CetokSearchBox extends StatelessWidget {
  const CetokSearchBox({super.key, required this.controller, required this.hint, required this.onChanged, this.autofocus = false});

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
      style: TextStyle(fontSize: 13, color: AppColors.ink),
      decoration: cetokInput(hint).copyWith(
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
class CetokChip extends StatelessWidget {
  const CetokChip({super.key, required this.label, required this.selected, required this.onTap, this.small = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final height = small ? 30.0 : 34.0;
    return Pressable(
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
                    fontSize: small ? 12 : 13,
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

/// RFU / NOT RFU / no status as a coloured dot and word.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 11});

  final String? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
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
class QtyText extends StatelessWidget {
  const QtyText(this.qty, {super.key, this.size = 22});

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
              QtyText(part.qty),
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
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
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
    return onTap == null ? card : Pressable(child: card);
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
