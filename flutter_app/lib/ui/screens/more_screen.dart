import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/bluetooth_printer.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import '../widgets/pos_ops.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final snap = ref.snap;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OfCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront, color: OfColors.emerald),
            title: Text(snap.store.profile.businessName, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${s.t(snap.store.model.name == 'services' ? 'services_model' : snap.store.model.name)} · ${s.t('currency')} ${snap.currency}'),
          ),
        ),
        const SizedBox(height: 16),
        _h(s.t('shop_section')),
        if (snap.isMain)
          _tile(context, Icons.store, s.t('business_model'), () => _changeModel(context, ref)),
        if (snap.isMain)
          _tile(context, Icons.receipt_long, s.t('bill_profile'), () => _bill(context, ref)),
        _h(s.t('hardware_section')),
        _tile(context, Icons.print, s.t('printers'), () => _printers(context, ref)),
        _h(s.t('people_section')),
        _tile(context, Icons.people, s.t('customers_book'), () => _customers(context, ref)),
        _tile(context, Icons.account_balance_wallet, s.t('shift'), () => _shiftCash(context, ref)),
        _tile(context, Icons.delivery_dining, s.t('drivers'), () => _drivers(context, ref)),
        _tile(context, Icons.badge, s.t('staff'), () => _staff(context, ref)),
        _tile(context, Icons.spa, s.t('services'), () => _services(context, ref)),
        _h(s.t('reports_section')),
        _tile(context, Icons.print, s.t('reprint_any'), () => reprintSearch(context, ref)),
        _tile(context, Icons.bar_chart, s.t('reports'), () => _reports(context, ref)),
        if (snap.isMain) _tile(context, Icons.lock_clock, s.t('day_close'), () => _closeDay(context, ref)),
        _h(s.t('account_section')),
        _tile(context, Icons.backup, s.t('export_backup'), () async {
          await ref.ctrl.backup.exportAndShare(snap.store);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('backup_ok'))));
          }
        }),
        _tile(context, Icons.unarchive, s.t('import_backup'), () async {
          if (!snap.isMain) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(s.t('import_backup')),
              content: Text(s.t('import_warn')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('import'))),
              ],
            ),
          );
          if (ok != true) return;
          try {
            final store = await ref.ctrl.backup.pickImport();
            if (store != null) {
              await ref.ctrl.importStore(store);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('import_ok'))));
              }
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }
        }),
        _tile(context, Icons.vpn_key, s.t('license'), () => _license(context, ref)),
        _tile(context, Icons.manage_accounts, s.t('roles'), () => leaveRoleWithPin(context, ref)),
        _tile(context, Icons.language, s.t('language'), () {
          ref.ctrl.setLocale(snap.session.locale == 'en' ? 'ur' : 'en');
        }),
        _tile(context, Icons.brightness_6, s.t('theme'), () {
          final next = switch (snap.session.theme) {
            ThemeChoice.system => ThemeChoice.dark,
            ThemeChoice.dark => ThemeChoice.light,
            ThemeChoice.light => ThemeChoice.system,
          };
          ref.ctrl.setTheme(next);
        }),
        _tile(context, Icons.support_agent, s.t('whatsapp_support'), () {
          launchUrl(Uri.parse(kWhatsAppUrl), mode: LaunchMode.externalApplication);
        }),
        const SizedBox(height: 16),
        Text('${s.t('version')} $kAppVersion', textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted)),
      ],
    );
  }

  Widget _h(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(title, style: const TextStyle(color: OfColors.muted, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OfCard(
        onTap: onTap,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: OfColors.emerald),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

Future<void> _changeModel(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final models = <(BusinessModel, String, String, IconData)>[
    (BusinessModel.restaurant, 'restaurant', 'model_restaurant_hint', Icons.restaurant),
    (BusinessModel.retail, 'retail', 'model_retail_hint', Icons.storefront),
    (BusinessModel.fastfood, 'fastfood', 'model_fastfood_hint', Icons.fastfood),
    (BusinessModel.services, 'services_model', 'model_services_hint', Icons.spa),
  ];
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.t('business_model'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          Text(s.t('change_model_hint'), style: const TextStyle(color: OfColors.muted)),
          const SizedBox(height: 12),
          ...models.map((m) {
            final selected = ref.snap.store.model == m.$1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OfCard(
                color: selected ? OfColors.emerald.withValues(alpha: 0.15) : null,
                onTap: () async {
                  await ref.ctrl.changeBusinessModel(m.$1);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.$4, color: OfColors.emerald),
                  title: Text(s.t(m.$2), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.t(m.$3)),
                  trailing: selected ? const Icon(Icons.check, color: OfColors.emerald) : null,
                ),
              ),
            );
          }),
        ],
      ),
    ),
  );
}

Future<void> _bill(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final p = ref.snap.store.profile.copy();
  final name = TextEditingController(text: p.businessName);
  final address = TextEditingController(text: p.address);
  final phone = TextEditingController(text: p.phone);
  final taxId = TextEditingController(text: p.taxId);
  final footer = TextEditingController(text: p.footer);
  final cur = TextEditingController(text: p.currencySymbol);
  final tax = TextEditingController(text: p.taxRate.toString());
  final svc = TextEditingController(text: p.serviceRate.toString());
  final pin = TextEditingController(text: p.managerPin);
  var prefix = p.currencyPrefix;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('bill_profile'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('business_name'))),
              const SizedBox(height: 8),
              TextField(controller: address, decoration: InputDecoration(labelText: s.t('address'))),
              const SizedBox(height: 8),
              TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
              const SizedBox(height: 8),
              TextField(controller: taxId, decoration: InputDecoration(labelText: s.t('tax_id'))),
              const SizedBox(height: 8),
              TextField(controller: footer, decoration: InputDecoration(labelText: s.t('footer'))),
              const SizedBox(height: 8),
              TextField(controller: cur, decoration: InputDecoration(labelText: s.t('currency_symbol'))),
              const SizedBox(height: 8),
              TextField(controller: tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('tax_rate'))),
              const SizedBox(height: 8),
              TextField(controller: svc, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('service_rate'))),
              const SizedBox(height: 8),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.t('set_pin'), helperText: s.t('pin_required')),
              ),
              SwitchListTile(value: prefix, onChanged: (v) => setSt(() => prefix = v), title: Text(s.t('prefix_currency'))),
              FilledButton(
                onPressed: () async {
                  final next = BillProfile(
                    businessName: name.text.trim().isEmpty ? 'My Shop' : name.text.trim(),
                    address: address.text.trim(),
                    phone: phone.text.trim(),
                    taxId: taxId.text.trim(),
                    footer: footer.text.trim(),
                    currencySymbol: cur.text.trim().isEmpty ? kDefaultCurrency : cur.text.trim(),
                    currencyPrefix: prefix,
                    taxRate: double.tryParse(tax.text) ?? 0,
                    serviceRate: double.tryParse(svc.text) ?? 0,
                    logoBase64: p.logoBase64,
                    managerPin: pin.text.trim(),
                  );
                  await ref.ctrl.dispatch(NetCommand(name: 'setProfile', payload: {'profile': next.toJson()}));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(s.t('save')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _printers(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final k = TextEditingController(text: ref.snap.store.kitchenPrinter.host);
  final r = TextEditingController(text: ref.snap.store.receiptPrinter.host);
  var ken = ref.snap.store.kitchenPrinter.enabled;
  var ren = ref.snap.store.receiptPrinter.enabled;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(value: ken, onChanged: (v) => setSt(() => ken = v), title: Text(s.t('kitchen_printer'))),
            TextField(controller: k, decoration: const InputDecoration(hintText: '192.168.1.50')),
            const SizedBox(height: 8),
            SwitchListTile(value: ren, onChanged: (v) => setSt(() => ren = v), title: Text(s.t('receipt_printer'))),
            TextField(controller: r, decoration: const InputDecoration(hintText: '192.168.1.51')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await ref.ctrl.dispatch(NetCommand(name: 'setPrinters', payload: {
                  'kitchen': PrinterConfig(host: k.text.trim(), enabled: ken).toJson(),
                  'receipt': PrinterConfig(host: r.text.trim(), enabled: ren).toJson(),
                }));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(s.t('save')),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await ref.ctrl.printer.test(
                    PrinterConfig(host: r.text.trim(), enabled: true),
                    ref.snap.store.profile.businessName,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_ok'))));
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_fail'))));
                  }
                }
              },
              child: Text(s.t('test_print')),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _drivers(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final drivers = ref.snap.store.drivers;
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              ListTile(
                title: Text(s.t('drivers'), style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final name = TextEditingController();
                    final phone = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: Text(s.t('add_driver')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
                            TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('save'))),
                        ],
                      ),
                    );
                    if (ok == true && name.text.trim().isNotEmpty) {
                      await ref.ctrl.dispatch(NetCommand(name: 'upsertDriver', payload: {
                        'driver': Driver(id: newId(), name: name.text.trim(), phone: phone.text.trim()).toJson(),
                      }));
                    }
                  },
                ),
              ),
              Expanded(
                child: drivers.isEmpty
                    ? EmptyState(icon: Icons.delivery_dining, message: s.t('no_drivers'))
                    : ListView(
                        children: drivers
                            .map((d) => ListTile(
                                  title: Text(d.name),
                                  subtitle: Text('${d.phone}  ${d.deviceId == null ? s.t('not_paired') : s.t('paired')}'),
                                  trailing: StatusChip(s.t('driver_${d.status.name}'), color: d.status == DriverStatus.free ? OfColors.emerald : OfColors.warn),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _staff(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final name = TextEditingController();
  final role = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...ref.snap.store.staff.map((st) => ListTile(
                title: Text(st.name),
                subtitle: Text(st.roleLabel),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => ref.ctrl.dispatch(NetCommand(name: 'deleteStaff', payload: {'id': st.id})),
                ),
              )),
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
          TextField(controller: role, decoration: InputDecoration(labelText: s.t('roles'))),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.ctrl.dispatch(NetCommand(name: 'upsertStaff', payload: {
                'staff': StaffMember(id: newId(), name: name.text.trim(), roleLabel: role.text.trim()).toJson(),
              }));
              name.clear();
              role.clear();
            },
            child: Text(s.t('add_staff')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _services(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final name = TextEditingController();
  final price = TextEditingController();
  final mins = TextEditingController(text: '30');
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...ref.snap.store.services.map((sv) => ListTile(
                title: Text(sv.name),
                subtitle: Text(moneyOf(ref.snap, sv.price)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => ref.ctrl.dispatch(NetCommand(name: 'deleteService', payload: {'id': sv.id})),
                ),
              )),
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${s.t('price')} (${ref.snap.currency})'),
          ),
          TextField(controller: mins, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('duration'))),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.ctrl.dispatch(NetCommand(name: 'upsertService', payload: {
                'service': ServiceOffering(
                  id: newId(),
                  name: name.text.trim(),
                  price: double.tryParse(price.text) ?? 0,
                  durationMin: int.tryParse(mins.text) ?? 30,
                ).toJson(),
              }));
              name.clear();
              price.clear();
            },
            child: Text(s.t('add_service')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _closeDay(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final store = ref.snap.store;
  final today = store.salesOn(DateTime.now());
  final open = store.openOrders.length;
  final last = store.lastDayClose;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('day_close')),
      content: Text(
        '${s.t('day_close_open')}\n${s.t('today_sales')}: ${moneyOf(ref.snap, today)}\n${s.t('open_orders')}: $open'
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

Future<void> _reports(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final store = ref.snap.store;
  final today = store.salesOn(DateTime.now());
  final paid = store.orders.where((o) => o.status == OrderStatus.paid).toList();
  final items = paid.fold<int>(0, (n, o) => n + o.lines.fold<int>(0, (a, l) => a + l.qty.round()));
  final avg = paid.isEmpty ? 0.0 : today / (paid.where((o) {
        final d = DateTime.now();
        return o.updatedAt.year == d.year && o.updatedAt.month == d.month && o.updatedAt.day == d.day;
      }).length.clamp(1, 9999));
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.t('reports'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ListTile(title: Text(s.t('today_sales')), trailing: Text(moneyOf(ref.snap, today), style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(title: Text(s.t('items_sold')), trailing: Text('$items')),
          ListTile(title: Text(s.t('avg_ticket')), trailing: Text(moneyOf(ref.snap, avg))),
          ListTile(title: Text(s.t('low_stock')), trailing: Text('${store.lowStock.length}')),
        ],
      ),
    ),
  );
}

Future<void> _license(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final lic = ref.snap.session.license;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('license_info'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          Text('${s.t('license_key')}: ${lic.key}'),
          Text('${s.t('device_id')}: ${ref.snap.session.deviceId}'),
          Text('${s.t('status')}: ${lic.locked ? s.t('key_revoked') : (lic.valid ? s.t('activated') : s.t('unbound'))}'),
          if (lic.expiresAt != null) Text('${s.t('expires')}: ${lic.expiresAt}'),
          if (lic.lastValidatedAt != null) Text('${s.t('last_validated')}: ${lic.lastValidatedAt}'),
          const SizedBox(height: 8),
          Text(s.t('reset_hint')),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: ref.snap.session.deviceId)),
            child: Text(s.t('device_id')),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              kBrandName,
              style: TextStyle(color: OfColors.muted, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ),
        ],
      ),
    ),
  );
}
