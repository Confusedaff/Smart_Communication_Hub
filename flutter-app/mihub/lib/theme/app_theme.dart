import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppThemeMode — persisted preference key: 'app_theme_mode'
// ─────────────────────────────────────────────────────────────────────────────
enum AppThemeMode { blue, green }

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme — resolves all color tokens from the active theme mode.
// Usage: AppTheme.of(context).accent  (anywhere in the widget tree)
//        AppTheme.accent              (legacy static access — resolves to blue)
// ─────────────────────────────────────────────────────────────────────────────
class AppTheme extends InheritedWidget {
  final AppThemeMode mode;
  final AppThemeTokens tokens;

  const AppTheme({
    super.key,
    required this.mode,
    required this.tokens,
    required super.child,
  });

  static AppThemeTokens of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    return result?.tokens ?? AppThemeTokens.blue;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) => oldWidget.mode != mode;

  // ── Legacy static access (blue theme — keeps all existing widget code
  //    compiling without changes) ─────────────────────────────────────────
  static const Color bgDeep        = Color(0xFF060B14);
  static const Color bgCard        = Color(0xFF0D1626);
  static const Color bgElevated    = Color(0xFF152033);
  static const Color bgSurface     = Color(0xFF1C2B42);
  static const Color accent        = Color(0xFF4F8EF7);
  static const Color accentLight   = Color(0xFF7FB3FF);
  static const Color accentGlow    = Color(0xFF1A3A6E);
  static const Color accentGreen   = Color(0xFF22D3A5);
  static const Color accentAmber   = Color(0xFFFBBF24);
  static const Color accentRed     = Color(0xFFFF5C6A);
  static const Color accentPurple  = Color(0xFFA78BFA);
  static const Color textPrimary   = Color(0xFFF0F6FF);
  static const Color textSecondary = Color(0xFF8BA4C4);
  static const Color textMuted     = Color(0xFF3D5A80);
  static const Color border        = Color(0xFF162035);
  static const Color borderBright  = Color(0xFF243554);
  static const Color borderGlow    = Color(0xFF2A4A80);

  static const List<Color> speakerColors = [
    Color(0xFF4F8EF7), Color(0xFFA78BFA), Color(0xFF22D3A5),
    Color(0xFFFBBF24), Color(0xFFFF5C6A), Color(0xFFF472B6),
    Color(0xFF22D3EE), Color(0xFF86EFAC),
  ];

  static Color speakerColor(int index) =>
      speakerColors[index % speakerColors.length];

  // ── ThemeData builders ────────────────────────────────────────────────────
  static ThemeData buildTheme(AppThemeMode mode) {
    final t = mode == AppThemeMode.green
        ? AppThemeTokens.green
        : AppThemeTokens.blue;
    return _buildMaterialTheme(t);
  }

  static ThemeData get theme => _buildMaterialTheme(AppThemeTokens.blue);

  static ThemeData _buildMaterialTheme(AppThemeTokens t) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: t.bgDeep,
      colorScheme: ColorScheme.dark(
        primary: t.accent,
        secondary: t.accentLight,
        surface: t.bgCard,
        onPrimary: t.onAccent,
        onSecondary: t.onAccent,
        onSurface: t.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bgDeep,
        foregroundColor: t.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: t.isGreen ? null : 'monospace',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: t.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: t.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: t.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2),
        headlineMedium: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5),
        titleLarge: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 18),
        titleMedium: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 15),
        bodyLarge: TextStyle(
            color: t.textPrimary, fontSize: 15, height: 1.6),
        bodyMedium: TextStyle(
            color: t.textSecondary, fontSize: 13, height: 1.5),
        labelSmall: TextStyle(
            color: t.textMuted, fontSize: 11, letterSpacing: 0.8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
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
          foregroundColor: t.accentLight,
          side: BorderSide(color: t.borderBright),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerTheme:
          DividerThemeData(color: t.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: t.bgElevated,
        selectedColor: t.accent.withOpacity(0.2),
        labelStyle: TextStyle(color: t.textPrimary, fontSize: 13),
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.accent,
        unselectedLabelColor: t.textSecondary,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: t.accent, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.bgSurface,
        contentTextStyle: TextStyle(color: t.textPrimary),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.bgCard,
        indicatorColor: t.accent.withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: t.accent, size: 22);
          }
          return IconThemeData(color: t.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
                color: t.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600);
          }
          return TextStyle(color: t.textMuted, fontSize: 11);
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        elevation: 8,
        height: 72,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppThemeTokens — the actual color/style values for each theme
// ─────────────────────────────────────────────────────────────────────────────
class AppThemeTokens {
  final bool isGreen;

  // Backgrounds
  final Color bgDeep;
  final Color bgCard;
  final Color bgElevated;
  final Color bgSurface;

  // Accents
  final Color accent;
  final Color accentLight;
  final Color accentGlow;
  final Color accentGreen;
  final Color accentAmber;
  final Color accentRed;
  final Color accentPurple;
  final Color onAccent; // text color on accent buttons

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Borders
  final Color border;
  final Color borderBright;
  final Color borderGlow;

  // Speaker colors
  final List<Color> speakerColors;

  const AppThemeTokens({
    required this.isGreen,
    required this.bgDeep,
    required this.bgCard,
    required this.bgElevated,
    required this.bgSurface,
    required this.accent,
    required this.accentLight,
    required this.accentGlow,
    required this.accentGreen,
    required this.accentAmber,
    required this.accentRed,
    required this.accentPurple,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderBright,
    required this.borderGlow,
    required this.speakerColors,
  });

  Color speakerColor(int index) => speakerColors[index % speakerColors.length];

  // ── Blue theme (original) ─────────────────────────────────────────────────
  static const AppThemeTokens blue = AppThemeTokens(
    isGreen: false,
    bgDeep:        Color(0xFF060B14),
    bgCard:        Color(0xFF0D1626),
    bgElevated:    Color(0xFF152033),
    bgSurface:     Color(0xFF1C2B42),
    accent:        Color(0xFF4F8EF7),
    accentLight:   Color(0xFF7FB3FF),
    accentGlow:    Color(0xFF1A3A6E),
    accentGreen:   Color(0xFF22D3A5),
    accentAmber:   Color(0xFFFBBF24),
    accentRed:     Color(0xFFFF5C6A),
    accentPurple:  Color(0xFFA78BFA),
    onAccent:      Colors.white,
    textPrimary:   Color(0xFFF0F6FF),
    textSecondary: Color(0xFF8BA4C4),
    textMuted:     Color(0xFF3D5A80),
    border:        Color(0xFF162035),
    borderBright:  Color(0xFF243554),
    borderGlow:    Color(0xFF2A4A80),
    speakerColors: [
      Color(0xFF4F8EF7), Color(0xFFA78BFA), Color(0xFF22D3A5),
      Color(0xFFFBBF24), Color(0xFFFF5C6A), Color(0xFFF472B6),
      Color(0xFF22D3EE), Color(0xFF86EFAC),
    ],
  );

  // ── Green theme (from screenshots) ───────────────────────────────────────
  // Background: near-black with very subtle warm tint + grid feel
  // Accent: mint/lime green #4ADE80
  // Cards: dark charcoal #161B22 (GitHub-dark style)
  // Borders: very subtle #21262D
  static const AppThemeTokens green = AppThemeTokens(
    isGreen: true,
    bgDeep:        Color(0xFF0D1117), // GitHub-dark near-black
    bgCard:        Color(0xFF161B22), // card surface
    bgElevated:    Color(0xFF1C2128), // slightly lifted
    bgSurface:     Color(0xFF21262D), // topmost surface
    accent:        Color(0xFF4ADE80), // bright mint green
    accentLight:   Color(0xFF86EFAC), // lighter mint
    accentGlow:    Color(0xFF0D2818), // green glow bg
    accentGreen:   Color(0xFF4ADE80), // same green
    accentAmber:   Color(0xFFFBBF24), // keep amber
    accentRed:     Color(0xFFFF5C6A), // keep red
    accentPurple:  Color(0xFFA78BFA), // keep purple
    onAccent:      Color(0xFF0D1117), // dark text on green buttons
    textPrimary:   Color(0xFFE6EDF3), // near-white
    textSecondary: Color(0xFF7D8590), // medium grey
    textMuted:     Color(0xFF484F58), // dark grey
    border:        Color(0xFF21262D), // subtle border
    borderBright:  Color(0xFF30363D), // brighter border
    borderGlow:    Color(0xFF1A4731), // green-tinted border
    speakerColors: [
      Color(0xFF4ADE80), Color(0xFFA78BFA), Color(0xFF38BDF8),
      Color(0xFFFBBF24), Color(0xFFFF5C6A), Color(0xFFF472B6),
      Color(0xFF34D399), Color(0xFF818CF8),
    ],
  );
}