import 'package:flutter/material.dart';

/// Paleta oscura profunda, con acentos naranja y rojo.
class AppColors {
  static const background = Color(0xFF060608);
  static const surface = Color(0xFF121216);
  static const surfaceHigh = Color(0xFF1F2026);
  static const primary = Color(0xFFFF6A1A);
  static const accentRed = Color(0xFFE50914);
  static const textMuted = Color(0xFFA0A0A0);
  static const divider = Color(0xFF26272D);
}

class AppRadius {
  static const small = 8.0;
  static const card = 12.0;
  static const button = 14.0;
  static const sheet = 20.0;
  static const cardAll = BorderRadius.all(Radius.circular(card));
}

class AppShadows {
  static const soft = [
    BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.black,
      secondary: AppColors.primary,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.divider,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: Colors.transparent,
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.primary,
        secondarySelectedColor: AppColors.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        secondaryLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black),
        checkmarkColor: Colors.black,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 3,
        shadowColor: Colors.black54,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 3,
          shadowColor: const Color(0x66FF6A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
    );
  }
}
