import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:image/image.dart' as img;

import '../core/money.dart';
import '../models/models.dart';
import 'bluetooth_printer.dart';

class PrintService {
  final bluetooth = BluetoothPrinter();

  /// ESC/POS drawer kick: pulse pin 2 for 50ms (most drawers open on 25).
  /// Harmless on printers without a drawer port — the printer just ignores it.
  static const drawerKickBytes = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  /// True when the failure is just "no printer configured on this device" —
  /// callers should stay silent for that, but toast for real I/O errors.
  static bool isConfigError(Object e) =>
      e.toString().contains('Printer is not configured');

  Future<void> send(PrinterConfig cfg, List<int> bytes) async {
    if (!cfg.enabled) throw Exception('Printer is not configured');
    if (cfg.isBluetooth) {
      if (cfg.btAddress.trim().isEmpty) {
        throw Exception('Printer is not configured');
      }
      await bluetooth.printBytes(cfg.btAddress.trim(), bytes);
      return;
    }
    if (cfg.host.trim().isEmpty) {
      throw Exception('Printer is not configured');
    }
    final socket = await Socket.connect(
      cfg.host.trim(),
      cfg.port <= 0 ? 9100 : cfg.port,
      timeout: const Duration(seconds: 6),
    );
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Kicks the cash drawer through the given printer (ESC/POS pin-2 pulse).
  Future<void> openDrawer(PrinterConfig cfg) {
    return send(cfg, List<int>.from(drawerKickBytes));
  }

  /// Plain-text receipt, used for WhatsApp / SMS sharing.
  String receiptText(AppStore store, PosOrder order) {
    final p = store.profile;
    final cur = p.currencySymbol;
    final prefix = p.currencyPrefix;
    String m(num n) => money(n, cur, prefix: prefix);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final w = StringBuffer();
    w.writeln('* * * ${p.businessName.toUpperCase()} * * *');
    if (p.address.isNotEmpty) w.writeln(p.address);
    if (p.phone.isNotEmpty) w.writeln('Tel. ${p.phone}');
    if (p.invoiceLabel.trim().isNotEmpty) w.writeln(p.invoiceLabel.trim().toUpperCase());
    if (p.taxRegNo.isNotEmpty) w.writeln('Reg. No: ${p.taxRegNo}');
    w.writeln('--------------------------------');
    w.writeln('Ticket ${order.ticketNo}  ${'${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}'}');
    if (order.tableName?.isNotEmpty == true) {
      w.writeln('Table ${order.tableName}');
    } else {
      w.writeln(order.type.name.toUpperCase());
    }
    if (order.customerName.isNotEmpty) w.writeln(order.customerName);
    w.writeln('--------------------------------');
    for (final line in order.lines) {
      final qty = line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 1);
      w.writeln('$qty x ${line.name}   ${m(line.lineTotal)}');
      if (line.notes.isNotEmpty) w.writeln('   * ${line.notes}');
    }
    w.writeln('--------------------------------');
    if (order.discount > 0) w.writeln('Discount: - ${m(order.discount)}');
    if (order.service > 0) w.writeln('Service: ${m(order.service)}');
    if (order.tax > 0) w.writeln('Tax: ${m(order.tax)}');
    if (order.tip > 0) w.writeln('Tip: ${m(order.tip)}');
    w.writeln('TOTAL: ${m(order.total)}');
    if (order.payment != null) {
      if (order.splitPayment != null && order.splitAmount > 0) {
        w.writeln('${order.payment!.name.toUpperCase()}: ${m(order.primaryAmount)}');
        w.writeln('${order.splitPayment!.name.toUpperCase()}: ${m(order.splitAmount)}');
      } else {
        w.writeln('PAID BY ${order.payment!.name.toUpperCase()}: ${m(order.total)}');
      }
    }
    if (p.footer.isNotEmpty) w.writeln(p.footer.toUpperCase());
    w.writeln('* * * * * * * * * * * * * * * *');
    return w.toString();
  }

  Future<void> kitchenTicket(
    AppStore store,
    PosOrder order, {
    AppRole? role,
    PrinterConfig? prefer,
  }) async {
    final bytes = await _build(store, order, kitchen: true);
    await send(prefer ?? store.printerForRole(role) ?? store.kitchenTarget(), bytes);
  }

  Future<void> receipt(
    AppStore store,
    PosOrder order, {
    AppRole? role,
    PrinterConfig? prefer,
  }) async {
    final bytes = await _build(store, order, kitchen: false);
    await send(prefer ?? store.receiptTarget(role), bytes);
  }

  Future<List<int>> _build(AppStore store, PosOrder order, {required bool kitchen}) async {
    final p = store.profile;
    final slip = p.slipFor(order, kitchen: kitchen);
    final cur = p.currencySymbol;
    final prefix = p.currencyPrefix;
    String m(num n) => money(n, cur, prefix: prefix);
    final now = DateTime.now();
    final b = EscPos()..init();

    Future<void> line(String value, {String align = 'left', bool big = false}) =>
        _line(b, value, align: align, big: big);

    b.align('center');
    if (slip.showLogo) _raster(b, p.logoBase64);
    await line(p.businessName.toUpperCase(), big: true);
    if (slip.showAddress && p.address.isNotEmpty) await line(p.address, align: 'center');
    if (slip.showPhone && p.phone.isNotEmpty) await line('Tel. ${p.phone}', align: 'center');
    if (p.taxId.isNotEmpty && !kitchen) await line('Tax ID: ${p.taxId}', align: 'center');
    // v1.1.59 — tax invoice / e-invoice style header (off unless set).
    if (p.taxRegNo.isNotEmpty && !kitchen) await line('Reg. No: ${p.taxRegNo}', align: 'center');
    final heading = (!kitchen && p.invoiceLabel.trim().isNotEmpty)
        ? p.invoiceLabel.trim().toUpperCase()
        : slip.heading.toUpperCase();
    await line('* * * * * * * * * * * * * * * *', align: 'center');
    await line(heading, align: 'center');
    await line('* * * * * * * * * * * * * * * *', align: 'center');
    await line('Ticket ${order.ticketNo}');
    await line(_fmt(now));
    if (order.tableName?.isNotEmpty == true) {
      // QR self-orders are served by table — make it unmissable (v1.1.60).
      await line(order.isQr ? '>>> QR TABLE ${order.tableName} <<<' : 'Table ${order.tableName}');
    } else {
      await line(order.type.name.toUpperCase());
    }
    if (slip.showCustomer) {
      if (order.customerName.isNotEmpty) await line(order.customerName);
      if (order.customerPhone.isNotEmpty) await line(order.customerPhone);
      if (order.type == OrderType.delivery && order.address.isNotEmpty) {
        await line(order.address);
      }
    }
    if (order.createdBy.isNotEmpty && kitchen) await line('Station: ${order.createdBy}');
    await line('* * * * * * * * * * * * * * * *');
    if (slip.showPrices) {
      await _row(b, 'Description', 'Price');
    }
    final lines = [...order.lines]..sort((a, c) => a.course.compareTo(c.course));
    String? last;
    for (final entry in lines) {
      if (kitchen && last != entry.course) {
        last = entry.course;
        await line('-- ${entry.course.toUpperCase()} --');
      }
      final qty = entry.qty.toStringAsFixed(entry.qty % 1 == 0 ? 0 : 1);
      if (slip.showPrices) {
        await _row(b, '$qty ${entry.name}', m(entry.lineTotal));
      } else {
        await line('$qty x ${entry.name}');
      }
      if (entry.notes.isNotEmpty) await line('  * ${entry.notes}');
    }
    if (order.notes.isNotEmpty) {
      await line('* * * * * * * * * * * * * * * *');
      await line('NOTE: ${order.notes}');
    }
    if (slip.showTotals) {
      await line('* * * * * * * * * * * * * * * *');
      await _row(b, 'Total', m(order.total), big: true);
      if (order.discount > 0) await _row(b, 'Discount', '- ${m(order.discount)}');
      if (order.service > 0) await _row(b, 'Service', m(order.service));
      if (order.tax > 0) await _row(b, 'Tax', m(order.tax));
      if (order.tip > 0) await _row(b, 'Tip', m(order.tip));
    }
    if (slip.showPayment && order.payment != null) {
      if (order.splitPayment != null && order.splitAmount > 0) {
        await _row(b, order.payment!.name, m(order.primaryAmount));
        await _row(b, order.splitPayment!.name, m(order.splitAmount));
      } else {
        await _row(b, order.payment!.name, m(order.total));
      }
    }
    await line('* * * * * * * * * * * * * * * *');
    if (p.footer.isNotEmpty) await line(p.footer.toUpperCase(), align: 'center');
    if (slip.showQr) {
      _raster(b, p.payQrBase64);
      if (p.payQrLabel.trim().isNotEmpty) await line(p.payQrLabel.trim(), align: 'center');
    }
    b
      ..feed(4)
      ..cut();
    return b.bytes;
  }

  /// One slip line. Pure-Latin1 text goes out as native ESC/POS bytes (fast,
  /// crisp, uses the printer's own font). Anything beyond Latin1 — Urdu /
  /// Arabic / emoji, which no code page on a 58/80mm printer can render — is
  /// shaped by Flutter's text engine (full bidi + Arabic ligatures) and sent
  /// as a raster line, so it prints exactly as it looks on screen.
  Future<void> _line(EscPos b, String value, {String align = 'left', bool big = false}) async {
    final native = _isLatin1(value);
    if (native) {
      b
        ..align(align)
        ..doubleSize(big)
        ..text(value);
      return;
    }
    try {
      await _rasterText(b, value, align: align, big: big);
    } catch (_) {
      // Never let a font/engine hiccup cost the shop a sale.
      b
        ..align(align)
        ..doubleSize(big)
        ..text(value);
    }
  }

  /// Two-column line ("name ……… price"); rasterized whole if either side
  /// needs shaping, so RTL names and Latin amounts stay on one visual line.
  Future<void> _row(EscPos b, String left, String right, {bool big = false}) async {
    if (_isLatin1(left) && _isLatin1(right)) {
      b
        ..align('left')
        ..doubleSize(big)
        ..row(left, right);
      return;
    }
    try {
      await _rasterRow(b, left, right, big: big);
    } catch (_) {
      b
        ..align('left')
        ..doubleSize(big)
        ..row(left, right);
    }
  }

  static bool _isLatin1(String v) {
    for (final u in v.codeUnits) {
      if (u > 0xFF) return false;
    }
    return true;
  }

  static const _rasterW = 384; // 58mm @ 203dpi; 80mm printers centre it.

  TextStyle _slipStyle({required bool big, ui.Color color = const ui.Color(0xFF000000)}) {
    return TextStyle(
      color: color,
      fontSize: (big ? 40.0 : 21.0),
      fontWeight: ui.FontWeight.w700,
      height: 1.5,
    );
  }

  Future<void> _rasterText(EscPos b, String value, {required String align, required bool big}) async {
    final tp = TextPainter(
      text: TextSpan(text: value, style: _slipStyle(big: big)),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: _rasterW.toDouble());
    final h = (tp.height.ceil() ~/ 2 * 2).clamp(12, 8000);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final double dx = switch (align) {
      'center' => ((_rasterW.toDouble() - tp.width) / 2).clamp(0.0, _rasterW.toDouble()).toDouble(),
      'right' => _rasterW.toDouble() - tp.width,
      _ => 0.0,
    };
    tp.paint(canvas, ui.Offset(dx, 0));
    await _emitPicture(b, rec, h);
  }

  Future<void> _rasterRow(EscPos b, String left, String right, {required bool big}) async {
    final ls = _slipStyle(big: big);
    final rw = TextPainter(
      text: TextSpan(text: right, style: ls),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final leftRoom = _rasterW.toDouble() - rw.width - 8;
    final wraps = leftRoom < 64;
    final lp = TextPainter(
      text: TextSpan(text: left, style: ls),
      textDirection: ui.TextDirection.ltr,
      maxLines: wraps ? null : 1,
      ellipsis: wraps ? null : '…',
    )..layout(maxWidth: wraps ? _rasterW.toDouble() : leftRoom);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    lp.paint(canvas, ui.Offset.zero);
    rw.paint(canvas, ui.Offset(_rasterW.toDouble() - rw.width, 0));
    final singleH = lp.height > rw.height ? lp.height : rw.height;
    final totalH = wraps ? lp.height : singleH;
    final h = totalH.ceil().clamp(24, 8000);
    await _emitPicture(b, rec, h ~/ 2 * 2);
  }

  Future<void> _emitPicture(EscPos b, ui.PictureRecorder rec, int height) async {
    final pic = rec.endRecording();
    final image = await pic.toImage(_rasterW, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) throw StateError('raster encode failed');
    final widthBytes = _rasterW ~/ 8;
    final out = <int>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < widthBytes; x++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final i = ((y * _rasterW) + (x * 8 + bit)) * 4;
          final a = data.lengthInBytes > i + 3 ? data.getUint8(i + 3) : 0;
          if (a > 96) byte |= 128 >> bit; // painted ink on transparent bg
        }
        out.add(byte);
      }
    }
    b.raw(const [0x1D, 0x76, 0x30, 0x00]);
    b.raw([widthBytes & 0xFF, (widthBytes >> 8) & 0xFF, height & 0xFF, (height >> 8) & 0xFF]);
    b.raw(out);
    b.raw(const [0x0A]);
  }

  Future<void> test(PrinterConfig cfg, String shop) async {
    final b = EscPos()
      ..init()
      ..align('center')
      ..text('ORDER FLOW')
      ..text(shop)
      ..text('Printer test OK')
      ..feed(4)
      ..cut();
    await send(cfg, b.bytes);
  }

  void _raster(EscPos b, String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final data = base64Decode(raw.contains(',') ? raw.split(',').last : raw);
      final decoded = img.decodeImage(data);
      if (decoded == null) return;
      var im = img.grayscale(decoded);
      const maxW = 384;
      if (im.width > maxW) {
        im = img.copyResize(im, width: maxW);
      }
      final w = (im.width + 7) ~/ 8 * 8;
      final h = im.height;
      final out = <int>[];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x += 8) {
          var byte = 0;
          for (var bit = 0; bit < 8; bit++) {
            final xx = x + bit;
            var dark = false;
            if (xx < im.width) {
              final p = im.getPixel(xx, y);
              dark = img.getLuminance(p) < 160;
            }
            if (dark) byte |= 128 >> bit;
          }
          out.add(byte);
        }
      }
      final widthBytes = w ~/ 8;
      b.raw([0x1D, 0x76, 0x30, 0x00, widthBytes & 0xFF, (widthBytes >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
      b.raw(out);
      b.raw(const [0x0A]);
    } catch (_) {}
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class EscPos {
  final bytes = <int>[];

  void raw(List<int> data) => bytes.addAll(data);

  void init() => raw(const [0x1B, 0x40]);

  void feed([int n = 1]) => raw([0x1B, 0x64, n.clamp(0, 10)]);

  void cut() => raw(const [0x1D, 0x56, 0x00]);

  void align(String side) {
    final n = side == 'center'
        ? 1
        : side == 'right'
            ? 2
            : 0;
    raw([0x1B, 0x61, n]);
  }

  void doubleSize(bool on) => raw([0x1D, 0x21, on ? 0x11 : 0x00]);

  void text(String value) {
    bytes.addAll(value.codeUnits.where((c) => c < 256));
    raw(const [0x0A]);
  }

  void stars() => text('* * * * * * * * * * * * * * * *');

  void rule() => stars();

  void row(String left, String right) {
    const width = 32;
    var l = left;
    var r = right;
    if (l.length + r.length + 1 > width) {
      l = l.substring(0, (width - r.length - 1).clamp(0, l.length));
    }
    final gap = (width - l.length - r.length).clamp(1, width);
    text('$l${' ' * gap}$r');
  }
}
