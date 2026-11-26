/// The bottom sheet with one part's details and its actions.
library;

import 'package:flutter/material.dart';

import '../../cetok.dart';
import '../../theme.dart';
import '../partsbook_search_screen.dart';
import 'style.dart';
import 'widgets.dart';

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
              SelectableText(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy)),
            Text(part.desc, style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Fact('Stok', QtyText(part.qty, size: 18))),
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
                    color: cetokNavy,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
