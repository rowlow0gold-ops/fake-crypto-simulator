import 'package:flutter/material.dart';

class AppColors {
  static const bg      = Color(0xFF0B0E11);
  static const card    = Color(0xFF161A1F);
  static const cardAlt = Color(0xFF1E232B);
  static const border  = Color(0xFF2A2F38);
  static const text    = Color(0xFFEAECEF);
  static const dim     = Color(0xFF8A8F98);
  static const green   = Color(0xFF0ECB81);
  static const red     = Color(0xFFF6465D);
  static const yellow  = Color(0xFFF0B90B);
  static const accent  = Color(0xFFF0B90B);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.card,
      onSurface: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerColor: AppColors.border,
    cardColor: AppColors.card,
  );
}
