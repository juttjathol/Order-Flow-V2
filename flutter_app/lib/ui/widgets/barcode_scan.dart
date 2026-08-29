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
  late final MobileScannerController controller;

  var _starting = false;
  var _showHelp = false;
  String? _errorHint;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
    );
    WidgetsBinding.instance.addObserver(this);
    // Start after first frame so the platform view has a size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openCamera());
    });
  }

  Future<void> _openCamera() async {
    if (_starting) return;
    _starting = true;
    if (mounted) {
      setState(() {
        _showHelp = false;
        _errorHint = null;
      });
    }

    try {
      // Ask OS for camera if needed (permission_handler).
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }

      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _showHelp = true;
            _errorHint = status.isPermanentlyDenied
                ? 'Camera blocked. Tap Open Settings, enable Camera, then return.'
                : 'Camera permission needed. Tap Open camera again.';
          });
        }
        return;
      }

      // Give Android a beat after the permission dialog closes.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      if (controller.value.isRunning) {
        await controller.stop();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      await controller.start();

      if (mounted) {
        setState(() {
          _showHelp = false;
          _errorHint = null;
        });
      }
    } catch (e) {
      debugPrint('Camera open error: $e');
      if (mounted) {
        setState(() {
          _showHelp = true;
          _errorHint = 'Could not start camera. Tap Open camera to retry.';
        });
      }
    } finally {
      _starting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // User may have enabled Camera in Settings.
        unawaited(_openCamera());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (controller.value.isRunning) {
          unawaited(controller.stop());
        }
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Widget _helpOverlay() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera_outlined, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorHint ??
                    'Allow camera while using the app.\n'
                        'If Android asks, choose While using the app.\n'
                        'You can still type or use a USB / Bluetooth scanner.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_openCamera()),
                child: const Text('Open camera'),
              ),
              TextButton(
                onPressed: openAppSettings,
                child: const Text('Open Settings', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Simple scan frame like the reference video.
  Widget _scanFrame() {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2.5),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always mount MobileScanner so the platform camera view exists.
    // Help overlay only covers it when permission/start failed.
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            fit: BoxFit.cover,
            errorBuilder: (context, error, child) {
              // Surface plugin errors into our help UI on next frame.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final msg = switch (error.errorCode) {
                  MobileScannerErrorCode.permissionDenied =>
                    'Camera permission denied. Tap Open Settings, enable Camera, then return.',
                  MobileScannerErrorCode.unsupported =>
                    'Camera not supported on this device.',
                  _ => 'Camera error. Tap Open camera to retry.',
                };
                if (!_showHelp || _errorHint != msg) {
                  setState(() {
                    _showHelp = true;
                    _errorHint = msg;
                  });
                }
              });
              return const SizedBox.expand();
            },
            onDetect: (capture) {
              final hit = capture.barcodes.firstOrNull;
              final value = (hit?.rawValue ?? hit?.displayValue)?.trim();
              if (value == null || value.isEmpty) return;
              widget.onCode(value);
            },
          ),
          if (!_showHelp) _scanFrame(),
          if (_showHelp) _helpOverlay(),
        ],
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
