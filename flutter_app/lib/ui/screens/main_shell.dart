import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/nav_tab.dart';
import '../widgets/common.dart';
import '../widgets/station_shell.dart';
import '../widgets/tour_overlay.dart';
import 'floor_screen.dart';
import 'home_screen.dart';
import 'menu_screen.dart';
import 'more_screen.dart';
import 'stock_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    // v1.1.93 — the guided tour switches tabs through [mainTabIndex]; keep the
    // shell's local index in sync with it (and vice versa on user taps).
    index = mainTabIndex.value;
    mainTabIndex.addListener(_syncTab);
    // v1.1.92 — first-run bubble tour (once per device; replay from More).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) TourOverlay.maybeShow(context, ref);
      });
    });
  }

  void _syncTab() {
    if (mounted && mainTabIndex.value != index) {
      setState(() => index = mainTabIndex.value);
    }
  }

  @override
  void dispose() {
    mainTabIndex.removeListener(_syncTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final model = ref.snap.store.model;
    final second = switch (model) {
      BusinessModel.restaurant => (Icons.table_restaurant, Icons.table_restaurant, s.t('tables')),
      BusinessModel.retail => (Icons.point_of_sale, Icons.point_of_sale, s.t('register')),
      BusinessModel.fastfood => (Icons.confirmation_number, Icons.confirmation_number, s.t('queue')),
      BusinessModel.services => (Icons.event, Icons.event, s.t('appointments')),
    };
    final third = model == BusinessModel.services
        ? (Icons.spa_outlined, Icons.spa, s.t('services'))
        : (Icons.restaurant_menu_outlined, Icons.restaurant_menu, s.t('menu'));
    return StationShell(
      title: ref.snap.store.profile.businessName,
      subtitle: s.t(ref.snap.isManager ? 'role_manager' : 'role_main'),
      index: index,
      onIndex: (i) {
        setState(() => index = i);
        // Publish so overlays (tour) see user-driven tab switches too.
        if (mainTabIndex.value != i) mainTabIndex.value = i;
      },
      actions: [
        // v1.1.93 — pinned amber pill while the license-screen demo is on;
        // tapping it offers "exit & wipe" (demo data never becomes real data).
        if (ref.snap.session.demoMode)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _DemoChip(onTap: () => _confirmEndDemo(context, ref)),
          ),
        if (ref.snap.isMain || ref.snap.isManager)
          PopupMenuButton<String>(
            tooltip: s.t('cover_role'),
            icon: const Icon(Icons.switch_account),
            onSelected: (p) => context.go(p),
            itemBuilder: (_) => [
              PopupMenuItem(value: '/taker', child: Text(s.t('role_taker'))),
              PopupMenuItem(value: '/kitchen', child: Text(s.t('role_kitchen'))),
              PopupMenuItem(value: '/cashier', child: Text(s.t('role_cashier'))),
              PopupMenuItem(value: '/clerk', child: Text(s.t('role_stock'))),
              PopupMenuItem(value: '/desk', child: Text(s.t('role_desk'))),
              PopupMenuItem(value: ref.snap.isManager ? '/manager' : '/main', child: Text(s.t('cover_home'))),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            // Main + stopped → tappable: one tap starts the LAN server
            // (covers any edge the auto-start watchdog could not).
            child: ref.snap.isMain && !ref.snap.serverOn
                ? _ServerRestartChip(ref: ref)
                : StatusChip(
                    ref.snap.isMain
                        ? s.t('server_on')
                        : (ref.snap.connected ? s.t('connected') : s.t('disconnected')),
                    color: (ref.snap.isMain ? ref.snap.serverOn : ref.snap.connected)
                        ? OfColors.mint
                        : OfColors.warn,
                  ),
          ),
        ),
      ],
      destinations: [
        StationDest(icon: Icons.home_outlined, selectedIcon: Icons.home, label: s.t('home')),
        StationDest(icon: second.$1, selectedIcon: second.$2, label: second.$3),
        StationDest(icon: third.$1, selectedIcon: third.$2, label: third.$3),
        StationDest(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: s.t('stock')),
        StationDest(icon: Icons.more_horiz, selectedIcon: Icons.more_horiz, label: s.t('more')),
      ],
      pages: const [
        HomeScreen(),
        FloorScreen(),
        MenuScreen(),
        StockScreen(),
        MoreScreen(),
      ],
    );
  }
}

/// One-tap LAN server starter shown only when Main's server is stopped.
class _ServerRestartChip extends StatefulWidget {
  const _ServerRestartChip({required this.ref});
  final WidgetRef ref;

  @override
  State<_ServerRestartChip> createState() => _ServerRestartChipState();
}

class _ServerRestartChipState extends State<_ServerRestartChip> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.ref.ctrl.startServer();
    if (!mounted) return;
    setState(() => _busy = false);
    final snap = widget.ref.snap;
    if (!snap.serverOn && snap.error != null) {
      final s = widget.ref.s;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.t('server_start_failed')}: ${snap.error}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.ref.s;
    return Tooltip(
      message: s.t('server_start_hint'),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _start,
        child: StatusChip(_busy ? '⋯' : s.t('server_off'), color: OfColors.warn),
      ),
    );
  }
}

/// v1.1.93 — amber DEMO pill shown on every main tab while demo mode runs.
class _DemoChip extends ConsumerWidget {
  const _DemoChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: const Color(0xFFFFB300),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.science_outlined, size: 15, color: Color(0xFF241A00)),
              const SizedBox(width: 5),
              Text(
                ref.s.t('demo_chip'),
                style: const TextStyle(
                  color: Color(0xFF241A00),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v1.1.93 — confirm then wipe the demo (AppController.endDemo navigates back
/// to /license automatically because the gate flips to LicenseGate.license).
Future<void> _confirmEndDemo(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('demo_exit_t')),
      content: Text(s.t('demo_exit_b')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(s.t('demo_keep')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: OfColors.danger, foregroundColor: Colors.white),
          child: Text(s.t('demo_exit')),
        ),
      ],
    ),
  );
  if (go == true) await ref.ctrl.endDemo();
}
