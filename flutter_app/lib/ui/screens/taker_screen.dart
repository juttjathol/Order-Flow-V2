import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import '../widgets/offsite_order.dart';
import 'floor_screen.dart';

class TakerScreen extends ConsumerWidget {
  const TakerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final snap = ref.snap;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('role_taker')),
              Text(
                snap.session.displayName.isEmpty ? s.t('tables') : snap.session.displayName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            const StationActions(),
            IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
          ],
          bottom: TabBar(tabs: [
            Tab(text: s.t('tables')),
            Tab(text: s.t('new_order')),
          ]),
        ),
        body: TabBarView(
          children: [
            const FloorScreen(manage: false),
            const _QuickTickets(),
          ],
        ),
      ),
    );
  }
}

class _QuickTickets extends ConsumerWidget {
  const _QuickTickets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => startOffsiteOrder(context, ref, OrderType.takeaway),
          icon: const Icon(Icons.takeout_dining),
          label: Text(s.t('takeaway')),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => startOffsiteOrder(context, ref, OrderType.delivery),
          icon: const Icon(Icons.delivery_dining),
          label: Text(s.t('delivery')),
        ),
        const SizedBox(height: 18),
        Text(s.t('recall'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        ...ref.snap.store.openOrders.where((o) => o.held).map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OfCard(
                  onTap: () async {
                    o.held = false;
                    await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': o.toJson()}));
                    if (context.mounted) context.push('/order/${o.id}');
                  },
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${o.ticketNo}  ${o.tableName ?? o.customerName}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: StatusChip(s.t('held'), color: const Color(0xFFF0A202)),
                  ),
                ),
              ),
            ),
        const SizedBox(height: 18),
        Text(s.t('ready_to_serve'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        ...ref.snap.store.orders.where((o) => o.status == OrderStatus.ready).map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OfCard(
                  onTap: () => context.push('/order/${o.id}'),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${o.ticketNo}  ${o.tableName ?? o.type.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: StatusChip(s.t('ready'), color: const Color(0xFF3DDC97)),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
