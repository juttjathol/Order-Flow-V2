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
                decoration: const InputDecoration(
                  labelText: 'USB / Bluetooth scanner',
                  hintText: 'Scan here or type SKU',
                  prefixIcon: Icon(Icons.document_scanner),
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

/// Stay-open sell/stock scan: code → qty → add → scan next.
Future<void> scanLoop(
  BuildContext context, {
  required String title,
  required String hint,
  required Future<String?> Function(String code, double qty) onCommit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (ctx) => _ScanLoopSheet(title: title, hint: hint, onCommit: onCommit),
  );
}

class _ScanLoopSheet extends StatefulWidget {
  const _ScanLoopSheet({required this.title, required this.hint, required this.onCommit});
  final String title;
  final String hint;
  final Future<String?> Function(String code, double qty) onCommit;

  @override
  State<_ScanLoopSheet> createState() => _ScanLoopSheetState();
}

class _ScanLoopSheetState extends State<_ScanLoopSheet> {
  final gun = TextEditingController();
  final qty = TextEditingController(text: '1');
  String? pending;
  String status = '';
  bool busy = false;
  DateTime? lastCam;

  @override
  void dispose() {
    gun.dispose();
    qty.dispose();
    super.dispose();
  }

  Future<void> _take(String code) async {
    final c = code.trim();
    if (c.isEmpty) return;
    setState(() {
      pending = c;
      gun.text = c;
      qty.text = '1';
      status = c;
    });
  }

  Future<void> _commit() async {
    final code = (pending ?? gun.text).trim();
    final n = double.tryParse(qty.text.trim()) ?? 0;
    if (code.isEmpty || n <= 0 || busy) return;
    setState(() => busy = true);
    final err = await widget.onCommit(code, n);
    if (!mounted) return;
    setState(() {
      busy = false;
      status = err ?? 'OK  $code × $n';
      pending = null;
      gun.clear();
      qty.text = '1';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            ListTile(
              title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(widget.hint),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: gun,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'USB / Bluetooth / SKU',
                        prefixIcon: Icon(Icons.document_scanner),
                      ),
                      onSubmitted: _take,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Qty'),
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: busy ? null : _commit, child: const Text('Add')),
                ],
              ),
            ),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text(status)),
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: MobileScanner(
                  onDetect: (capture) {
                    final now = DateTime.now();
                    if (lastCam != null && now.difference(lastCam!).inMilliseconds < 900) return;
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value == null || value.trim().isEmpty) return;
                    lastCam = now;
                    _take(value);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
