import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../widgets/common.dart';
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
      BusinessModel.restaurant => (Icons.table_restaurant, s.t('tables')),
      BusinessModel.retail => (Icons.point_of_sale, s.t('register')),
      BusinessModel.fastfood => (Icons.confirmation_number, s.t('queue')),
      BusinessModel.services => (Icons.event, s.t('appointments')),
    };
    final third = model == BusinessModel.services
        ? (Icons.spa, s.t('services'))
        : (Icons.restaurant_menu, s.t('menu'));
    final pages = const [
      HomeScreen(),
      FloorScreen(),
      MenuScreen(),
      StockScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(ref.snap.store.profile.businessName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: StatusChip(
                ref.snap.serverOn ? s.t('server_on') : s.t('server_off'),
                color: ref.snap.serverOn ? const Color(0xFF3DDC97) : const Color(0xFFF0A202),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.t('home')),
          NavigationDestination(icon: Icon(second.$1), label: second.$2),
          NavigationDestination(icon: Icon(third.$1), label: third.$2),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: s.t('stock')),
          NavigationDestination(icon: const Icon(Icons.more_horiz), label: s.t('more')),
        ],
      ),
    );
  }
}
