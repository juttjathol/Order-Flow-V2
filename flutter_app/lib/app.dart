import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'models/models.dart';
import 'state/app_controller.dart';
import 'ui/widgets/common.dart';

class _OfScroll extends ScrollBehavior {
  const _OfScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

class OrderFlowApp extends ConsumerWidget {
  const OrderFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(appControllerProvider);
    final router = ref.watch(routerProvider);
    final l10n = L10n(snap.session.locale);
    final theme = snap.session.theme;
    return MaterialApp.router(
      title: l10n.t('app'),
      debugShowCheckedModeBanner: false,
      theme: OfTheme.light(),
      darkTheme: OfTheme.dark(),
      themeMode: switch (theme) {
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.system => ThemeMode.light,
      },
      locale: Locale(snap.session.locale),
      supportedLocales: L10n.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        // v1.1.70 — respect the user's font-size setting, but within a range
        // the layouts are actually designed for: tiny OS text stays legible
        // and huge OS text never blows sheets/dialogs off screen.
        final mq = MediaQuery.of(context);
        final scaled = MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.35)),
          child: child ?? const SizedBox.shrink(),
        );
        return ScrollConfiguration(
          behavior: const _OfScroll(),
          child: Directionality(
            textDirection: l10n.direction,
            child: ReadyBannerHost(child: scaled),
          ),
        );
      },
    );
  }
}
