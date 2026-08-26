import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../ui/screens/cashier_screen.dart';
import '../ui/screens/connect_screen.dart';
import '../ui/screens/driver_screen.dart';
import '../ui/screens/front_desk_screen.dart';
import '../ui/screens/gate_screens.dart';
import '../ui/screens/kitchen_screen.dart';
import '../ui/screens/main_shell.dart';
import '../ui/screens/order_screen.dart';
import '../ui/screens/specialist_screen.dart';
import '../ui/screens/stock_clerk_screen.dart';
import '../ui/screens/taker_screen.dart';

final _routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final n = ValueNotifier<int>(0);
  ref.listen(appControllerProvider, (prev, next) {
    if (prev?.gate != next.gate ||
        prev?.session.role != next.session.role ||
        prev?.ready != next.ready) {
      n.value++;
    }
  });
  ref.onDispose(n.dispose);
  return n;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final snap = ref.read(appControllerProvider);
      final loc = state.matchedLocation;
      if (!snap.ready || snap.gate == LicenseGate.boot) {
        return loc == '/splash' ? null : '/splash';
      }
      if (snap.gate == LicenseGate.locked) {
        return loc == '/locked' ? null : '/locked';
      }
      if (snap.gate == LicenseGate.license) {
        const allowed = {'/license', '/connect', '/role'};
        return allowed.contains(loc) ? null : '/license';
      }
      if (snap.gate == LicenseGate.setup) {
        return loc == '/setup' ? null : '/setup';
      }
      bool cover(String p) =>
          p.startsWith('/taker') ||
          p.startsWith('/kitchen') ||
          p.startsWith('/cashier') ||
          p.startsWith('/clerk') ||
          p.startsWith('/desk') ||
          p.startsWith('/specialist') ||
          p.startsWith('/driver');
      switch (snap.session.role) {
        case AppRole.main:
          if (loc.startsWith('/main') || loc.startsWith('/order') || cover(loc)) return null;
          return '/main';
        case AppRole.manager:
          if (loc.startsWith('/manager') || loc.startsWith('/order') || cover(loc)) return null;
          return '/manager';
        case AppRole.orderTaker:
          if (loc.startsWith('/taker') || loc.startsWith('/order')) return null;
          return '/taker';
        case AppRole.kitchen:
          if (loc.startsWith('/kitchen') || loc.startsWith('/order')) return null;
          return '/kitchen';
        case AppRole.cashier:
          if (loc.startsWith('/cashier') || loc.startsWith('/order')) return null;
          return '/cashier';
        case AppRole.driver:
          return loc.startsWith('/driver') ? null : '/driver';
        case AppRole.stockClerk:
          return loc.startsWith('/clerk') ? null : '/clerk';
        case AppRole.frontDesk:
          if (loc.startsWith('/desk') || loc.startsWith('/order')) return null;
          return '/desk';
        case AppRole.specialist:
          return loc.startsWith('/specialist') ? null : '/specialist';
        case AppRole.none:
          return '/license';
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/license', builder: (_, __) => const LicenseScreen()),
      GoRoute(path: '/locked', builder: (_, __) => const LockedScreen()),
      GoRoute(path: '/connect', builder: (_, __) => const ConnectScreen()),
      GoRoute(path: '/role', builder: (_, __) => const RoleScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/main', builder: (_, __) => const MainShell()),
      GoRoute(path: '/manager', builder: (_, __) => const MainShell()),
      GoRoute(path: '/taker', builder: (_, __) => const TakerScreen()),
      GoRoute(path: '/kitchen', builder: (_, __) => const KitchenScreen()),
      GoRoute(path: '/cashier', builder: (_, __) => const CashierScreen()),
      GoRoute(path: '/driver', builder: (_, __) => const DriverScreen()),
      GoRoute(path: '/clerk', builder: (_, __) => const StockClerkScreen()),
      GoRoute(path: '/desk', builder: (_, __) => const FrontDeskScreen()),
      GoRoute(path: '/specialist', builder: (_, __) => const SpecialistScreen()),
      GoRoute(
        path: '/order/:id',
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: OrderScreen(orderId: state.pathParameters['id']!),
          transitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            child: child,
          ),
        ),
      ),
    ],
  );
});
