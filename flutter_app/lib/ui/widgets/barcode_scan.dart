import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';

Future<String?> scanBarcode(BuildContext context, {required String title, required String hint}) {
  var handled = false;
  final gun = TextEditingController();
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ShopCameraScan(
              onCode: (value) {
                if (handled) return;
                handled = true;
                Navigator.pop(ctx, value);
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.viewInsetsOf(ctx).bottom),
                child: TextField(
                  controller: gun,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xCC1A1A1A),
                    labelText: 'USB / Bluetooth scanner',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.document_scanner, color: Colors.white70),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (v) {
                    final code = v.trim();
                    if (code.isEmpty) return;
                    Navigator.pop(ctx, code);
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

/// Live CameraX preview + ML Kit stream decode (Lens-style).
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
  CameraDescription? _camera;
  late final BarcodeScanner _scanner;
  late final AnimationController _scanLineCtrl;
  var _starting = false;
  var _busy = false;
  var _ready = false;
  var _showHelp = false;
  var _torchOn = false;
  var _hit = false;
  String? _errorHint;
  String? _lastCode;
  DateTime? _lastEmit;

  static const _orients = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

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
    _scanLineCtrl.dispose();
    unawaited(_teardown());
    _scanner.close();
    super.dispose();
  }

  Future<void> _teardown() async {
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
      _camera = camera;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}
      await controller.startImageStream(_onStream);
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

  Future<void> _onStream(CameraImage image) async {
    if (_busy || !_ready || _hit) return;
    final input = _toInputImage(image);
    if (input == null) return;
    _busy = true;
    try {
      final barcodes = await _scanner.processImage(input);
      if (barcodes.isEmpty) return;
      final raw = barcodes.first.rawValue?.trim();
      if (raw == null || raw.isEmpty) return;
      await _emit(raw);
    } catch (e) {
      debugPrint('stream scan error: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = _camera;
    final c = _controller;
    if (cam == null || c == null) return null;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final orient = _orients[c.value.deviceOrientation] ?? 0;
    final deg = Platform.isAndroid
        ? (cam.lensDirection == CameraLensDirection.front
            ? (cam.sensorOrientation + orient) % 360
            : (cam.sensorOrientation - orient + 360) % 360)
        : cam.sensorOrientation;
    final rotation = switch (deg) {
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => InputImageRotation.rotation0deg,
    };
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _emit(String raw) async {
    final now = DateTime.now();
    if (_lastEmit != null && now.difference(_lastEmit!).inMilliseconds < 900) return;
    _lastEmit = now;
    _lastCode = raw;
    if (mounted) setState(() => _hit = true);
    HapticFeedback.mediumImpact();
    _scanLineCtrl.stop();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    widget.onCode(raw);
    if (widget.continuous) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() => _hit = false);
      _scanLineCtrl.repeat(reverse: true);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (file == null) return;
      final barcodes = await _scanner.processImage(InputImage.fromFilePath(file.path));
      if (barcodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No barcode in photo')));
        }
        return;
      }
      final raw = barcodes.first.rawValue?.trim();
      if (raw == null || raw.isEmpty) return;
      await _emit(raw);
    } catch (e) {
      debugPrint('gallery scan error: $e');
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
                  width: MediaQuery.sizeOf(context).shortestSide * 0.72,
                  height: MediaQuery.sizeOf(context).shortestSide * 0.72,
                  child: CustomPaint(painter: _FramePainter(hit: _hit)),
                ),
              ),
            ),
          if (_lastCode != null && _hit)
            Align(
              alignment: const Alignment(0, 0.18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xE61A1A1A), borderRadius: BorderRadius.circular(24)),
                child: Text(_lastCode!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          if (_ready && !_showHelp)
            Positioned(
              left: 28,
              right: 28,
              bottom: 88,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundBtn(Icons.photo_library_outlined, () => unawaited(_pickGallery())),
                  _roundBtn(_torchOn ? Icons.flash_on : Icons.flash_off, () => unawaited(_toggleTorch()), filled: true),
                ],
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
                      TextButton(
                        onPressed: () => unawaited(_pickGallery()),
                        child: const Text('Choose photo', style: TextStyle(color: Colors.white70)),
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

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return Material(
      color: filled ? Colors.white : const Color(0xCC2A2A2A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: filled ? Colors.black : Colors.white, size: 28),
        ),
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
    const c = 36.0;
    final r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawLine(Offset(r.left, r.top + c), Offset(r.left, r.top), paint);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + c, r.top), paint);
    canvas.drawLine(Offset(r.right - c, r.top), Offset(r.right, r.top), paint);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + c), paint);
    canvas.drawLine(Offset(r.left, r.bottom - c), Offset(r.left, r.bottom), paint);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + c, r.bottom), paint);
    canvas.drawLine(Offset(r.right - c, r.bottom), Offset(r.right, r.bottom), paint);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - c), paint);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.hit != hit;
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
