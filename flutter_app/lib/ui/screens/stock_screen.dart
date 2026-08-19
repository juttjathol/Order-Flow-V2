import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  String q = '';
  bool onlyLow = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final items = ref.snap.store.stock.where((e) {
      final query = q.trim().toLowerCase();
      final qOk = query.isEmpty ||
          e.name.toLowerCase().contains(query) ||
          e.sku.toLowerCase().contains(query);
      final lowOk = !onlyLow || e.level != StockLevel.ok;
      return qOk && lowOk;
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editStock(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s.t('add_stock')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: InputDecoration(hintText: s.t('sku_or_name'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          SwitchListTile(
            value: onlyLow,
            onChanged: (v) => setState(() => onlyLow = v),
            title: Text(s.t('low_stock')),
          ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2,
                    message: s.t('no_stock'),
                    action: () => editStock(context, ref),
                    actionLabel: s.t('add_stock'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCount(context, phone: 1, tablet: 2),
                      mainAxisExtent: 132,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => StockCard(
                      item: items[i],
                      onTap: () => editStock(context, ref, existing: items[i]),
                      onAdjust: (delta) => ref.ctrl.dispatch(NetCommand(
                        name: 'adjustStock',
                        payload: {'id': items[i].id, 'delta': delta},
                      )),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class StockCard extends ConsumerWidget {
  const StockCard({super.key, required this.item, this.onTap, this.onAdjust});
  final StockItem item;
  final VoidCallback? onTap;
  final ValueChanged<double>? onAdjust;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final color = stockColor(item.level);
    return OfCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 88,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${s.t('sku')}: ${item.sku.isEmpty ? '—' : item.sku}', style: const TextStyle(color: OfColors.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusChip(
                      item.level == StockLevel.ok
                          ? s.t('ok_stock')
                          : item.level == StockLevel.low
                              ? s.t('low')
                              : s.t('out'),
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Text('${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}'),
                  ],
                ),
              ],
            ),
          ),
          if (onAdjust != null)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(onPressed: () => onAdjust!(1), icon: const Icon(Icons.add)),
                IconButton.filledTonal(onPressed: () => onAdjust!(-1), icon: const Icon(Icons.remove)),
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> editStock(BuildContext context, WidgetRef ref, {StockItem? existing}) async {
  final s = ref.s;
  final name = TextEditingController(text: existing?.name ?? '');
  final sku = TextEditingController(text: existing?.sku ?? '');
  final qty = TextEditingController(text: existing?.quantity.toString() ?? '0');
  final low = TextEditingController(text: existing?.lowStockAt.toString() ?? '5');
  final unit = TextEditingController(text: existing?.unit ?? 'pcs');
  final cost = TextEditingController(text: existing?.cost.toString() ?? '');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
            const SizedBox(height: 8),
            TextField(controller: sku, decoration: InputDecoration(labelText: s.t('sku'))),
            const SizedBox(height: 8),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('on_hand'))),
            const SizedBox(height: 8),
            TextField(controller: low, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('low_at'))),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: InputDecoration(labelText: s.t('unit'))),
            const SizedBox(height: 8),
            TextField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: '${s.t('cost')} (${ref.read(appControllerProvider).store.profile.currencySymbol})'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await ref.ctrl.dispatch(NetCommand(name: 'deleteStock', payload: {'id': existing.id}));
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: Text(s.t('delete')),
              ),
          ],
        ),
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    final item = StockItem(
      id: existing?.id ?? newId(),
      name: name.text.trim(),
      sku: sku.text.trim(),
      quantity: double.tryParse(qty.text) ?? 0,
      lowStockAt: double.tryParse(low.text) ?? 5,
      unit: unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
      cost: double.tryParse(cost.text) ?? 0,
      sellPrice: existing?.sellPrice,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'upsertStock', payload: {'stock': item.toJson()}));
  }
}
