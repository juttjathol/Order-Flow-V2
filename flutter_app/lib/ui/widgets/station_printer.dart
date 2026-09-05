import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/bluetooth_printer.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/plan_lock.dart';

/// Printer settings for THIS device (any station or Main).
/// Choosing a local printer overrides the shop-level printer targets
/// for everything this device prints (kitchen slips, receipts, drawer).
Future<void> showStationPrinterSheet(BuildContext context, WidgetRef ref) async {
  // v1.1.59 plan gate — legacy keys (no plan set) are unaffected.
  if (!ref.snap.canFeature('station_printers')) {
    await showPlanLock(context, ref, featureKey: 'station_printers');
    return;
  }
  final s = ref.s;
  List<BtDevice> bonded = const [];
  var btErr = '';
  var loading = true;
  var started = false;
  var mode = 0; // 0 = Bluetooth, 1 = LAN
  final host = TextEditingController(text: ref.snap.session.localNetHost);
  final port = TextEditingController(
    text: ref.snap.session.localNetPort.toString(),
  );
  var selectedBt = ref.read(appControllerProvider).session.localBtAddress;

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

        Future<void> saveLan() async {
          final h = host.text.trim();
          final p = int.tryParse(port.text.trim()) ?? kEscPosPort;
          if (h.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('lan_host_required'))),
              );
            }
            return;
          }
          await ref.ctrl.setLocalLanPrinter(host: h, port: p, enabled: true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.t('printer_saved'))),
            );
          }
        }

        Future<void> testPrinter() async {
          final local = ref.ctrl.deviceLocalPrinter();
          if (local == null) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('no_local_printer'))),
              );
            }
            return;
          }
          try {
            await ref.ctrl.printer.test(local, ref.snap.store.profile.businessName);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('print_ok'))),
              );
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('print_fail'))),
              );
            }
          }
        }

        final hasLocal = ref.snap.session.hasLocalBtPrinter ||
            ref.snap.session.hasLocalNetPrinter;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.t('station_printer'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(s.t('station_printer_hint'), style: const TextStyle(color: OfColors.muted, height: 1.35)),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, icon: const Icon(Icons.bluetooth), label: Text(s.t('bluetooth'))),
                    ButtonSegment(value: 1, icon: const Icon(Icons.lan), label: Text(s.t('lan_network'))),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => setSt(() => mode = v.first),
                ),
                const SizedBox(height: 10),
                if (hasLocal)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: StatusChip(
                      ref.snap.session.hasLocalNetPrinter
                          ? '${s.t('lan_network')}: ${ref.snap.session.localNetHost}:${ref.snap.session.localNetPort}'
                          : '${s.t('bluetooth')}: ${ref.snap.session.localBtName.isNotEmpty ? ref.snap.session.localBtName : ref.snap.session.localBtAddress}',
                      color: OfColors.mint,
                    ),
                  ),
                Expanded(
                  child: mode == 0
                      ? loading
                          ? const Center(child: CircularProgressIndicator())
                          : Column(
                              children: [
                                if (btErr.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(btErr, style: const TextStyle(color: Colors.orange, height: 1.3)),
                                  ),
                                if (btErr == s.t('bt_permission_settings') || btErr == s.t('bt_permission_retry'))
                                  TextButton(
                                    onPressed: () => openAppSettings(),
                                    child: Text(s.t('open_app_settings')),
                                  ),
                                Expanded(
                                  child: bonded.isEmpty
                                      ? Center(child: Text(s.t('no_bt_printers'), textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted)))
                                      : ListView.builder(
                                          itemCount: bonded.length,
                                          itemBuilder: (_, i) {
                                            final d = bonded[i];
                                            final sel = selectedBt == d.address;
                                            return ListTile(
                                              leading: Icon(Icons.print, color: sel ? OfColors.emerald : OfColors.muted),
                                              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                              subtitle: Text(d.address),
                                              trailing: sel ? const Icon(Icons.check_circle, color: OfColors.emerald) : null,
                                              onTap: () async {
                                                selectedBt = d.address;
                                                setSt(() {});
                                                await ref.ctrl.setLocalBluetoothPrinter(
                                                  address: d.address,
                                                  name: d.name,
                                                  enabled: true,
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(s.t('printer_saved'))),
                                                  );
                                                }
                                              },
                                            );
                                          },
                                        ),
                                ),
                                TextButton.icon(
                                  onPressed: loading ? null : loadBt,
                                  icon: loading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.refresh),
                                  label: Text(s.t('pick_bt_printer')),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: host,
                                  keyboardType: TextInputType.url,
                                  decoration: InputDecoration(
                                    labelText: s.t('printer_ip'),
                                    hintText: '192.168.1.100',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: port,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(labelText: s.t('printer_port')),
                                ),
                                const SizedBox(height: 8),
                                Text(s.t('lan_printer_hint'), style: const TextStyle(color: OfColors.muted, fontSize: 12, height: 1.35)),
                                const SizedBox(height: 8),
                                FilledButton.tonal(onPressed: saveLan, child: Text(s.t('use_this_lan_printer'))),
                              ],
                            ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: hasLocal
                          ? () async {
                              await ref.ctrl.clearLocalBluetoothPrinter();
                              setSt(() {});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.t('use_shop_printer'))),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.storefront),
                      label: Text(s.t('use_shop_printer')),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: hasLocal ? testPrinter : null,
                      icon: const Icon(Icons.print),
                      label: Text(s.t('test_print')),
                    ),
                  ],
                ),
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
