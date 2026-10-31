import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Delivery dispatch board: every live delivery ticket flows
/// Queued → Out for delivery → Delivered, with driver assignment.
class DispatchScreen extends ConsumerWidget {
  const DispatchScreen({super.key});

  bool _live(PosOrder o) =>
      o.type == OrderType.delivery && o.status != OrderStatus.cancelled;

  String _stateOf(PosOrder o) {
    if (o.deliveryState == 'out' || o.deliveryState == 'delivered') {
      return o.deliveryState;
    }
    return 'queued'; // '' and legacy rows with no dispatch marker
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    final all = store.orders.where(_live).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final todayStart =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final queued = all.where((o) => _stateOf(o) == 'queued').toList();
    final out = all.where((o) => _stateOf(o) == 'out').toList();
    final delivered = all
        .where((o) =>
            _stateOf(o) == 'delivered' && !o.createdAt.isBefore(todayStart))
        .toList();

    String driverName(String? id) {
      if (id == null) return s.t('assign_driver');
      for (final d in store.drivers) {
        if (d.id == id) return d.name;
      }
      return s.t('assign_driver');
    }

    Widget card(PosOrder o, String state) {
      final due = o.total;
      return OfCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.ticketNo} · ${o.customerName.isEmpty ? o.address : o.customerName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(moneyOf(ref.snap, due),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: OfColors.forest)),
              ],
            ),
            if (o.customerPhone.isNotEmpty || o.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [o.customerPhone, o.address]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(
                      fontSize: 12, color: OfColors.muted, height: 1.25),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delivery_dining, size: 18),
                    label: Text(driverName(o.driverId),
                        overflow: TextOverflow.ellipsis),
                    onPressed: () => _pickDriver(context, ref, o, state),
                  ),
                ),
                const SizedBox(width: 8),
                if (state != 'delivered')
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: state == 'queued'
                          ? OfColors.forest
                          : OfColors.emerald,
                    ),
                    onPressed: () => _advance(ref, o, state),
                    child: Text(state == 'queued'
                        ? s.t('send_out')
                        : s.t('mark_delivered')),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget section(String title, Color color, List<PosOrder> rows,
        String state) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text('$title (${rows.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            ...rows.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: card(o, state))),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('dispatch_board'))),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.local_shipping_outlined,
              message: s.t('no_deliveries'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                section(s.t('dispatch_queued'), OfColors.info, queued, 'queued'),
                section(s.t('dispatch_out'), Colors.orange.shade800, out, 'out'),
                section(s.t('dispatch_delivered'), OfColors.emerald, delivered,
                    'delivered'),
              ],
            ),
    );
  }

  Future<void> _advance(WidgetRef ref, PosOrder o, String state) {
    return ref.ctrl.dispatch(NetCommand(name: 'setDelivery', payload: {
      'orderId': o.id,
      'state': state == 'queued' ? 'out' : 'delivered',
    }));
  }

  Future<void> _pickDriver(
      BuildContext context, WidgetRef ref, PosOrder o, String state) async {
    final s = ref.s;
    final store = ref.snap.store;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.t('assign_driver'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            ...store.drivers.map((d) => ListTile(
                  leading: const Icon(Icons.delivery_dining),
                  title: Text(d.name),
                  subtitle: d.phone.isEmpty ? null : Text(d.phone),
                  trailing: o.driverId == d.id
                      ? const Icon(Icons.check_circle, color: OfColors.emerald)
                      : null,
                  onTap: () => Navigator.pop(ctx, d.id),
                )),
            if (store.drivers.isEmpty)
              const ListTile(title: Text('—')), // drivers managed in More → Drivers
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.ctrl.dispatch(NetCommand(name: 'setDelivery', payload: {
      'orderId': o.id,
      'driverId': picked,
      'state': _stateOf(o),
    }));
  }
}
