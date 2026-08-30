import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';
import 'image_utils.dart';

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

/// Live stream + ML Kit (reference decode path) with scan-line / hit animation.
class ShopCameraScan extends StatefulWidget {
  const ShopCameraScan({
    super.key,
    required this.onCode,
    this.hint,
    this.continuous = false,
  });

  final void Function(String code) onCode;
  final String? hint;
  final bool continuous;

  @override
  State<ShopCameraScan> createState() => _ShopCameraScanState();
}

class _ShopCameraScanState extends State<ShopCameraScan>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static const _frameSize = 240.0;

  CameraController? _controller;
  late final BarcodeScanner _scanner;
  List<CameraDescription> _cameras = const [];

  late final AnimationController _scanLineCtrl;
  late final AnimationController _hitCtrl;

  var _starting = false;
  var _processing = false;
  var _ready = false;
  var _showHelp = false;
  var _torchOn = false;
  var _hit = false;
  String? _errorHint;
  String? _lastCode;
  DateTime? _lastEmit;
  double _zoom = 1;
  double _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    // Only BarcodeFormat.all — individual enum names broke CI before.
    _scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _hitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanLineCtrl.dispose();
    _hitCtrl.dispose();
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

      try {
        _maxZoom = await controller.getMaxZoomLevel();
        _zoom = await controller.getMinZoomLevel();
      } catch (_) {
        _maxZoom = 1;
        _zoom = 1;
      }

      await controller.startImageStream(_processCameraImage);

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
        _scanLineCtrl.repeat(reverse: true);
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

  Future<void> _processCameraImage(CameraImage image) async {
    if (_processing || !_ready || _hit) return;
    _processing = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final barcodes = await _scanner.processImage(inputImage);
      if (barcodes.isEmpty) return;

      final first = barcodes.first;
      final raw = (first.rawValue ?? first.displayValue)?.trim();
      if (raw == null || raw.isEmpty) return;

      // Reference accuracy: zoom in if code is very small in frame.
      final bx = first.boundingBox;
      final area = bx.width * bx.height;
      final frameArea = (image.width * image.height).toDouble();
      if (frameArea > 0 && area / frameArea < 0.01 && _zoom + 0.5 <= _maxZoom) {
        _zoom = math.min(_zoom + 0.5, _maxZoom);
        try {
          await _controller?.setZoomLevel(_zoom);
        } catch (_) {}
        return;
      }

      final now = DateTime.now();
      if (_lastEmit != null && now.difference(_lastEmit!).inMilliseconds < 900) return;
      _lastEmit = now;
      _lastCode = raw;

      // Hit animation (like reference: pause stream feel + frame flash).
      if (mounted) setState(() => _hit = true);
      HapticFeedback.mediumImpact();
      _scanLineCtrl.stop();
      unawaited(_hitCtrl.forward(from: 0));

      final c = _controller;
      if (c != null && c.value.isStreamingImages && !widget.continuous) {
        try {
          await c.stopImageStream();
        } catch (_) {}
      }

      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      widget.onCode(raw);

      if (widget.continuous) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() => _hit = false);
        _scanLineCtrl.repeat(reverse: true);
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _processing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final c = _controller;
    if (c == null || _cameras.isEmpty) return null;

    final camera = c.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var compensation = _orientations[c.value.deviceOrientation] ?? 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        compensation = (sensorOrientation + compensation) % 360;
      } else {
        compensation = (sensorOrientation - compensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensation);
    }
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      return ImageUtils.buildAndroidInputImage(image, rotation);
    }
    return ImageUtils.buildIOSInputImage(image, rotation);
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

  /// Corner brackets + moving scan line + green flash on hit (reference-style).
  Widget _scanOverlay() {
    final accent = _hit ? const Color(0xFF34D399) : Colors.white;
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: _frameSize,
          height: _frameSize,
          child: AnimatedBuilder(
            animation: Listenable.merge([_scanLineCtrl, _hitCtrl]),
            builder: (context, _) {
              final lineT = _scanLineCtrl.value;
              final hitT = _hitCtrl.value;
              return CustomPaint(
                painter: _ScanFramePainter(
                  accent: accent,
                  lineY: lineT * _frameSize,
                  hitProgress: hitT,
                  showLine: !_hit,
                ),
                child: _hit && _lastCode != null
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Text(
                                _lastCode!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              );
            },
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
          if (_ready && !_showHelp) _scanOverlay(),
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

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.accent,
    required this.lineY,
    required this.hitProgress,
    required this.showLine,
  });

  final Color accent;
  final double lineY;
  final double hitProgress;
  final bool showLine;

  @override
  void paint(Canvas canvas, Size size) {
    const corner = 28.0;
    const stroke = 3.5;
    final pad = 2.0;
    final r = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);

    // Dim outside is handled by parent; draw corner brackets.
    final paint = Paint()
      ..color = accent
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(r.left, r.top + corner), Offset(r.left, r.top), paint);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + corner, r.top), paint);
    // Top-right
    canvas.drawLine(Offset(r.right - corner, r.top), Offset(r.right, r.top), paint);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + corner), paint);
    // Bottom-left
    canvas.drawLine(Offset(r.left, r.bottom - corner), Offset(r.left, r.bottom), paint);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + corner, r.bottom), paint);
    // Bottom-right
    canvas.drawLine(Offset(r.right - corner, r.bottom), Offset(r.right, r.bottom), paint);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - corner), paint);

    if (showLine) {
      final y = (lineY).clamp(r.top + 4, r.bottom - 4);
      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(r.left, y - 1, r.width, 2));
      canvas.drawLine(Offset(r.left + 8, y), Offset(r.right - 8, y), linePaint..strokeWidth = 2.5);
    }

    if (hitProgress > 0) {
      final flash = Paint()
        ..color = accent.withValues(alpha: 0.18 * (1 - hitProgress))
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)), flash);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter old) =>
      old.accent != accent ||
      old.lineY != lineY ||
      old.hitProgress != hitProgress ||
      old.showLine != showLine;
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
