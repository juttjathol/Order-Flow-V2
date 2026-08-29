import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';

/// Camera or a USB/Bluetooth HID gun (guns type the code and press Enter).
Future<String?> scanBarcode(BuildContext context, {required String title, required String hint}) {
  var handled = false;
  final gun = TextEditingController();
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                controller: gun,
                autofocus: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'USB / Bluetooth scanner',
                  hintText: hint,
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
              child: ShopCameraScan(
                onCode: (value) {
                  if (handled) return;
                  handled = true;
                  Navigator.pop(ctx, value);
                },
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
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _ScanLoopSheet(title: title, hint: hint, onCommit: onCommit),
      ),
    ),
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
      child: Column(
          children: [
            ListTile(
              title: Text(widget.hint, style: const TextStyle(fontSize: 13)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: gun,
                      autofocus: false,
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
              child: ShopCameraScan(
                onCode: (value) {
                  final now = DateTime.now();
                  if (lastCam != null && now.difference(lastCam!).inMilliseconds < 900) return;
                  lastCam = now;
                  _take(value);
                },
              ),
            ),
          ],
        ),
    );
  }
}

class ShopCameraScan extends StatefulWidget {
  const ShopCameraScan({super.key, required this.onCode, this.hint});
  final void Function(String code) onCode;
  final String? hint;

  @override
  State<ShopCameraScan> createState() => _ShopCameraScanState();
}

class _ShopCameraScanState extends State<ShopCameraScan> with WidgetsBindingObserver {
  MobileScannerController? _ctrl;
  var _live = false;
  var _fail = false;
  var _busy = false;

  static const _ask = MethodChannel('jathol/shop_keepalive');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Widget _failPane() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_outlined, color: Colors.white70, size: 36),
            const SizedBox(height: 10),
            const Text(
              'Allow camera while using the app. If Android asks, choose While using the app. You can still type or use a USB / Bluetooth scanner.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _boot, child: const Text('Open camera')),
          ],
        ),
      ),
    );
  }

  Future<bool> _waitCameraPermission() async {
    try {
      final ok = await _ask.invokeMethod<dynamic>('askCamera');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  MobileScannerController _newCtrl() {
    return MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  Future<void> _boot() async {
    if (_busy) return;
    _busy = true;
    setState(() {
      _live = false;
      _fail = false;
    });
    await _ctrl?.dispose();
    _ctrl = _newCtrl();
    final allowed = await _waitCameraPermission();
    if (!mounted) {
      _busy = false;
      return;
    }
    if (!allowed) {
      _busy = false;
      setState(() => _fail = true);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) {
      _busy = false;
      return;
    }
    await _ctrl?.dispose();
    _ctrl = _newCtrl();
    setState(() {});
    try {
      await _ctrl!.start();
      if (mounted) setState(() => _live = true);
    } catch (_) {
      if (mounted) setState(() => _fail = true);
    }
    _busy = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(c.start());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(c.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: _fail
          ? _failPane()
          : !_live || _ctrl == null
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : MobileScanner(
                  controller: _ctrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, child) => _failPane(),
                  onDetect: (capture) {
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value == null || value.trim().isEmpty) return;
                    widget.onCode(value.trim());
                  },
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
