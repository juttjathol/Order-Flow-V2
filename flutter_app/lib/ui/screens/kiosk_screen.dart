import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/stock_engine.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';

/// Wall-mounted self-order kiosk (rides the QR ordering add-on).
/// Guests build a ticket and send it straight to the kitchen; staff confirm
/// and take payment at the counter. Exiting the kiosk needs the manager PIN.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  final Map<String, double> _cart = {}; // productId → qty
  final TextEditingController _name = TextEditingController();
  String? _catId;
  bool _sent = false;

  Future<void> _exit() async {
    // Guests must never wander into the staff shell — manager PIN only.
    final ok = await confirmManagerPin(context, ref);
    if (ok && mounted) Navigator.of(context).pop();
  }

  double get _total {
    final store = ref.snap.store;
    double t = 0;
    _cart.forEach((pid, qty) {
      for (final p in store.products) {
        if (p.id == pid) {
          t += p.price * qty;
          return;
        }
      }
    });
    return t;
  }

  Future<void> _send() async {
    final s = ref.s;
    final store = ref.snap.store;
    if (_cart.isEmpty) return;
    final lines = <OrderLine>[];
    _cart.forEach((pid, qty) {
      MenuProduct? p;
      for (final e in store.products) {
        if (e.id == pid) p = e;
      }
      if (p == null) return;
      lines.add(OrderLine(
        id: newId(),
        productId: p!.id,
        name: p.name,
        unitPrice: p.price,
        qty: qty,
        inventoryId: p.inventoryId,
        deductQty: p.deductQty,
      ));
    });
    if (lines.isEmpty) return;
    final order = PosOrder(
      id: newId(),
      ticketNo: '',
      type: OrderType.takeaway,
      status: OrderStatus.open,
      tableName: 'KIOSK',
      customerName: _name.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      channel: 'kiosk',
      lines: lines,
      createdBy: 'kiosk',
    );
    await ref.ctrl
        .dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
    await ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': order.id,
      'status': OrderStatus.preparing.name,
    }));
    if (!mounted) return;
    setState(() {
      _cart.clear();
      _name.clear();
      _sent = true;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.t('kiosk_sent'))));
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _sent = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final store = ref.snap.store;
    final products = store.products
        .where((p) => p.available)
        .where((p) => _catId == null || p.categoryId == _catId)
        .toList();
    final cats = store.categories;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              const Icon(Icons.storefront),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  store.profile.businessName.isEmpty
                      ? s.t('kiosk_title')
                      : store.profile.businessName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: s.t('exit_kiosk'),
              icon: const Icon(Icons.lock_outline),
              onPressed: _exit,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_sent)
              Container(
                width: double.infinity,
                color: OfColors.emerald.withValues(alpha: 0.12),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Text(s.t('kiosk_thanks'),
                    style: const TextStyle(
                        color: OfColors.emerald, fontWeight: FontWeight.w800)),
              ),
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.t('all')),
                      selected: _catId == null,
                      onSelected: (_) => setState(() => _catId = null),
                    ),
                  ),
                  ...cats.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.name),
                          selected: _catId == c.id,
                          onSelected: (_) => setState(() => _catId = c.id),
                        ),
                      )),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridCount(context, phone: 2, tablet: 4),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  final qty = _cart[p.id] ?? 0;
                  final badge = StockEngine.badgeCount(p, store);
                  return OfCard(
                    padding: const EdgeInsets.all(10),
                    onTap: () => setState(
                        () => _cart[p.id] = qty + 1),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(
                                  child: ProductImage(p.imageBase64, size: 64)),
                              if (badge != null)
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badge == 0
                                          ? OfColors.danger.withValues(alpha: 0.14)
                                          : Colors.orange.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      badge == 0
                                          ? (s.isUrdu ? 'ختم' : 'none left')
                                          : (s.isUrdu ? '$badge باقی' : '$badge left'),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: badge == 0
                                            ? OfColors.danger
                                            : Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                ),
                              if (qty > 0)
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: OfColors.forest,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text('×${_fmt(qty)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (p.nameUr.isNotEmpty)
                          Text(p.nameUr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: OfColors.muted)),
                        const SizedBox(height: 4),
                        Text(moneyOf(ref.snap, p.price),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: OfColors.forest)),
                        if (qty > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _stepper(Icons.remove, () {
                                  setState(() {
                                    if (qty <= 1) {
                                      _cart.remove(p.id);
                                    } else {
                                      _cart[p.id] = qty - 1;
                                    }
                                  });
                                }),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(_fmt(qty),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                ),
                                _stepper(Icons.add, () =>
                                    setState(() => _cart[p.id] = qty + 1)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: const Border(
                      top: BorderSide(color: OfColors.creamBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.person_outline),
                          hintText: s.t('kiosk_name_hint'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: OfColors.forest,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      icon: const Icon(Icons.send),
                      onPressed: _cart.isEmpty ? null : _send,
                      label: Text(
                        _cart.isEmpty
                            ? s.t('kiosk_send')
                            : '${s.t('kiosk_send')} · ${moneyOf(ref.snap, _total)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper(IconData icon, VoidCallback onTap) {
    return Material(
      color: OfColors.forest.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: OfColors.forest),
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
