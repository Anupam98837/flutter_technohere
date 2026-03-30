import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF9E363A);
  static const Color secondary = Color(0xFF6B2528);
  static const Color accent = Color(0xFFC94B50);

  // Light theme
  static const Color lightBackground = Color(0xFFF1FBFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFF5FAF9);
  static const Color lightSurface3 = Color(0xFFEDF4F3);

  static const Color lightInk = Color(0xFF042F2E);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);

  static const Color lightBorderSoft = Color(0xFFE4F1EF);
  static const Color lightBorderMedium = Color(0xFFC6DED9);
  static const Color lightBorderStrong = Color(0xFFB6D5D0);

  // Dark theme
  static const Color darkBackground = Color(0xFF020617);
  static const Color darkSurface = Color(0xFF04151F);
  static const Color darkSurface2 = Color(0xFF061B26);
  static const Color darkSurface3 = Color(0xFF071F2B);

  static const Color darkInk = Color(0xFFE0F2F1);
  static const Color darkTextPrimary = Color(0xFFDBEAFE);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);

  static const Color darkBorderSoft = Color(0xFF0B2531);
  static const Color darkBorderMedium = Color(0xFF123341);
  static const Color darkBorderStrong = Color(0xFF123341);

  // States
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF0EA5E9);

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color background(BuildContext context) {
    return isDark(context) ? darkBackground : lightBackground;
  }

  static Color surface(BuildContext context) {
    return isDark(context) ? darkSurface : lightSurface;
  }

  static Color surface2(BuildContext context) {
    return isDark(context) ? darkSurface2 : lightSurface2;
  }

  static Color surface3(BuildContext context) {
    return isDark(context) ? darkSurface3 : lightSurface3;
  }

  static Color ink(BuildContext context) {
    return isDark(context) ? darkInk : lightInk;
  }

  static Color textPrimary(BuildContext context) {
    return isDark(context) ? darkTextPrimary : lightTextPrimary;
  }

  static Color textSecondary(BuildContext context) {
    return isDark(context) ? darkTextSecondary : lightTextSecondary;
  }

  static Color borderSoft(BuildContext context) {
    return isDark(context) ? darkBorderSoft : lightBorderSoft;
  }

  static Color borderMedium(BuildContext context) {
    return isDark(context) ? darkBorderMedium : lightBorderMedium;
  }

  static Color borderStrong(BuildContext context) {
    return isDark(context) ? darkBorderStrong : lightBorderStrong;
  }
}