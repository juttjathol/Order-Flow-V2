import 'dart:io';

import '../core/money.dart';
import '../models/models.dart';

class PrintService {
  Future<void> send(PrinterConfig cfg, List<int> bytes) async {
    if (!cfg.enabled || cfg.host.trim().isEmpty) {
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

  Future<void> kitchenTicket(AppStore store, PosOrder order) {
    final b = EscPos()
      ..init()
      ..align('center')
      ..doubleSize(true)
      ..text(store.profile.businessName)
      ..doubleSize(false)
      ..text('KITCHEN TICKET')
      ..rule()
      ..align('left')
      ..text('Ticket ${order.ticketNo}');
    if (order.createdBy.isNotEmpty) b.text('Station: ${order.createdBy}');
    b
      ..text(order.tableName == null || order.tableName!.isEmpty
          ? order.type.name.toUpperCase()
          : 'TABLE ${order.tableName}');
    if (order.customerName.isNotEmpty) b.text(order.customerName);
    if (order.type == OrderType.delivery && order.address.isNotEmpty) {
      b.text(order.address);
    }
    b
      ..text(_fmt(order.createdAt))
      ..rule();
    final lines = [...order.lines]..sort((a, b) => a.course.compareTo(b.course));
    String? last;
    for (final line in lines) {
      if (last != line.course) {
        last = line.course;
        b.text('-- ${line.course.toUpperCase()} --');
      }
      b.text('${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 1)} x ${line.name}');
      if (line.notes.isNotEmpty) b.text('  * ${line.notes}');
    }
    if (order.notes.isNotEmpty) {
      b
        ..rule()
        ..text('NOTE: ${order.notes}');
    }
    b
      ..rule()
      ..feed(4)
      ..cut();
    return send(store.kitchenPrinter, b.bytes);
  }

  Future<void> receipt(AppStore store, PosOrder order) {
    final cur = store.profile.currencySymbol;
    final prefix = store.profile.currencyPrefix;
    String m(num n) => money(n, cur, prefix: prefix);
    final b = EscPos()
      ..init()
      ..align('center')
      ..doubleSize(true)
      ..text(store.profile.businessName)
      ..doubleSize(false);
    if (store.profile.address.isNotEmpty) b.text(store.profile.address);
    if (store.profile.phone.isNotEmpty) b.text(store.profile.phone);
    if (store.profile.taxId.isNotEmpty) b.text('Tax ID: ${store.profile.taxId}');
    b
      ..rule()
      ..align('left')
      ..text('Receipt ${order.ticketNo}')
      ..text(_fmt(order.updatedAt));
    if (order.tableName?.isNotEmpty == true) b.text('Table ${order.tableName}');
    b.text(order.type.name.toUpperCase());
    if (order.customerName.isNotEmpty) b.text('Customer: ${order.customerName}');
    if (order.customerPhone.isNotEmpty) b.text(order.customerPhone);
    if (order.address.isNotEmpty) b.text(order.address);
    b.rule();
    for (final line in order.lines) {
      b.row(
        '${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 1)} ${line.name}',
        m(line.lineTotal),
      );
    }
    b
      ..rule()
      ..row('Subtotal', m(order.subtotal + order.discount));
    if (order.discount > 0) b.row('Discount', '- ${m(order.discount)}');
    if (order.service > 0) {
      b.row('Service ${order.serviceRate.toStringAsFixed(1)}%', m(order.service));
    }
    if (order.tax > 0) {
      b.row('Tax ${order.taxRate.toStringAsFixed(1)}%', m(order.tax));
    }
    if (order.tip > 0) b.row('Tip', m(order.tip));
    b
      ..doubleSize(true)
      ..row('TOTAL', m(order.total))
      ..doubleSize(false);
    if (order.payment != null) b.text('Paid: ${order.payment!.name}');
    if (store.profile.footer.isNotEmpty) {
      b
        ..rule()
        ..align('center')
        ..text(store.profile.footer);
    }
    b
      ..feed(4)
      ..cut();
    return send(store.receiptPrinter, b.bytes);
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

  void rule() => text('--------------------------------');

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
