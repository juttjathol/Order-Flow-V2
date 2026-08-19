import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class DriverScreen extends ConsumerWidget {
  const DriverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final snap = ref.snap;
    final me = snap.store.driverById(snap.session.pairedDriverId) ??
        snap.store.drivers.cast<Driver?>().firstWhere(
              (d) => d?.deviceId == snap.session.deviceId,
              orElse: () => null,
            );
    final status = me?.status ?? DriverStatus.offline;
    final jobs = snap.store.orders
        .where((o) =>
            o.type == OrderType.delivery &&
            o.status != OrderStatus.paid &&
            o.status != OrderStatus.cancelled &&
            (o.driverId == me?.id || o.driverId == null))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('role_driver')),
        actions: [
          IconButton(onPressed: () => ref.ctrl.leaveRole(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snap.session.displayName.isEmpty ? s.t('role_driver') : snap.session.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                const SizedBox(height: 6),
                Text(snap.connected ? s.t('connected') : s.t('local_only')),
                Text(s.t('pair_ok'), style: const TextStyle(color: OfColors.muted)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(s.t('driver_free')),
                      selected: status == DriverStatus.free,
                      onSelected: (_) => ref.ctrl.setDriverStatus(DriverStatus.free),
                    ),
                    ChoiceChip(
                      label: Text(s.t('driver_busy')),
                      selected: status == DriverStatus.busy,
                      onSelected: (_) => ref.ctrl.setDriverStatus(DriverStatus.busy),
                    ),
                    ChoiceChip(
                      label: Text(s.t('driver_offline')),
                      selected: status == DriverStatus.offline,
                      onSelected: (_) => ref.ctrl.setDriverStatus(DriverStatus.offline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(s.t('delivery_queue'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          if (jobs.isEmpty) EmptyState(icon: Icons.delivery_dining, message: s.t('no_orders')),
          ...jobs.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OfCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${o.ticketNo}  ${o.customerName.isEmpty ? s.t('guest') : o.customerName}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(o.address.isEmpty ? o.customerPhone : o.address),
                    trailing: MoneyText(o.total),
                    onTap: () async {
                      await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
                        'id': o.id,
                        'status': o.status == OrderStatus.ready ? OrderStatus.served.name : OrderStatus.ready.name,
                        'driverId': me?.id,
                      }));
                    },
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
