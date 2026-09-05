import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

import '../core/money.dart';
import '../models/models.dart';
import 'bluetooth_printer.dart';

class PrintService {
  final bluetooth = BluetoothPrinter();

  /// ESC/POS drawer kick: pulse pin 2 for 50ms (most drawers open on 25).
  /// Harmless on printers without a drawer port — the printer just ignores it.
  static const drawerKickBytes = [0x1B, 0x70, 0x00, 0x19, 0xFA];

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
  }) {
    return send(
      prefer ?? store.printerForRole(role) ?? store.kitchenTarget(),
      _build(store, order, kitchen: true),
    );
  }

  Future<void> receipt(
    AppStore store,
    PosOrder order, {
    AppRole? role,
    PrinterConfig? prefer,
  }) {
    return send(
      prefer ?? store.receiptTarget(role),
      _build(store, order, kitchen: false),
    );
  }

  List<int> _build(AppStore store, PosOrder order, {required bool kitchen}) {
    final p = store.profile;
    final slip = p.slipFor(order, kitchen: kitchen);
    final cur = p.currencySymbol;
    final prefix = p.currencyPrefix;
    String m(num n) => money(n, cur, prefix: prefix);
    final now = DateTime.now();
    final b = EscPos()..init()..align('center');
    if (slip.showLogo) _raster(b, p.logoBase64);
    b
      ..doubleSize(true)
      ..text(p.businessName.toUpperCase())
      ..doubleSize(false);
    if (slip.showAddress && p.address.isNotEmpty) b.text(p.address);
    if (slip.showPhone && p.phone.isNotEmpty) b.text('Tel. ${p.phone}');
    if (p.taxId.isNotEmpty && !kitchen) b.text('Tax ID: ${p.taxId}');
    // v1.1.59 — tax invoice / e-invoice style header (off unless set).
    if (p.taxRegNo.isNotEmpty && !kitchen) b.text('Reg. No: ${p.taxRegNo}');
    final heading = (!kitchen && p.invoiceLabel.trim().isNotEmpty)
        ? p.invoiceLabel.trim().toUpperCase()
        : slip.heading.toUpperCase();
    b
      ..stars()
      ..text(heading)
      ..stars();
    b
      ..align('left')
      ..text('Ticket ${order.ticketNo}')
      ..text(_fmt(now));
    if (order.tableName?.isNotEmpty == true) {
      // QR self-orders are served by table — make it unmissable (v1.1.60).
      b.text(order.isQr ? '>>> QR TABLE ${order.tableName} <<<' : 'Table ${order.tableName}');
    } else {
      b.text(order.type.name.toUpperCase());
    }
    if (slip.showCustomer) {
      if (order.customerName.isNotEmpty) b.text(order.customerName);
      if (order.customerPhone.isNotEmpty) b.text(order.customerPhone);
      if (order.type == OrderType.delivery && order.address.isNotEmpty) {
        b.text(order.address);
      }
    }
    if (order.createdBy.isNotEmpty && kitchen) b.text('Station: ${order.createdBy}');
    b.stars();
    if (slip.showPrices) {
      b.row('Description', 'Price');
    }
    final lines = [...order.lines]..sort((a, c) => a.course.compareTo(c.course));
    String? last;
    for (final line in lines) {
      if (kitchen && last != line.course) {
        last = line.course;
        b.text('-- ${line.course.toUpperCase()} --');
      }
      final qty = line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 1);
      if (slip.showPrices) {
        b.row('$qty ${line.name}', m(line.lineTotal));
      } else {
        b.text('$qty x ${line.name}');
      }
      if (line.notes.isNotEmpty) b.text('  * ${line.notes}');
    }
    if (order.notes.isNotEmpty) {
      b
        ..stars()
        ..text('NOTE: ${order.notes}');
    }
    if (slip.showTotals) {
      b
        ..stars()
        ..doubleSize(true)
        ..row('Total', m(order.total))
        ..doubleSize(false);
      if (order.discount > 0) b.row('Discount', '- ${m(order.discount)}');
      if (order.service > 0) b.row('Service', m(order.service));
      if (order.tax > 0) b.row('Tax', m(order.tax));
      if (order.tip > 0) b.row('Tip', m(order.tip));
    }
    if (slip.showPayment && order.payment != null) {
      if (order.splitPayment != null && order.splitAmount > 0) {
        b.row(order.payment!.name, m(order.primaryAmount));
        b.row(order.splitPayment!.name, m(order.splitAmount));
      } else {
        b.row(order.payment!.name, m(order.total));
      }
    }
    b.stars();
    b.align('center');
    if (p.footer.isNotEmpty) b.text(p.footer.toUpperCase());
    if (slip.showQr) {
      _raster(b, p.payQrBase64);
      if (p.payQrLabel.trim().isNotEmpty) b.text(p.payQrLabel.trim());
    }
    b
      ..feed(4)
      ..cut();
    return b.bytes;
  }

  Future<void> test(PrinterConfig cfg, String shop) {
    final b = EscPos()
      ..init()
      ..align('center')
      ..text('ORDER FLOW')
      ..text(shop)
      ..text('Printer test OK')
      ..feed(4)
      ..cut();
    return send(cfg, b.bytes);
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
