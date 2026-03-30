import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const double _fieldRadius = 6;
  static const double _buttonRadius = 6;
  static const double _cardRadius = 10;

  static const EdgeInsets _fieldPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 14);

  static const EdgeInsets _buttonPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  static final _lightInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.lightBorderStrong,
      width: 1,
    ),
  );

  static final _lightFocusedInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.primary,
      width: 1.1,
    ),
  );

  static final _lightErrorInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.error,
      width: 1.1,
    ),
  );

  static final _darkInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.darkBorderStrong,
      width: 1,
    ),
  );

  static final _darkFocusedInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.primary,
      width: 1.1,
    ),
  );

  static final _darkErrorInputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_fieldRadius),
    borderSide: const BorderSide(
      color: AppColors.error,
      width: 1.1,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.lightTextPrimary,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 52,
      titleTextStyle: TextStyle(
        color: AppColors.lightTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: const BorderSide(color: AppColors.lightBorderStrong),
      ),
    ),
    dividerColor: AppColors.lightBorderSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      contentPadding: _fieldPadding,
      isDense: true,
      hintStyle: TextStyle(
        color: AppColors.lightTextSecondary.withOpacity(.8),
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
      labelStyle: const TextStyle(
        color: AppColors.lightTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      enabledBorder: _lightInputBorder,
      focusedBorder: _lightFocusedInputBorder,
      errorBorder: _lightErrorInputBorder,
      focusedErrorBorder: _lightErrorInputBorder,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppColors.lightBorderSoft),
      ),
      border: _lightInputBorder,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.lightTextSecondary,
      suffixIconColor: AppColors.lightTextSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lightBorderMedium,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lightBorderMedium,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.lightTextSecondary,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.lightBorderStrong, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.secondary,
        minimumSize: const Size(0, 36),
        maximumSize: const Size(double.infinity, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return Colors.transparent;
      }),
      side: const BorderSide(color: AppColors.lightBorderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.lightSurface,
      contentTextStyle: const TextStyle(
        color: AppColors.lightTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_buttonRadius),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 52,
      titleTextStyle: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: const BorderSide(color: AppColors.darkBorderStrong),
      ),
    ),
    dividerColor: AppColors.darkBorderSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      contentPadding: _fieldPadding,
      isDense: true,
      hintStyle: TextStyle(
        color: AppColors.darkTextSecondary.withOpacity(.85),
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
      ),
      labelStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      enabledBorder: _darkInputBorder,
      focusedBorder: _darkFocusedInputBorder,
      errorBorder: _darkErrorInputBorder,
      focusedErrorBorder: _darkErrorInputBorder,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppColors.darkBorderSoft),
      ),
      border: _darkInputBorder,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.darkTextSecondary,
      suffixIconColor: AppColors.darkTextSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.darkBorderMedium,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.darkBorderMedium,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkTextPrimary,
        disabledForegroundColor: AppColors.darkTextSecondary,
        minimumSize: const Size(0, 42),
        maximumSize: const Size(double.infinity, 42),
        padding: _buttonPadding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: AppColors.darkBorderStrong, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        minimumSize: const Size(0, 36),
        maximumSize: const Size(double.infinity, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.accent;
        return Colors.transparent;
      }),
      side: const BorderSide(color: AppColors.darkBorderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.darkSurface,
      contentTextStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_buttonRadius),
      ),
    ),
  );
}