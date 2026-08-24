import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import 'common.dart';
import 'pin_gate.dart';

Future<void> applyDiscount(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  if (!await confirmManagerPin(context, ref)) return;
  final ctrl = TextEditingController(text: order.discount > 0 ? order.discount.toString() : '');
  var percent = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text(s.t('discount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: percent ? '%' : s.t('discount'))),
            SwitchListTile(value: percent, onChanged: (v) => setSt(() => percent = v), title: const Text('%')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final n = double.tryParse(ctrl.text) ?? 0;
  order.discount = percent ? (order.subtotal + order.discount) * (n / 100) : n;
  await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
}

Future<void> compTicket(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  if (!await confirmManagerPin(context, ref)) return;
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('comp_meal')),
      content: TextField(controller: reason, decoration: InputDecoration(labelText: s.t('void_reason'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('comp_meal'))),
      ],
    ),
  );
  if (ok != true) return;
  order.discount = order.subtotal + order.discount;
  order.notes = [order.notes, 'COMP ${reason.text.trim()}'].where((e) => e.isNotEmpty).join(' | ');
  await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
  await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
    'id': order.id,
    'status': OrderStatus.paid.name,
    'payment': PaymentMethod.complimentary.name,
  }));
}

Future<void> moveTicket(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  final tables = ref.snap.store.tables.where((t) => t.status == TableStatus.free || t.id == order.tableId).toList();
  if (tables.isEmpty) return;
  String? id = tables.first.id;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('move_table')),
      content: DropdownButtonFormField<String>(
        value: id,
        items: tables.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
        onChanged: (v) => id = v,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
      ],
    ),
  );
  if (ok == true && id != null) {
    await ref.ctrl.dispatch(NetCommand(name: 'moveOrder', payload: {'orderId': order.id, 'tableId': id}));
  }
}

Future<void> mergeTicket(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  final others = ref.snap.store.openOrders.where((o) => o.id != order.id).toList();
  if (others.isEmpty) return;
  String? drop = others.first.id;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('merge_table')),
      content: DropdownButtonFormField<String>(
        value: drop,
        items: others.map((o) => DropdownMenuItem(value: o.id, child: Text('${o.ticketNo} ${o.tableName ?? ''}'))).toList(),
        onChanged: (v) => drop = v,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('merge_table'))),
      ],
    ),
  );
  if (ok == true && drop != null) {
    await ref.ctrl.dispatch(NetCommand(name: 'mergeOrders', payload: {'keepId': order.id, 'dropId': drop}));
  }
}

Future<void> fireCourse(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  String course = 'starter';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('fire_course')),
      content: DropdownButtonFormField<String>(
        value: course,
        items: const ['starter', 'main', 'side', 'dessert', 'drink', '']
            .map((c) => DropdownMenuItem(value: c, child: Text(c.isEmpty ? 'All' : c)))
            .toList(),
        onChanged: (v) => course = v ?? course,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('fire_course'))),
      ],
    ),
  );
  if (ok == true) {
    await ref.ctrl.dispatch(NetCommand(name: 'fireCourse', payload: {'orderId': order.id, 'course': course}));
    try {
      await ref.ctrl.printer.kitchenTicket(ref.snap.store, order, role: ref.snap.session.role);
    } catch (_) {
      if (context.mounted) showPrintFailed(context, ref);
    }
  }
}

Future<void> eightySix(BuildContext context, WidgetRef ref, MenuProduct p) async {
  p.available = !p.available;
  await ref.ctrl.dispatch(NetCommand(name: 'upsertProduct', payload: {'product': p.toJson()}));
}

Future<void> reprintSearch(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final q = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final list = ref.snap.store.orders.where((o) {
          final t = q.text.trim().toLowerCase();
          if (t.isEmpty) return true;
          return o.ticketNo.toLowerCase().contains(t) || o.customerName.toLowerCase().contains(t) || (o.tableName ?? '').toLowerCase().contains(t);
        }).take(40).toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Text(s.t('reprint_any'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                TextField(controller: q, decoration: InputDecoration(hintText: s.t('search')), onChanged: (_) => setSt(() {})),
                Expanded(
                  child: ListView(
                    children: list
                        .map((o) => ListTile(
                              title: Text('${o.ticketNo}  ${o.tableName ?? o.customerName}'),
                              subtitle: Text(s.t(o.status.name)),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.outdoor_grill),
                                    onPressed: () async {
                                      try {
                                        await ref.ctrl.printer.kitchenTicket(ref.snap.store, o, role: ref.snap.session.role);
                                      } catch (_) {
                                        if (context.mounted) showPrintFailed(context, ref);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.print),
                                    onPressed: () async {
                                      try {
                                        await ref.ctrl.printer.receipt(ref.snap.store, o, role: ref.snap.session.role);
                                      } catch (_) {
                                        if (context.mounted) showPrintFailed(context, ref);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void showPrintFailed(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: OfColors.danger,
      title: Text(ref.s.t('print_failed_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      content: Text(ref.s.t('print_failed_body'), style: const TextStyle(color: Colors.white, fontSize: 16)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: Colors.white)))],
    ),
  );
}

Future<void> showSalesReports(BuildContext context, WidgetRef ref, {required bool zReport}) async {
  final s = ref.s;
  final store = ref.snap.store;
  final now = DateTime.now();
  final paid = store.orders.where((o) => o.status == OrderStatus.paid && o.updatedAt.year == now.year && o.updatedAt.month == now.month && o.updatedAt.day == now.day);
  final cash = paid.where((o) => o.payment == PaymentMethod.cash).fold<double>(0, (a, o) => a + o.total);
  final card = paid.where((o) => o.payment == PaymentMethod.card).fold<double>(0, (a, o) => a + o.total);
  final voids = store.orders.where((o) => o.status == OrderStatus.cancelled && o.updatedAt.year == now.year && o.updatedAt.month == now.month && o.updatedAt.day == now.day).toList();
  final hours = List.generate(24, (h) {
    final sum = paid.where((o) => o.updatedAt.hour == h).fold<double>(0, (a, o) => a + o.total);
    return MapEntry(h, sum);
  }).where((e) => e.value > 0).toList();
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(zReport ? s.t('z_report') : s.t('x_report'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            if (store.shiftCashier.isNotEmpty) Text('${s.t('shift')}: ${store.shiftCashier}'),
            ListTile(title: Text(s.t('today_sales')), trailing: Text(moneyOf(ref.snap, store.salesOn(now)))),
            ListTile(title: Text(s.t('cash')), trailing: Text(moneyOf(ref.snap, cash))),
            ListTile(title: Text(s.t('card')), trailing: Text(moneyOf(ref.snap, card))),
            Text(s.t('hourly_sales'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ...hours.map((e) => Text('${e.key.toString().padLeft(2, '0')}:00  ${moneyOf(ref.snap, e.value)}')),
            const SizedBox(height: 10),
            Text(s.t('void_report'), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (voids.isEmpty) Text(s.t('none'), style: const TextStyle(color: OfColors.muted)),
            ...voids.map((o) => Text('${o.ticketNo}  ${o.voidReason.isEmpty ? o.notes : o.voidReason}')),
          ],
        ),
      ),
    ),
  );
}

Future<void> startShift(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final store = ref.snap.store;
  if (store.shiftCashier.isNotEmpty) {
    final cash = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('end_shift')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${s.t('shift_open')}: ${store.shiftCashier}'),
            Text('${s.t('shift_float')}: ${moneyOf(ref.snap, store.shiftFloat)}'),
            TextField(
              controller: cash,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s.t('shift_end_cash')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('end_shift'))),
        ],
      ),
    );
    if (ok == true) {
      await ref.ctrl.dispatch(NetCommand(name: 'endShift', payload: {'endCash': double.tryParse(cash.text) ?? 0}));
    }
    return;
  }
  final name = TextEditingController(text: ref.snap.session.displayName);
  final float = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('start_shift')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('your_name'))),
          TextField(
            controller: float,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s.t('shift_float')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('start_shift'))),
      ],
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    await ref.ctrl.setDisplayName(name.text.trim());
    await ref.ctrl.dispatch(NetCommand(name: 'startShift', payload: {
      'name': name.text.trim(),
      'float': double.tryParse(float.text) ?? 0,
    }));
  }
}
