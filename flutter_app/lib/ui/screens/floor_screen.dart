import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/offsite_order.dart';
import '../widgets/plan_extras.dart';

class FloorScreen extends ConsumerWidget {
  const FloorScreen({super.key, this.manage = true});
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.snap.store.model;
    final board = switch (model) {
      BusinessModel.restaurant => _TablesMap(manage: manage),
      BusinessModel.retail => const _RetailRegister(),
      BusinessModel.fastfood => const _QueueBoard(),
      BusinessModel.services => const _AppointmentsBoard(),
    };
    if (!isTablet(context) || model == BusinessModel.services) return board;
    return Row(
      children: [
        Expanded(child: board),
        const VerticalDivider(width: 1),
        const SizedBox(width: 360, child: _TicketRail()),
      ],
    );
  }
}

class _TicketRail extends ConsumerWidget {
  const _TicketRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final orders = ref.snap.store.openOrders;
    return ColoredBox(
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
            child: Text(s.t('live_board'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          Expanded(
            child: orders.isEmpty
                ? EmptyState(icon: Icons.receipt_long, message: s.t('no_orders'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      return OfCard(
                        onTap: () => context.push('/order/${o.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              StatusChip(s.t(o.status.name), color: statusColor(o.status)),
                              const Spacer(),
                              MoneyText(o.total, style: const TextStyle(fontSize: 14)),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              '${o.ticketNo}  ${o.tableName ?? (o.customerName.isEmpty ? s.t(o.type.name == 'dineIn' ? 'dine_in' : o.type.name) : o.customerName)}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
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
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Text(s.t('tap_table'), style: TextStyle(color: OfColors.mute(context), fontSize: 16)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            StatusChip(s.t('free'), color: OfColors.emerald),
                            StatusChip(s.t('ordered'), color: OfColors.warn),
                            StatusChip(s.t('ready'), color: OfColors.mint),
                          ],
                        ),
                      ),
                      if (manage && ref.snap.canFeature('qr_ordering'))
                        PopupMenuButton<String>(
                          tooltip: s.t('qr_table_title'),
                          icon: const Icon(Icons.qr_code_2, size: 20, color: OfColors.mint),
                          itemBuilder: (_) => [
                            for (final t in store.tables)
                              PopupMenuItem(
                                value: t.id,
                                child: Text('${t.name} — ${s.t('qr_table_title')}'),
                              ),
                          ],
                          onSelected: (id) {
                            final t = store.tableById(id);
                            if (t != null) showTableQr(context, ref, t);
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _FloorClock(
                    builder: (now) => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCount(context, phone: 2, tablet: 4),
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: store.tables.length,
                    itemBuilder: (_, i) {
                      final t = store.tables[i];
                      final ticket = t.currentOrderId == null ? null : store.orderById(t.currentOrderId);
                      final color = tableColor(t.status);
                      final mins = ticket == null ? null : now.difference(ticket.createdAt).inMinutes;
                      return Material(
                        color: OfColors.card(context),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(color: color, width: 3),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () => _openTable(context, ref, t),
                          onLongPress: manage ? () => _editTable(context, ref, existing: t) : null,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                            child: Column(
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)],
                                  ),
                                ),
                                const Spacer(),
                                Text(t.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: -0.8)),
                                const SizedBox(height: 4),
                                Text('${t.seats} ${s.t('seats_n')}', style: TextStyle(color: OfColors.mute(context), fontSize: 14)),
                                const Spacer(),
                                StatusChip(s.t(t.status.name), color: color),
                                if (ticket != null) ...[
                                  const SizedBox(height: 10),
                                  Text('${ticket.ticketNo}  ·  ${mins}m', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  MoneyText(ticket.total, style: const TextStyle(fontSize: 16)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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

/// Retail landing — registers don't browse tables, they open sales.
/// A big New-sale hero, held sales first (recall without hunting), and the
/// open-sale list with item counts, the way till software lays it out.
class _RetailRegister extends ConsumerWidget {
  const _RetailRegister();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final open = ref.snap.store.openOrders;
    final held = open.where((o) => o.held).toList();
    final live = open.where((o) => !o.held).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSale(context, ref),
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(s.t('new_sale')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                onPressed: () => _newSale(context, ref),
                icon: const Icon(Icons.point_of_sale),
                label: Text('${s.t('new_sale')}  ·  ${s.t('scan_to_add_short')}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          Expanded(
            child: open.isEmpty
                ? EmptyState(icon: Icons.shopping_cart_outlined, message: s.t('no_open_sale'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                    children: [
                      if (held.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text(s.t('recall'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                        ...held.map((o) => _SaleCard(order: o, recall: true)),
                        const SizedBox(height: 10),
                        Text(s.t('open_orders'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        const SizedBox(height: 8),
                      ],
                      ...live.map((o) => _SaleCard(order: o)),
                      if (live.isEmpty && held.isNotEmpty) const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends ConsumerWidget {
  const _SaleCard({required this.order, this.recall = false});
  final PosOrder order;
  final bool recall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final items = order.lines.fold<double>(0, (a, l) => a + l.qty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OfCard(
        onTap: () async {
          if (recall && !order.held) {
            order.held = false;
            await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
          }
          if (context.mounted) context.push('/order/${order.id}');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Column(
                children: [
                  Text(order.ticketNo.isEmpty ? '#' : '#${order.ticketNo}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  if (recall) StatusChip(s.t('held'), color: OfColors.warn),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName.isEmpty
                          ? '${items.toStringAsFixed(items % 1 == 0 ? 0 : 1)} ${s.t('items')}'
                          : order.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(s.t(order.status.name), style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              MoneyText(order.total, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fastfood bump board — the counter rhythm is New → Cooking → Ready → gone.
/// Big ticket numbers, one-tap bump buttons, live clock, exactly like the
/// queue screens on Square Quick / Toast Go; no table or course furniture.
class _QueueBoard extends ConsumerWidget {
  const _QueueBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final open = ref.snap.store.openOrders;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startOffsiteOrder(context, ref, OrderType.takeaway),
        icon: const Icon(Icons.confirmation_number),
        label: Text(s.t('new_order')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          if (open.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.confirmation_number,
                message: s.t('queue_empty'),
                action: () => startOffsiteOrder(context, ref, OrderType.takeaway),
                actionLabel: s.t('new_order'),
              ),
            )
          else
            Expanded(
              child: _FloorClock(
                builder: (now) {
                  final cols = <(OrderStatus, List<PosOrder>)>[
                    for (final st in [OrderStatus.open, OrderStatus.preparing, OrderStatus.ready])
                      (st, open.where((o) => o.status == st).toList()),
                  ];
                  if (isTablet(context)) {
                    return Row(
                      children: [
                        for (final c in cols)
                          Expanded(child: _QueueCol(status: c.$1, orders: c.$2, now: now)),
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                    children: [
                      for (final c in cols)
                        if (c.$2.isNotEmpty)
                          _QueueCol(status: c.$1, orders: c.$2, now: now, collapsed: true),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueCol extends ConsumerWidget {
  const _QueueCol({required this.status, required this.orders, required this.now, this.collapsed = false});
  final OrderStatus status;
  final List<PosOrder> orders;
  final DateTime now;
  final bool collapsed;

  Color get _accent => switch (status) {
        OrderStatus.open => OfColors.gold,
        OrderStatus.preparing => OfColors.warn,
        _ => OfColors.emerald,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(s.t(status.name), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const Spacer(),
          Text('${orders.length}', style: TextStyle(fontWeight: FontWeight.w900, color: _accent, fontSize: 15)),
        ],
      ),
    );
    final body = orders.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(child: Text('·', style: TextStyle(color: OfColors.mute(context), fontSize: 22))),
          )
        : ListView.separated(
            shrinkWrap: collapsed,
            physics: collapsed ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _QueueTicket(order: orders[i], now: now, status: status),
          );
    if (collapsed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, body]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const Divider(height: 1),
      Expanded(child: body),
    ]);
  }
}

class _QueueTicket extends ConsumerWidget {
  const _QueueTicket({required this.order, required this.now, required this.status});
  final PosOrder order;
  final DateTime now;
  final OrderStatus status;

  Future<void> _bump(WidgetRef ref, OrderStatus next) async {
    await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': order.id,
      'status': next.name,
    }));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final mins = now.difference(order.createdAt).inMinutes;
    final overdue = mins >= 12;
    final items = order.lines.fold<double>(0, (a, l) => a + l.qty);
    return OfCard(
      onTap: () => context.push('/order/${order.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(order.ticketNo, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                const Spacer(),
                Text(
                  '$mins min',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: overdue ? OfColors.danger : OfColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              order.customerName.isEmpty
                  ? '${items.toStringAsFixed(items % 1 == 0 ? 0 : 1)} ${s.t('items')}'
                  : '${order.customerName}  ·  ${items.toStringAsFixed(items % 1 == 0 ? 0 : 1)} ${s.t('items')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: OfColors.muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                MoneyText(order.total, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const Spacer(),
                if (status == OrderStatus.open)
                  FilledButton(onPressed: () => _bump(ref, OrderStatus.preparing), child: Text(s.t('mark_preparing'))),
                if (status == OrderStatus.preparing)
                  FilledButton(onPressed: () => _bump(ref, OrderStatus.ready), child: Text(s.t('mark_ready'))),
                if (status == OrderStatus.ready)
                  FilledButton.tonal(onPressed: () => _bump(ref, OrderStatus.served), child: Text(s.t('handed_over'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Services day board — appointment POS (Square Appointments / Vagaro) is a
/// day timeline with time slots, the booked service + duration, who's on it,
/// and one-tap Start / Finish — not a generic list.
class _AppointmentsBoard extends ConsumerStatefulWidget {
  const _AppointmentsBoard();

  @override
  ConsumerState<_AppointmentsBoard> createState() => _AppointmentsBoardState();
}

class _AppointmentsBoardState extends ConsumerState<_AppointmentsBoard> {
  bool onlyToday = true;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _dayLabel(DateTime d) {
    final s = ref.s;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = that.difference(today).inDays;
    if (diff == 0) return s.t('today');
    if (diff == 1) return s.t('tomorrow');
    if (diff == -1) return s.t('yesterday');
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final store = ref.snap.store;
    final now = DateTime.now();
    final all = [...store.appointments]..sort((a, b) => a.start.compareTo(b.start));
    final list = onlyToday
        ? all
            .where((a) =>
                a.start.year == now.year && a.start.month == now.month && a.start.day == now.day)
            .toList()
        : all
            .where((a) => a.status != 'done' || a.start.isAfter(now.subtract(const Duration(days: 2))))
            .toList();
    final groups = <DateTime, List<Appointment>>{};
    for (final a in list) {
      groups.putIfAbsent(DateTime(a.start.year, a.start.month, a.start.day), () => []).add(a);
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _book(context),
        icon: const Icon(Icons.event),
        label: Text(s.t('add_appointment')),
      ),
      body: Column(
        children: [
          const OffsiteOrderBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(s.t('today')),
                  selected: onlyToday,
                  onSelected: (_) => setState(() => onlyToday = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(s.t('filter_all')),
                  selected: !onlyToday,
                  onSelected: (_) => setState(() => onlyToday = false),
                ),
                const Spacer(),
                Text('${list.length}', style: const TextStyle(fontWeight: FontWeight.w900, color: OfColors.muted)),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? EmptyState(
                    icon: Icons.event_busy,
                    message: onlyToday ? s.t('no_appt_today') : s.t('no_appts'),
                    action: () => _book(context),
                    actionLabel: s.t('book'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      for (final e in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                          child: Text(_dayLabel(e.key),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                        for (final a in e.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ApptCard(appointment: a, time: _time),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _book(BuildContext context) async {
    final s = ref.s;
    final store = ref.snap.store;
    if (store.services.isEmpty || store.staff.isEmpty) return;
    var serviceId = store.services.first.id;
    var staffId = store.staff.first.id;
    final name = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    var start = DateTime.now().add(const Duration(minutes: 30));
    start = DateTime(start.year, start.month, start.day, start.hour, (start.minute ~/ 5) * 5);
    int slotFor(String id) {
      final svc = store.services.where((e) => e.id == id).firstOrNull;
      return svc?.durationMin ?? 30;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: s.t('customer'))),
                const SizedBox(height: 8),
                TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: serviceId,
                  items: store.services
                      .map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text('${e.name} · ${e.durationMin}m · ${moneyOf(ref.snap, e.price)}')))
                      .toList(),
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
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, color: OfColors.mint),
                  title: Text(s.t('start_time')),
                  subtitle: Text(
                    '${start.day}/${start.month}  ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
                    '  →  ${(start.add(Duration(minutes: slotFor(serviceId)))).hour.toString().padLeft(2, '0')}'
                    ':${(start.add(Duration(minutes: slotFor(serviceId)))).minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
                    );
                    if (time == null) return;
                    setSt(() => start = DateTime(
                        date.year, date.month, date.day, time.hour, (time.minute ~/ 5) * 5));
                  },
                ),
                TextField(controller: notes, decoration: InputDecoration(labelText: s.t('notes'))),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('book'))),
              ],
            ),
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
        start: start,
        notes: notes.text.trim(),
      );
      await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {'appointment': a.toJson()}));
    }
  }
}

class _ApptCard extends ConsumerWidget {
  const _ApptCard({required this.appointment, required this.time});
  final Appointment appointment;
  final String Function(DateTime) time;

  Future<void> _setStatus(WidgetRef ref, String next) async {
    appointment.status = next;
    await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {'appointment': appointment.toJson()}));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final store = ref.snap.store;
    final a = appointment;
    final svc = store.services.where((e) => e.id == a.serviceId).firstOrNull;
    final staff = store.staff.where((e) => e.id == a.staffId).firstOrNull;
    final end = a.start.add(Duration(minutes: svc?.durationMin ?? 30));
    final accent = switch (a.status) {
      'inProgress' => OfColors.warn,
      'done' => OfColors.emerald,
      _ => OfColors.info,
    };
    final late = a.status == 'booked' && a.start.isBefore(DateTime.now());
    return Opacity(
      opacity: a.status == 'done' ? 0.72 : 1,
      child: OfCard(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(time(a.start), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  Text(time(end), style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                  if (svc != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: StatusChip('${svc.durationMin}m', color: accent),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.customerName} · ${svc?.name ?? s.t('service_ticket')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        if (staff != null) '${s.t('staff')}: ${staff.name}',
                        if (svc != null) moneyOf(ref.snap, svc.price),
                        if (late) s.t('running_late'),
                      ].join('  ·  '),
                      style: TextStyle(color: late ? OfColors.danger : OfColors.muted, fontSize: 12),
                    ),
                    if (a.notes.trim().isNotEmpty)
                      Text(a.notes.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: OfColors.gold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (a.status == 'booked')
                FilledButton(
                  onPressed: () => _setStatus(ref, 'inProgress'),
                  child: Text(s.t('start')),
                )
              else if (a.status == 'inProgress')
                FilledButton(
                  onPressed: () => _setStatus(ref, 'done'),
                  child: Text(s.t('finish')),
                )
              else
                const Icon(Icons.check_circle, color: OfColors.emerald),
            ],
          ),
        ),
      ),
    );
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

class _FloorClock extends StatefulWidget {
  const _FloorClock({required this.builder});
  final Widget Function(DateTime now) builder;

  @override
  State<_FloorClock> createState() => _FloorClockState();
}

class _FloorClockState extends State<_FloorClock> {
  Timer? _t;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(now);
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
