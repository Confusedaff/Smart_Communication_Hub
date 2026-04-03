import 'package:flutter/material.dart';

class AppTheme {
  // Core palette — deeper, richer, more refined
  static const Color bgDeep = Color(0xFF060B14);
  static const Color bgCard = Color(0xFF0D1626);
  static const Color bgElevated = Color(0xFF152033);
  static const Color bgSurface = Color(0xFF1C2B42);
  static const Color accent = Color(0xFF4F8EF7);
  static const Color accentLight = Color(0xFF7FB3FF);
  static const Color accentGlow = Color(0xFF1A3A6E);
  static const Color accentGreen = Color(0xFF22D3A5);
  static const Color accentAmber = Color(0xFFFBBF24);
  static const Color accentRed = Color(0xFFFF5C6A);
  static const Color accentPurple = Color(0xFFA78BFA);
  static const Color textPrimary = Color(0xFFF0F6FF);
  static const Color textSecondary = Color(0xFF8BA4C4);
  static const Color textMuted = Color(0xFF3D5A80);
  static const Color border = Color(0xFF162035);
  static const Color borderBright = Color(0xFF243554);
  static const Color borderGlow = Color(0xFF2A4A80);

  // Speaker colours
  static const List<Color> speakerColors = [
    Color(0xFF4F8EF7),
    Color(0xFFA78BFA),
    Color(0xFF22D3A5),
    Color(0xFFFBBF24),
    Color(0xFFFF5C6A),
    Color(0xFFF472B6),
    Color(0xFF22D3EE),
    Color(0xFF86EFAC),
  ];

  static Color speakerColor(int index) =>
      speakerColors[index % speakerColors.length];

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentLight,
        surface: bgCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDeep,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'monospace',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2),
        headlineMedium: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5),
        titleLarge: TextStyle(
            color: textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium: TextStyle(
            color: textPrimary, fontWeight: FontWeight.w500, fontSize: 15),
        bodyLarge:
            TextStyle(color: textPrimary, fontSize: 15, height: 1.6),
        bodyMedium: TextStyle(
            color: textSecondary, fontSize: 13, height: 1.5),
        labelSmall: TextStyle(
            color: textMuted, fontSize: 11, letterSpacing: 0.8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentLight,
          side: const BorderSide(color: borderBright),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: bgElevated,
        selectedColor: accent.withOpacity(0.2),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 13),
        side: const BorderSide(color: border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textSecondary,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSurface,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgCard,
        indicatorColor: accent.withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                color: accent, fontSize: 11, fontWeight: FontWeight.w600);
          }
          return const TextStyle(color: textMuted, fontSize: 11);
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        elevation: 8,
        height: 72,
      ),
    );
  }
}