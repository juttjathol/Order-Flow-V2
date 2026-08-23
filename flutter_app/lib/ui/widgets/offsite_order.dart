import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import 'common.dart';

class OffsiteOrderBar extends ConsumerWidget {
  const OffsiteOrderBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => startOffsiteOrder(context, ref, OrderType.takeaway),
              icon: const Icon(Icons.takeout_dining),
              label: Text(s.t('takeaway')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => startOffsiteOrder(context, ref, OrderType.delivery),
              icon: const Icon(Icons.delivery_dining),
              label: Text(s.t('delivery')),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> startOffsiteOrder(
  BuildContext context,
  WidgetRef ref,
  OrderType type, {
  bool openTicket = true,
}) async {
  final s = ref.s;
  final store = ref.snap.store;
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final notes = TextEditingController();
  String? driverId = store.drivers.isEmpty ? null : store.drivers.first.id;

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
              Text(
                type == OrderType.delivery ? s.t('new_delivery') : s.t('new_takeaway'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(
                type == OrderType.delivery ? s.t('delivery_hint') : s.t('takeaway_hint'),
                style: const TextStyle(color: OfColors.muted),
              ),
              const SizedBox(height: 14),
              if (store.customers.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final c = await showModalBottomSheet<ShopCustomer>(
                        context: ctx,
                        builder: (d) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(title: Text(s.t('pick_customer'), style: const TextStyle(fontWeight: FontWeight.w800))),
                              ...store.customers.map((c) => ListTile(
                                    title: Text(c.name),
                                    subtitle: Text(c.phone),
                                    onTap: () => Navigator.pop(d, c),
                                  )),
                            ],
                          ),
                        ),
                      );
                      if (c != null) {
                        setSt(() {
                          name.text = c.name;
                          phone.text = c.phone;
                          if (c.address.isNotEmpty) address.text = c.address;
                        });
                      }
                    },
                    icon: const Icon(Icons.contacts),
                    label: Text(s.t('pick_customer')),
                  ),
                ),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: s.t('customer_name'), prefixIcon: const Icon(Icons.person)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.t('phone'), prefixIcon: const Icon(Icons.phone)),
              ),
              if (type == OrderType.delivery) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: address,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.t('delivery_address'), prefixIcon: const Icon(Icons.place)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: driverId,
                  decoration: InputDecoration(labelText: s.t('assign_driver')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(s.t('assign_later'))),
                    ...store.drivers.map((d) => DropdownMenuItem<String?>(
                          value: d.id,
                          child: Text('${d.name} · ${s.t('driver_${d.status.name}')}'),
                        )),
                  ],
                  onChanged: (v) => setSt(() => driverId = v),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: InputDecoration(labelText: s.t('notes'), prefixIcon: const Icon(Icons.notes)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  if (type == OrderType.delivery && address.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(s.t('address_required'))));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                icon: Icon(type == OrderType.delivery ? Icons.delivery_dining : Icons.takeout_dining),
                label: Text(s.t('create')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true) return;

  final order = PosOrder(
    id: newId(),
    ticketNo: '',
    type: type,
    taxRate: store.profile.taxRate,
    customerName: name.text.trim().isEmpty ? s.t('guest') : name.text.trim(),
    customerPhone: phone.text.trim(),
    address: address.text.trim(),
    driverId: type == OrderType.delivery ? driverId : null,
    notes: notes.text.trim(),
    createdBy: ref.snap.session.displayName,
  );
  await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
  if (order.customerPhone.isNotEmpty || (order.customerName.isNotEmpty && order.customerName != s.t('guest'))) {
    await ref.ctrl.dispatch(NetCommand(name: 'upsertCustomer', payload: {
      'customer': ShopCustomer(
        id: newId(),
        name: order.customerName,
        phone: order.customerPhone,
        address: order.address,
      ).toJson(),
    }));
  }
  if (openTicket && context.mounted) context.push('/order/${order.id}');
}

Future<void> editOffsiteDetails(BuildContext context, WidgetRef ref, PosOrder order) async {
  final s = ref.s;
  final store = ref.snap.store;
  final name = TextEditingController(text: order.customerName);
  final phone = TextEditingController(text: order.customerPhone);
  final address = TextEditingController(text: order.address);
  String? driverId = order.driverId;
  OrderType type = order.type;

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
              Text(s.t('customer_details'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(s.t('takeaway')),
                    selected: type == OrderType.takeaway,
                    onSelected: (_) => setSt(() => type = OrderType.takeaway),
                  ),
                  ChoiceChip(
                    label: Text(s.t('delivery')),
                    selected: type == OrderType.delivery,
                    onSelected: (_) => setSt(() => type = OrderType.delivery),
                  ),
                  if (order.tableId != null)
                    ChoiceChip(
                      label: Text(s.t('dine_in')),
                      selected: type == OrderType.dineIn,
                      onSelected: (_) => setSt(() => type = OrderType.dineIn),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('customer_name'))),
              TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
              if (type == OrderType.delivery) ...[
                TextField(controller: address, minLines: 2, maxLines: 3, decoration: InputDecoration(labelText: s.t('delivery_address'))),
                DropdownButtonFormField<String?>(
                  value: driverId,
                  decoration: InputDecoration(labelText: s.t('assign_driver')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(s.t('assign_later'))),
                    ...store.drivers.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                  ],
                  onChanged: (v) => setSt(() => driverId = v),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true) return;
  order.type = type;
  order.customerName = name.text.trim();
  order.customerPhone = phone.text.trim();
  order.address = type == OrderType.delivery ? address.text.trim() : '';
  order.driverId = type == OrderType.delivery ? driverId : null;
  await ref.ctrl.dispatch(NetCommand(name: 'patchOrder', payload: {'order': order.toJson()}));
}
