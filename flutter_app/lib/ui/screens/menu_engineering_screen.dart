import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/menu_engineering.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Menu engineering matrix (Advanced reports): each dish is a ⭐ star,
/// 🐴 plowhorse, 🧩 puzzle, or 🐕 dog based on its volume × margin against
/// the menu medians over the last 30 days.
class MenuEngineeringScreen extends ConsumerWidget {
  const MenuEngineeringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    final rows = MenuEngineering.compute(store);
    final classed = rows.where((r) => r.klass.isNotEmpty).toList();
    final uncosted = rows.where((r) => r.klass.isEmpty).toList();

    final klassEmoji = {
      'star': '⭐',
      'plowhorse': '🐴',
      'puzzle': '🧩',
      'dog': '🐕',
    };
    final klassCount = {for (final k in klassEmoji.keys) k: classed.where((r) => r.klass == k).length};

    Widget chip(String k) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text('${klassEmoji[k]} ${klassCount[k]}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 2),
              Text(s.t('me_$k'),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OfColors.muted)),
            ],
          ),
        ),
      );
    }

    Widget tile(MenuEngRow r) {
      return OfCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(klassEmoji[r.klass] ?? '🏷️', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text(
                    '${s.t('sold')}: ${_num(r.qty)} × ${moneyOf(ref.snap, r.product.price)}',
                    style: const TextStyle(fontSize: 12, color: OfColors.muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (r.cashMarginPct != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: (r.cashMarginPct! >= 50 ? OfColors.emerald : Colors.orange.shade800)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${r.cashMarginPct!.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: r.cashMarginPct! >= 50 ? OfColors.emerald : Colors.orange.shade800)),
              )
            else
              Text(s.t('me_no_recipe'),
                  style: const TextStyle(fontSize: 11, color: OfColors.muted, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('menu_engineering'))),
      body: rows.isEmpty
          ? EmptyState(icon: Icons.query_stats, message: s.t('me_empty'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(s.t('me_sub'),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                ),
                Row(
                  children: [
                    chip('star'),
                    const SizedBox(width: 8),
                    chip('plowhorse'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    chip('puzzle'),
                    const SizedBox(width: 8),
                    chip('dog'),
                  ],
                ),
                const SizedBox(height: 16),
                ...classed.map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: tile(r))),
                if (uncosted.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(s.t('me_uncosted'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...uncosted.map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: tile(r))),
                ],
              ],
            ),
    );
  }

  String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
