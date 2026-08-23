import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/models.dart';

/// Camera or a USB/Bluetooth HID gun (guns type the code and press Enter).
Future<String?> scanBarcode(BuildContext context, {required String title, required String hint}) {
  var handled = false;
  final gun = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(hint),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: gun,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'USB / Bluetooth scanner',
                  hintText: 'Scan here or type SKU',
                  prefixIcon: const Icon(Icons.document_scanner),
                ),
                onSubmitted: (v) {
                  final code = v.trim();
                  if (code.isEmpty) return;
                  Navigator.pop(ctx, code);
                },
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: MobileScanner(
                  onDetect: (capture) {
                    if (handled) return;
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value == null || value.trim().isEmpty) return;
                    handled = true;
                    Navigator.pop(ctx, value.trim());
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<double?> askScanQty(BuildContext context, {required String title, double initial = 1}) async {
  final ctrl = TextEditingController(text: initial % 1 == 0 ? initial.toInt().toString() : '$initial');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Qty'),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ],
    ),
  );
  if (ok != true) return null;
  final n = double.tryParse(ctrl.text.trim());
  if (n == null || n <= 0) return null;
  return n;
}

MenuProduct? productBySku(AppStore store, String code) {
  final needle = code.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final p in store.products) {
    if (p.sku.trim().toLowerCase() == needle) return p;
  }
  for (final p in store.products) {
    if (p.sku.isNotEmpty && p.sku.trim().toLowerCase().contains(needle)) return p;
  }
  return null;
}

StockItem? stockBySku(AppStore store, String code) {
  final needle = code.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final s in store.stock) {
    if (s.sku.trim().toLowerCase() == needle) return s;
  }
  for (final s in store.stock) {
    if (s.sku.isNotEmpty && s.sku.trim().toLowerCase().contains(needle)) return s;
  }
  return null;
}
