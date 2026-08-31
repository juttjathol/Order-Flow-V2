import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('kitchen_queue'), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              '${orders.length}  ·  ${ref.snap.session.displayName}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: StatusChip(
                ref.snap.connected || ref.snap.isMain ? 'ONLINE' : 'OFFLINE',
                color: (ref.snap.connected || ref.snap.isMain) ? OfColors.mint : OfColors.warn,
              ),
            ),
          ),
          const StationActions(),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
        ],
      ),
      body: orders.isEmpty
          ? EmptyState(icon: Icons.soup_kitchen, message: s.t('no_orders'))
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: finalGrid(context),
              itemCount: orders.length,
              itemBuilder: (_, i) {
                final o = orders[i];
                final mins = DateTime.now().difference(o.sentAt ?? o.createdAt).inMinutes;
                final ageColor = mins >= 15 ? OfColors.danger : mins >= 8 ? OfColors.warn : OfColors.mint;
                final lines = (List<OrderLine>.from(o.lines))
                  ..sort((a, b) => a.course.compareTo(b.course));
                return OfCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                        title: Text('${o.ticketNo}${o.tableName == null || o.tableName!.isEmpty ? '' : ' · ${o.tableName}'}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        subtitle: Text(_age(o), style: TextStyle(color: ageColor, fontWeight: FontWeight.w700)),
                        trailing: StatusChip(o.status.name.toUpperCase(), color: ageColor),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: lines
                              .map((l) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${l.qty % 1 == 0 ? l.qty.toInt() : l.qty}  ${l.name}${l.notes.isEmpty ? '' : ' — ${l.notes}'}',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
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
                                  await ref.ctrl.printer.kitchenTicket(ref.snap.store, o, role: ref.snap.session.role, prefer: ref.ctrl.deviceLocalPrinter());
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.print),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  SliverGridDelegateWithFixedCrossAxisCount finalGrid(BuildContext context) {
    return remainingGrid(context);
  }

  SliverGridDelegateWithFixedCrossAxisCount remainingGrid(BuildContext context) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: gridCount(context, phone: 1, tablet: 3),
      mainAxisExtent: 380,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
    );
  }

  String _age(PosOrder o) {
    final start = o.sentAt ?? o.createdAt;
    final m = DateTime.now().difference(start).inMinutes;
    return '${m}m';
  }

  Future<void> _set(WidgetRef ref, PosOrder o, OrderStatus status) {
    return ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': o.id,
      'status': status.name,
    }));
  }
}
