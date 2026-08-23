import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/barcode_scan.dart';
import '../widgets/common.dart';
import '../widgets/offsite_order.dart';
import '../widgets/pin_gate.dart';
import '../widgets/pos_ops.dart';

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  String q = '';
  String? catId;
  int phoneTab = 0;

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
      final catOk = catId == null || p.categoryId == catId;
      return catOk &&
          (query.isEmpty ||
              p.name.toLowerCase().contains(query) ||
              p.sku.toLowerCase().contains(query));
    }).toList();
    final role = snap.session.role;
    final kitchenOnly = role == AppRole.kitchen;
    final canPay = role == AppRole.main || role == AppRole.cashier;
    final canEdit = role == AppRole.main ||
        role == AppRole.orderTaker ||
        role == AppRole.cashier ||
        role == AppRole.frontDesk;
    final closed = order.status == OrderStatus.paid || order.status == OrderStatus.cancelled;
    final locked = closed || !canEdit;

    return Scaffold(
      appBar: AppBar(
        title: Text('${order.ticketNo}  ${_typeLabel(s, order)}'),
        actions: [
          if (!locked)
            IconButton(
              tooltip: s.t('scan_sku'),
              onPressed: () => _scanSku(order),
              icon: const Icon(Icons.qr_code_scanner),
            ),
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
      body: kitchenOnly
          ? _ticket(order, closed, kitchenOnly: true, canPay: false)
          : isTablet(context)
              ? Row(
                  children: [
                    SizedBox(width: 200, child: _categories()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _catalog(products, order, locked, hideCats: true)),
                    SizedBox(width: 420, child: _ticket(order, closed, canPay: canPay)),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 0, label: Text(s.t('menu')), icon: const Icon(Icons.restaurant_menu)),
                          ButtonSegment(value: 1, label: Text(s.t('ticket')), icon: const Icon(Icons.receipt_long)),
                        ],
                        selected: {phoneTab},
                        onSelectionChanged: (v) => setState(() => phoneTab = v.first),
                      ),
                    ),
                    Expanded(
                      child: phoneTab == 0
                          ? _catalog(products, order, locked)
                          : _ticket(order, closed, canPay: canPay),
                    ),
                  ],
                ),
    );
  }

  Widget _categories() {
    final s = ref.s;
    final cats = [...ref.snap.store.categories]..sort((a, b) => a.sort.compareTo(b.sort));
    return Material(
      color: Theme.of(context).cardColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(s.t('menu'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          _catTile(s.t('all'), null),
          ...cats.map((c) => _catTile(c.name, c.id)),
        ],
      ),
    );
  }

  Widget _catTile(String label, String? id) {
    final on = catId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: on,
        selectedTileColor: OfColors.mint.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600, fontSize: 15)),
        onTap: () => setState(() => catId = id),
      ),
    );
  }

  Widget _catalog(List<MenuProduct> products, PosOrder order, bool locked, {bool hideCats = false}) {
    final s = ref.s;
    final cats = [...ref.snap.store.categories]..sort((a, b) => a.sort.compareTo(b.sort));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: s.t('sku_or_name'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: locked
                  ? null
                  : IconButton(
                      tooltip: s.t('scan_sku'),
                      onPressed: () => _scanSku(order),
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
            ),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        if (!hideCats)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(s.t('all')), selected: catId == null, onSelected: (_) => setState(() => catId = null)),
                ),
                ...cats.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(c.name), selected: catId == c.id, onSelected: (_) => setState(() => catId = c.id)),
                    )),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(18),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCount(context, phone: 2, tablet: 3),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: products.length,
            itemBuilder: (_, i) {
              final p = products[i];
              return OfCard(
                padding: const EdgeInsets.all(8),
                onTap: locked || !p.available ? null : () => _add(order, p),
                onLongPress: () => eightySix(context, ref, p),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: ProductImage(p.imageBase64, size: 72)),
                          if (!p.available) Align(alignment: Alignment.topRight, child: StatusChip('86', color: OfColors.danger)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    MoneyText(p.price, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ticket(PosOrder order, bool locked, {bool kitchenOnly = false, bool canPay = true}) {
    final s = ref.s;
    return Material(
      color: OfColors.isDark(context) ? OfColors.cardDark : const Color(0xFFFFFBF4),
      elevation: 8,
      shadowColor: const Color(0x220B3D2E),
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
                    if (order.held) ...[
                      const SizedBox(width: 8),
                      StatusChip(s.t('held'), color: OfColors.warn),
                    ],
                    const Spacer(),
                    MoneyText(order.total, style: const TextStyle(fontSize: 22)),
                  ],
                ),
                if (order.createdBy.isNotEmpty)
                  Text('${s.t('station')}: ${order.createdBy}', style: const TextStyle(color: OfColors.muted, fontSize: 12)),
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    itemCount: order.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final line = order.lines[i];
                      final qty = line.qty % 1 == 0 ? line.qty.toInt().toString() : line.qty.toString();
                      return InkWell(
                        onTap: locked ? null : () => _noteLine(order, line),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              if (!locked)
                                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => _qty(order, line, line.qty - 1)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                      StatusChip(s.t('course_${line.course}'), color: OfColors.mint),
                                      Text(moneyOf(ref.snap, line.unitPrice), style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                                    ]),
                                    if (line.notes.isNotEmpty) Text(line.notes, style: const TextStyle(color: OfColors.gold, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(qty, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              if (!locked)
                                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () => _qty(order, line, line.qty + 1)),
                              MoneyText(line.unitPrice * line.qty, style: const TextStyle(fontSize: 14)),
                            ],
                          ),
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
                if (order.service > 0) _kv('${s.t('service_charge')} ${order.serviceRate}%', moneyOf(ref.snap, order.service)),
                if (order.tax > 0) _kv('${s.t('tax')} ${order.taxRate}%', moneyOf(ref.snap, order.tax)),
                if (order.tip > 0) _kv(s.t('tip'), moneyOf(ref.snap, order.tip)),
                _kv(s.t('total'), moneyOf(ref.snap, order.total), bold: true),
              ],
            ),
          ),
          if (!locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: kitchenOnly
                  ? Row(children: [
                      if (order.status == OrderStatus.open)
                        Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.preparing), child: Text(s.t('mark_preparing')))),
                      if (order.status == OrderStatus.preparing)
                        Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.ready), child: Text(s.t('mark_ready')))),
                      if (order.status == OrderStatus.ready)
                        Expanded(child: FilledButton.tonal(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('mark_served')))),
                    ])
                  : Row(
                      children: [
                        OutlinedButton(onPressed: () => _moreOps(order, canPay), child: Text(s.t('more'))),
                        const SizedBox(width: 8),
                        if (order.status == OrderStatus.open && !order.held)
                          Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.preparing), child: Text(s.t('send_kitchen')))),
                        if (order.status == OrderStatus.preparing && canPay)
                          Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.ready), child: Text(s.t('mark_ready')))),
                        if (order.status == OrderStatus.ready && order.type == OrderType.takeaway)
                          Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('mark_picked_up')))),
                        if (order.status == OrderStatus.ready && order.type == OrderType.delivery)
                          Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('out_for_delivery')))),
                        if (order.status == OrderStatus.ready &&
                            order.type != OrderType.takeaway &&
                            order.type != OrderType.delivery)
                          Expanded(child: FilledButton(onPressed: () => _status(order, OrderStatus.served), child: Text(s.t('mark_served')))),
                        if (canPay) ...[
                          const SizedBox(width: 8),
                          Expanded(child: FilledButton.tonal(onPressed: () => _pay(order), child: Text(s.t('pay')))),
                        ],
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

  String _guessCourse(MenuProduct p) {
    if (p.course.isNotEmpty && p.course != 'main') return p.course;
    final cat = ref.snap.store.categories.where((c) => c.id == p.categoryId).firstOrNull?.name.toLowerCase() ?? '';
    if (cat.contains('start') || cat.contains('soup')) return 'starter';
    if (cat.contains('drink') || cat.contains('bever') || cat.contains('cola')) return 'drink';
    if (cat.contains('dessert') || cat.contains('sweet')) return 'dessert';
    if (cat.contains('side') || cat.contains('bread')) return 'side';
    return 'main';
  }

  Future<void> _scanSku(PosOrder order) async {
    final s = ref.s;
    final code = await scanBarcode(context, title: s.t('scan_sku'), hint: s.t('scan_sku_hint'));
    if (code == null || !mounted) return;
    final product = productBySku(ref.snap.store, code);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.t('sku_not_found')}: $code')));
      return;
    }
    if (!product.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('unavailable'))));
      return;
    }
    final qty = await askScanQty(context, title: '${product.name}  ${product.sku}');
    if (qty == null || !mounted) return;
    await _add(order, product, qty: qty);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} × $qty')));
    }
  }

  Future<bool> _stockOk(MenuProduct p) async {
    final invId = p.inventoryId;
    if (invId == null) return true;
    final item = ref.snap.store.stockById(invId);
    if (item == null || item.quantity > 0) return true;
    final s = ref.s;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('stock_out_block')),
        content: Text(p.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('stock_override'))),
        ],
      ),
    );
    if (go != true) return false;
    return confirmManagerPin(context, ref);
  }

  Future<void> _add(PosOrder order, MenuProduct p) async {
    if (!await _stockOk(p)) return;
    HapticFeedback.lightImpact();
    var name = p.name;
    var price = p.price;
    var note = '';
    if (p.mods.isNotEmpty) {
      final picked = await _pickMods(p);
      if (picked == null) return;
      if (picked.isNotEmpty) {
        name = '$name · ${picked.map((m) => m.name).join(', ')}';
        price += picked.fold<double>(0, (s, m) => s + m.price);
        note = picked.map((m) => m.name).join(', ');
      }
    } else {
      final existing = order.lines.where((l) => l.productId == p.id && l.notes.isEmpty).firstOrNull;
      if (existing != null) {
        existing.qty += qty;
        await ref.ctrl.dispatch(NetCommand(name: 'updateLine', payload: {
          'orderId': order.id,
          'line': existing.toJson(),
        }));
        return;
      }
    }
    final same = order.lines.where((l) => l.productId == p.id && l.notes == note && l.unitPrice == price).firstOrNull;
    if (same != null) {
      same.qty += qty;
      await ref.ctrl.dispatch(NetCommand(name: 'updateLine', payload: {
        'orderId': order.id,
        'line': same.toJson(),
      }));
      return;
    }
    final line = OrderLine(
      id: newId(),
      productId: p.id,
      name: name,
      unitPrice: price,
      qty: qty,
      notes: note,
      inventoryId: p.inventoryId,
      deductQty: p.deductQty,
      course: _guessCourse(p),
    );
    await ref.ctrl.dispatch(NetCommand(name: 'addLine', payload: {
      'orderId': order.id,
      'line': line.toJson(),
    }));
  }

  Future<List<ItemMod>?> _pickMods(MenuProduct p) async {
    final s = ref.s;
    final chosen = <String, ItemMod>{};
    final extras = <String>{};
    for (final g in ['size', 'spice']) {
      final first = p.mods.where((m) => m.group == g).firstOrNull;
      if (first != null) chosen[g] = first;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          double extra = chosen.values.fold<double>(0, (a, m) => a + m.price) +
              p.mods.where((m) => extras.contains(m.id)).fold<double>(0, (a, m) => a + m.price);
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(moneyOf(ref.snap, p.price + extra), style: const TextStyle(fontWeight: FontWeight.w800)),
                  for (final g in ['size', 'spice'])
                    if (p.mods.any((m) => m.group == g)) ...[
                      const SizedBox(height: 10),
                      Text(s.t('mod_$g'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Wrap(
                        spacing: 8,
                        children: p.mods.where((m) => m.group == g).map((m) => ChoiceChip(
                              label: Text('${m.name}${m.price == 0 ? '' : ' +${m.price}'}'),
                              selected: chosen[g]?.id == m.id,
                              onSelected: (_) => setSt(() => chosen[g] = m),
                            )).toList(),
                      ),
                    ],
                  if (p.mods.any((m) => m.group == 'extra')) ...[
                    const SizedBox(height: 10),
                    Text(s.t('mod_extra'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ...p.mods.where((m) => m.group == 'extra').map((m) => CheckboxListTile(
                          dense: true,
                          value: extras.contains(m.id),
                          title: Text('${m.name}${m.price == 0 ? '' : '  +${moneyOf(ref.snap, m.price)}'}'),
                          onChanged: (v) => setSt(() {
                            if (v == true) {
                              extras.add(m.id);
                            } else {
                              extras.remove(m.id);
                            }
                          }),
                        )),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('add'))),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (ok != true) return null;
    return [
      ...chosen.values,
      ...p.mods.where((m) => extras.contains(m.id)),
    ];
  }

  Future<void> _qty(PosOrder order, OrderLine line, double qty) async {
    if (qty <= 0) {
      final reason = await _askVoid();
      if (reason == null) return;
      order.notes = [order.notes, 'VOID ${line.name}: $reason'].where((e) => e.isNotEmpty).join(' | ');
      await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
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

  Future<void> _toggleHold(PosOrder order) async {
    order.held = !order.held;
    await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
  }

  Future<void> _split(PosOrder order) async {
    final s = ref.s;
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('split_bill'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ...order.lines.map((l) => CheckboxListTile(
                    value: picked.contains(l.id),
                    title: Text('${l.qty.toStringAsFixed(l.qty % 1 == 0 ? 0 : 1)}  ${l.name}'),
                    onChanged: (v) => setSt(() {
                      if (v == true) {
                        picked.add(l.id);
                      } else {
                        picked.remove(l.id);
                      }
                    }),
                  )),
              FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(s.t('split_pay'))),
            ],
          ),
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    final move = order.lines.where((l) => picked.contains(l.id)).toList();
    final child = PosOrder(
      id: newId(),
      ticketNo: '',
      type: order.type,
      tableId: order.tableId,
      tableName: order.tableName,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      address: order.address,
      taxRate: order.taxRate,
      lines: move.map((l) => OrderLine(
            id: newId(),
            productId: l.productId,
            name: l.name,
            unitPrice: l.unitPrice,
            qty: l.qty,
            notes: l.notes,
            inventoryId: l.inventoryId,
            deductQty: l.deductQty,
          )).toList(),
      createdBy: ref.snap.session.displayName,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': child.toJson()}));
    for (final l in move) {
      await ref.ctrl.dispatch(NetCommand(name: 'removeLine', payload: {'orderId': order.id, 'lineId': l.id}));
    }
    if (mounted) _pay(child);
  }

  Future<void> _status(PosOrder order, OrderStatus status) async {
    await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': order.id,
      'status': status.name,
    }));
  }

  Future<void> _noteLine(PosOrder order, OrderLine line) async {
    final s = ref.s;
    final c = TextEditingController(text: line.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('line_notes')),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: s.t('notes'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    line.notes = c.text.trim();
    await ref.ctrl.dispatch(NetCommand(name: 'updateLine', payload: {'orderId': order.id, 'line': line.toJson()}));
  }

  Future<void> _moreOps(PosOrder order, bool canPay) async {
    final s = ref.s;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(order.held ? s.t('unhold') : s.t('hold')), leading: const Icon(Icons.pause_circle), onTap: () { Navigator.pop(ctx); _toggleHold(order); }),
            if (canPay) ListTile(title: Text(s.t('split_bill')), leading: const Icon(Icons.call_split), onTap: () { Navigator.pop(ctx); _split(order); }),
            if (canPay) ListTile(title: Text(s.t('discount')), leading: const Icon(Icons.percent), onTap: () { Navigator.pop(ctx); applyDiscount(context, ref, order); }),
            if (canPay) ListTile(title: Text(s.t('comp_meal')), leading: const Icon(Icons.card_giftcard), onTap: () { Navigator.pop(ctx); compTicket(context, ref, order); }),
            ListTile(title: Text(s.t('move_table')), leading: const Icon(Icons.swap_horiz), onTap: () { Navigator.pop(ctx); moveTicket(context, ref, order); }),
            ListTile(title: Text(s.t('merge_table')), leading: const Icon(Icons.merge_type), onTap: () { Navigator.pop(ctx); mergeTicket(context, ref, order); }),
            ListTile(title: Text(s.t('fire_course')), leading: const Icon(Icons.local_fire_department), onTap: () { Navigator.pop(ctx); fireCourse(context, ref, order); }),
            ListTile(title: Text(s.t('cancel_order')), leading: const Icon(Icons.cancel, color: OfColors.danger), onTap: () { Navigator.pop(ctx); _voidOrder(order); }),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(PosOrder order) async {
    final s = ref.s;
    PaymentMethod method = PaymentMethod.cash;
    var tender = '';
    var tip = order.tip;
    final base = order.subtotal + order.service + order.tax;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final due = base + tip;
          final received = double.tryParse(tender) ?? 0;
          final change = received - due;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.t('payment')}  ${moneyOf(ref.snap, due)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: PaymentMethod.values
                      .map((m) => ChoiceChip(label: Text(s.t(m.name)), selected: method == m, onSelected: (_) => setSt(() => method = m)))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(s.t('tip'), style: const TextStyle(color: OfColors.muted))),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in [0, 5, 10, 15])
                      ChoiceChip(
                        label: Text(p == 0 ? s.t('tip_none') : '$p%'),
                        selected: (base <= 0 && tip == 0 && p == 0) ||
                            (base > 0 && (tip - base * p / 100).abs() < 0.02) ||
                            (p == 0 && tip == 0),
                        onSelected: (_) => setSt(() => tip = base * p / 100),
                      ),
                  ],
                ),
                if (method == PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text(s.t('tendered'), style: const TextStyle(color: OfColors.muted))),
                  Text(tender.isEmpty ? '0' : tender, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28)),
                  if (received >= due) Text('${s.t('change_due')}  ${moneyOf(ref.snap, change)}', style: const TextStyle(color: OfColors.mint, fontWeight: FontWeight.w800)),
                  if (tender.isNotEmpty && received < due) Text(s.t('cash_short'), style: const TextStyle(color: OfColors.danger, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'])
                        SizedBox(
                          width: 72,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => setSt(() {
                              if (d == '⌫') {
                                if (tender.isNotEmpty) tender = tender.substring(0, tender.length - 1);
                              } else if (!(d == '.' && tender.contains('.'))) {
                                tender += d;
                              }
                            }),
                            child: Text(d, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      FilledButton.tonal(
                        onPressed: () => setSt(() => tender = due.toStringAsFixed(due % 1 == 0 ? 0 : 2)),
                        child: Text(s.t('exact')),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: method == PaymentMethod.cash && received + 0.001 < due ? null : () => Navigator.pop(ctx, true),
                  child: Text(s.t('pay_and_close')),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok == true) {
      await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
        'id': order.id,
        'status': OrderStatus.paid.name,
        'payment': method.name,
      }));
      ref.ctrl.rememberReceipt(order.id);
      try {
        await ref.ctrl.printer.receipt(ref.read(appControllerProvider).store, order);
      } catch (_) {}
    }
  }

  Future<String?> _askVoid() async {
    final s = ref.s;
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(s.t('void_reason'), style: const TextStyle(fontWeight: FontWeight.w800))),
            ListTile(title: Text(s.t('void_wrong')), onTap: () => Navigator.pop(ctx, s.t('void_wrong'))),
            ListTile(title: Text(s.t('void_left')), onTap: () => Navigator.pop(ctx, s.t('void_left'))),
            ListTile(title: Text(s.t('void_other')), onTap: () => Navigator.pop(ctx, s.t('void_other'))),
          ],
        ),
      ),
    );
  }

  Future<void> _voidOrder(PosOrder order) async {
    final reason = await _askVoid();
    if (reason == null) return;
    order.notes = [order.notes, 'VOID: $reason'].where((e) => e.isNotEmpty).join(' | ');
    await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
    await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': order.id,
      'status': OrderStatus.cancelled.name,
    }));
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
