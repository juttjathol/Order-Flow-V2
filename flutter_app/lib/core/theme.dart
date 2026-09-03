import 'package:flutter/material.dart';

/// Hybrid POS: forest night + Suzlon cream day. Same layout language.
class OfColors {
  static const forest = Color(0xFF0B3D2E);
  static const deep = Color(0xFF0A0F0D);
  static const cardDark = Color(0xFF151C19);
  static const cardDarkAlt = Color(0xFF1C2622);
  static const emerald = Color(0xFF1B8F62);
  static const mint = Color(0xFF3DDC97);
  static const gold = Color(0xFFE6C35C);
  static const cream = Color(0xFFF3F6F2);
  static const ink = Color(0xFF10231B);
  static const danger = Color(0xFFE85D4C);
  static const warn = Color(0xFFF0A202);
  static const info = Color(0xFF3D9CF0);
  static const muted = Color(0xFF7A9A8C);
  static const line = Color(0x1A3DDC97);
  static const paper = Color(0xFFFFFFFF);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color card(BuildContext context) =>
      isDark(context) ? cardDark : paper;

  static Color mute(BuildContext context) =>
      isDark(context) ? muted : const Color(0xFF5C7468);
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
    final ink = isDark ? const Color(0xFFF3F7F2) : OfColors.ink;
    final quiet = isDark ? OfColors.muted : const Color(0xFF5C7468);
    final text = TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: -0.8, height: 1.1, color: ink),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.6, height: 1.15, color: ink),
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.4, color: ink),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3, color: ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: ink),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, height: 1.45, color: quiet),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      splashColor: OfColors.mint.withValues(alpha: isDark ? 0.16 : 0.22),
      highlightColor: OfColors.mint.withValues(alpha: 0.08),
      scaffoldBackgroundColor: isDark ? OfColors.deep : OfColors.cream,
      dividerColor: isDark ? OfColors.line : const Color(0x14000000),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.forest,
        foregroundColor: Colors.white,
        toolbarHeight: 64,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shadowColor: const Color(0x140B3D2E),
        color: isDark ? OfColors.cardDark : OfColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDark ? const Color(0x223DDC97) : const Color(0x140B3D2E),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.paper,
        indicatorColor: OfColors.mint.withValues(alpha: isDark ? 0.22 : 0.35),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: isDark ? OfColors.mint : OfColors.forest,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          elevation: 0,
          backgroundColor: isDark ? OfColors.mint : OfColors.forest,
          foregroundColor: isDark ? const Color(0xFF042016) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? OfColors.mint : OfColors.forest,
        foregroundColor: isDark ? const Color(0xFF042016) : Colors.white,
        elevation: 2,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0x22000000) : OfColors.paper,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? OfColors.line : const Color(0x22000000)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
