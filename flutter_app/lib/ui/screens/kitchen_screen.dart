import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final orders = ref.snap.store.orders
        .where((o) =>
            o.status == OrderStatus.open ||
            o.status == OrderStatus.preparing ||
            o.status == OrderStatus.ready)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('kitchen_queue')),
        actions: [
          StatusChip(ref.snap.connected ? s.t('connected') : s.t('disconnected'),
              color: ref.snap.connected ? OfColors.mint : OfColors.danger),
          IconButton(onPressed: () => ref.ctrl.leaveRole(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: orders.isEmpty
          ? EmptyState(icon: Icons.soup_kitchen, message: s.t('no_orders'))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCount(context, phone: 1, tablet: 3),
                mainAxisExtent: 240,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: orders.length,
              itemBuilder: (_, i) {
                final o = orders[i];
                return OfCard(
                  onTap: () => context.push('/order/${o.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(o.ticketNo, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(o.tableName ?? o.type.name),
                          const Spacer(),
                          StatusChip(s.t(o.status.name), color: statusColor(o.status)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: o.lines
                              .map((l) => Text('${l.qty % 1 == 0 ? l.qty.toInt() : l.qty}  ${l.name}${l.notes.isEmpty ? '' : ' — ${l.notes}'}'))
                              .toList(),
                        ),
                      ),
                      Row(
                        children: [
                          if (o.status == OrderStatus.open)
                            Expanded(child: FilledButton(onPressed: () => _set(ref, o, OrderStatus.preparing), child: Text(s.t('mark_preparing')))),
                          if (o.status == OrderStatus.preparing)
                            Expanded(child: FilledButton(onPressed: () => _set(ref, o, OrderStatus.ready), child: Text(s.t('mark_ready')))),
                          if (o.status == OrderStatus.ready)
                            Expanded(child: FilledButton.tonal(onPressed: () => _set(ref, o, OrderStatus.served), child: Text(s.t('mark_served')))),
                          IconButton(
                            onPressed: () async {
                              try {
                                await ref.ctrl.printer.kitchenTicket(ref.snap.store, o);
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.print),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _set(WidgetRef ref, PosOrder o, OrderStatus status) {
    return ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': o.id,
      'status': status.name,
    }));
  }
}
