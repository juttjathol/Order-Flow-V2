import 'package:flutter/material.dart';

/// Dark-green modern POS palette (Suzlon-inspired).
class OfColors {
  static const forest = Color(0xFF0B3D2E);
  static const deep = Color(0xFF051912);
  static const cardDark = Color(0xFF0E2F24);
  static const cardDarkAlt = Color(0xFF134233);
  static const emerald = Color(0xFF1B8F62);
  static const mint = Color(0xFF3DDC97);
  static const gold = Color(0xFFE6C35C);
  static const cream = Color(0xFFF3F7F2);
  static const ink = Color(0xFF10231B);
  static const danger = Color(0xFFE85D4C);
  static const warn = Color(0xFFF0A202);
  static const info = Color(0xFF3D9CF0);
  static const muted = Color(0xFF7A9A8C);
}

class OfTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: OfColors.forest,
      brightness: Brightness.light,
      primary: OfColors.forest,
      secondary: OfColors.emerald,
      surface: OfColors.cream,
      error: OfColors.danger,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: OfColors.mint,
      brightness: Brightness.dark,
      primary: OfColors.mint,
      secondary: OfColors.emerald,
      surface: OfColors.deep,
      error: OfColors.danger,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? OfColors.deep : OfColors.cream,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.forest,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? OfColors.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? OfColors.cardDark : Colors.white,
        indicatorColor: OfColors.emerald.withValues(alpha: 0.25),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: isDark ? OfColors.mint : OfColors.forest,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
