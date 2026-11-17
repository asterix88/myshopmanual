/// Shared look of the Cetok Online screens: motion, header colours, the
/// text-field style, and small formatting helpers.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// How long the screen's moves take, and their easing.
const cetokMotion = Duration(milliseconds: 300);
const cetokCurve = Curves.easeOutCubic;

/// The navy of the header, the same in light and dark mode (as on Home).
const cetokNavy = Color(0xFF1E3A64);
const cetokNavySoft = Color(0xFFC9D3E3);

/// When the stock was last updated: "14.05" today, "3/11 14.05" before.
String stockTime(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
  return '${t.day}/${t.month} $hm';
}

/// The rounded text-field look of every Cetok form and search box.
InputDecoration cetokInput(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: AppColors.faint, fontWeight: FontWeight.w400),
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

/// Green for RFU, red for NOT RFU, grey without a status.
Color statusColor(String? status) => switch (status) {
      'RFU' => AppColors.green,
      'NOT RFU' => AppColors.danger,
      _ => AppColors.muted,
    };
