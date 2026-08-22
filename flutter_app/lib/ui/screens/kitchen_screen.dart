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
            Text(s.t('kitchen_queue')),
            Text(
              '${orders.length}  ·  ${ref.snap.session.displayName}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          const StationActions(),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
        ],
      ),
      body: orders.isEmpty
          ? EmptyState(icon: Icons.soup_kitchen, message: s.t('no_orders'))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCount(context, phone: 1, tablet: 3),
                mainAxisExtent: 280,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: orders.length,
              itemBuilder: (_, i) {
                final o = orders[i];
                final mins = DateTime.now().difference(o.sentAt ?? o.createdAt).inMinutes;
                final ageColor = mins >= 15 ? OfColors.danger : mins >= 8 ? OfColors.warn : OfColors.mint;
                return OfCard(
                  onTap: () => context.push('/order/${o.id}'),
                  color: ageColor.withValues(alpha: 0.14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(o.ticketNo, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: ageColor)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(o.tableName ?? (o.type == OrderType.dineIn ? s.t('dine_in') : s.t(o.type.name)), style: const TextStyle(fontWeight: FontWeight.w700))),
                          StatusChip(s.t(o.status.name), color: statusColor(o.status)),
                        ],
                      ),
                      if (o.type == OrderType.delivery && o.address.isNotEmpty)
                        Text(o.address, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                      if (o.createdBy.isNotEmpty)
                        Text('${s.t('station')}: ${o.createdBy}', style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                      if (o.type == OrderType.takeaway && o.customerName.isNotEmpty)
                        Text('${s.t('takeaway')} · ${o.customerName}', style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                      Text(
                        '${s.t('kot_age')}: ${_age(o)}',
                        style: TextStyle(color: ageColor, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: ([...o.lines.where((l) => o.lines.every((x) => !x.fired) || l.fired)]
                                ..sort((a, b) => a.course.compareTo(b.course)))
                              .map((l) => Text('${s.t('course_${l.course}')}  ${l.qty % 1 == 0 ? l.qty.toInt() : l.qty}  ${l.name}${l.notes.isEmpty ? '' : ' — ${l.notes}'}'))
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
