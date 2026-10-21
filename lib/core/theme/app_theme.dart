import 'package:flutter/material.dart';

/// Bảng màu theo giao diện FlareLine (MIT, github.com/FlutterFlareLine/FlareLine).
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF3C50E0);
  static const background = Color(0xFFEFF4FB);
  static const sidebar = Color(0xFF1C2434);
  static const sidebarText = Color(0xFF8A99AF);
  static const border = Color(0xFFE5E8EC);
  static const text = Color(0xFF1C2434);
  static const muted = Color(0xFF64748B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
    onSurface: AppColors.text,
  );
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(color: AppColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x11000000),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: cardShape,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.sidebar,
      indicatorColor: AppColors.primary,
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: const IconThemeData(color: AppColors.sidebarText),
      selectedLabelTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: const TextStyle(color: AppColors.sidebarText),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    ),
  );
}
