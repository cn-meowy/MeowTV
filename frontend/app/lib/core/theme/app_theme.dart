import 'package:flutter/material.dart';

/// Theme constants aligned with docs/meowtv-design-spec.md
class AppTheme {
  AppTheme._();

  // ─── Dark theme colors ──────────────────────────────────────────────────────
  // Deep charcoal palette — warm undertones for visual comfort

  // Background
  static const Color background = Color(0xFF0C0C0E);
  static const Color surface = Color(0xFF161618);
  static const Color card = Color(0xFF1E1E22);
  static const Color elevated = Color(0xFF28282E);
  static const Color overlay = Color(0xCC0C0C0E);

  // Primary — Vibrant teal-cyan
  static const Color primary = Color(0xFF00BCD4);
  static const Color primaryDark = Color(0xFF0097A7);
  static const Color primaryGlow = Color(0x4000BCD4);
  static const Color primaryLight = Color(0xFF4DD0E1);

  // Text
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B0B8);
  static const Color textMuted = Color(0xFF6E6E78);
  static const Color textInverse = Color(0xFF0C0C0E);

  // Functional
  static const Color success = Color(0xFF4CAF82);
  static const Color warning = Color(0xFFE8A838);
  static const Color error = Color(0xFFE05252);
  static const Color info = Color(0xFF00BCD4);

  // Border/divider
  static const Color border = Color(0xFF2A2A30);
  static const Color divider = Color(0xFF222228);
  static const Color separator = Color(0xFF3A3A42);

  // TabBar
  static const Color tabBarBg = Color(0xFF161618);

  // ─── Light theme colors ─────────────────────────────────────────────────────
  // Cool gray palette — clean and airy with warm accents

  static const Color lightBackground = Color(0xFFF2F3F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFEBECEF);
  static const Color lightOverlay = Color(0x99F2F3F5);
  static const Color lightPrimary = Color(0xFF00838F);
  static const Color lightPrimaryDark = Color(0xFF006064);
  static const Color lightPrimaryGlow = Color(0x2600838F);
  static const Color lightPrimaryLight = Color(0xFF4DB6AC);
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF5C5C72);
  static const Color lightTextMuted = Color(0xFF9E9EB0);
  static const Color lightTextInverse = Color(0xFFFFFFFF);
  static const Color lightSuccess = Color(0xFF2E7D52);
  static const Color lightWarning = Color(0xFFD4881A);
  static const Color lightError = Color(0xFFC62828);
  static const Color lightInfo = Color(0xFF00838F);
  static const Color lightBorder = Color(0xFFD8D8E0);
  static const Color lightDivider = Color(0xFFEBECEF);
  static const Color lightSeparator = Color(0xFFD0D0D8);
  static const Color lightTabBarBg = Color(0xFFFFFFFF);

  // ─── Sizing ─────────────────────────────────────────────────────────────────

  static const double radiusCard = 8.0;
  static const double radiusButton = 8.0;
  static const double radiusSearch = 24.0; // Capsule shape
  static const double radiusTag = 8.0;
  static const double radiusInput = 24.0; // Capsule

  static const double inputHeight = 48.0;
  static const double tabBarHeight = 56.0;

  // Spacing
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Card dimensions
  static const double cardWidth = 120.0;
  static const double cardHeight = 180.0;
  static const double bannerHeight = 220.0;

  // ─── Dark theme ─────────────────────────────────────────────────────────────

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        primaryColor: primary,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: primaryDark,
          surface: surface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: textPrimary,
          error: error,
        ),
        extensions: <ThemeExtension<dynamic>>[
          AppColors.dark,
        ],
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        cardTheme: const CardThemeData(
          color: card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            color: textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: textPrimary, fontSize: 14),
          bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
          bodySmall: TextStyle(color: textMuted, fontSize: 12),
          labelSmall: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            minimumSize: const Size(120, 48),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          hintStyle: const TextStyle(color: textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 1,
        ),
      );

  // ─── Light theme ────────────────────────────────────────────────────────────

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: lightBackground,
        primaryColor: lightPrimary,
        colorScheme: const ColorScheme.light(
          primary: lightPrimary,
          secondary: lightPrimaryDark,
          surface: lightSurface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: lightTextPrimary,
          error: lightError,
        ),
        extensions: <ThemeExtension<dynamic>>[
          AppColors.light,
        ],
        appBarTheme: const AppBarTheme(
          backgroundColor: lightSurface,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: lightTextPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: lightTextPrimary),
        ),
        cardTheme: const CardThemeData(
          color: lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: lightTextPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: TextStyle(
            color: lightTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: lightTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: lightTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: TextStyle(
            color: lightTextPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: lightTextPrimary, fontSize: 14),
          bodyMedium: TextStyle(color: lightTextSecondary, fontSize: 14),
          bodySmall: TextStyle(color: lightTextMuted, fontSize: 12),
          labelSmall: TextStyle(color: lightTextMuted, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: lightPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            minimumSize: const Size(120, 48),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightCard,
          hintStyle: const TextStyle(color: lightTextMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide: const BorderSide(color: lightPrimary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: lightSurface,
          selectedItemColor: lightPrimary,
          unselectedItemColor: lightTextMuted,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),
        dividerTheme: const DividerThemeData(
          color: lightDivider,
          thickness: 1,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// AppColors — ThemeExtension for semantic color tokens
// ═══════════════════════════════════════════════════════════════════════════════

/// Semantic color tokens that adapt to the current theme.
///
/// Usage:
/// ```dart
/// final colors = context.colors;
/// Container(color: colors.background);
/// ```
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color card;
  final Color elevated;
  final Color overlay;

  final Color primary;
  final Color primaryDark;
  final Color primaryGlow;
  final Color primaryLight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  final Color border;
  final Color divider;
  final Color separator;

  final Color tabBarBg;

  const AppColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.elevated,
    required this.overlay,
    required this.primary,
    required this.primaryDark,
    required this.primaryGlow,
    required this.primaryLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.border,
    required this.divider,
    required this.separator,
    required this.tabBarBg,
  });

  /// Dark theme colors
  static const AppColors dark = AppColors(
    background: AppTheme.background,
    surface: AppTheme.surface,
    card: AppTheme.card,
    elevated: AppTheme.elevated,
    overlay: AppTheme.overlay,
    primary: AppTheme.primary,
    primaryDark: AppTheme.primaryDark,
    primaryGlow: AppTheme.primaryGlow,
    primaryLight: AppTheme.primaryLight,
    textPrimary: AppTheme.textPrimary,
    textSecondary: AppTheme.textSecondary,
    textMuted: AppTheme.textMuted,
    textInverse: AppTheme.textInverse,
    success: AppTheme.success,
    warning: AppTheme.warning,
    error: AppTheme.error,
    info: AppTheme.info,
    border: AppTheme.border,
    divider: AppTheme.divider,
    separator: AppTheme.separator,
    tabBarBg: AppTheme.tabBarBg,
  );

  /// Light theme colors
  static const AppColors light = AppColors(
    background: AppTheme.lightBackground,
    surface: AppTheme.lightSurface,
    card: AppTheme.lightCard,
    elevated: AppTheme.lightElevated,
    overlay: AppTheme.lightOverlay,
    primary: AppTheme.lightPrimary,
    primaryDark: AppTheme.lightPrimaryDark,
    primaryGlow: AppTheme.lightPrimaryGlow,
    primaryLight: AppTheme.lightPrimaryLight,
    textPrimary: AppTheme.lightTextPrimary,
    textSecondary: AppTheme.lightTextSecondary,
    textMuted: AppTheme.lightTextMuted,
    textInverse: AppTheme.lightTextInverse,
    success: AppTheme.lightSuccess,
    warning: AppTheme.lightWarning,
    error: AppTheme.lightError,
    info: AppTheme.lightInfo,
    border: AppTheme.lightBorder,
    divider: AppTheme.lightDivider,
    separator: AppTheme.lightSeparator,
    tabBarBg: AppTheme.lightTabBarBg,
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? elevated,
    Color? overlay,
    Color? primary,
    Color? primaryDark,
    Color? primaryGlow,
    Color? primaryLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? border,
    Color? divider,
    Color? separator,
    Color? tabBarBg,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      elevated: elevated ?? this.elevated,
      overlay: overlay ?? this.overlay,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      primaryLight: primaryLight ?? this.primaryLight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      separator: separator ?? this.separator,
      tabBarBg: tabBarBg ?? this.tabBarBg,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      tabBarBg: Color.lerp(tabBarBg, other.tabBarBg, t)!,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BuildContext extension for convenient access
// ═══════════════════════════════════════════════════════════════════════════════

extension BuildContextThemeX on BuildContext {
  /// Get the current [AppColors] from the theme.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
