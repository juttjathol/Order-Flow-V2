import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/offsite_order.dart';

class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key, this.manage = true});
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.snap.store.model;
    return switch (model) {
      BusinessModel.restaurant => _TablesMap(manage: manage),
      BusinessModel.retail => const _RetailRegister(),
      BusinessModel.fastfood => const _QueueBoard(),
      BusinessModel.services => const _AppointmentsBoard(),
    };
  }
}

class _TablesMap extends ConsumerWidget {
  const _TablesMap({this.manage = true});
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    return Scaffold(
      floatingActionButton: manage
          ? FloatingActionButton.extended(
              onPressed: () => _editTable(context, ref),
              icon: const Icon(Icons.add),
              label: Text(s.t('add_table')),
            )
          : null,
      body: store.tables.isEmpty
          ? Column(
              children: [
                const OffsiteOrderBar(),
                Expanded(
                  child: EmptyState(
                    icon: Icons.table_restaurant,
                    message: s.t('no_tables'),
                    action: () => _editTable(context, ref),
                    actionLabel: s.t('add_table'),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                const OffsiteOrderBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(s.t('tap_table')),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      StatusChip(s.t('free'), color: OfColors.emerald),
                      StatusChip(s.t('ordered'), color: OfColors.warn),
                      StatusChip(s.t('ready'), color: OfColors.mint),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCount(context, phone: 3, tablet: 5),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: store.tables.length,
                    itemBuilder: (_, i) {
                      final t = store.tables[i];
                      final ticket = t.currentOrderId == null ? null : store.orderById(t.currentOrderId);
                      return Material(
                        color: tableColor(t.status).withValues(alpha: 0.18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: tableColor(t.status), width: 2.5),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openTable(context, ref, t),
                          onLongPress: manage ? () => _editTable(context, ref, existing: t) : null,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(t.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
                                Text('${t.seats} ${s.t('seats_n')}', style: const TextStyle(color: OfColors.muted)),
                                const SizedBox(height: 6),
                                StatusChip(s.t(t.status.name), color: tableColor(t.status)),
                                if (ticket != null) ...[
                                  const SizedBox(height: 6),
                                  Text(ticket.ticketNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  MoneyText(ticket.total, style: const TextStyle(fontSize: 14)),
                                ],
                              ],
                            ),
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

  Future<void> _openTable(BuildContext context, WidgetRef ref, FloorTable t) async {
    if (t.currentOrderId != null) {
      context.push('/order/${t.currentOrderId}');
      return;
    }
    final recent = ref.snap.store.orders.where((o) =>
        o.tableId == t.id && DateTime.now().difference(o.createdAt).inSeconds < 10);
    if (recent.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref.s.t('dup_order')),
          content: Text(ref.s.t('dup_order_body')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ref.s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ref.s.t('continue'))),
          ],
        ),
      );
      if (go != true) return;
    }
    final store = ref.snap.store;
    final order = PosOrder(
      id: newId(),
      ticketNo: '',
      type: OrderType.dineIn,
      tableId: t.id,
      tableName: t.name,
      taxRate: store.profile.taxRate,
      createdBy: ref.snap.session.displayName,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
    if (context.mounted) context.push('/order/${order.id}');
  }

  Future<void> _editTable(BuildContext context, WidgetRef ref, {FloorTable? existing}) async {
    final s = ref.s;
    final name = TextEditingController(text: existing?.name ?? 'T${ref.snap.store.tables.length + 1}');
    final seats = TextEditingController(text: '${existing?.seats ?? 4}');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
            const SizedBox(height: 8),
            TextField(controller: seats, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('seats'))),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await ref.ctrl.dispatch(NetCommand(name: 'deleteTable', payload: {'id': existing.id}));
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: Text(s.t('delete')),
              ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final table = FloorTable(
        id: existing?.id ?? newId(),
        name: name.text.trim().isEmpty ? 'T' : name.text.trim(),
        seats: int.tryParse(seats.text) ?? 4,
        status: existing?.status ?? TableStatus.free,
        currentOrderId: existing?.currentOrderId,
      );
      await ref.ctrl.dispatch(NetCommand(name: 'upsertTable', payload: {'table': table.toJson()}));
    }
  }
}

class _RetailRegister extends ConsumerWidget {
  const _RetailRegister();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSale(context, ref),
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(s.t('new_order')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Expanded(child: _OpenOrderList(empty: s.t('no_orders'))),
        ],
      ),
    );
  }
}

class _QueueBoard extends ConsumerWidget {
  const _QueueBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startOffsiteOrder(context, ref, OrderType.takeaway),
        icon: const Icon(Icons.confirmation_number),
        label: Text(s.t('new_order')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Expanded(child: _OpenOrderList(empty: s.t('no_orders'))),
        ],
      ),
    );
  }
}

class _AppointmentsBoard extends ConsumerWidget {
  const _AppointmentsBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    final list = [...store.appointments]..sort((a, b) => a.start.compareTo(b.start));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _book(context, ref),
        icon: const Icon(Icons.event),
        label: Text(s.t('add_appointment')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Expanded(
            child: list.isEmpty
                ? EmptyState(icon: Icons.event_busy, message: s.t('no_appts'), action: () => _book(context, ref), actionLabel: s.t('book'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final svc = store.services.where((e) => e.id == a.serviceId).firstOrNull;
                      final staff = store.staff.where((e) => e.id == a.staffId).firstOrNull;
                      return OfCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${a.customerName} · ${svc?.name ?? s.t('service_ticket')}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${a.start.hour.toString().padLeft(2, '0')}:${a.start.minute.toString().padLeft(2, '0')}  ${staff?.name ?? ''}'),
                          trailing: StatusChip(a.status, color: OfColors.emerald),
                          onTap: () async {
                            final next = a.status == 'booked'
                                ? 'inProgress'
                                : a.status == 'inProgress'
                                    ? 'done'
                                    : 'booked';
                            a.status = next;
                            await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {'appointment': a.toJson()}));
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    final store = ref.snap.store;
    if (store.services.isEmpty || store.staff.isEmpty) return;
    var serviceId = store.services.first.id;
    var staffId = store.staff.first.id;
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('customer'))),
              const SizedBox(height: 8),
              TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: serviceId,
                items: store.services.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name}  ${moneyOf(ref.snap, e.price)}'))).toList(),
                onChanged: (v) => setSt(() => serviceId = v ?? serviceId),
                decoration: InputDecoration(labelText: s.t('services')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: staffId,
                items: store.staff.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                onChanged: (v) => setSt(() => staffId = v ?? staffId),
                decoration: InputDecoration(labelText: s.t('staff')),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('book'))),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      final a = Appointment(
        id: newId(),
        serviceId: serviceId,
        staffId: staffId,
        customerName: name.text.trim().isEmpty ? 'Guest' : name.text.trim(),
        customerPhone: phone.text.trim(),
      );
      await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {'appointment': a.toJson()}));
    }
  }
}

class _OpenOrderList extends ConsumerWidget {
  const _OpenOrderList({required this.empty});
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final orders = ref.snap.store.openOrders;
    if (orders.isEmpty) return EmptyState(icon: Icons.receipt_long, message: empty);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final o = orders[i];
        return OfCard(
          onTap: () => context.push('/order/${o.id}'),
          child: Row(
            children: [
              StatusChip(s.t(o.status.name), color: statusColor(o.status)),
              const SizedBox(width: 8),
              StatusChip(s.t(o.type.name == 'dineIn' ? 'dine_in' : o.type.name), color: o.type == OrderType.delivery ? OfColors.info : OfColors.mint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${o.ticketNo}  ${o.customerName.isEmpty ? s.t(o.type.name == 'dineIn' ? 'dine_in' : o.type.name) : o.customerName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (o.type == OrderType.delivery && o.address.isNotEmpty)
                      Text(o.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              MoneyText(o.total),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _newSale(BuildContext context, WidgetRef ref) async {
  final store = ref.snap.store;
  final order = PosOrder(
    id: newId(),
    ticketNo: '',
    type: OrderType.retail,
    taxRate: store.profile.taxRate,
    createdBy: ref.snap.session.displayName,
  );
  await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
  if (context.mounted) context.push('/order/${order.id}');
}

Future<void> _newTicket(BuildContext context, WidgetRef ref, OrderType type) async {
  final store = ref.snap.store;
  final order = PosOrder(
    id: newId(),
    ticketNo: '',
    type: type,
    taxRate: store.profile.taxRate,
    createdBy: ref.snap.session.displayName,
  );
  await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
  if (context.mounted) context.push('/order/${order.id}');
}
