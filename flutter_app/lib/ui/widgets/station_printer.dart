import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/platform_check.dart';
import '../../core/theme.dart';
import '../../services/bluetooth_printer.dart';
import '../../services/windows_printer.dart';
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
  await showLocalPrinterSheet(context, ref);
}

/// Ungated entry (v1.1.76): a desktop Main configuring its own printer is
/// core printing, not a per-station extra — same as the Main BT sheet on
/// Android. On phones this is identical to [showStationPrinterSheet].
Future<void> showLocalPrinterSheet(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  List<BtDevice> bonded = const [];
  var btErr = '';
  var loading = true;
  var started = false;
  String mode; // 'bt' | 'sys' (Windows system printers) | 'lan'
  if (OfPlatform.supportsBluetoothPrinting) {
    mode = 'bt';
  } else if (OfPlatform.supportsWindowsSpooler) {
    mode = 'sys';
  } else {
    mode = 'lan';
  }
  // What this device supports — phones get Bluetooth, desktop gets the
  // Windows spooler, and everyone gets plain LAN (port 9100).
  final modes = <MapEntry<String, IconData>>[
    if (OfPlatform.supportsBluetoothPrinting)
      MapEntry('bt', Icons.bluetooth),
    if (OfPlatform.supportsWindowsSpooler)
      MapEntry('sys', Icons.print),
    MapEntry('lan', Icons.lan),
  ];
  List<String> sysPrinters = const [];
  var sysLoading = false;
  var sysStarted = false;
  final host = TextEditingController(text: ref.snap.session.localNetHost);
  final port = TextEditingController(
    text: ref.snap.session.localNetPort.toString(),
  );
  var selectedBt = ref.read(appControllerProvider).session.localBtAddress;
  var selTransport = ref.read(appControllerProvider).session.localBtTransport;
  List<BtDevice> ble = const [];
  var scanning = false;

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
            await Permission.bluetoothScan.request();
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

        Future<void> scanBle() async {
          setSt(() => scanning = true);
          try {
            ble = await BluetoothPrinter().bleScan();
          } catch (_) {
            ble = const [];
          }
          if (ctx.mounted) setSt(() => scanning = false);
        }

        Future<void> loadSystemPrinters() async {
          try {
            sysPrinters = WindowsRawPrinter.listNames();
          } catch (_) {
            sysPrinters = const [];
          }
          sysLoading = false;
          if (ctx.mounted) setSt(() {});
        }

        if (!started) {
          started = true;
          if (mode == 'bt') {
            Future.microtask(loadBt);
          } else if (mode == 'sys') {
            Future.microtask(loadSystemPrinters);
          }
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
          } on PlatformException catch (e) {
            if (context.mounted) {
              final why = e.code == 'bt_permission'
                  ? s.t('bt_permission_retry')
                  : '${s.t('print_fail')}: ${_errCap(e.message ?? '')}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(why)),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('${s.t('print_fail')}: ${_errCap(e.toString())}')),
              );
            }
          }
        }

        final hasLocal = ref.snap.session.hasLocalBtPrinter ||
            ref.snap.session.hasLocalNetPrinter ||
            ref.snap.session.hasLocalSpoolerPrinter;

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
                SegmentedButton<String>(
                  segments: [
                    for (final m in modes)
                      ButtonSegment(
                        value: m.key,
                        icon: Icon(m.value),
                        label: Text(s.t(m.key == 'bt'
                            ? 'bluetooth'
                            : m.key == 'sys'
                                ? 'win_printers'
                                : 'lan_network')),
                      ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) => setSt(() {
                    mode = v.first;
                    if (mode == 'bt') {
                      Future.microtask(loadBt);
                    } else if (mode == 'sys' && !sysStarted) {
                      sysStarted = true;
                      sysLoading = true;
                      Future.microtask(loadSystemPrinters);
                    }
                  }),
                ),
                const SizedBox(height: 10),
                if (ref.snap.session.hasLocalSpoolerPrinter)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: StatusChip(
                      '${s.t('win_printers')}: ${ref.snap.session.localSpoolerName.trim()}',
                      color: OfColors.mint,
                    ),
                  ),
                if (ref.snap.session.hasLocalNetPrinter)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: StatusChip(
                      '${s.t('lan_network')}: ${ref.snap.session.localNetHost}:${ref.snap.session.localNetPort}',
                      color: OfColors.mint,
                    ),
                  ),
                if (ref.snap.session.hasLocalBtPrinter)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: StatusChip(
                      '${s.t('bluetooth')}: ${ref.snap.session.localBtName.isNotEmpty ? ref.snap.session.localBtName : ref.snap.session.localBtAddress}',
                      color: OfColors.mint,
                    ),
                  ),
                Expanded(
                  child: switch (mode) {
                    'sys' => () {
                        if (sysLoading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final sp = sysPrinters;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s.t('win_printers_hint'),
                              style: const TextStyle(color: OfColors.muted, fontSize: 12.5, height: 1.35),
                            ),
                            const SizedBox(height: 8),
                            if (sp.isEmpty)
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      sp.isEmpty
                                          ? s.t('no_win_printers')
                                          : '',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: OfColors.muted, height: 1.5),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: ListView.separated(
                                  itemCount: sp.length,
                                  separatorBuilder: (_, __) => const Divider(height: 12),
                                  itemBuilder: (_, i) {
                                    final name = sp[i];
                                    final selected = ref.snap.session.localSpoolerEnabled && ref.snap.session.localSpoolerName.trim() == name;
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        Icons.print,
                                        color: selected ? OfColors.emerald : OfColors.muted,
                                        size: 20,
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                      subtitle: Text(
                                        s.t(selected ? 'win_printers_selected' : 'tap_to_choose_win_printer'),
                                        style: TextStyle(
                                          color: selected ? OfColors.emerald : OfColors.muted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                      onTap: () async {
                                        await ref.ctrl.setLocalSpoolerPrinter(name: name, enabled: true);
                                        setSt(() {});
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
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () {
                                sysLoading = true;
                                setSt(() {});
                                loadSystemPrinters();
                              },
                              icon: sysLoading
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh, size: 16),
                              label: Text(s.t('refresh')),
                            ),
                          ],
                        );
                      }(),
                    'lan' => Column(
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
                    _ => loading
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
                                  child: () {
                                    final seen = bonded.map((e) => e.address).toSet();
                                    final all = [
                                      ...bonded,
                                      ...ble.where((d) => !seen.contains(d.address)),
                                    ];
                                    if (all.isEmpty) {
                                      return Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Text(
                                            '${s.t('no_bt_printers')}\n${s.t('bt_pair_first')}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: OfColors.muted, height: 1.5),
                                          ),
                                        ),
                                      );
                                    }
                                    return ListView.builder(
                                          itemCount: all.length,
                                          itemBuilder: (_, i) {
                                            final d = all[i];
                                            final sel = selectedBt == d.address;
                                            return ListTile(
                                              leading: Icon(
                                                  d.transport == 'ble'
                                                      ? Icons.bluetooth
                                                      : Icons.print,
                                                  color: sel ? OfColors.emerald : OfColors.muted),
                                              title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                              subtitle: Text(d.address),
                                              trailing: sel
                                                  ? const Icon(Icons.check_circle,
                                                      color: OfColors.emerald)
                                                  : (d.transport == 'ble'
                                                      ? const Text('LE',
                                                          style: TextStyle(
                                                              color: OfColors.info,
                                                              fontWeight: FontWeight.w800))
                                                      : null),
                                              onTap: () async {
                                                selectedBt = d.address;
                                                selTransport =
                                                    d.transport == 'ble' ? 'ble' : 'auto';
                                                setSt(() {});
                                                await ref.ctrl.setLocalBluetoothPrinter(
                                                  address: d.address,
                                                  name: d.name,
                                                  enabled: true,
                                                  transport: selTransport,
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(s.t('printer_saved'))),
                                                  );
                                                }
                                              },
                                            );
                                          },
                                        );
                                  }(),
                                ),
                                TextButton.icon(
                                  onPressed: loading ? null : loadBt,
                                  icon: loading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.refresh),
                                  label: Text(s.t('pick_bt_printer')),
                                ),
                                TextButton.icon(
                                  onPressed: scanning ? null : scanBle,
                                  icon: scanning
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.bluetooth_searching),
                                  label: Text(s.t(scanning ? 'bt_scanning' : 'bt_ble_scan')),
                                ),
                                if (selectedBt.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 6,
                                      children: [
                                        for (final t in const ['auto', 'spp', 'ble'])
                                          ChoiceChip(
                                            label: Text(t == 'spp'
                                                ? s.t('bt_via_classic')
                                                : t == 'ble'
                                                    ? s.t('bt_via_le')
                                                    : s.t('bt_via_auto')),
                                            selected: selTransport == t,
                                            onSelected: (_) async {
                                              selTransport = t;
                                              setSt(() {});
                                              await ref.ctrl.setLocalBluetoothPrinter(
                                                address: selectedBt,
                                                name: ref.snap.session.localBtName,
                                                enabled: true,
                                                transport: t,
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            )
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.t('print_size'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final mm in const [0, 58, 76, 80, 100])
                      ChoiceChip(
                        label: Text(mm == 0 ? s.t('print_size_auto') : '$mm mm'),
                        selected: ref.snap.session.localPaperMm == mm,
                        onSelected: (_) => ref.ctrl.setLocalPaperMm(mm),
                      ),
                  ],
                ),
                Text(
                  s.t('print_size_hint'),
                  style: const TextStyle(color: OfColors.muted, fontSize: 11, height: 1.3),
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
                      onPressed: hasLocal
                          ? () async {
                              try {
                                await ref.ctrl.printer
                                    .openDrawer(ref.ctrl.deviceLocalPrinter()!);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(s.t('drawer_opened'))),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(s.t('drawer_failed'))),
                                  );
                                }
                              }
                            }
                          : null,
                      icon: const Icon(Icons.unarchive),
                      label: Text(s.t('drawer_test')),
                    ),
                    const SizedBox(width: 4),
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

/// Toast-size error detail: printer complaints can be long.
String _errCap(String s) => s.length <= 140 ? s : '${s.substring(0, 137)}…';
