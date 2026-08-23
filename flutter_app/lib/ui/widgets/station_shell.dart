import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'common.dart';

class StationDest {
  const StationDest({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Tablet: left rail. Phone: bottom bar. Same 5 destinations on every model.
class StationShell extends ConsumerWidget {
  const StationShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.index,
    required this.onIndex,
    required this.destinations,
    required this.pages,
    this.actions,
  });

  final String title;
  final String subtitle;
  final int index;
  final ValueChanged<int> onIndex;
  final List<StationDest> destinations;
  final List<Widget> pages;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isTablet(context);
    final bar = AppBar(
      titleSpacing: 12,
      title: Row(
        children: [
          const BrandMark(size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
    );
    if (!wide) {
      return Scaffold(
        appBar: bar,
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: onIndex,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: bar,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: onIndex,
            labelType: NavigationRailLabelType.all,
            backgroundColor: OfColors.isDark(context) ? OfColors.cardDark : OfColors.paper,
            indicatorColor: OfColors.mint.withValues(alpha: 0.28),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: index, children: pages)),
        ],
      ),
    );
  }
}
