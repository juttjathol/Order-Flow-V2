import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
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
/// Directive: sprawling ambient layers + crisp 1px internal border.
class OfShadows {
  static List<BoxShadow> soft(BuildContext context) => OfColors.isDark(context)
      ? const [
          BoxShadow(color: Color(0x38000000), blurRadius: 26, offset: Offset(0, 10), spreadRadius: -2),
          BoxShadow(color: Color(0x22000000), blurRadius: 56, offset: Offset(0, 26), spreadRadius: -6),
        ]
      : const [
          BoxShadow(color: Color(0x12163E2E), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -2),
          BoxShadow(color: Color(0x0A163E2E), blurRadius: 64, offset: Offset(0, 28), spreadRadius: -12),
        ];
  static List<BoxShadow> card(BuildContext context) => OfColors.isDark(context)
      ? const [
          BoxShadow(color: Color(0x42000000), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -1),
          BoxShadow(color: Color(0x26000000), blurRadius: 48, offset: Offset(0, 22), spreadRadius: -6),
        ]
      : const [
          BoxShadow(color: Color(0x0E163E2E), blurRadius: 26, offset: Offset(0, 10), spreadRadius: -1),
          BoxShadow(color: Color(0x08163E2E), blurRadius: 52, offset: Offset(0, 24), spreadRadius: -6),
        ];
  static List<BoxShadow> floating(BuildContext context) => OfColors.isDark(context)
      ? const [
          BoxShadow(color: Color(0x55000000), blurRadius: 34, offset: Offset(0, 16), spreadRadius: -2),
          BoxShadow(color: Color(0x2A000000), blurRadius: 72, offset: Offset(0, 40), spreadRadius: -8),
        ]
      : const [
          BoxShadow(color: Color(0x18163E2E), blurRadius: 32, offset: Offset(0, 16), spreadRadius: -2),
          BoxShadow(color: Color(0x0D163E2E), blurRadius: 70, offset: Offset(0, 38), spreadRadius: -8),
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
    final border = isDark ? const Color(0x1E3DDC97) : OfColors.creamBorder;
    final accent = isDark ? OfColors.mint : OfColors.forest;
    final cardSurface = isDark ? OfColors.cardDark : OfColors.creamSurface;

    // Kill Material's default purple-shifted neutral scale + surface tint —
    // generic "out of the box" look. Every surface token is OURS.
    scheme = scheme.copyWith(
      surfaceTint: Colors.transparent,
      outline: border,
      outlineVariant: (isDark ? const Color(0xFF24352E) : OfColors.line),
      onPrimary: isDark ? const Color(0xFF042016) : OfColors.cream,
      primaryContainer: accent.withValues(alpha: 0.14),
      onPrimaryContainer: accent,
      secondaryContainer: (isDark ? OfColors.cardDarkAlt : OfColors.creamMuted),
      onSecondaryContainer: ink,
      surfaceContainerLowest: isDark ? const Color(0xFF0B100D) : Colors.white,
      surfaceContainerLow: cardSurface,
      surfaceContainer: cardSurface,
      surfaceContainerHigh: isDark ? const Color(0xFF1E2A24) : const Color(0xFFEFE7D8),
      surfaceContainerHighest: isDark ? const Color(0xFF26332C) : const Color(0xFFE8DECC),
      inverseSurface: isDark ? OfColors.creamSurface : OfColors.ink,
      onInverseSurface: isDark ? OfColors.ink : const Color(0xFFF6FAF7),
      inversePrimary: isDark ? OfColors.forest : OfColors.mint,
      shadow: isDark ? const Color(0x66000000) : const Color(0x1A163E2E),
    );

    final text = TextTheme(
      displaySmall: TextStyle(fontWeight: FontWeight.w900, fontSize: 30, letterSpacing: -0.6, height: 1.08, color: ink),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: -0.7, height: 1.08, color: ink),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.55, height: 1.12, color: ink),
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.44, height: 1.2, color: ink),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.4, height: 1.25, color: ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.15, height: 1.3, color: ink),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, height: 1.5, color: quiet),
      bodySmall: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, height: 1.45, letterSpacing: 0.12, color: quiet.withValues(alpha: 0.88)),
      titleSmall: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.1, color: ink),
      labelLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: -0.1, color: ink),
      labelMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.22, color: quiet),
      labelSmall: TextStyle(fontWeight: FontWeight.w600, fontSize: 10.5, letterSpacing: 0.3, color: quiet.withValues(alpha: 0.85)),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      applyElevationOverlayColor: false,
      visualDensity: VisualDensity.standard,
      textTheme: text,
      splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
      splashColor: accent.withValues(alpha: 0.10),
      highlightColor: accent.withValues(alpha: 0.05),
      hoverColor: accent.withValues(alpha: 0.04),
      focusColor: accent.withValues(alpha: 0.10),
      scaffoldBackgroundColor: isDark ? OfColors.deep : OfColors.cream,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 28, indent: 4, endIndent: 4),
      iconTheme: IconThemeData(color: quiet, size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: OfPageTransitionsBuilder(),
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
        height: 74,
        elevation: 0,
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: isDark ? 0.20 : 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 23,
              color: states.contains(WidgetState.selected) ? accent : quiet,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.1,
              color: states.contains(WidgetState.selected) ? accent : quiet,
            )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: quiet,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: -0.1),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        iconColor: quiet,
        textColor: ink,
        titleTextStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2, color: ink),
        subtitleTextStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: quiet),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: isDark ? const Color(0xFF042016) : OfColors.cream,
          disabledBackgroundColor: border,
          disabledForegroundColor: quiet,
          overlayColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          foregroundColor: accent,
          side: BorderSide(color: accent, width: 1.4),
          disabledForegroundColor: quiet,
          disabledBorder: BorderSide(color: border, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          disabledForegroundColor: quiet,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.05),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: isDark ? const Color(0xFF042016) : Colors.white,
        elevation: 0,
        highlightElevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: scheme.shadow,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.3, color: ink),
        contentTextStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, height: 1.5, color: quiet),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        dragHandleColor: border,
        elevation: 10,
        shadowColor: scheme.shadow,
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: OfRadii.sheet),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0x22000000) : OfColors.creamSurface,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: quiet),
        floatingLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.1, color: accent),
        hintStyle: TextStyle(fontWeight: FontWeight.w500, color: quiet.withValues(alpha: 0.65)),
        errorStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: OfColors.danger),
        prefixIconColor: quiet,
        suffixIconColor: quiet,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OfColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OfColors.danger, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        side: BorderSide(color: border, width: 1.1),
        backgroundColor: cardSurface,
        selectedColor: accent.withValues(alpha: 0.14),
        checkmarkColor: accent,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: ink),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : (isDark ? const Color(0xFF8FA79A) : const Color(0xFF9BB5A8))),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent.withValues(alpha: 0.30) : border),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.12)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(isDark ? const Color(0xFF042016) : Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: quiet, width: 1.6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: border,
        circularTrackColor: border,
        linearMinHeight: 8,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: isDark ? OfColors.ink : OfColors.cream),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: OfColors.danger, textColor: Colors.white),
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

/// Shared-axis "breath" transition: new page rises 3.5% + settles from 98.5% scale
/// while fading — the Android default fade-through feels flat and systemy.
class OfPageTransitionsBuilder extends PageTransitionsBuilder {
  const OfPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
