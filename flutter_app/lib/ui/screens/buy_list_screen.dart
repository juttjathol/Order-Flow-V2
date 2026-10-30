import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/stock_engine.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Stock & recipes engine add-on — Buy list.
///
/// Trailing-7-day sales drive per-ingredient usage; anything whose on-hand
/// stock cannot cover the NEXT 7 days is listed with a suggested buy qty.
/// Shareable as WhatsApp text for the supplier.
class BuyListScreen extends ConsumerWidget {
  const BuyListScreen({super.key});

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    final rows = StockEngine.buyList(store);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('buy_list')),
        actions: [
          IconButton(
            tooltip: s.t('share'),
            icon: const Icon(Icons.share),
            onPressed: rows.isEmpty
                ? null
                : () => Share.share(
                    StockEngine.buyListText(store, urdu: s.isUrdu)),
          ),
        ],
      ),
      body: rows.isEmpty
          ? EmptyState(
              icon: Icons.shopping_cart_checkout,
              message: s.t('nothing_to_buy'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.t('buy_list_sub'),
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                ...rows.map((r) => OfCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.stock.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15)),
                                const SizedBox(height: 3),
                                Text(
                                  '${s.t('on_hand')}: ${_num(r.onHand)} ${r.stock.unit} · ≈${_num(r.perDay)}/${s.t('day')}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: OfColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: OfColors.danger.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color:
                                      OfColors.danger.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              '+${_num(r.suggest)} ${r.stock.unit}',
                              style: const TextStyle(
                                  color: OfColors.danger,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
    );
  }
}
