import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:image/image.dart' as img;

import '../core/money.dart';
import '../core/sanitize.dart';
import '../models/models.dart';
import 'bluetooth_printer.dart';

class PrintService {
  final bluetooth = BluetoothPrinter();
  final _lanChain = <String, Future<void>>{};

  /// Receipt qty: whole numbers stay whole; weights keep up to 3 decimals.
  static String formatQty(num qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    var s = qty.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// ESC/POS drawer kick: pulse pin 2 for 50ms (most drawers open on 25).
  /// Harmless on printers without a drawer port — the printer just ignores it.
  static const drawerKickBytes = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  /// True when the failure is just "no printer configured on this device" —
  /// callers should stay silent for that, but toast for real I/O errors.
  static bool isConfigError(Object e) =>
      e.toString().contains('Printer is not configured');

  /// Printable dots per paper width (203 dpi). Auto (0) = 58 mm: the
  /// narrowest paper any of these printers carries, so nothing ever clips.
  /// Bigger widths only make lines longer — the font stays its native size.
  static int dotsForMm(int mm) => switch (mm) {
        72 || 76 => 512,
        80 => 576,
        100 => 720,
        _ => 384,
      };

  Future<void> send(PrinterConfig cfg, List<int> bytes) async {
    if (!cfg.enabled) throw Exception('Printer is not configured');
    if (cfg.isBluetooth) {
      if (cfg.btAddress.trim().isEmpty) {
        throw Exception('Printer is not configured');
      }
      await bluetooth.printBytes(
        cfg.btAddress.trim(),
        bytes,
        transport: cfg.btTransport,
      );
      return;
    }
    if (cfg.host.trim().isEmpty) {
      throw Exception('Printer is not configured');
    }
    final host = cfg.host.trim();
    final port = cfg.port <= 0 ? 9100 : cfg.port;
    final key = '$host:$port';
    final job = (_lanChain[key] ?? Future<void>.value()).then((_) async {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 6),
      );
      try {
        socket.add(bytes);
        await socket.flush();
      } finally {
        await socket.close();
      }
    });
    _lanChain[key] = job.catchError((_) {});
    return job;
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
    if (order.customerName.isNotEmpty) w.writeln(sanitizeText(order.customerName));
    w.writeln('--------------------------------');
    for (final line in order.lines) {
      final qty = formatQty(line.qty);
      w.writeln('$qty x ${sanitizeText(line.name)}   ${m(line.lineTotal)}');
      if (line.notes.isNotEmpty) w.writeln('   * ${sanitizeText(line.notes)}');
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
    final ftShare = p.slipFor(order, kitchen: false).footer.trim();
    if (ftShare.isNotEmpty || p.footer.isNotEmpty) w.writeln((ftShare.isNotEmpty ? ftShare : p.footer).toUpperCase());
    w.writeln('* * * * * * * * * * * * * * * *');
    return w.toString();
  }

  Future<void> kitchenTicket(
    AppStore store,
    PosOrder order, {
    AppRole? role,
    PrinterConfig? prefer,
  }) async {
    final cfg = prefer ?? store.printerForRole(role) ?? store.kitchenTarget();
    final bytes = await _build(
      store,
      order,
      kitchen: true,
      dots: dotsForMm(cfg.paperMm),
    );
    await send(cfg, bytes);
  }

  Future<void> receipt(
    AppStore store,
    PosOrder order, {
    AppRole? role,
    PrinterConfig? prefer,
    bool preBill = false,
  }) async {
    final cfg = prefer ?? store.receiptTarget(role);
    final bytes = await _build(
      store,
      order,
      kitchen: false,
      preBill: preBill,
      dots: dotsForMm(cfg.paperMm),
    );
    await send(cfg, bytes);
  }

  Future<List<int>> _build(
    AppStore store,
    PosOrder order, {
    required bool kitchen,
    bool preBill = false,
    int dots = 384,
  }) async {
    final p = store.profile;
    final slip = p.slipFor(order, kitchen: kitchen);
    final cur = p.currencySymbol;
    final prefix = p.currencyPrefix;
    String m(num n) => money(n, cur, prefix: prefix);
    final now = DateTime.now();
    final chars = dots ~/ 12;
    final b = EscPos(chars)..init();

    Future<void> line(String value, {String align = 'left', bool big = false}) =>
        _line(b, sanitizeText(value), align: align, big: big);
    void rule() => b.text('-' * (chars - 1));

    // v1.1.69 — Focus-Point-style layout: dashed rules, everything wraps
    // (no mid-word truncation), the total is huge, the footer is centred.
    b.align('center');
    if (slip.showLogo) _raster(b, p.logoBase64, dots, scale: 0.8);
    // v1.1.70 — the shop name gets ONE line, always: double-size only when it
    // actually fits the paper at that size, otherwise full-width single-size.
    final nm = (p.businessName.trim().isEmpty ? 'SHOP' : p.businessName).trim().toUpperCase();
    await line(nm, align: 'center', big: nm.length <= (chars - 6) ~/ 2);
    if (slip.showAddress && p.address.isNotEmpty) await line(p.address, align: 'center');
    if (slip.showPhone && p.phone.isNotEmpty) await line('Tel. ${p.phone}', align: 'center');
    if (p.taxId.isNotEmpty && !kitchen) await line('Tax ID: ${p.taxId}', align: 'center');
    if (p.taxRegNo.isNotEmpty && !kitchen) await line('Reg. No: ${p.taxRegNo}', align: 'center');
    b.text(''); // blank line under the contact block
    final heading = preBill
        ? 'PRE-BILL'
        : (!kitchen && p.invoiceLabel.trim().isNotEmpty)
            ? p.invoiceLabel.trim().toUpperCase()
            : slip.heading.toUpperCase();
    rule();
    await line(heading, align: 'center', big: kitchen);
    rule();

    // Ticket / table / order type — the kitchen reads these across a room.
    // nextTicket() already carries '#', so never prepend a second one.
    final tNo = order.ticketNo.startsWith('#') ? order.ticketNo : '#${order.ticketNo}';
    final when = _fmt(now);
    if (kitchen) {
      await line('Ticket $tNo', big: true);
      await line(when, big: true);
    } else {
      final label = 'Ticket $tNo';
      final gap = chars - 1 - label.length - when.length;
      await line(gap >= 1 ? '$label${' ' * gap}${when}' : label);
      if (gap < 1) await line(when);
    }
    if (order.tableName?.isNotEmpty == true) {
      await line(
        order.isQr ? '>>> QR TABLE ${order.tableName} <<<' : 'Table ${order.tableName}',
        big: kitchen,
      );
    } else {
      await line(order.type.name.toUpperCase(), big: kitchen);
    }
    if (slip.showCustomer) {
      if (order.customerName.isNotEmpty) await line(order.customerName);
      if (order.customerPhone.isNotEmpty) await line(order.customerPhone);
      if (order.type == OrderType.delivery && order.address.isNotEmpty) {
        await line(order.address);
      }
    }
    if (order.createdBy.isNotEmpty && kitchen) await line('Station: ${order.createdBy}');
    rule();

    final lines = [...order.lines]..sort((a, c) => a.course.compareTo(c.course));
    if (slip.showPrices) {
      // ITEM | QTY | AMOUNT columns, like a proper invoice.
      var amtW = 10;
      for (final e in lines) {
        final l = m(e.lineTotal).length + 1;
        if (l > amtW) amtW = l;
      }
      if (amtW > 14) amtW = 14;
      const qtyW = 6;
      final nameW = (chars - amtW - qtyW).clamp(8, 512);
      await _columns(b, ['Item', 'Qty', 'Amount'], nameW: nameW, qtyW: qtyW, amtW: amtW);
      String? last;
      for (final entry in lines) {
        if (kitchen && last != entry.course) {
          last = entry.course;
          await line('-- ${entry.course.toUpperCase()} --');
        }
        final qty = formatQty(entry.qty);
        final nameLines = wrapLines(sanitizeText(entry.name), nameW);
        for (var i = 0; i < nameLines.length; i++) {
          await _columns(b, [
            i == 0 ? nameLines[i] : '',
            i == 0 ? qty : '',
            i == 0 ? m(entry.lineTotal) : '',
          ], nameW: nameW, qtyW: qtyW, amtW: amtW);
          if (entry.notes.isNotEmpty) await line('  * ${sanitizeText(entry.notes)}');
        }
      }
    } else {
      String? last;
      for (final entry in lines) {
        if (kitchen && last != entry.course) {
          last = entry.course;
          await line('-- ${entry.course.toUpperCase()} --');
        }
        final qty = formatQty(entry.qty);
        await line('$qty x ${sanitizeText(entry.name)}');
        if (entry.notes.isNotEmpty) await line('  * ${sanitizeText(entry.notes)}');
      }
    }
    if (order.notes.isNotEmpty) {
      rule();
      await line('NOTE: ${sanitizeText(order.notes)}');
    }
    if (slip.showTotals) {
      rule();
      b.text('');
      await _row(b, 'Total', m(order.total), big: true);
      if (order.discount > 0) await _row(b, 'Discount', '- ${m(order.discount)}');
      if (order.service > 0) await _row(b, 'Service', m(order.service));
      if (order.tax > 0) await _row(b, 'Tax', m(order.tax));
      if (order.tip > 0) await _row(b, 'Tip', m(order.tip));
    }
    if (!preBill && slip.showPayment && order.payment != null) {
      if (order.splitPayment != null && order.splitAmount > 0) {
        await _row(b, 'PAID BY ${order.payment!.name.toUpperCase()}', m(order.primaryAmount));
        await _row(b, order.splitPayment!.name.toUpperCase(), m(order.splitAmount));
      } else {
        await _row(b, 'PAID BY ${order.payment!.name.toUpperCase()}', m(order.total));
      }
    }
    if (preBill) {
      await line('NOT PAID YET', align: 'center');
    }
    rule();
    // v1.1.70 — every slip type can carry its own thank-you line; fall back
    // to the shop footer for receipts (kitchen stays silent when unset).
    final footTxt = (slip.footer.trim().isNotEmpty ? slip.footer.trim() : (kitchen ? '' : p.footer)).trim();
    if (footTxt.isNotEmpty) {
      b.text('');
      await line(footTxt.toUpperCase(), align: 'center');
    }
    if (slip.showQr) {
      _raster(b, p.payQrBase64, dots);
      if (p.payQrLabel.trim().isNotEmpty) await line(p.payQrLabel.trim(), align: 'center');
    }
    b
      ..feed(4)
      ..cut();
    return b.bytes;
  }

  /// One slip line. Pure-Latin1 text goes out as native ESC/POS bytes (fast,
  /// crisp, uses the printer's own font, wrapped at the paper width).
  /// Anything beyond Latin1 — Urdu / Arabic / emoji, which no code page on a
  /// 58/80mm printer can render — is shaped by Flutter's text engine (full
  /// bidi + Arabic ligatures) and sent as a raster line, so it prints
  /// exactly as it looks on screen.
  Future<void> _line(EscPos b, String value, {String align = 'left', bool big = false}) async {
    final native = _isLatin1(value);
    if (native) {
      b.align(align);
      if (big) b.doubleSize(true);
      for (final l in wrapLines(value, big ? (b.chars ~/ 2).clamp(8, 512) : b.chars)) {
        b.text(l);
      }
      if (big) b.doubleSize(false);
      return;
    }
    try {
      await _rasterText(b, value, align: align, big: big);
    } catch (_) {
      // Never let a font/engine hiccup cost the shop a sale.
      b
        ..align(align)
        ..doubleSize(big)
        ..text(value)
        ..doubleSize(false);
    }
  }

  /// Two-column line ("name ……… price"); rasterized whole if either side
  /// needs shaping, so RTL names and Latin amounts stay on one visual line.
  Future<void> _row(EscPos b, String left, String right, {bool big = false}) async {
    if (_isLatin1(left) && _isLatin1(right)) {
      b.align('left');
      if (big) b.doubleSize(true);
      for (final l in b.rowLines(left, right, big: big)) {
        b.text(l);
      }
      if (big) b.doubleSize(false);
      return;
    }
    try {
      await _rasterRow(b, left, right, big: big);
    } catch (_) {
      b
        ..align('left')
        ..doubleSize(big)
        ..row(left, right)
        ..doubleSize(false);
    }
  }

  Future<void> _columns(EscPos b, List<String> cols, {int nameW = 0, int qtyW = 4, int amtW = 10}) async {
    // Pure ASCII layout — never needs shaping.
    final n = nameW > 0 ? nameW : b.chars - qtyW - amtW;
    final line = cols[0].padRight(n > 0 ? n : 0);
    final q = cols.length > 1 ? cols[1] : '';
    final a = cols.length > 2 ? cols[2] : '';
    b.text('$line${q.padLeft(qtyW)}${a.padLeft(amtW)}');
  }

  static bool _isLatin1(String v) {
    for (final u in v.codeUnits) {
      if (u > 0xFF) return false;
    }
    return true;
  }

  /// Word-wrap at [width] chars (hard-splits words longer than a line).
  static List<String> wrapLines(String v, int width) {
    if (width < 8) width = 8;
    final out = <String>[];
    for (final raw in v.split('\n')) {
      var cur = '';
      for (var w in raw.split(' ')) {
        while (w.length > width) {
          if (cur.isNotEmpty) {
            out.add(cur);
            cur = '';
          }
          out.add(w.substring(0, width));
          w = w.substring(width);
        }
        final add = cur.isEmpty ? w : '$cur $w';
        if (add.length > width) {
          if (cur.isNotEmpty) out.add(cur);
          cur = w;
        } else {
          cur = add;
        }
      }
      if (cur.isNotEmpty) out.add(cur);
    }
    return out.isEmpty ? const [''] : out;
  }

  TextStyle _slipStyle({required bool big, ui.Color color = const ui.Color(0xFF000000)}) {
    return TextStyle(
      color: color,
      fontSize: (big ? 40.0 : 21.0),
      fontWeight: ui.FontWeight.w700,
      height: 1.5,
    );
  }

  Future<void> _rasterText(EscPos b, String value, {required String align, required bool big}) async {
    final dots = b.dots;
    final tp = TextPainter(
      text: TextSpan(text: value, style: _slipStyle(big: big)),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: dots.toDouble());
    final h = (tp.height.ceil() ~/ 2 * 2).clamp(12, 8000);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final double dx = switch (align) {
      'center' => ((dots.toDouble() - tp.width) / 2).clamp(0.0, dots.toDouble()).toDouble(),
      'right' => dots.toDouble() - tp.width,
      _ => 0.0,
    };
    tp.paint(canvas, ui.Offset(dx, 0));
    await _emitPicture(b, rec, h);
  }

  Future<void> _rasterRow(EscPos b, String left, String right, {required bool big}) async {
    final dots = b.dots;
    final ls = _slipStyle(big: big);
    final rw = TextPainter(
      text: TextSpan(text: right, style: ls),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final leftRoom = dots.toDouble() - rw.width - 8;
    final wraps = leftRoom < 64;
    final lp = TextPainter(
      text: TextSpan(text: left, style: ls),
      textDirection: ui.TextDirection.ltr,
      maxLines: wraps ? null : 1,
      ellipsis: wraps ? null : '…',
    )..layout(maxWidth: wraps ? dots.toDouble() : leftRoom);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    lp.paint(canvas, ui.Offset.zero);
    rw.paint(canvas, ui.Offset(dots.toDouble() - rw.width, 0));
    final singleH = lp.height > rw.height ? lp.height : rw.height;
    final totalH = wraps ? lp.height : singleH;
    final h = totalH.ceil().clamp(24, 8000);
    await _emitPicture(b, rec, h ~/ 2 * 2);
  }

  Future<void> _emitPicture(EscPos b, ui.PictureRecorder rec, int height) async {
    final dots = b.dots;
    final pic = rec.endRecording();
    final image = await pic.toImage(dots, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) throw StateError('raster encode failed');
    final widthBytes = dots ~/ 8;
    final out = <int>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < widthBytes; x++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final i = ((y * dots) + (x * 8 + bit)) * 4;
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
    final b = EscPos(32)
      ..init()
      ..align('center')
      ..text('ORDER FLOW')
      ..text(shop)
      ..text('Printer test OK')
      ..feed(4)
      ..cut();
    await send(cfg, b.bytes);
  }

  /// Logos & pay QRs, v1.1.69: transparent PNGs used to print as a solid
  /// black slab because alpha was ignored (a clear pixel reads as "black").
  /// Now every pixel is composited onto white paper first, the contrast
  /// threshold adapts to the actual image, and a mostly-dark logo (white
  /// artwork on transparent) is auto-inverted so it prints as ink — whatever
  /// format the shop uploaded, it comes out as it looks.
  void _raster(EscPos b, String? raw, int dots, {double scale = 1.0}) {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final data = base64Decode(raw.contains(',') ? raw.split(',').last : raw);
      final decoded = img.decodeImage(data);
      if (decoded == null) return;
      var im = decoded;
      final maxW = (dots * scale).floor().clamp(64, dots);
      if (im.width > maxW) im = img.copyResize(im, width: maxW);
      final w = im.width;
      final h = im.height;
      final vals = List<int>.filled(w * h, 255);
      var mn = 255;
      var mx = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          final af = p.a / 255.0;
          final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          final v = (lum * af + 255.0 * (1 - af)).round().clamp(0, 255);
          vals[y * w + x] = v;
          if (v < mn) mn = v;
          if (v > mx) mx = v;
        }
      }
      var t = ((mn + mx) ~/ 2).clamp(24, 232);
      if (mx - mn < 24) t = 128; // flat image: just pick a mid threshold
      var dark = 0;
      for (final v in vals) {
        if (v <= t) dark++;
      }
      // Majority dark artwork (white-on-transparent logos included) → invert
      // so the marks print and the background stays paper.
      final invert = dark > (w * h * 3) ~/ 5;
      final off = ((dots - w) ~/ 2).clamp(0, dots);
      final widthBytes = dots ~/ 8;
      final out = <int>[];
      for (var y = 0; y < h; y++) {
        for (var bx = 0; bx < widthBytes; bx++) {
          var byte = 0;
          for (var bit = 0; bit < 8; bit++) {
            final xx = bx * 8 + bit - off;
            if (xx < 0 || xx >= w) continue;
            var v = vals[y * w + xx];
            if (invert) v = 255 - v;
            if (v <= t) byte |= 128 >> bit;
          }
          out.add(byte);
        }
      }
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
  EscPos(this.chars);

  /// Characters per line for the native font (12 dots wide at 203dpi).
  final int chars;
  int get dots => chars * 12;

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

  void stars() => text('-' * (chars - 1));

  void rule() => stars();

  void row(String left, String right) {
    for (final l in rowLines(left, right)) {
      text(l);
    }
  }

  /// Two-column line wrapped at the paper width: the value hugs the right
  /// margin on the first line, the label continues below — nothing is ever
  /// cut mid-word again.
  List<String> rowLines(String left, String right, {bool big = false}) {
    final w = big ? (chars ~/ 2).clamp(8, 512) : chars;
    var l = left.trimRight();
    final r = right.trim();
    if (r.isEmpty) return PrintService.wrapLines(l, w);
    if (l.isEmpty) return [r.padLeft(w)];
    if (l.length + r.length + 1 <= w) {
      final gap = w - l.length - r.length;
      return ['$l${' ' * gap}$r'];
    }
    final firstW = (w - r.length - 1).clamp(8, w);
    final firstTail = l.length > firstW ? l.substring(firstW).trimLeft() : '';
    final head = l.length > firstW ? l.substring(0, firstW).trimRight() : l;
    final lines = ['$head${' ' * (w - head.length - r.length).clamp(1, w)}$r'];
    if (firstTail.isNotEmpty) lines.addAll(PrintService.wrapLines(firstTail, w));
    return lines;
  }
}
