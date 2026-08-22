import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});
  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String? catId;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final store = ref.snap.store;
    final cats = [...store.categories]..sort((a, b) => a.sort.compareTo(b.sort));
    final products = store.products.where((p) {
      final catOk = catId == null || p.categoryId == catId;
      final query = q.trim().toLowerCase();
      final qOk = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query);
      return catOk && qOk;
    }).toList();

    return Scaffold(
      floatingActionButton: store.categories.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () => editCategory(context, ref),
              icon: const Icon(Icons.category),
              label: Text(s.t('add_category')),
            )
          : FloatingActionButton.extended(
              onPressed: () => editProduct(context, ref, categoryId: catId ?? store.categories.first.id),
              icon: const Icon(Icons.add),
              label: Text(s.t('add_item')),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.t('search'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.t('all')),
                    selected: catId == null,
                    onSelected: (_) => setState(() => catId = null),
                  ),
                ),
                ...cats.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onLongPress: () => editCategory(context, ref, existing: c),
                        child: ChoiceChip(
                          label: Text(c.name),
                          selected: catId == c.id,
                          onSelected: (_) => setState(() => catId = c.id),
                        ),
                      ),
                    )),
                ActionChip(
                  label: Text(s.t('add_category')),
                  onPressed: () => editCategory(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? EmptyState(
                    icon: Icons.restaurant_menu,
                    message: s.t('no_menu'),
                    action: store.categories.isEmpty
                        ? () => editCategory(context, ref)
                        : () => editProduct(context, ref, categoryId: store.categories.first.id),
                    actionLabel: s.t('add'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCount(context, phone: 2, tablet: 4),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: products.length,
                    itemBuilder: (_, i) {
                      final p = products[i];
                      return OfCard(
                        padding: EdgeInsets.zero,
                        onTap: () => editProduct(context, ref, existing: p, categoryId: p.categoryId),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: p.imageBase64 == null || p.imageBase64!.isEmpty
                                        ? ColoredBox(color: OfColors.emerald.withValues(alpha: 0.12), child: const Icon(Icons.restaurant, color: OfColors.emerald, size: 40))
                                        : ProductImage(p.imageBase64, size: 400),
                                  ),
                                  Positioned(
                                    right: 8,
                                    bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: OfColors.deep.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(20)),
                                      child: MoneyText(p.price, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ),
                                  ),
                                  if (!p.available)
                                    const Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(8), child: StatusChip('86', color: OfColors.danger))),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
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

Future<void> editCategory(BuildContext context, WidgetRef ref, {MenuCategory? existing}) async {
  final s = ref.s;
  final name = TextEditingController(text: existing?.name ?? '');
  final ur = TextEditingController(text: existing?.nameUr ?? '');
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
          TextField(controller: ur, decoration: const InputDecoration(labelText: 'اردو')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
          if (existing != null)
            TextButton(
              onPressed: () async {
                await ref.ctrl.dispatch(NetCommand(name: 'deleteCategory', payload: {'id': existing.id}));
                if (ctx.mounted) Navigator.pop(ctx, false);
              },
              child: Text(s.t('delete')),
            ),
        ],
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    final c = MenuCategory(
      id: existing?.id ?? newId(),
      name: name.text.trim(),
      nameUr: ur.text.trim(),
      sort: existing?.sort ?? ref.read(appControllerProvider).store.categories.length,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'upsertCategory', payload: {'category': c.toJson()}));
  }
}

Future<void> editProduct(
  BuildContext context,
  WidgetRef ref, {
  MenuProduct? existing,
  required String categoryId,
}) async {
  final s = ref.s;
  final store = ref.read(appControllerProvider).store;
  final name = TextEditingController(text: existing?.name ?? '');
  final ur = TextEditingController(text: existing?.nameUr ?? '');
  final price = TextEditingController(text: existing == null ? '' : existing.price.toString());
  final sku = TextEditingController(text: existing?.sku ?? '');
  var available = existing?.available ?? true;
  var image = existing?.imageBase64;
  var cat = existing?.categoryId ?? categoryId;
  var inv = existing?.inventoryId;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProductImage(image, size: 72),
              TextButton(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600);
                  if (picked == null) return;
                  final bytes = await picked.readAsBytes();
                  final encoded = await _shrink(bytes);
                  setSt(() => image = encoded);
                },
                child: Text(s.t('pick_photo')),
              ),
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
              const SizedBox(height: 8),
              TextField(controller: ur, decoration: const InputDecoration(labelText: 'اردو')),
              const SizedBox(height: 8),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${s.t('price')} (${ref.read(appControllerProvider).store.profile.currencySymbol})'),
              ),
              const SizedBox(height: 8),
              TextField(controller: sku, decoration: InputDecoration(labelText: s.t('sku'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: cat,
                items: store.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setSt(() => cat = v ?? cat),
                decoration: InputDecoration(labelText: s.t('category')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: inv,
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(s.t('none'))),
                  ...store.stock.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setSt(() => inv = v),
                decoration: InputDecoration(labelText: s.t('auto_deduct')),
              ),
              SwitchListTile(
                value: available,
                onChanged: (v) => setSt(() => available = v),
                title: Text(s.t('available')),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    await ref.ctrl.dispatch(NetCommand(name: 'deleteProduct', payload: {'id': existing.id}));
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  },
                  child: Text(s.t('delete')),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    final p = MenuProduct(
      id: existing?.id ?? newId(),
      categoryId: cat,
      name: name.text.trim(),
      nameUr: ur.text.trim(),
      price: double.tryParse(price.text) ?? 0,
      sku: sku.text.trim(),
      available: available,
      imageBase64: image,
      inventoryId: inv,
    );
    await ref.ctrl.dispatch(NetCommand(name: 'upsertProduct', payload: {'product': p.toJson()}));
  }
}

Future<String> _shrink(List<int> bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes), targetWidth: 400);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return base64Encode(bytes);
    return base64Encode(data.buffer.asUint8List());
  } catch (_) {
    return base64Encode(bytes);
  }
}
