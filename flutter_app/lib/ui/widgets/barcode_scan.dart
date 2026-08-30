import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';

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
          ListTile(title: Text(widget.hint, style: const TextStyle(fontSize: 13))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: gun,
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
              continuous: true,
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

/// Preview + JPEG photo decode (reliable on Android) with scan-line overlay.
class ShopCameraScan extends StatefulWidget {
  const ShopCameraScan({super.key, required this.onCode, this.hint, this.continuous = false});
  final void Function(String code) onCode;
  final String? hint;
  final bool continuous;
  @override
  State<ShopCameraScan> createState() => _ShopCameraScanState();
}

class _ShopCameraScanState extends State<ShopCameraScan>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  late final BarcodeScanner _scanner;
  late final AnimationController _scanLineCtrl;
  Timer? _photoTimer;
  var _starting = false;
  var _busy = false;
  var _ready = false;
  var _showHelp = false;
  var _torchOn = false;
  var _hit = false;
  String? _errorHint;
  String? _lastCode;
  DateTime? _lastEmit;

  @override
  void initState() {
    super.initState();
    _scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    _scanLineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _photoTimer?.cancel();
    _scanLineCtrl.dispose();
    unawaited(_teardown());
    _scanner.close();
    super.dispose();
  }

  Future<void> _teardown() async {
    _photoTimer?.cancel();
    _photoTimer = null;
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _openCamera() async {
    if (_starting) return;
    _starting = true;
    if (mounted) {
      setState(() {
        _showHelp = false;
        _errorHint = null;
        _ready = false;
        _hit = false;
      });
    }
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _showHelp = true;
            _errorHint = status.isPermanentlyDenied
                ? 'Camera blocked. Open Settings and enable Camera.'
                : 'Camera permission needed. Tap Open camera again.';
          });
        }
        return;
      }
      await _teardown();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() { _showHelp = true; _errorHint = 'No camera found.'; });
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}
      _photoTimer?.cancel();
      _photoTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
        unawaited(_scanPhoto());
      });
      if (mounted) {
        setState(() {
          _ready = true;
          _showHelp = false;
          _errorHint = null;
          _torchOn = false;
        });
        _scanLineCtrl.repeat(reverse: true);
      }
    } catch (e) {
      debugPrint('Camera open error: $e');
      if (mounted) {
        setState(() {
          _showHelp = true;
          _errorHint = 'Could not start camera. Tap Open camera to retry.';
          _ready = false;
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _scanPhoto() async {
    if (_busy || !_ready || _hit) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _busy = true;
    try {
      try {
        await c.setFocusMode(FocusMode.auto);
        await c.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}
      XFile shot;
      try {
        shot = await c.takePicture();
      } catch (_) {
        try {
          if (c.value.isStreamingImages) await c.stopImageStream();
        } catch (_) {}
        shot = await c.takePicture();
      }
      final barcodes = await _scanner.processImage(InputImage.fromFilePath(shot.path));
      try { await File(shot.path).delete(); } catch (_) {}
      if (barcodes.isEmpty) return;
      final raw = (barcodes.first.rawValue ?? barcodes.first.displayValue)?.trim();
      if (raw == null || raw.isEmpty) return;
      final now = DateTime.now();
      if (_lastEmit != null && now.difference(_lastEmit!).inMilliseconds < 900) return;
      _lastEmit = now;
      _lastCode = raw;
      if (mounted) setState(() => _hit = true);
      HapticFeedback.mediumImpact();
      _scanLineCtrl.stop();
      _photoTimer?.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      widget.onCode(raw);
      if (widget.continuous) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() => _hit = false);
        _scanLineCtrl.repeat(reverse: true);
        _photoTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
          unawaited(_scanPhoto());
        });
      }
    } catch (e) {
      debugPrint('photo scan error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      if (_torchOn) {
        await c.setFlashMode(FlashMode.off);
        if (mounted) setState(() => _torchOn = false);
      } else {
        await c.setFlashMode(FlashMode.torch);
        if (mounted) setState(() => _torchOn = true);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_openCamera());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_teardown());
        if (mounted) setState(() => _ready = false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.previewSize?.height ?? 1,
                height: c.value.previewSize?.width ?? 1,
                child: CameraPreview(c),
              ),
            )
          else if (!_showHelp)
            const Center(child: CircularProgressIndicator(color: Colors.white70)),
          if (_ready && !_showHelp)
            IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: AnimatedBuilder(
                    animation: _scanLineCtrl,
                    builder: (_, __) {
                      final y = 12.0 + _scanLineCtrl.value * 216;
                      return CustomPaint(
                        painter: _FramePainter(lineY: y, hit: _hit),
                      );
                    },
                  ),
                ),
              ),
            ),
          if (_ready && !_showHelp)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: IconButton.filledTonal(
                  onPressed: () => unawaited(_toggleTorch()),
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                ),
              ),
            ),
          if (_showHelp)
            ColoredBox(
              color: const Color(0xEB000000),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorHint ?? 'Allow camera to scan.',
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
            ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.lineY, required this.hit});
  final double lineY;
  final bool hit;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = hit ? const Color(0xFF34D399) : Colors.white;
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const c = 28.0;
    final r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawLine(Offset(r.left, r.top + c), Offset(r.left, r.top), paint);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + c, r.top), paint);
    canvas.drawLine(Offset(r.right - c, r.top), Offset(r.right, r.top), paint);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + c), paint);
    canvas.drawLine(Offset(r.left, r.bottom - c), Offset(r.left, r.bottom), paint);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + c, r.bottom), paint);
    canvas.drawLine(Offset(r.right - c, r.bottom), Offset(r.right, r.bottom), paint);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - c), paint);
    if (!hit) {
      final y = lineY.clamp(r.top + 4, r.bottom - 4);
      canvas.drawLine(Offset(r.left + 8, y), Offset(r.right - 8, y), paint..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.lineY != lineY || old.hit != hit;
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
