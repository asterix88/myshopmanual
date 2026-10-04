import 'package:flutter/material.dart';

/// Colors taken from the Track Section logo (navy + orange); the layout
/// follows the company app the mechanics already use.
abstract final class AppColors {
  static const navy = Color(0xFF1E3A64);
  static const navyDark = Color(0xFF142A4A);
  static const navySoft = Color(0xFFE8EDF5);
  static const orange = Color(0xFFF08A1C);
  static const orangeText = Color(0xFFA0520A);
  static const orangeSoft = Color(0xFFFEF1E3);
  static const background = Color(0xFFF1F2F4);
  static const surface = Colors.white;
  static const ink = Color(0xFF1F2328);
  static const muted = Color(0xFF6B7178);
  static const divider = Color(0xFFEEF0F2);
  static const border = Color(0xFFDADDE1);
  static const greySoft = Color(0xFFECEEF1);
  static const green = Color(0xFF1E7A46);
  static const greenSoft = Color(0xFFE8F6EE);
  static const blue = Color(0xFF1B5FB8);
  static const blueSoft = Color(0xFFEAF2FD);
  static const danger = Color(0xFFC62828);
  static const highlight = Color(0xFFFFE066);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      secondary: AppColors.orange,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // Smoother opening of folders and manuals than the default zoom.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
  );
}
