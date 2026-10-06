import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colors taken from the Track Section logo (navy + orange); the layout
/// follows the company app the mechanics already use.
/// Colors taken from the Track Section logo (navy + orange); the layout
/// follows the company app the mechanics already use. Each color has a
/// light and a dark version; [dark] picks which (set before the app is
/// built, see [buildTheme]).
abstract final class AppColors {
  static bool dark = false;

  static Color _pick(int light, int night) => Color(dark ? night : light);

  /// Buttons, active tab, links.
  static Color get navy => _pick(0xFF1E3A64, 0xFF4A78BD);
  static Color get navyDark => _pick(0xFF142A4A, 0xFF0E1A2C);
  static Color get navySoft => _pick(0xFFE8EDF5, 0xFF1F2A3A);
  static Color get orange => _pick(0xFFF08A1C, 0xFFF08A1C);
  static Color get orangeText => _pick(0xFFA0520A, 0xFFF5B26B);
  static Color get orangeSoft => _pick(0xFFFEF1E3, 0xFF3A2A18);
  static Color get background => _pick(0xFFF1F2F4, 0xFF111316);
  static Color get surface => _pick(0xFFFFFFFF, 0xFF1C1F24);
  static Color get ink => _pick(0xFF1F2328, 0xFFE6E8EB);
  /// Body text a step lighter than [ink].
  static Color get inkSoft => _pick(0xFF3A3F45, 0xFFC9CDD2);
  static Color get muted => _pick(0xFF6B7178, 0xFF9AA0A6);
  /// Chevrons and disabled text.
  static Color get faint => _pick(0xFF9AA0A6, 0xFF6B7178);
  static Color get tabInactive => _pick(0xFF8A9097, 0xFF8A9097);
  static Color get divider => _pick(0xFFEEF0F2, 0xFF2A2E35);
  /// Borders under bars and around pictures.
  static Color get line => _pick(0xFFE6E8EB, 0xFF2A2E35);
  static Color get border => _pick(0xFFDADDE1, 0xFF3A3F47);
  /// Background of text fields.
  static Color get field => _pick(0xFFF4F5F7, 0xFF262A30);
  static Color get greySoft => _pick(0xFFECEEF1, 0xFF2A2E35);
  /// Around the pages in the PDF viewer.
  static Color get viewerBackground => _pick(0xFFE4E6EA, 0xFF0B0C0E);
  static Color get green => _pick(0xFF1E7A46, 0xFF5CC98A);
  static Color get greenSoft => _pick(0xFFE8F6EE, 0xFF16301F);
  static Color get blue => _pick(0xFF1B5FB8, 0xFF7FB0F0);
  static Color get blueSoft => _pick(0xFFEAF2FD, 0xFF172A44);
  /// Text saying a manual has an update.
  static Color get update => _pick(0xFFC2410C, 0xFFFF8A50);
  static Color get danger => _pick(0xFFC62828, 0xFFEF5350);
  /// Behind matching words in search results.
  static Color get highlight => _pick(0xFFFFE066, 0xFF7A6400);
}

ThemeData buildTheme({required bool dark}) {
  AppColors.dark = dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Poppins',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.navy,
      secondary: AppColors.orange,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: AppColors.surface,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // Smoother opening of folders and manuals than the default zoom.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
  );
}
