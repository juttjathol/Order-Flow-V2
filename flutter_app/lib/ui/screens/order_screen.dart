import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/offsite_order.dart';

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final snap = ref.snap;
    final order = snap.store.orderById(widget.orderId);
    if (order == null) {
      return OfScaffold(
        title: s.t('ticket'),
        body: EmptyState(icon: Icons.receipt_long, message: s.t('no_orders')),
      );
    }
    final products = snap.store.products.where((p) {
      final query = q.trim().toLowerCase();
      return p.available &&
          (query.isEmpty ||
              p.name.toLowerCase().contains(query) ||
              p.sku.toLowerCase().contains(query));
    }).toList();
    final locked = order.status == OrderStatus.paid || order.status == OrderStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text('${order.ticketNo}  ${_typeLabel(s, order)}'),
        actions: [
          IconButton(
            tooltip: s.t('print_kitchen'),
            onPressed: () => _printKitchen(order),
            icon: const Icon(Icons.outdoor_grill),
          ),
          IconButton(
            tooltip: s.t('print_receipt'),
            onPressed: () => _printReceipt(order),
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: isTablet(context)
          ? Row(
              children: [
                Expanded(child: _catalog(products, order, locked)),
                SizedBox(width: 380, child: _ticket(order, locked)),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 3, child: _catalog(products, order, locked)),
                Expanded(flex: 2, child: _ticket(order, locked)),
              ],
            ),
    );
  }

  Widget _catalog(List<MenuProduct> products, PosOrder order, bool locked) {
    final s = ref.s;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            decoration: InputDecoration(hintText: s.t('sku_or_name'), prefixIcon: const Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCount(context, phone: 3, tablet: 4),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.78,
            ),
            itemCount: products.length,
            itemBuilder: (_, i) {
              final p = products[i];
              return OfCard(
                onTap: locked ? null : () => _add(order, p),
                child: Column(
                  children: [
                    ProductImage(p.imageBase64, size: 44),
                    const SizedBox(height: 4),
                    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    MoneyText(p.price, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ticket(PosOrder order, bool locked) {
    final s = ref.s;
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusChip(s.t(order.status.name), color: statusColor(order.status)),
                    const SizedBox(width: 8),
                    StatusChip(_typeLabel(s, order), color: order.type == OrderType.delivery ? OfColors.info : OfColors.mint),
                    const Spacer(),
                    MoneyText(order.total, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                if (order.type == OrderType.takeaway || order.type == OrderType.delivery)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(order.type == OrderType.delivery ? Icons.delivery_dining : Icons.takeout_dining, color: OfColors.emerald),
                    title: Text(order.customerName.isEmpty ? s.t('guest') : order.customerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([
                      if (order.customerPhone.isNotEmpty) order.customerPhone,
                      if (order.type == OrderType.delivery && order.address.isNotEmpty) order.address,
                      if (order.driverId != null)
                        ref.snap.store.driverById(order.driverId)?.name ?? s.t('assign_driver'),
                    ].join(' · ')),
                    trailing: locked
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => editOffsiteDetails(context, ref, order),
                          ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: order.lines.isEmpty
                ? EmptyState(icon: Icons.add_shopping_cart, message: s.t('add_items'))
                : ListView.builder(
                    itemCount: order.lines.length,
                    itemBuilder: (_, i) {
                      final line = order.lines[i];
                      return ListTile(
                        title: Text(line.name),
                        subtitle: Text(moneyOf(ref.snap, line.unitPrice)),
                        leading: locked
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => _qty(order, line, line.qty - 1),
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${line.qty % 1 == 0 ? line.qty.toInt() : line.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (!locked)
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => _qty(order, line, line.qty + 1),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                _kv(s.t('subtotal'), moneyOf(ref.snap, order.subtotal + order.discount)),
                if (order.discount > 0) _kv(s.t('discount'), '- ${moneyOf(ref.snap, order.discount)}'),
                if (order.tax > 0) _kv('${s.t('tax')} ${order.taxRate}%', moneyOf(ref.snap, order.tax)),
                _kv(s.t('total'), moneyOf(ref.snap, order.total), bold: true),
              ],
            ),
          ),
          if (!locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (order.status == OrderStatus.open)
                    FilledButton(onPressed: () => _status(order, OrderStatus.preparing), child: Text(s.t('send_kitchen'))),
                  if (order.status == OrderStatus.preparing)
                    FilledButton(onPressed: () => _status(order, OrderStatus.ready), child: Text(s.t('mark_ready'))),
                  if (order.status == OrderStatus.ready && order.type == OrderType.takeaway)
                    FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('mark_picked_up'))),
                  if (order.status == OrderStatus.ready && order.type == OrderType.delivery)
                    FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('out_for_delivery'))),
                  if (order.status == OrderStatus.ready && order.type != OrderType.takeaway && order.type != OrderType.delivery)
                    FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('mark_served'))),
                  FilledButton.tonal(onPressed: () => _pay(order), child: Text(s.t('pay_and_close'))),
                  OutlinedButton(
                    onPressed: () => confirm(
                      context,
                      title: s.t('cancel_order'),
                      body: s.t('confirm_cancel'),
                      onYes: () => _status(order, OrderStatus.cancelled),
                    ),
                    child: Text(s.t('cancel_order')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _typeLabel(dynamic s, PosOrder order) {
    if (order.tableName?.isNotEmpty == true && order.type == OrderType.dineIn) return order.tableName!;
    if (order.type == OrderType.dineIn) return s.t('dine_in');
    if (order.type == OrderType.takeaway) return s.t('takeaway');
    if (order.type == OrderType.delivery) return s.t('delivery');
    if (order.type == OrderType.retail) return s.t('retail_sale');
    return s.t('service_ticket');
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(k),
          const Spacer(),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _add(PosOrder order, MenuProduct p) async {
    final existing = order.lines.where((l) => l.productId == p.id && l.notes.isEmpty).firstOrNull;
    if (existing != null) {
      existing.qty += 1;
      await ref.ctrl.dispatch(NetCommand(name: 'updateLine', payload: {
        'orderId': order.id,
        'line': existing.toJson(),
      }));
      return;
    }
    final line = OrderLine(
      id: newId(),
      productId: p.id,
      name: p.name,
      unitPrice: p.price,
      inventoryId: p.inventoryId,
      deductQty: p.deductQty,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'addLine', payload: {
      'orderId': order.id,
      'line': line.toJson(),
    }));
  }

  Future<void> _qty(PosOrder order, OrderLine line, double qty) async {
    if (qty <= 0) {
      await ref.ctrl.dispatch(NetCommand(name: 'removeLine', payload: {
        'orderId': order.id,
        'lineId': line.id,
      }));
      return;
    }
    line.qty = qty;
    await ref.ctrl.dispatch(NetCommand(name: 'updateLine', payload: {
      'orderId': order.id,
      'line': line.toJson(),
    }));
  }

  Future<void> _status(PosOrder order, OrderStatus status) async {
    await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': order.id,
      'status': status.name,
    }));
  }

  Future<void> _pay(PosOrder order) async {
    final s = ref.s;
    PaymentMethod method = PaymentMethod.cash;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${s.t('payment')}  ${moneyOf(ref.snap, order.total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: PaymentMethod.values
                    .map((m) => ChoiceChip(
                          label: Text(s.t(m.name)),
                          selected: method == m,
                          onSelected: (_) => setSt(() => method = m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('pay_and_close'))),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
        'id': order.id,
        'status': OrderStatus.paid.name,
        'payment': method.name,
      }));
      try {
        await ref.ctrl.printer.receipt(ref.read(appControllerProvider).store, order);
      } catch (_) {}
    }
  }

  Future<void> _printKitchen(PosOrder order) async {
    final s = ref.s;
    try {
      await ref.ctrl.printer.kitchenTicket(ref.snap.store, order);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_ok'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_fail'))));
    }
  }

  Future<void> _printReceipt(PosOrder order) async {
    final s = ref.s;
    try {
      await ref.ctrl.printer.receipt(ref.snap.store, order);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_ok'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_fail'))));
    }
  }
}
