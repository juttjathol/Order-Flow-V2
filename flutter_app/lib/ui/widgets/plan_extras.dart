// v1.1.59 "Growth" extras — QR ordering, recipe costing, wastage log,
// suppliers & purchase orders, and insights. Every sheet here is additive:
// it only dispatches new store commands and never touches existing flows.
// Each entry point in More is wrapped by planAwareRow (plan_lock.dart).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import 'common.dart';

Future<void> _sheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.82,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

Widget _title(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
    );

// ─────────────────────────────── QR ordering ───────────────────────────────

Future<void> showQrOrdering(BuildContext context, WidgetRef ref) async {
  final snap = ref.snap;
  final ctrl = ref.read(appControllerProvider.notifier);
  final store = snap.store;
  final ip = snap.lanIp ?? '';
  final url = ip.isEmpty ? '' : 'http://$ip:$kLanPort/order';
  await _sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(snap.l10n.t('qr_ordering')),
        Text(snap.l10n.t('qr_ordering_hint'),
            style: const TextStyle(color: OfColors.muted, height: 1.45)),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: store.qrOrderOn,
          onChanged: (v) => ctrl.setQrOrdering(v),
          title: Text(snap.l10n.t('qr_enable')),
        ),
        const SizedBox(height: 6),
        if (!store.qrOrderOn)
          Text(snap.l10n.t('qr_off_note'),
              style: const TextStyle(color: OfColors.muted, fontSize: 12))
        else ...[
          if (url.isEmpty)
            Text(snap.l10n.t('qr_need_wifi'),
                style: const TextStyle(color: OfColors.warn))
          else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(data: url, size: 210, version: QrVersions.auto),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(snap.l10n.t('qr_same_wifi'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: OfColors.muted, fontSize: 12)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(snap.l10n.t('link_copied'))));
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(snap.l10n.t('copy_link')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Share.share(url),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(snap.l10n.t('share_link')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(snap.l10n.t('qr_tables_note'),
                style: const TextStyle(color: OfColors.muted, fontSize: 12)),
          ],
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(snap.l10n.t('done')),
        ),
      ],
    ),
  );
}

/// Per-table QR (from the floor screen long-press menu).
Future<void> showTableQr(BuildContext context, WidgetRef ref, FloorTable t) async {
  final snap = ref.snap;
  final ip = snap.lanIp ?? '';
  if (ip.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snap.l10n.t('qr_need_wifi'))));
    return;
  }
  final url =
      'http://$ip:$kLanPort/order?table=${Uri.encodeComponent(t.id)}&name=${Uri.encodeComponent(t.name)}';
  await _sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('${snap.l10n.t('qr_table_title')} · ${t.name}'),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(data: url, size: 230, version: QrVersions.auto),
          ),
        ),
        const SizedBox(height: 10),
        SelectableText(url,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(snap.l10n.t('qr_table_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: OfColors.muted, fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(snap.l10n.t('link_copied'))));
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(snap.l10n.t('copy_link')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Share.share(
                    '${snap.l10n.t('qr_share_body')}\n${snap.store.profile.businessName} — ${snap.l10n.t('qr_table_title')} ${t.name}\n$url'),
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(snap.l10n.t('share_link')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

// ────────────────────────────── Recipe costing ──────────────────────────────

Future<void> showRecipesMargin(BuildContext context, WidgetRef ref) async {
  final store = ref.snap.store;
  await _sheet(
    context,
    Builder(
      builder: (ctx) {
        final st = ref.snap.store;
        final rows = st.products.toList()
          ..sort((a, b) {
            final pa = a.price > 0 ? (a.price - st.productCost(a)) / a.price : 0.0;
            final pb = b.price > 0 ? (b.price - st.productCost(b)) / b.price : 0.0;
            return pb.compareTo(pa);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(ref.snap.l10n.t('recipes')),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(ref.snap.l10n.t('recipes_hint'),
                  style: const TextStyle(color: OfColors.muted, height: 1.4)),
            ),
            if (st.stock.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(ref.snap.l10n.t('recipes_need_stock'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: OfColors.muted)),
              ),
            for (final p in rows) _recipeRow(context, ref, st, p),
            const SizedBox(height: 10),
          ],
        );
      },
    ),
  );
}

Widget _recipeRow(BuildContext context, WidgetRef ref, AppStore st, MenuProduct p) {
  final cost = st.productCost(p);
  final profit = p.price - cost;
  final pct = p.price > 0 ? (profit / p.price * 100) : 0.0;
  final low = p.price > 0 && pct < 25;
  return OfCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        '${ref.snap.l10n.t('cost')} ${moneyOf(ref.snap, cost)}  ·  '
        '${ref.snap.l10n.t('profit')} ${moneyOf(ref.snap, profit)}',
        style: TextStyle(
            fontSize: 12, color: low ? OfColors.danger : OfColors.muted),
      ),
      trailing: Text('${pct.toStringAsFixed(0)}%',
          style: TextStyle(
              fontWeight: FontWeight.w900, color: low ? OfColors.danger : OfColors.mint)),
      onTap: () => _editRecipe(context, ref, p),
    ),
  );
}

Future<void> _editRecipe(BuildContext context, WidgetRef ref, MenuProduct p) async {
  final snap = ref.snap;
  final lines = <RecipeLine>[
    for (final r in p.recipe) RecipeLine(stockId: r.stockId, quantity: r.quantity)
  ];
  final edited = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> addLine() async {
          final st = ref.snap.store;
          final used = lines.map((e) => e.stockId).toSet();
          final options = st.stock.where((s) => !used.contains(s.id)).toList();
          if (options.isEmpty) {
            ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(snap.l10n.t('recipes_need_stock'))));
            return;
          }
          String pickId = options.first.id;
          final qty = TextEditingController(text: '1');
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (d) => AlertDialog(
              title: Text(snap.l10n.t('add_ingredient')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: pickId,
                    items: options
                        .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} · ${moneyOf(snap, s.cost)}/${s.unit}')))
                        .toList(),
                    onChanged: (v) => pickId = v ?? pickId,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: snap.l10n.t('qty_per_sale')),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false),
                    child: Text(snap.l10n.t('cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: Text(snap.l10n.t('add'))),
              ],
            ),
          );
          if (ok == true) {
            final q = double.tryParse(qty.text) ?? 0;
            if (q > 0) {
              setSt(() => lines.add(RecipeLine(stockId: pickId, quantity: q)));
            }
          }
        }

        double cost = 0;
        for (final l in lines) {
          final item = snap.store.stockById(l.stockId);
          if (item != null) cost += item.cost * l.quantity;
        }
        return Padding(
          padding:
              EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 8),
              for (final l in lines)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(snap.store.stockById(l.stockId)?.name ?? '?'),
                  subtitle:
                      Text('${l.quantity} ${snap.store.stockById(l.stockId)?.unit ?? ''}',
                          style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setSt(() => lines.remove(l))),
                ),
              OutlinedButton.icon(
                onPressed: addLine,
                icon: const Icon(Icons.add),
                label: Text(snap.l10n.t('add_ingredient')),
              ),
              const SizedBox(height: 10),
              Text(
                '${snap.l10n.t('cost')}: ${moneyOf(snap, cost)}  ·  '
                '${snap.l10n.t('price')}: ${moneyOf(snap, p.price)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(snap.l10n.t('save')),
              ),
              if (lines.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setSt(() => lines.clear());
                  },
                  child: Text(snap.l10n.t('clear_recipe')),
                ),
            ],
          ),
        );
      },
    ),
  );
  if (edited == true) {
    final copy = MenuProduct(
      id: p.id,
      categoryId: p.categoryId,
      name: p.name,
      nameUr: p.nameUr,
      description: p.description,
      price: p.price,
      imageBase64: p.imageBase64,
      available: p.available,
      sku: p.sku,
      inventoryId: p.inventoryId,
      deductQty: p.deductQty,
      course: p.course,
      mods: p.mods,
      recipe: lines,
    );
    await ref.ctrl
        .dispatch(NetCommand(name: 'upsertProduct', payload: {'product': copy.toJson()}));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snap.l10n.t('recipe_saved'))));
    }
  }
}

// ───────────────────────────────── Wastage ──────────────────────────────────

Future<void> showWastageLog(BuildContext context, WidgetRef ref) async {
  final snap = ref.snap;
  final store = snap.store;
  final week = store.waste
      .where((w) => DateTime.now().difference(w.at).inDays < 7)
      .fold<double>(0, (s, w) => s + w.cost);
  await _sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(snap.l10n.t('wastage_log')),
        OfCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.delete_sweep, color: OfColors.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${snap.l10n.t('waste_week')}: ${moneyOf(snap, week)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _logWaste(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(snap.l10n.t('log_waste')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (store.waste.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(snap.l10n.t('empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: OfColors.muted)),
          ),
        for (final w in store.waste.take(60))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(store.stockById(w.stockId)?.name ?? '?',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${w.quantity} · ${moneyOf(snap, w.cost)}'
              '${w.reason.isEmpty ? '' : ' · ${w.reason}'}'
              '${w.actor.isEmpty ? '' : ' · ${w.actor}'}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.undo, size: 18, color: OfColors.mint),
              tooltip: snap.l10n.t('undo'),
              onPressed: () => ref.ctrl.dispatch(NetCommand(
                name: 'deleteWastage',
                payload: {'id': w.id},
                actor: snap.session.displayName,
              )),
            ),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

Future<void> _logWaste(BuildContext context, WidgetRef ref) async {
  final snap = ref.snap;
  final store = snap.store;
  if (store.stock.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snap.l10n.t('recipes_need_stock'))));
    return;
  }
  String pickId = store.stock.first.id;
  final qty = TextEditingController(text: '1');
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(snap.l10n.t('log_waste')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: pickId,
            items: store.stock
                .map((s) => DropdownMenuItem(
                    value: s.id, child: Text('${s.name} (${s.quantity} ${s.unit})')))
                .toList(),
            onChanged: (v) => pickId = v ?? pickId,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: snap.l10n.t('waste_qty')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: reason,
            decoration: InputDecoration(labelText: snap.l10n.t('waste_reason')),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(snap.l10n.t('cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(snap.l10n.t('log'))),
      ],
    ),
  );
  if (ok == true) {
    final q = double.tryParse(qty.text) ?? 0;
    if (q > 0) {
      await ref.ctrl.dispatch(NetCommand(
        name: 'logWastage',
        payload: {
          'id': newId(),
          'stockId': pickId,
          'quantity': q,
          'reason': reason.text.trim(),
        },
        actor: snap.session.displayName,
      ));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(snap.l10n.t('waste_logged'))));
      }
    }
  }
}

// ─────────────────────── Suppliers & purchase orders ────────────────────────

Future<void> showPurchasing(BuildContext context, WidgetRef ref) async {
  await _sheet(context, const _PurchaseTab());
}

class _PurchaseTab extends ConsumerStatefulWidget {
  const _PurchaseTab();
  @override
  ConsumerState<_PurchaseTab> createState() => _PurchaseTabState();
}

class _PurchaseTabState extends ConsumerState<_PurchaseTab> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final snap = ref.snap;
    final s = snap.l10n;
    final store = snap.store;
    final open = store.purchases.where((p) => p.status != 'received').toList();
    final done = store.purchases.where((p) => p.status == 'received').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(s.t('purchasing')),
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, label: Text(s.t('purchase_orders'))),
            ButtonSegment(value: 1, label: Text(s.t('suppliers'))),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        const SizedBox(height: 12),
        if (tab == 0) ...[
          FilledButton.icon(
            onPressed: () => _newPurchase(context, ref),
            icon: const Icon(Icons.add),
            label: Text(s.t('new_purchase')),
          ),
          const SizedBox(height: 10),
          if (store.purchases.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(s.t('empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OfColors.muted)),
            ),
          for (final po in [...open, ...done]) _poCard(store, po),
        ] else ...[
          FilledButton.icon(
            onPressed: () => _editSupplier(context, ref),
            icon: const Icon(Icons.add),
            label: Text(s.t('add_supplier')),
          ),
          const SizedBox(height: 10),
          if (store.suppliers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(s.t('empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OfColors.muted)),
            ),
          for (final sup in store.suppliers)
            OfCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping, color: OfColors.emerald),
                title: Text(sup.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: sup.phone.isEmpty && sup.notes.isEmpty
                    ? null
                    : Text([sup.phone, sup.notes].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12)),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _editSupplier(context, ref, existing: sup);
                    } else if (v == 'delete') {
                      await ref.ctrl.dispatch(NetCommand(
                          name: 'deleteSupplier', payload: {'id': sup.id}));
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(s.t('edit'))),
                    PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _poCard(AppStore store, PurchaseOrder po) {
    final s = ref.snap.l10n;
    final received = po.status == 'received';
    return OfCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${po.poNo} · ${po.supplierName.isEmpty ? s.t('no_supplier') : po.supplierName}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              StatusChip(
                po.status,
                color: received
                    ? OfColors.mint
                    : (po.status == 'cancelled' ? OfColors.danger : OfColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in po.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${store.stockById(l.stockId)?.name ?? '?'} × ${l.quantity} — ${moneyOf(ref.snap, l.lineCost)}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 4),
          Text('${s.t('total')}: ${moneyOf(ref.snap, po.total)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (!received && po.status == 'ordered') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: OfColors.mint),
                    onPressed: () async {
                      await ref.ctrl.dispatch(NetCommand(
                          name: 'receivePurchase',
                          payload: {'id': po.id},
                          actor: ref.snap.session.displayName));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.t('stock_received'))));
                      }
                    },
                    icon: const Icon(Icons.inventory, size: 18),
                    label: Text(s.t('receive')),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: s.t('cancel'),
                  onPressed: () => ref.ctrl.dispatch(
                      NetCommand(name: 'cancelPurchase', payload: {'id': po.id})),
                  icon: const Icon(Icons.delete_outline, color: OfColors.danger),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _editSupplier(BuildContext context, WidgetRef ref,
    {Supplier? existing}) async {
  final s = ref.snap.l10n;
  final name = TextEditingController(text: existing?.name ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(existing == null ? s.t('add_supplier') : s.t('edit')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: name, decoration: InputDecoration(labelText: s.t('supplier_name'))),
          const SizedBox(height: 8),
          TextField(
              controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
          const SizedBox(height: 8),
          TextField(
              controller: notes, decoration: InputDecoration(labelText: s.t('notes'))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('save'))),
      ],
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    final sup = Supplier(
      id: existing?.id ?? newId(),
      name: name.text.trim(),
      phone: phone.text.trim(),
      notes: notes.text.trim(),
    );
    await ref.ctrl
        .dispatch(NetCommand(name: 'upsertSupplier', payload: {'supplier': sup.toJson()}));
  }
}

Future<void> _newPurchase(BuildContext context, WidgetRef ref) async {
  final snap = ref.snap;
  final s = snap.l10n;
  final store = snap.store;
  if (store.stock.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('recipes_need_stock'))));
    return;
  }
  final lines = <PurchaseLine>[];
  String? supplierId;
  final notes = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> addLine() async {
          String pickId = store.stock.first.id;
          final qty = TextEditingController(text: '1');
          final cost = TextEditingController(
              text: (store.stock.first.cost).toStringAsFixed(2));
          final added = await showDialog<bool>(
            context: ctx,
            builder: (d) => AlertDialog(
              title: Text(s.t('add_line')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: pickId,
                    items: store.stock
                        .map((st) => DropdownMenuItem(
                            value: st.id, child: Text('${st.name} · ${st.quantity} ${st.unit}')))
                        .toList(),
                    onChanged: (v) => pickId = v ?? pickId,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: s.t('qty')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: s.t('unit_cost')),
                    onChanged: (_) {},
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(d, true), child: Text(s.t('add'))),
              ],
            ),
          );
          if (added == true) {
            final q = double.tryParse(qty.text) ?? 0;
            final c = double.tryParse(cost.text) ?? 0;
            if (q > 0) {
              setSt(() =>
                  lines.add(PurchaseLine(stockId: pickId, quantity: q, cost: c)));
            }
          }
        }

        final total = lines.fold<double>(0, (a, l) => a + l.lineCost);
        return Padding(
          padding:
              EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.t('new_purchase'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 10),
              if (store.suppliers.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: supplierId,
                  hint: Text(s.t('no_supplier')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(s.t('no_supplier'))),
                    ...store.suppliers.map((sp) =>
                        DropdownMenuItem<String?>(value: sp.id, child: Text(sp.name))),
                  ],
                  onChanged: (v) => setSt(() => supplierId = v),
                ),
              const SizedBox(height: 10),
              for (final l in lines)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      '${store.stockById(l.stockId)?.name ?? '?'} × ${l.quantity}'),
                  subtitle: Text(moneyOf(snap, l.lineCost),
                      style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setSt(() => lines.remove(l))),
                ),
              OutlinedButton.icon(
                onPressed: addLine,
                icon: const Icon(Icons.add),
                label: Text(s.t('add_line')),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: notes, decoration: InputDecoration(labelText: s.t('notes'))),
              const SizedBox(height: 10),
              Text('${s.t('total')}: ${moneyOf(snap, total)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              FilledButton(
                onPressed:
                    lines.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(s.t('create_po')),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (ok == true && lines.isNotEmpty) {
    final po = PurchaseOrder(
      id: newId(),
      poNo: '',
      supplierId: supplierId ?? '',
      supplierName: store.supplierById(supplierId)?.name ?? '',
      lines: lines,
      notes: notes.text.trim(),
      createdBy: snap.session.displayName,
    );
    await ref.ctrl
        .dispatch(NetCommand(name: 'upsertPurchase', payload: {'purchase': po.toJson()}));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('po_created'))));
    }
  }
}

// ────────────────────────────────── Insights ────────────────────────────────

Future<void> showInsights(BuildContext context, WidgetRef ref) async {
  final snap = ref.snap;
  final s = snap.l10n;
  final store = snap.store;
  final now = DateTime.now();
  final week = now.subtract(const Duration(days: 7));
  final paid = store.orders
      .where((o) => o.status == OrderStatus.paid && o.updatedAt.isAfter(week))
      .toList();

  // product rollup
  final qty = <String, double>{};
  final revenue = <String, double>{};
  final costMap = <String, double>{};
  final catSales = <String, double>{};
  final staffSales = <String, double>{};
  var qrCount = 0;
  for (final o in paid) {
    if (o.isQr) qrCount++;
    final staff = o.staffId != null && store.staffById(o.staffId) != null
        ? store.staffById(o.staffId)!.name
        : (o.createdBy.isEmpty ? s.t('unknown') : o.createdBy);
    staffSales[staff] = (staffSales[staff] ?? 0) + o.total;
    for (final l in o.lines) {
      qty[l.productId] = (qty[l.productId] ?? 0) + l.qty;
      revenue[l.productId] = (revenue[l.productId] ?? 0) + l.lineTotal;
      final p = store.productById(l.productId);
      if (p != null) {
        costMap[l.productId] =
            (costMap[l.productId] ?? 0) + store.productCost(p) * l.qty;
        final cat = store.categories
            .where((c) => c.id == p.categoryId)
            .map((c) => c.name)
            .firstOrNullWithDefault('?');
        catSales[cat] = (catSales[cat] ?? 0) + l.lineTotal;
      }
    }
  }
  double profitTotal = 0;
  revenue.forEach((id, r) => profitTotal += r - (costMap[id] ?? 0));
  final wasteWeek = store.waste
      .where((w) => now.difference(w.at).inDays < 7)
      .fold<double>(0, (a, w) => a + w.cost);
  final selling = qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final slow = selling.reversed
      .where((e) => e.value <= 2)
      .take(6)
      .toList();
  final nameOf = (String id) => store.productById(id)?.name ?? id;

  await _sheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(s.t('insights')),
        OfCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kv(s.t('week_revenue'), moneyOf(snap, paid.fold<double>(0, (a, o) => a + o.total))),
              _kv(s.t('est_profit'), moneyOf(snap, profitTotal)),
              _kv(s.t('waste_week'), moneyOf(snap, wasteWeek)),
              _kv(s.t('qr_orders_week'), '$qrCount / ${paid.length}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(s.t('best_sellers'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        if (selling.isEmpty)
          Text(s.t('empty'), style: const TextStyle(color: OfColors.muted)),
        for (final e in selling.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
                radius: 13,
                backgroundColor: OfColors.emerald,
                child: Text('${selling.indexOf(e) + 1}',
                    style: const TextStyle(fontSize: 12, color: Colors.white))),
            title: Text(nameOf(e.key)),
            trailing: Text(
                '${e.value.toStringAsFixed(0)} × · ${moneyOf(snap, revenue[e.key] ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        Text(s.t('slow_movers'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        if (slow.isEmpty)
          Text(s.t('all_moving'), style: const TextStyle(color: OfColors.muted, fontSize: 12.5)),
        for (final e in slow)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(nameOf(e.key)),
            trailing: Text('${e.value.toStringAsFixed(0)} ×',
                style: const TextStyle(color: OfColors.warn, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 10),
        Text(s.t('by_category'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ..._bars(catSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value)), snap),
        const SizedBox(height: 10),
        Text(s.t('by_staff'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ..._bars(staffSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value)), snap),
        const SizedBox(height: 16),
      ],
    ),
  );
}

List<Widget> _bars(List<MapEntry<String, double>> entries, AppSnapshot snap) {
  if (entries.isEmpty) {
    return [Text(snap.l10n.t('empty'), style: const TextStyle(color: OfColors.muted, fontSize: 12.5))];
  }
  final maxV = entries.fold<double>(0, (m, e) => math.max(m, e.value));
  return [
    for (final e in entries)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 108,
                child: Text(e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: maxV == 0 ? 0 : e.value / maxV,
                  minHeight: 9,
                  backgroundColor: Colors.white10,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(OfColors.emerald),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(moneyOf(snap, e.value),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
  ];
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(k, style: const TextStyle(color: OfColors.muted, fontSize: 13))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );

extension on Iterable<String> {
  String firstOrNullWithDefault(String fallback) =>
      isEmpty ? fallback : first;
}
