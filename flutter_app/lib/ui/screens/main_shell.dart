import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/station_shell.dart';
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
      onIndex: (i) => setState(() => index = i),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: StatusChip(
              ref.snap.isMain
                  ? (ref.snap.serverOn ? s.t('server_on') : s.t('server_off'))
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
