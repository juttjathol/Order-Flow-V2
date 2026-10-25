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

Future<void> evenSplit(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  var n = 2;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final each = n <= 0 ? 0.0 : order.total / n;
        return AlertDialog(
          title: Text(s.t('even_split')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: n,
                items: [2, 3, 4, 5, 6, 7, 8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                onChanged: (v) => setSt(() => n = v ?? 2),
              ),
              const SizedBox(height: 12),
              Text(moneyOf(ref.snap, each), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('ok'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
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
      await ref.ctrl.printKitchenTicket(order);
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
                                        await ref.ctrl.printKitchenTicket(o);
                                      } catch (_) {
                                        if (context.mounted) showPrintFailed(context, ref);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.print),
                                    onPressed: () async {
                                      try {
                                        await ref.ctrl.printCustomerReceipt(o);
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
  final today = store.orders.where((o) =>
      o.updatedAt.year == now.year && o.updatedAt.month == now.month && o.updatedAt.day == now.day);
  final paid = today.where((o) => o.status == OrderStatus.paid).toList();
  final voids = today.where((o) => o.status == OrderStatus.cancelled && o.voidReason != 'refund').toList();
  final refunds = today.where((o) => o.status == OrderStatus.cancelled && o.voidReason == 'refund').toList();
  final total = store.salesOn(now);
  final cash = paid.where((o) => o.payment == PaymentMethod.cash).fold<double>(0, (a, o) => a + o.total);
  final card = paid.where((o) => o.payment == PaymentMethod.card).fold<double>(0, (a, o) => a + o.total);
  final hours = List.generate(24, (h) {
    final sum = paid.where((o) => o.updatedAt.hour == h).fold<double>(0, (a, o) => a + o.total);
    return MapEntry(h, sum);
  }).where((e) => e.value > 0).toList();
  final maxHour = hours.isEmpty ? 1.0 : hours.map((e) => e.value).reduce((a, b) => a > b ? a : b);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: OfColors.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: (zReport ? OfColors.danger : OfColors.emerald).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(zReport ? Icons.summarize : Icons.receipt_long, color: zReport ? OfColors.danger : OfColors.emerald),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(zReport ? s.t('z_report') : s.t('x_report'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text(zReport ? s.t('z_report_sub') : s.t('x_report_sub'), style: const TextStyle(color: OfColors.muted, fontSize: 12)),
              ])),
              if (zReport) StatusChip('Z — closing', color: OfColors.danger) else StatusChip('X — safe', color: OfColors.emerald),
            ]),
            if (store.shiftCashier.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${s.t('shift')}: ${store.shiftCashier}', style: const TextStyle(color: OfColors.muted, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            OfCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('today_sales'), style: const TextStyle(color: OfColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(moneyOf(ref.snap, total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: OfColors.forest)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _miniStat('Cash', moneyOf(ref.snap, cash), Icons.payments, OfColors.emerald)),
                  const SizedBox(width: 12),
                  Expanded(child: _miniStat('Card', moneyOf(ref.snap, card), Icons.credit_card, OfColors.info)),
                  const SizedBox(width: 12),
                  Expanded(child: _miniStat('Tickets', '${paid.length}', Icons.receipt, OfColors.forest)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Text(s.t('payment_breakdown'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in PaymentMethod.values)
                Chip(
                  label: Text('${s.t(m.name)} · ${moneyOf(ref.snap, paid.fold<double>(0, (a, o) => a + o.paidBy(m)))}'),
                  backgroundColor: OfColors.creamSurface,
                  side: const BorderSide(color: OfColors.creamBorder),
                ),
            ]),
            const SizedBox(height: 16),
            Text(s.t('hourly_sales'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (hours.isEmpty)
              const Text('No sales yet today', style: TextStyle(color: OfColors.muted))
            else
              ...hours.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 52, child: Text('${e.key.toString().padLeft(2, '0')}:00', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (e.value / maxHour).clamp(0.0, 1.0), minHeight: 10, backgroundColor: OfColors.creamBorder, color: OfColors.emerald))),
                      const SizedBox(width: 8),
                      Text(moneyOf(ref.snap, e.value), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                  )),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OfCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('void_report'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                if (voids.isEmpty) const Text('None — clean day', style: TextStyle(color: OfColors.muted, fontSize: 12)),
                ...voids.take(6).map((o) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${o.ticketNo}  ${o.voidReason.isEmpty ? o.notes : o.voidReason}', style: const TextStyle(fontSize: 12)))),
                if (voids.length > 6) Text('+${voids.length - 6} more', style: const TextStyle(color: OfColors.muted, fontSize: 11)),
              ]))),
              const SizedBox(width: 12),
              Expanded(child: OfCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('refunds'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                if (refunds.isEmpty) const Text('None', style: TextStyle(color: OfColors.muted, fontSize: 12)),
                ...refunds.take(6).map((o) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${o.ticketNo}  ${moneyOf(ref.snap, o.total)}', style: const TextStyle(fontSize: 12)))),
                if (refunds.length > 6) Text('+${refunds.length - 6} more', style: const TextStyle(color: OfColors.muted, fontSize: 11)),
              ]))),
            ]),
            const SizedBox(height: 20),
            if (zReport) ...[
              SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.lock_clock), style: FilledButton.styleFrom(backgroundColor: OfColors.danger), label: Text(s.t('day_close')), onPressed: () async {
                    Navigator.pop(ctx);
                    await closeShopShift(context, ref);
                  })),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Print Z Report'), onPressed: () => Navigator.pop(ctx))),
            ] else ...[
              SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Print X Report'), onPressed: () => Navigator.pop(ctx))),
              const SizedBox(height: 6),
              const Center(child: Text('X does not close the day — check anytime', style: TextStyle(color: OfColors.muted, fontSize: 11))),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _miniStat(String label, String value, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.18))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: color)),
      Text(label, style: const TextStyle(color: OfColors.muted, fontSize: 11)),
    ]),
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

/// Shop-level shift lock (not the cashier float). Dispatch is silent when
/// denied, so every createOrder path must call this first.
Future<bool> ensureCanCreateOrder(BuildContext context, WidgetRef ref) async {
  if (!ref.read(appControllerProvider).store.shiftClosed) return true;
  final s = ref.s;
  final canOpen = ref.read(appControllerProvider).isMain ||
      ref.read(appControllerProvider).isManager;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('shift_closed_title')),
      content: Text(s.t('shift_closed_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        if (canOpen)
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('open_shop_shift'))),
      ],
    ),
  );
  if (go != true) return false;
  if (!await confirmManagerPin(context, ref)) return false;
  await ref.ctrl.dispatch(NetCommand(name: 'openShift', payload: {}));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('open_shop_shift_ok'))));
  }
  return !ref.read(appControllerProvider).store.shiftClosed;
}

Future<void> openShopShift(BuildContext context, WidgetRef ref) async {
  if (!ref.read(appControllerProvider).store.shiftClosed) return;
  final s = ref.s;
  if (!await confirmManagerPin(context, ref)) return;
  await ref.ctrl.dispatch(NetCommand(name: 'openShift', payload: {}));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('open_shop_shift_ok'))));
  }
}

Future<void> closeShopShift(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final store = ref.snap.store;
  final today = store.salesOn(DateTime.now());
  final paid = store.orders.where((o) => o.status == OrderStatus.paid).where((o) {
    final d = DateTime.now();
    return o.updatedAt.year == d.year && o.updatedAt.month == d.month && o.updatedAt.day == d.day;
  });
  final cash = paid.where((o) => o.payment == PaymentMethod.cash).fold<double>(0, (a, o) => a + o.total);
  final card = paid.where((o) => o.payment == PaymentMethod.card).fold<double>(0, (a, o) => a + o.total);
  final open = store.openOrders.length;
  final last = store.lastDayClose;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('day_close')),
      content: Text(
        '${s.t('day_close_open')}\n\n'
        '${s.t('today_sales')}: ${moneyOf(ref.snap, today)}\n'
        '${s.t('cash')}: ${moneyOf(ref.snap, cash)}\n'
        '${s.t('card')}: ${moneyOf(ref.snap, card)}\n'
        '${s.t('open_orders')}: $open'
        '${last == null ? '' : '\n${s.t('last_close')}: $last'}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('day_close'))),
      ],
    ),
  );
  if (ok == true) {
    await ref.ctrl.dispatch(NetCommand(name: 'closeDay', payload: {}));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('day_close_ok'))));
    }
  }
}
