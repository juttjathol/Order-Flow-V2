import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' as ml;
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';

/// Camera or a USB/Bluetooth HID gun (guns type the code and press Enter).
/// Used by stock scan and station-join QR (Connect screen).
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

/// Live camera barcode/QR scanner using the same stack as the working reference:
/// `camera` + `google_mlkit_barcode_scanning` (not mobile_scanner).
class ShopCameraScan extends StatefulWidget {
  const ShopCameraScan({
    super.key,
    required this.onCode,
    this.hint,
    this.continuous = false,
  });

  final void Function(String code) onCode;
  final String? hint;

  /// When true (stock loop), keep scanning after each hit.
  final bool continuous;

  @override
  State<ShopCameraScan> createState() => _ShopCameraScanState();
}

class _ShopCameraScanState extends State<ShopCameraScan> with WidgetsBindingObserver {
  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  late final BarcodeScanner _scanner;
  List<CameraDescription> _cameras = const [];

  var _starting = false;
  var _processing = false;
  var _ready = false;
  var _showHelp = false;
  var _torchOn = false;
  String? _errorHint;
  DateTime? _lastEmit;

  @override
  void initState() {
    super.initState();
    _scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      });
    }

    try {
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

      await _teardown();

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _showHelp = true;
            _errorHint = 'No camera found on this device.';
          });
        }
        return;
      }

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      _controller = controller;

      await controller.initialize();
      if (!mounted) return;

      await controller.startImageStream(_onFrame);

      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}

      if (mounted) {
        setState(() {
          _ready = true;
          _showHelp = false;
          _errorHint = null;
          _torchOn = false;
        });
      }
    } catch (e, st) {
      debugPrint('Camera open error: $e\n$st');
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

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || !_ready) return;
    _processing = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;

      final barcodes = await _scanner.processImage(input);
      if (barcodes.isEmpty) return;

      final raw = barcodes.first.rawValue?.trim();
      if (raw == null || raw.isEmpty) return;

      final now = DateTime.now();
      if (_lastEmit != null && now.difference(_lastEmit!).inMilliseconds < 800) return;
      _lastEmit = now;

      HapticFeedback.mediumImpact();
      widget.onCode(raw);

      // One-shot scanners (join / single scan) stop the stream after first hit.
      if (!widget.continuous) {
        final c = _controller;
        if (c != null && c.value.isStreamingImages) {
          try {
            await c.stopImageStream();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Frame process error: $e');
    } finally {
      _processing = false;
    }
  }

  ml.InputImage? _toInputImage(CameraImage image) {
    final c = _controller;
    if (c == null || _cameras.isEmpty) return null;

    final camera = c.description;
    final sensorOrientation = camera.sensorOrientation;
    var deg = sensorOrientation;
    if (Platform.isAndroid) {
      final compensation = _orientations[c.value.deviceOrientation] ?? 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        deg = (sensorOrientation + compensation) % 360;
      } else {
        deg = (sensorOrientation - compensation + 360) % 360;
      }
    }
    final ml.InputImageRotation rotation;
    switch (deg) {
      case 90:
        rotation = ml.InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = ml.InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = ml.InputImageRotation.rotation270deg;
        break;
      default:
        rotation = ml.InputImageRotation.rotation0deg;
    }

    final format = Platform.isAndroid ? ml.InputImageFormat.nv21 : ml.InputImageFormat.bgra8888;

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    late final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = plane.bytes;
    } else {
      final all = WriteBuffer();
      for (final p in image.planes) {
        all.putUint8List(p.bytes);
      }
      bytes = all.done().buffer.asUint8List();
    }

    return ml.InputImage.fromBytes(
      bytes: bytes,
      metadata: ml.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
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
    final c = _controller;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_openCamera());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (c != null) {
          unawaited(_teardown());
          if (mounted) setState(() => _ready = false);
        }
        break;
    }
  }

  Widget _helpOverlay() {
    return ColoredBox(
      color: const Color(0xEB000000),
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
          if (_ready && !_showHelp) _scanFrame(),
          if (_ready && !_showHelp)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: IconButton.filledTonal(
                  onPressed: () => unawaited(_toggleTorch()),
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                  tooltip: 'Flash',
                ),
              ),
            ),
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
