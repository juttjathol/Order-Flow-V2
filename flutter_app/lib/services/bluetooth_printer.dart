import 'dart:typed_data';

import 'package:flutter/services.dart';

class BtDevice {
  BtDevice({required this.name, required this.address});
  final String name;
  final String address;
}

class BluetoothPrinter {
  static const _ch = MethodChannel('jathol/printer');

  Future<List<BtDevice>> bonded() async {
    final raw = await _ch.invokeMethod<List<dynamic>>('bonded');
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) => BtDevice(
              name: (e['name'] ?? 'Printer').toString(),
              address: (e['address'] ?? '').toString(),
            ))
        .where((d) => d.address.isNotEmpty)
        .toList();
  }

  Future<void> printBytes(String address, List<int> bytes) async {
    await _ch.invokeMethod('print', {
      'address': address,
      'bytes': Uint8List.fromList(bytes),
    });
  }
}
