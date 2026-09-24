import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class BtDevice {
  BtDevice({required this.name, required this.address, this.transport = 'auto'});
  final String name;
  final String address;

  /// 'auto' (classic ladder, then LE), 'spp' (Bluetooth Classic RFCOMM)
  /// or 'ble' (GATT). v1.1.68 — the native transport no longer cares what
  /// the printer is called; it just speaks both languages.
  final String transport;
}

class BluetoothPrinter {
  static const _ch = MethodChannel('jathol/printer');

  /// Paired Classic/LE Bluetooth devices. Throws [PlatformException] with
  /// code `bt_permission` when Android 12+ needs Nearby devices permission.
  Future<List<BtDevice>> bonded() async {
    // Desktop (Main on a shop laptop): no Bluetooth printing — printers go
    // over LAN or through the Windows spooler instead.
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('bonded');
      return (raw ?? const [])
          .whereType<Map>()
          .map((e) => BtDevice(
                name: (e['name'] ?? 'Printer').toString(),
                address: (e['address'] ?? '').toString(),
                // Native reports device.type; 2 == LE-only peripheral.
                transport: '${e['type']}' == '2' ? 'ble' : 'auto',
              ))
          .where((d) => d.address.isNotEmpty)
          .toList();
    } on PlatformException {
      rethrow;
    }
  }

  /// Nearby BLE peripherals (whether paired or not) — for LE-only printers
  /// that never show up in Android's classic pairing list.
  Future<List<BtDevice>> bleScan() async {
    if (!Platform.isAndroid) return const [];
    final raw = await _ch.invokeMethod<List<dynamic>>('ble_scan');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => BtDevice(
              name: (e['name'] ?? '').toString(),
              address: (e['address'] ?? '').toString(),
              transport: 'ble',
            ))
        .where((d) => d.address.isNotEmpty)
        .toList();
  }

  /// Release the native held RFCOMM link (printer switch / un-set) so the
  /// printer is instantly free for the next app or device.
  Future<void> forget(String address) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('forget', {'address': address});
    } catch (_) {}
  }

  /// [transport]: 'auto' tries Bluetooth Classic (SPP) first, then BLE
  /// GATT; 'spp'/'ble' pin one. Errors carry the real reason.
  Future<void> printBytes(String address, List<int> bytes,
      {String transport = 'auto'}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Bluetooth printing is only available on Android devices.');
    }
    await _ch.invokeMethod('print', {
      'address': address,
      'bytes': Uint8List.fromList(bytes),
      'transport': transport,
    });
  }
}
