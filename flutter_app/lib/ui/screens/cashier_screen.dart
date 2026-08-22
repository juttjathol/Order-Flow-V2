import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/offsite_order.dart';

class CashierScreen extends ConsumerWidget {
  const CashierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final orders = ref.snap.store.orders
        .where((o) => o.status != OrderStatus.paid && o.status != OrderStatus.cancelled)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('payment_queue')),
        actions: [
          StatusChip(ref.snap.connected ? s.t('connected') : s.t('disconnected'),
              color: ref.snap.connected ? OfColors.mint : OfColors.danger),
          IconButton(onPressed: () => ref.ctrl.leaveRole(), icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: ref.snap.store.model == BusinessModel.retail
          ? FloatingActionButton.extended(
              onPressed: () async {
                final store = ref.snap.store;
                final order = PosOrder(
                  id: newId(),
                  ticketNo: '',
                  type: OrderType.retail,
                  taxRate: store.profile.taxRate,
                );
                await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
                if (context.mounted) context.push('/order/${order.id}');
              },
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(s.t('checkout')),
            )
          : null,
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Expanded(
            child: orders.isEmpty
                ? EmptyState(icon: Icons.payments, message: s.t('no_orders'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      return OfCard(
                        onTap: () => context.push('/order/${o.id}'),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${o.ticketNo}  ${o.tableName ?? (o.customerName.isEmpty ? s.t(o.type.name) : o.customerName)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${s.t(o.type.name == 'dineIn' ? 'dine_in' : o.type.name)} · ${o.lines.length} ${s.t('items')} · ${s.t(o.status.name)}',
                          ),
                          trailing: MoneyText(o.total),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
