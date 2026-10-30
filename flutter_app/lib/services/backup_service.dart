import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/money.dart';
import '../models/models.dart';
import 'storage_service.dart';

class BackupService {
  BackupService(this.storage);
  final StorageService storage;

  static const kind = 'jathol.orderflow.backup';

  Future<String> exportAndShare(AppStore store, {required String passphrase}) async {
    if (passphrase.trim().length < 8) throw ArgumentError('Backup passphrase must be at least 8 characters');
    final shop = store.profile.businessName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final name = 'Jathol_${shop.isEmpty ? 'Shop' : shop}_backup_$stamp.ofbak';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    final payload = {
      'kind': kind,
      'app': kAppName,
      'appVersion': kAppVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'store': store.toJson(),
    };
    final plain = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
    final random = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
    final iv = Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
    final key = _deriveKey(passphrase, salt, 200000);
    final cipher = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(encrypt_pkg.Key(key), mode: encrypt_pkg.AESMode.gcm),
    );
    final encrypted = cipher.encryptBytes(plain, iv: encrypt_pkg.IV(iv));
    final envelope = {
      'format': 'jathol.orderflow.encrypted-backup',
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 200000,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': encrypted.base64,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(envelope));
    await Share.shareXFiles(
      [XFile(file.path, name: name, mimeType: 'application/octet-stream')],
      subject: 'Order Flow backup — $name',
      text: 'Encrypted Order Flow shop backup. Restore it in More → Import backup using the passphrase you set.',
    );
    return file.path;
  }

  static String _csvCell(String v) => '"${v.replaceAll('"', '""')}"';

  static String _latinOnly(String v) => v.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');

  /// R5 — orders CSV (paid, voided, open — everything recent) for spreadsheets.
  Future<String> exportOrdersCsv(AppStore store, {int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final orders = store.orders.where((o) => o.createdAt.isAfter(since)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    String tm(DateTime t) => t.toIso8601String().substring(11, 16);
    final rows = <List<String>>[
      const ['ticket', 'date', 'time', 'status', 'type', 'table', 'channel', 'customer', 'items', 'subtotal', 'discount', 'service', 'tax', 'tip', 'total', 'payment'],
      for (final o in orders)
        [
          o.ticketNo, d(o.createdAt), tm(o.createdAt), o.status.name, o.type.name,
          (o.tableName ?? '').trim(), o.channel, o.customerName, '${o.lines.length}',
          o.subtotal.toStringAsFixed(2), o.discount.toStringAsFixed(2), o.service.toStringAsFixed(2),
          o.tax.toStringAsFixed(2), o.tip.toStringAsFixed(2), o.total.toStringAsFixed(2), o.payment?.name ?? '',
        ],
    ];
    final csv = rows.map((r) => r.map(_csvCell).join(',')).join('\n');
    final stamp = d(DateTime.now());
    final name = 'order_flow_orders_$stamp.csv';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString('\uFEFF$csv');
    await Share.shareXFiles(
      [XFile(file.path, name: name, mimeType: 'text/csv')],
      subject: 'Order Flow orders — $stamp',
      text: 'Orders export (last $days days).',
    );
    return file.path;
  }

  /// R5 — today's sales summary as a simple, PDF-viewer-safe document.
  Future<String> exportSalesPdf(AppStore store) async {
    final now = DateTime.now();
    final paid = store.orders
        .where((o) => o.status == OrderStatus.paid && o.updatedAt.year == now.year && o.updatedAt.month == now.month && o.updatedAt.day == now.day)
        .toList();
    final cur = store.profile.currencySymbol;
    final prefix = store.profile.currencyPrefix;
    String m(num v) => _latinOnly(money(v, cur, prefix: prefix));
    double paidBy(PaymentMethod m) => paid.fold<double>(0, (a, o) => a + o.paidBy(m));
    final cash = paidBy(PaymentMethod.cash);
    final card = paidBy(PaymentMethod.card);
    final byMethod = <String, double>{
      for (final m in PaymentMethod.values) m.name: paidBy(m),
    }..removeWhere((_, v) => v <= 0);
    final qty = <String, double>{};
    for (final o in paid) {
      for (final l in o.lines) {
        qty.update(l.name, (a) => a + l.qty, ifAbsent: () => l.qty);
      }
    }
    final top = qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final stamp = now.toIso8601String().substring(0, 10);
    final lines = <String>[
      '',
      'Date: $stamp',
      'Shop: ${_latinOnly(store.profile.businessName)}',
      '',
      'Total sales: ${m(store.salesOn(now))}',
      'Cash: ${m(cash)}    Card: ${m(card)}    Tickets: ${paid.length}',
      '',
      '--- Payment breakdown ---',
      for (final e in byMethod.entries) '${e.key}: ${m(e.value)}',
      '',
      '--- Top items ---',
      for (final e in top.take(10)) '${e.value.toStringAsFixed(e.value % 1 == 0 ? 0 : 1)} x ${_latinOnly(e.key)}',
      '',
      'Generated by Order Flow $kAppVersion',
    ];
    final name = 'order_flow_daily_$stamp.pdf';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(_miniPdf('Order Flow - Daily summary $stamp', lines));
    await Share.shareXFiles(
      [XFile(file.path, name: name, mimeType: 'application/pdf')],
      subject: 'Order Flow daily summary — $stamp',
      text: 'Daily sales summary ($stamp).',
    );
    return file.path;
  }

  /// Minimal single/multi-page text PDF (Courier, A4). Input must be Latin-1
  /// safe — callers pass [_latinOnly] output. Offsets are byte offsets.
  static List<int> _miniPdf(String title, List<String> lines) {
    const perPage = 46;
    final clean = lines.map(_latinOnly).toList();
    final pages = <List<String>>[
      for (var i = 0; i < clean.length; i += perPage)
        clean.sublist(i, i + perPage > clean.length ? clean.length : i + perPage),
    ];
    if (pages.isEmpty) pages.add(const <String>[]);
    String esc(String v) => v.replaceAll('\\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
    final sb = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    void obj(String body) {
      offsets.add(sb.length);
      sb.write('${offsets.length} 0 obj\n$body\nendobj\n');
    }
    obj('<< /Type /Catalog /Pages 2 0 R >>');
    final kids = [for (var i = 0; i < pages.length; i++) '${4 + i * 2} 0 R'].join(' ');
    obj('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>');
    obj('<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>');
    for (var i = 0; i < pages.length; i++) {
      final content = StringBuffer('BT /F1 11 Tf 46 800 Td 15 TL\n');
      if (i == 0) content.write('(${esc(_latinOnly(title))}) Tj T*\nT*\n');
      for (final line in pages[i]) {
        content.write('(${esc(line)}) Tj T*\n');
      }
      content.write('ET');
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>');
      obj('<< /Length ${content.length} >>\nstream\n$content\nendstream');
    }
    final xrefAt = sb.length;
    final size = offsets.length + 1;
    sb.write('xref\n0 $size\n0000000000 65535 f \n');
    for (final off in offsets) {
      sb.write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    sb.write('trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xrefAt\n%%EOF\n');
    return latin1.encode(sb.toString());
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(passphrase));
    final input = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
    input.setRange(salt.length, salt.length + 4, const [0, 0, 0, 1]);
    var u = Uint8List.fromList(hmac.convert(input).bytes);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  static Map<String, dynamic> _decodeBackup(String raw, String passphrase) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('This file is not an Order Flow backup');
    final map = Map<String, dynamic>.from(decoded);
    if (map['format'] != 'jathol.orderflow.encrypted-backup') return map;
    if (passphrase.trim().length < 8) throw const FormatException('Backup passphrase required');
    final iterations = map['iterations'] is int ? map['iterations'] as int : 200000;
    if (iterations < 100000 || iterations > 1000000) throw const FormatException('Invalid backup KDF settings');
    try {
      final key = _deriveKey(passphrase, base64Decode(map['salt'].toString()), iterations);
      final cipher = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(encrypt_pkg.Key(key), mode: encrypt_pkg.AESMode.gcm),
      );
      final clear = cipher.decryptBytes(
        encrypt_pkg.Encrypted.fromBase64(map['ciphertext'].toString()),
        iv: encrypt_pkg.IV(base64Decode(map['iv'].toString())),
      );
      final inner = jsonDecode(utf8.decode(clear));
      if (inner is! Map || inner['kind'] != kind) {
        throw const FormatException('Wrong passphrase or damaged backup');
      }
      return Map<String, dynamic>.from(inner);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Wrong passphrase or damaged backup');
    }
  }

  Future<AppStore?> pickImport({required String passphrase}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'ofbak', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    String raw;
    if (picked.bytes != null && picked.bytes!.isNotEmpty) {
      raw = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      raw = await File(picked.path!).readAsString();
    } else {
      return null;
    }
    final map = _decodeBackup(raw, passphrase);
    final storeRaw = map['store'];
    if (storeRaw is Map) {
      return AppStore.fromJson(Map<String, dynamic>.from(storeRaw));
    }
    return AppStore.fromJson(map);
  }
}
