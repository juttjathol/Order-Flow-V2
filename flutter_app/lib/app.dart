import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'models/models.dart';
import 'state/app_controller.dart';
import 'ui/widgets/common.dart';

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
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.system => ThemeMode.system,
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
        return Directionality(
          textDirection: l10n.direction,
          child: ReadyBannerHost(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
