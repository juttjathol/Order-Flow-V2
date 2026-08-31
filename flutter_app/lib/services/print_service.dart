import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

import '../core/money.dart';
import '../models/models.dart';
import 'bluetooth_printer.dart';

class PrintService {
  final bluetooth = BluetoothPrinter();

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
    b
      ..stars()
      ..text(slip.heading.toUpperCase())
      ..stars()
      ..align('left')
      ..text('Ticket ${order.ticketNo}')
      ..text(_fmt(now));
    if (order.tableName?.isNotEmpty == true) {
      b.text('Table ${order.tableName}');
    } else {
      b.text(order.type.name.toUpperCase());
    }
    if (order.customerName?.isNotEmpty == true) b.text(order.customerName!);
    if (order.customerPhone?.isNotEmpty == true) b.text(order.customerPhone!);
    if (order.note?.isNotEmpty == true) b.text('Note: ${order.note}');
    b.rule();
    for (final line in order.lines) {
      final name = line.productName;
      final qty = line.qty;
      final price = line.unitPrice;
      final total = line.lineTotal;
      if (kitchen) {
        b.row('${qty}x $name', '');
        if (line.note?.isNotEmpty == true) b.text('  ${line.note}');
      } else {
        b.row('${qty}x $name', m(total));
        if (slip.showUnitPrices) b.text('  ${m(price)} each');
        if (line.note?.isNotEmpty == true) b.text('  ${line.note}');
      }
    }
    b.rule();
    if (!kitchen) {
      b.row('Subtotal', m(order.subtotal));
      if (order.discount > 0) b.row('Discount', '-${m(order.discount)}');
      if (order.tax > 0) b.row('Tax', m(order.tax));
      b.doubleSize(true);
      b.row('TOTAL', m(order.total));
      b.doubleSize(false);
      if (order.paymentMethod != null) b.text('Paid: ${order.paymentMethod}');
      if (slip.footer.isNotEmpty) {
        b.align('center');
        b.text(slip.footer);
      }
    } else {
      b.align('center');
      b.text('--- KITCHEN ---');
    }
    b.feed(3);
    b.cut();
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
