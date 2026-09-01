import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
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
    final model = snap.store.model;
    final people = <Widget>[
      _row(Icons.people, s.t('customers_book'), () => _customers(context, ref)),
      _row(Icons.account_balance_wallet, s.t('shift'), () => _shiftCash(context, ref)),
      _row(Icons.badge, s.t('staff'), () => _staff(context, ref)),
      if (model == BusinessModel.restaurant || model == BusinessModel.fastfood)
        _row(Icons.delivery_dining, s.t('drivers'), () => _drivers(context, ref)),
      if (model == BusinessModel.services)
        _row(Icons.spa, s.t('services'), () => _services(context, ref)),
      if (model == BusinessModel.restaurant || model == BusinessModel.services)
        _row(Icons.event, s.t('appointments'), () => _reservations(context, ref)),
    ];
    final shop = <Widget>[
      if (snap.isMain) _row(Icons.store, s.t('business_model'), () => _changeModel(context, ref)),
      if (snap.isMain || snap.isManager) _row(Icons.receipt_long, s.t('bill_profile'), () => _bill(context, ref)),
    ];
    final reports = <Widget>[
      _row(Icons.print, s.t('reprint_any'), () => reprintSearch(context, ref)),
      _row(Icons.bar_chart, s.t('reports'), () => _reports(context, ref)),
      _row(Icons.receipt_long, s.t('x_report'), () => showSalesReports(context, ref, zReport: false)),
      _row(Icons.summarize, s.t('z_report'), () => showSalesReports(context, ref, zReport: true)),
      _row(Icons.block, s.t('eighty_six_board'), () => _eightySixBoard(context, ref)),
      _row(Icons.hourglass_bottom, s.t('unpaid_tabs'), () => _unpaidTabs(context, ref)),
      if (snap.isMain || snap.isManager) _row(Icons.lock_clock, s.t('day_close'), () => _closeDay(context, ref)),
    ];
    final data = <Widget>[
      _row(Icons.ios_share, s.t('export_backup'), () async {
        await ref.ctrl.backup.exportAndShare(snap.store);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('backup_ok'))));
        }
      }),
      if (snap.isMain)
        _row(Icons.unarchive, s.t('import_backup'), () async {
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
    ];
    final account = <Widget>[
      if (snap.isMain) _row(Icons.vpn_key, s.t('license'), () => _license(context, ref)),
      _row(Icons.manage_accounts, s.t('roles'), () => leaveRoleWithPin(context, ref)),
      _row(Icons.language, s.t('language'), () {
        ref.ctrl.setLocale(snap.session.locale == 'en' ? 'ur' : 'en');
      }),
      _row(Icons.brightness_6, s.t('theme'), () {
        final next = switch (snap.session.theme) {
          ThemeChoice.system => ThemeChoice.dark,
          ThemeChoice.dark => ThemeChoice.light,
          ThemeChoice.light => ThemeChoice.system,
        };
        ref.ctrl.setTheme(next);
      }),
      _row(Icons.support_agent, s.t('whatsapp_support'), () {
        launchUrl(Uri.parse(kWhatsAppUrl), mode: LaunchMode.externalApplication);
      }),
      _row(Icons.privacy_tip_outlined, s.t('privacy_policy'), () {
        launchUrl(Uri.parse(kPrivacyUrl), mode: LaunchMode.externalApplication);
      }),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(opacity: v.clamp(0.4, 1), child: Transform.scale(scale: v, child: child)),
          child: OfCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront, color: OfColors.emerald),
              title: Text(snap.store.profile.businessName, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${s.t(snap.store.model.name == 'services' ? 'services_model' : snap.store.model.name)} · ${s.t('currency')} ${snap.currency}'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (shop.isNotEmpty) _folder(context, Icons.storefront, s.t('shop_section'), shop),
        _folder(context, Icons.print, s.t('hardware_section'), [
          _row(Icons.print, s.t('printers'), () => _printers(context, ref)),
        ]),
        _folder(context, Icons.groups, s.t('people_section'), people),
        _folder(context, Icons.insights, s.t('reports_section'), reports),
        _folder(context, Icons.backup, s.t('backup'), data),
        _folder(context, Icons.settings, s.t('account_section'), account),
        const SizedBox(height: 16),
        Text('${s.t('version')} $kAppVersion', textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted)),
      ],
    );
  }

  Widget _folder(BuildContext context, IconData icon, String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OfCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(icon, color: OfColors.emerald),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            childrenPadding: const EdgeInsets.only(bottom: 6),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: OfColors.emerald),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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

Future<String?> _pickB64() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 70);
  if (picked == null) return null;
  return base64Encode(await picked.readAsBytes());
}

Widget _slipEditor(String title, String hint, SlipTemplate t, void Function(void Function()) setSt, dynamic s) {
  Widget sw(String label, bool v, void Function(bool) on) =>
      SwitchListTile(contentPadding: EdgeInsets.zero, value: v, onChanged: (x) => setSt(() => on(x)), title: Text(label));
  return OfCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(hint, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: TextEditingController(text: t.heading)..selection = TextSelection.collapsed(offset: t.heading.length),
          decoration: InputDecoration(labelText: s.t('slip_heading')),
          onChanged: (v) => t.heading = v,
        ),
        sw(s.t('slip_logo'), t.showLogo, (v) => t.showLogo = v),
        sw(s.t('address'), t.showAddress, (v) => t.showAddress = v),
        sw(s.t('phone'), t.showPhone, (v) => t.showPhone = v),
        sw(s.t('slip_prices'), t.showPrices, (v) => t.showPrices = v),
        sw(s.t('total'), t.showTotals, (v) => t.showTotals = v),
        sw(s.t('payment'), t.showPayment, (v) => t.showPayment = v),
        sw(s.t('slip_qr'), t.showQr, (v) => t.showQr = v),
        sw(s.t('customer'), t.showCustomer, (v) => t.showCustomer = v),
      ],
    ),
  );
}

Widget _b64Thumb(String? raw, {double h = 56}) {
  if (raw == null || raw.isEmpty) {
    return Container(
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0x11000000), borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.add_photo_alternate_outlined),
    );
  }
  try {
    return Image.memory(base64Decode(raw.contains(',') ? raw.split(',').last : raw), height: h, fit: BoxFit.contain);
  } catch (_) {
    return SizedBox(height: h);
  }
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
  final qrLabel = TextEditingController(text: p.payQrLabel);
  var prefix = p.currencyPrefix;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.9,
          child: Column(
            children: [
              Text(s.t('bill_profile'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(s.t('bill_template_hint'), style: const TextStyle(color: OfColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    OfCard(
                      child: Column(
                        children: [
                          Text(s.t('slip_preview'), style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            color: Colors.white,
                            child: DefaultTextStyle(
                              style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.35),
                              child: Column(
                                children: [
                                  _b64Thumb(p.logoBase64, h: 48),
                                  Text(name.text.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  if (address.text.isNotEmpty) Text(address.text, textAlign: TextAlign.center),
                                  if (phone.text.isNotEmpty) Text('Tel. ${phone.text}'),
                                  const Text('* * * * * * * * * * * *'),
                                  Text(p.counterSlip.heading.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const Text('* * * * * * * * * * * *'),
                                  const Align(alignment: Alignment.centerLeft, child: Text('Items & prices come from the order')),
                                  const Align(alignment: Alignment.centerLeft, child: Text('Date & time print when you print')),
                                  const Text('* * * * * * * * * * * *'),
                                  Text(footer.text.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  _b64Thumb(p.payQrBase64, h: 72),
                                  if (qrLabel.text.isNotEmpty) Text(qrLabel.text),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(s.t('slip_header'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final v = await _pickB64();
                        if (v != null) setSt(() => p.logoBase64 = v);
                      },
                      icon: const Icon(Icons.storefront),
                      label: Text(s.t('slip_logo')),
                    ),
                    _b64Thumb(p.logoBase64),
                    const SizedBox(height: 8),
                    TextField(controller: name, decoration: InputDecoration(labelText: s.t('business_name')), onChanged: (_) => setSt(() {})),
                    const SizedBox(height: 8),
                    TextField(controller: address, decoration: InputDecoration(labelText: s.t('address')), onChanged: (_) => setSt(() {})),
                    const SizedBox(height: 8),
                    TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone')), onChanged: (_) => setSt(() {})),
                    const SizedBox(height: 8),
                    TextField(controller: taxId, decoration: InputDecoration(labelText: s.t('tax_id'))),
                    const SizedBox(height: 8),
                    TextField(controller: footer, decoration: InputDecoration(labelText: s.t('footer')), onChanged: (_) => setSt(() {})),
                    const SizedBox(height: 8),
                    TextField(controller: cur, decoration: InputDecoration(labelText: s.t('currency_symbol'))),
                    const SizedBox(height: 8),
                    TextField(controller: tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('tax_rate'))),
                    const SizedBox(height: 8),
                    TextField(controller: svc, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('service_rate'))),
                    const SizedBox(height: 8),
                    if (ref.snap.isMain)
                      TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('set_pin'))),
                    SwitchListTile(value: prefix, onChanged: (v) => setSt(() => prefix = v), title: Text(s.t('prefix_currency'))),
                    const SizedBox(height: 12),
                    Text(s.t('slip_pay_qr'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final v = await _pickB64();
                        if (v != null) setSt(() => p.payQrBase64 = v);
                      },
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(s.t('slip_qr')),
                    ),
                    _b64Thumb(p.payQrBase64, h: 80),
                    TextField(controller: qrLabel, decoration: InputDecoration(labelText: s.t('slip_qr_label')), onChanged: (_) => setSt(() {})),
                    const SizedBox(height: 16),
                    _slipEditor(s.t('role_kitchen'), s.t('slip_kitchen_hint'), p.kitchenSlip, setSt, s),
                    const SizedBox(height: 10),
                    _slipEditor(s.t('slip_counter'), s.t('slip_counter_hint'), p.counterSlip, setSt, s),
                    const SizedBox(height: 10),
                    _slipEditor(s.t('takeaway'), s.t('slip_takeaway_hint'), p.takeawaySlip, setSt, s),
                    const SizedBox(height: 10),
                    _slipEditor(s.t('delivery'), s.t('slip_delivery_hint'), p.deliverySlip, setSt, s),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final next = BillProfile(
                    businessName: name.text.trim().isEmpty ? 'My Shop' : name.text.trim(),
                    address: address.text.trim(),
                    phone: phone.text.trim(),
                    taxId: taxId.text.trim(),
                    footer: footer.text.trim().isEmpty ? 'THANK YOU!' : footer.text.trim(),
                    currencySymbol: cur.text.trim().isEmpty ? kDefaultCurrency : cur.text.trim(),
                    currencyPrefix: prefix,
                    taxRate: double.tryParse(tax.text) ?? 0,
                    serviceRate: double.tryParse(svc.text) ?? 0,
                    logoBase64: p.logoBase64,
                    payQrBase64: p.payQrBase64,
                    payQrLabel: qrLabel.text.trim(),
                    managerPin: ref.snap.isMain ? pin.text.trim() : p.managerPin,
                    kitchenSlip: p.kitchenSlip,
                    counterSlip: p.counterSlip,
                    takeawaySlip: p.takeawaySlip,
                    deliverySlip: p.deliverySlip,
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
  List<BtDevice> bonded = const [];
  var btErr = '';
  var loading = true;
  var started = false;
  var selectedAddress = ref.read(appControllerProvider).session.localBtAddress;
  var selectedName = ref.read(appControllerProvider).session.localBtName;
  var enabled = ref.read(appControllerProvider).session.localBtEnabled;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> loadBt() async {
          setSt(() {
            loading = true;
            btErr = '';
          });
          try {
            final connect = await Permission.bluetoothConnect.request();
            if (connect.isPermanentlyDenied) {
              btErr = s.t('bt_permission_settings');
              bonded = const [];
              if (ctx.mounted) setSt(() => loading = false);
              return;
            }
            bonded = await BluetoothPrinter().bonded();
            btErr = bonded.isEmpty ? s.t('no_bt_printers') : '';
          } on PlatformException catch (e) {
            bonded = const [];
            if (e.code == 'bt_permission') {
              btErr = s.t('bt_permission_retry');
            } else {
              btErr = e.message?.isNotEmpty == true ? e.message! : s.t('bluetooth_off');
            }
          } catch (_) {
            bonded = const [];
            btErr = s.t('bluetooth_off');
          }
          if (ctx.mounted) setSt(() => loading = false);
        }

        if (!started) {
          started = true;
          Future.microtask(loadBt);
        }

        Future<void> testLocal() async {
          final addr = selectedAddress.trim();
          if (addr.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('no_bt_printers'))));
            return;
          }
          try {
            final cfg = PrinterConfig(
              name: selectedName.isEmpty ? 'Bluetooth' : selectedName,
              enabled: true,
              transport: 'bluetooth',
              btAddress: addr,
              btName: selectedName,
            );
            await ref.ctrl.printer.test(cfg, ref.snap.store.profile.businessName);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_ok'))));
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('print_fail'))));
            }
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.t('station_bt_printer'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 6),
                Text(s.t('station_bt_printer_hint'), style: const TextStyle(color: OfColors.muted, height: 1.35)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('use_this_bt_printer')),
                  subtitle: Text(
                    selectedAddress.isEmpty
                        ? s.t('no_bt_selected')
                        : (selectedName.isEmpty ? selectedAddress : '$selectedName · $selectedAddress'),
                  ),
                  value: enabled && selectedAddress.isNotEmpty,
                  onChanged: (v) async {
                    if (v && selectedAddress.isEmpty) {
                      setSt(() => btErr = s.t('pick_bt_first'));
                      return;
                    }
                    enabled = v;
                    setSt(() {});
                    if (v) {
                      await ref.ctrl.setLocalBluetoothPrinter(
                        address: selectedAddress,
                        name: selectedName,
                        enabled: true,
                      );
                    } else {
                      await ref.ctrl.clearLocalBluetoothPrinter();
                    }
                  },
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: loading ? null : loadBt,
                      icon: loading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(s.t('pick_bt_printer')),
                    ),
                    const Spacer(),
                    TextButton(onPressed: testLocal, child: Text(s.t('test_print'))),
                  ],
                ),
                if (btErr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(btErr, style: const TextStyle(color: Colors.orange, height: 1.3)),
                  ),
                if (btErr == s.t('bt_permission_settings') || btErr == s.t('bt_permission_retry'))
                  TextButton(
                    onPressed: () => openAppSettings(),
                    child: Text(s.t('open_app_settings')),
                  ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : bonded.isEmpty
                          ? Center(child: Text(s.t('no_bt_printers'), textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted)))
                          : ListView.builder(
                              itemCount: bonded.length,
                              itemBuilder: (_, i) {
                                final d = bonded[i];
                                final sel = selectedAddress == d.address;
                                return ListTile(
                                  leading: Icon(Icons.print, color: sel ? OfColors.emerald : OfColors.muted),
                                  title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(d.address),
                                  trailing: sel ? const Icon(Icons.check_circle, color: OfColors.emerald) : null,
                                  onTap: () async {
                                    selectedAddress = d.address;
                                    selectedName = d.name;
                                    enabled = true;
                                    setSt(() {});
                                    await ref.ctrl.setLocalBluetoothPrinter(
                                      address: d.address,
                                      name: d.name,
                                      enabled: true,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(s.t('bt_printer_saved'))),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                ),
                const SizedBox(height: 8),
                Text(s.t('station_bt_note'), style: const TextStyle(color: OfColors.muted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.t('done')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _customers(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final list = [...ref.snap.store.customers]..sort((a, b) => a.name.compareTo(b.name));
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: Column(
            children: [
              ListTile(
                title: Text(s.t('customers_book'), style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _editCustomer(ctx, ref)),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.people_outline, message: s.t('no_customers'))
                    : ListView(
                        children: list
                            .map((c) => ListTile(
                                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text([
                                    c.phone,
                                    c.address,
                                    if (c.points > 0) '${s.t('loyalty')} ${c.points.toStringAsFixed(0)}',
                                    if (c.credit > 0) '${s.t('store_credit')} ${moneyOf(ref.snap, c.credit)}',
                                  ].where((e) => e.isNotEmpty).join(' · ')),
                                  onTap: () => _editCustomer(ctx, ref, existing: c),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => ref.ctrl.dispatch(NetCommand(name: 'deleteCustomer', payload: {'id': c.id})),
                                  ),
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

Future<void> _editCustomer(BuildContext context, WidgetRef ref, {ShopCustomer? existing}) async {
  final s = ref.s;
  final name = TextEditingController(text: existing?.name ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final address = TextEditingController(text: existing?.address ?? '');
  final points = TextEditingController(text: (existing?.points ?? 0).toStringAsFixed(0));
  final credit = TextEditingController(text: (existing?.credit ?? 0).toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(s.t('customers_book')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: s.t('customer_name'))),
            TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
            TextField(controller: address, decoration: InputDecoration(labelText: s.t('address'))),
            TextField(controller: points, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('loyalty'))),
            TextField(controller: credit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: s.t('store_credit'))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('save'))),
      ],
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    await ref.ctrl.dispatch(NetCommand(name: 'upsertCustomer', payload: {
      'customer': ShopCustomer(
        id: existing?.id ?? newId(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        address: address.text.trim(),
        notes: existing?.notes ?? '',
        points: double.tryParse(points.text) ?? 0,
        credit: double.tryParse(credit.text) ?? 0,
      ).toJson(),
    }));
  }
}

Future<void> _shiftCash(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final store = ref.snap.store;
  final open = store.shiftCashier.isNotEmpty;
  final name = TextEditingController(text: store.shiftCashier.isEmpty ? ref.snap.session.displayName : store.shiftCashier);
  final cash = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(open ? s.t('end_shift') : s.t('start_shift')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (open) Text('${s.t('shift_open')}: ${store.shiftCashier}'),
          if (!open) TextField(controller: name, decoration: InputDecoration(labelText: s.t('your_name'))),
          TextField(
            controller: cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: open ? s.t('shift_end_cash') : s.t('shift_float')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(open ? s.t('end_shift') : s.t('start_shift'))),
      ],
    ),
  );
  if (ok != true) return;
  final amount = double.tryParse(cash.text) ?? 0;
  if (open) {
    await ref.ctrl.dispatch(NetCommand(name: 'endShift', payload: {'endCash': amount}));
  } else {
    await ref.ctrl.setDisplayName(name.text.trim());
    await ref.ctrl.dispatch(NetCommand(name: 'startShift', payload: {'name': name.text.trim(), 'float': amount}));
  }
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

Color _dutyColor(StaffDuty d) => switch (d) {
      StaffDuty.onShift => OfColors.emerald,
      StaffDuty.mealBreak => OfColors.warn,
      StaffDuty.teaBreak => OfColors.gold,
      StaffDuty.offline => OfColors.muted,
    };

Future<void> _editStaff(BuildContext context, WidgetRef ref, {StaffMember? existing}) async {
  final s = ref.s;
  final name = TextEditingController(text: existing?.name ?? '');
  final role = TextEditingController(text: existing?.roleLabel ?? '');
  final pin = TextEditingController(text: existing?.pin ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(s.t('staff')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('name'))),
          TextField(controller: role, decoration: InputDecoration(labelText: s.t('roles'))),
          TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('staff_pin'))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('save'))),
      ],
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty && pin.text.trim().isNotEmpty) {
    await ref.ctrl.dispatch(NetCommand(name: 'upsertStaff', payload: {
      'staff': StaffMember(
        id: existing?.id ?? newId(),
        name: name.text.trim(),
        roleLabel: role.text.trim(),
        pin: pin.text.trim(),
        duty: existing?.duty ?? StaffDuty.offline,
        active: existing?.active ?? true,
      ).toJson(),
    }));
  }
}

Future<void> _staff(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final list = [...ref.snap.store.staff]..sort((a, b) => a.name.compareTo(b.name));
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.72,
          child: Column(
            children: [
              ListTile(
                title: Text(s.t('staff'), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(s.t('staff_duty_hint')),
                trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _editStaff(ctx, ref)),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.badge, message: s.t('staff_empty'))
                    : ListView(
                        children: list
                            .map((st) => ListTile(
                                  title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(st.roleLabel),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      StatusChip(s.t('duty_${st.duty.name}'), color: _dutyColor(st.duty)),
                                      if (ref.snap.isMain || ref.snap.isManager)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                          onPressed: () => ref.ctrl.dispatch(NetCommand(name: 'deleteStaff', payload: {'id': st.id})),
                                        ),
                                    ],
                                  ),
                                  onTap: (ref.snap.isMain || ref.snap.isManager) ? () => _editStaff(ctx, ref, existing: st) : null,
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
          ListTile(
            title: Text(s.t('x_report')),
            subtitle: Text(s.t('cash')),
            trailing: Text(
              moneyOf(
                ref.snap,
                paid.where((o) {
                  final d = DateTime.now();
                  return o.updatedAt.year == d.year && o.updatedAt.month == d.month && o.updatedAt.day == d.day && o.payment == PaymentMethod.cash;
                }).fold<double>(0, (a, o) => a + o.total),
              ),
            ),
          ),
          ListTile(
            title: Text(s.t('z_report')),
            subtitle: Text(s.t('day_close')),
            trailing: Text(moneyOf(ref.snap, today)),
          ),
          ListTile(
            title: Text(s.t('void_report')),
            trailing: Text('${store.orders.where((o) => o.status == OrderStatus.cancelled).length}'),
          ),
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
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: () {
              launchUrl(
                Uri.parse(kLicenseWhatsAppUrl(
                  name: ref.snap.session.displayName,
                  businessName: ref.snap.store.profile.businessName,
                  phone: ref.snap.store.profile.phone,
                )),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.chat),
            label: Text(s.t('whatsapp_support')),
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


Future<void> _eightySixBoard(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final off = ref.snap.store.products.where((p) => !p.available).toList();
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
          child: Column(
            children: [
              ListTile(title: Text(s.t('eighty_six_board'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(
                child: off.isEmpty
                    ? EmptyState(icon: Icons.check_circle, message: s.t('empty'))
                    : ListView(
                        children: off
                            .map((p) => ListTile(
                                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  trailing: TextButton(
                                    onPressed: () => eightySix(ctx, ref, p),
                                    child: Text(s.t('available')),
                                  ),
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

Future<void> _unpaidTabs(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final list = ref.snap.store.orders
            .where((o) => o.status == OrderStatus.served || o.status == OrderStatus.ready)
            .toList();
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
          child: Column(
            children: [
              ListTile(title: Text(s.t('unpaid_tabs'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.payments, message: s.t('empty'))
                    : ListView(
                        children: list
                            .map((o) => ListTile(
                                  title: Text('${o.ticketNo}  ${o.tableName ?? o.customerName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(s.t(o.status.name)),
                                  trailing: Text(moneyOf(ref.snap, o.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    context.push('/order/${o.id}');
                                  },
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

Future<void> _reservations(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final list = [...ref.snap.store.appointments]..sort((a, b) => a.start.compareTo(b.start));
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              ListTile(
                title: Text(s.t('appointments'), style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final name = TextEditingController();
                    final phone = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: Text(s.t('add_appointment')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(controller: name, decoration: InputDecoration(labelText: s.t('customer_name'))),
                            TextField(controller: phone, decoration: InputDecoration(labelText: s.t('phone'))),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('book'))),
                        ],
                      ),
                    );
                    if (ok != true || name.text.trim().isEmpty) return;
                    final staffId = ref.snap.store.staff.isEmpty ? '' : ref.snap.store.staff.first.id;
                    final serviceId = ref.snap.store.services.isEmpty ? '' : ref.snap.store.services.first.id;
                    await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {
                      'appointment': Appointment(
                        id: newId(),
                        serviceId: serviceId,
                        staffId: staffId,
                        customerName: name.text.trim(),
                        customerPhone: phone.text.trim(),
                      ).toJson(),
                    }));
                  },
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.event_busy, message: s.t('no_appts'))
                    : ListView(
                        children: list
                            .map((a) => ListTile(
                                  title: Text(a.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${a.start.hour.toString().padLeft(2, '0')}:${a.start.minute.toString().padLeft(2, '0')}  ${a.customerPhone}'),
                                  trailing: StatusChip(a.status, color: OfColors.emerald),
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
