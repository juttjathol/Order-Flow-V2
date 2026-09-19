import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import '../widgets/offsite_order.dart';
import '../widgets/pos_ops.dart';
import '../widgets/station_printer.dart';

class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});
  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final orders = ref.snap.store.orders.where((o) {
      if (o.status == OrderStatus.paid || o.status == OrderStatus.cancelled) return false;
      if (filter == 'held') return o.held;
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('payment_queue')),
            Text(
              ref.snap.session.displayName.isEmpty ? s.t('role_cashier') : ref.snap.session.displayName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          const StationActions(),
          IconButton(
            tooltip: s.t('station_printer'),
            onPressed: () => showStationPrinterSheet(context, ref),
            icon: const Icon(Icons.print),
          ),
          IconButton(tooltip: s.t('start_shift'), onPressed: () => startShift(context, ref), icon: const Icon(Icons.badge)),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
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
          Material(
            color: (ref.snap.store.shiftCashier.isEmpty ? OfColors.warn : OfColors.mint)
                .withValues(alpha: 0.16),
            child: InkWell(
              onTap: () => startShift(context, ref),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge,
                      color: ref.snap.store.shiftCashier.isEmpty ? OfColors.warn : OfColors.mint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ref.snap.store.shiftCashier.isEmpty
                            ? s.t('shift_none')
                            : '${s.t('shift_open')}: ${ref.snap.store.shiftCashier}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      ref.snap.store.shiftCashier.isEmpty ? s.t('start_shift') : s.t('end_shift'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: Text(s.t('filter_all')), selected: filter == 'all', onSelected: (_) => setState(() => filter = 'all')),
                ChoiceChip(label: Text(s.t('recall')), selected: filter == 'held', onSelected: (_) => setState(() => filter = 'held')),
              ],
            ),
          ),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (o.held)
                                TextButton(
                                  onPressed: () async {
                                    o.held = false;
                                    await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': o.toJson()}));
                                    if (context.mounted) context.push('/order/${o.id}');
                                  },
                                  child: Text(s.t('recall')),
                                ),
                              MoneyText(o.total),
                            ],
                          ),
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
