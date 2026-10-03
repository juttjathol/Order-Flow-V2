import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Hybrid POS: bistro modern — warm cream canvas, forest depth, layered shadows.
/// Inspired by Food POS Dark [FigJam 9441889], FoodiPOS 512102, and POS System Web UI (Figma) — see research notes.
class OfColors {
  /// Dark forest green: exclusively for buttons, primary actions, and brand marks.
  static const forest = Color(0xFF163E2E);
  static const forestDark = Color(0xFF0D281E);
  static const forestLight = Color(0xFF23543F);
  static const deep = Color(0xFF0F1512);
  static const cardDark = Color(0xFF18221D);
  static const cardDarkAlt = Color(0xFF202C26);
  static const emerald = Color(0xFF1B8F62);
  static const mint = Color(0xFF2EA771);
  static const gold = Color(0xFFD49E35);
  /// Bistro brass accent for premium chips & busy pulse.
  static const brass = Color(0xFFC4932E);
  static const amber = Color(0xFFF6B33E);
  static const blush = Color(0xFFFFE8C8);
  /// Main app & website background: warm artisan bistro cream.
  static const cream = Color(0xFFFAF7F2);
  static const creamSurface = Color(0xFFFFFDF9);
  static const creamMuted = Color(0xFFF3ECE0);
  static const creamBorder = Color(0xFFE8E0D2);
  static const ink = Color(0xFF13231A);
  static const danger = Color(0xFFD94838);
  static const warn = Color(0xFFD98816);
  static const info = Color(0xFF2B7DE9);
  static const muted = Color(0xFF5E7166);
  static const line = Color(0x1F163E2E);
  static const paper = Color(0xFFFFFFFF);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color card(BuildContext context) =>
      isDark(context) ? cardDark : creamSurface;

  static Color mute(BuildContext context) =>
      isDark(context) ? const Color(0xFFA9C6B7) : const Color(0xFF5E7166);

  /// Soft bistro surface for elevated cards (light: paper white with warm undertone).
  static Color elevated(BuildContext context) =>
      isDark(context) ? const Color(0xFF1F2E27) : Colors.white;

  /// Glass overlay for app bars / floating filters.
  static Color glass(BuildContext context) =>
      isDark(context) ? const Color(0xB818221D) : const Color(0xE6FFFDFA);
}

/// Radii system — 14/16/22/28 for nested cards, sheets, table tiles.
class OfRadii {
  static const r12 = Radius.circular(12);
  static const r14 = Radius.circular(14);
  static const r16 = Radius.circular(16);
  static const r18 = Radius.circular(18);
  static const r22 = Radius.circular(22);
  static const r28 = Radius.circular(28);
  static BorderRadius get card => BorderRadius.circular(22);
  static BorderRadius get sheet => const BorderRadius.vertical(top: Radius.circular(28));
  static BorderRadius get pill => BorderRadius.circular(999);
}

/// Shadow presets — layered soft shadows instead of hard elevation.
class OfShadows {
  static List<BoxShadow> soft(BuildContext context) => OfColors.isDark(context)
      ? const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))]
      : const [
          BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x0A163E2E), blurRadius: 40, offset: Offset(0, 20)),
        ];
  static List<BoxShadow> card(BuildContext context) => OfColors.isDark(context)
      ? const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))]
      : const [
          BoxShadow(color: Color(0x0F163E2E), blurRadius: 22, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x07163E2E), blurRadius: 36, offset: Offset(0, 18)),
        ];
  static List<BoxShadow> floating(BuildContext context) => const [
        BoxShadow(color: Color(0x1A000000), blurRadius: 28, offset: Offset(0, 16)),
        BoxShadow(color: Color(0x0D163E2E), blurRadius: 6, offset: Offset(0, 2)),
      ];
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
    final quiet = isDark ? const Color(0xFFA9C6B7) : OfColors.muted;
    final text = TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: -0.8, height: 1.1, color: ink),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.6, height: 1.15, color: ink),
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.4, color: ink),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3, color: ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: ink),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, height: 1.45, color: quiet),
      bodySmall: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, height: 1.4, color: quiet),
      titleSmall: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ink),
      labelLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ink),
      labelMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: quiet),
      labelSmall: TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: quiet),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      splashColor: (isDark ? OfColors.mint : OfColors.forest).withValues(alpha: 0.14),
      highlightColor: (isDark ? OfColors.mint : OfColors.forest).withValues(alpha: 0.06),
      scaffoldBackgroundColor: isDark ? OfColors.deep : OfColors.cream,
      dividerColor: isDark ? OfColors.line : OfColors.creamBorder,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.cream,
        foregroundColor: isDark ? Colors.white : OfColors.forest,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : OfColors.forest,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 0,
        shadowColor: Colors.transparent,
        color: isDark ? OfColors.cardDark : OfColors.creamSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: OfRadii.card,
          side: BorderSide(
            color: isDark ? const Color(0x1E3DDC97) : OfColors.creamBorder,
            width: 1.2,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.creamSurface,
        indicatorColor: isDark
            ? OfColors.mint.withValues(alpha: 0.22)
            : OfColors.forest.withValues(alpha: 0.12),
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
          foregroundColor: isDark ? const Color(0xFF042016) : OfColors.cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: isDark ? OfColors.mint : OfColors.forest,
          side: BorderSide(color: isDark ? OfColors.mint : OfColors.forest, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? OfColors.mint : OfColors.forest,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? OfColors.mint : OfColors.forest,
        foregroundColor: isDark ? const Color(0xFF042016) : Colors.white,
        elevation: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: isDark ? OfColors.cardDark : OfColors.creamSurface,
        shape: RoundedRectangleBorder(borderRadius: OfRadii.sheet),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0x22000000) : OfColors.creamSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? OfColors.line : OfColors.creamBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? OfColors.line : OfColors.creamBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? OfColors.mint : OfColors.forest, width: 1.8),
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
        backgroundColor: isDark ? const Color(0xFF223029) : OfColors.ink,
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFFF3F7F2) : OfColors.cream,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
