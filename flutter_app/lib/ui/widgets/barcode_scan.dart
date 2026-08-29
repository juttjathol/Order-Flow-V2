import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/models.dart';

/// Camera or a USB/Bluetooth HID gun (guns type the code and press Enter).
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                child: TextField(
                  controller: gun,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xCC051912),
                    labelText: 'USB / Bluetooth scanner',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.document_scanner, color: Colors.white70),
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
        backgroundColor: Colors.black,
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
    return Stack(
      fit: StackFit.expand,
      children: [
        ShopCameraScan(
          onCode: (value) {
            final now = DateTime.now();
            if (lastCam != null && now.difference(lastCam!).inMilliseconds < 900) return;
            lastCam = now;
            _take(value);
          },
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(status, style: const TextStyle(color: Colors.white)),
                  ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: gun,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xCC051912),
                          labelText: 'USB / Bluetooth / SKU',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.document_scanner, color: Colors.white70),
                        ),
                        onSubmitted: _take,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 88,
                      child: TextField(
                        controller: qty,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xCC051912),
                          labelText: 'Qty',
                          labelStyle: TextStyle(color: Colors.white70),
                        ),
                        onSubmitted: (_) => _commit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: busy ? null : _commit, child: const Text('Add')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
  var _sized = false;

  static const _ask = MethodChannel('jathol/shop_keepalive');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
    if (c == null) return;
    try {
      if (state == AppLifecycleState.resumed) {
        unawaited(c.start());
      } else if (state == AppLifecycleState.inactive) {
        unawaited(c.stop());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth > 80 && box.maxHeight > 80 && !_sized) {
          _sized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _boot();
          });
        }
        return ColoredBox(
          color: Colors.black,
          child: _fail
              ? _failPane()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_live && _ctrl != null)
                      MobileScanner(
                        controller: _ctrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, child) => _failPane(),
                        onDetect: (capture) {
                          final value = capture.barcodes.firstOrNull?.rawValue;
                          if (value == null || value.trim().isEmpty) return;
                          widget.onCode(value.trim());
                        },
                      )
                    else
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    const IgnorePointer(child: _ScanFrame()),
                    if (_live && _ctrl != null)
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.flash_on),
                            onPressed: () async {
                              try {
                                await _ctrl?.toggleTorch();
                              } catch (_) {}
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScanFramePainter(), child: const SizedBox.expand());
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.72;
    final h = w * 0.62;
    final hole = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: w, height: h);
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)));
    canvas.drawPath(overlay, Paint()..color = const Color(0x99000000));
    const arm = 28.0;
    final p = Paint()
      ..color = const Color(0xFF3DDC97)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void corner(Offset a, Offset b, Offset c) {
      canvas.drawLine(a, b, p);
      canvas.drawLine(a, c, p);
    }

    corner(hole.topLeft, hole.topLeft + const Offset(arm, 0), hole.topLeft + const Offset(0, arm));
    corner(hole.topRight, hole.topRight + const Offset(-arm, 0), hole.topRight + const Offset(0, arm));
    corner(hole.bottomLeft, hole.bottomLeft + const Offset(arm, 0), hole.bottomLeft + const Offset(0, -arm));
    corner(hole.bottomRight, hole.bottomRight + const Offset(-arm, 0), hole.bottomRight + const Offset(0, -arm));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
