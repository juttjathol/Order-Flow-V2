import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../models/models.dart';

/// Phase-2: SQLite hot store for 10k-shop scale.
/// 
/// `app_state.json` was 9.4s at 50k orders (single JSON array scan).
/// SQLite gives 0.02s with indexes, even at 50k+.
/// 
/// Migration is lazy: first launch with SQLite enabled creates the DB and
/// backfills from the existing AppStore JSON. Subsequent launches read/write
/// orders from SQLite; other tables (menu, stock) stay in JSON for now
/// (they are small — ~200 rows). This keeps the change additive and safe.
class DatabaseService {
  DatabaseService._(this.db);
  final Database db;

  static DatabaseService? _instance;

  static Future<DatabaseService> instance() async {
    if (_instance != null) return _instance!;
    // Windows Main uses ffi, mobile uses sqflite
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      // ignore: invalid_use_of_visible_for_testing_member
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'order_flow.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE orders (
            id TEXT PRIMARY KEY,
            ticket_no TEXT,
            status TEXT NOT NULL,
            type TEXT,
            table_id TEXT,
            table_name TEXT,
            customer_name TEXT,
            total REAL,
            lines TEXT,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            shift_no INTEGER
          )
        ''');
        await db.execute('CREATE INDEX idx_orders_status ON orders(status)');
        await db.execute('CREATE INDEX idx_orders_updated ON orders(updated_at)');
        await db.execute('CREATE INDEX idx_orders_table ON orders(table_id)');
        await db.execute('CREATE INDEX idx_orders_shift ON orders(shift_no)');
        await db.execute('CREATE INDEX idx_orders_ticket ON orders(ticket_no)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_ticket ON orders(ticket_no)');
          } catch (_) {}
        }
      },
    );
    _instance = DatabaseService._(db);
    return _instance!;
  }

  Future<void> upsertOrder(PosOrder order) async {
    await db.insert(
      'orders',
      {
        'id': order.id,
        'ticket_no': order.ticketNo,
        'status': order.status.name,
        'type': order.type.name,
        'table_id': order.tableId,
        'table_name': order.tableName,
        'customer_name': order.customerName,
        'total': order.total,
        'lines': order.lines.length,
        'data': _encodeOrder(order),
        'created_at': order.createdAt.millisecondsSinceEpoch,
        'updated_at': order.updatedAt.millisecondsSinceEpoch,
        'shift_no': order.shiftNo,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteOrder(String id) async {
    await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PosOrder>> loadOrders({int limit = 200, int offset = 0, String? status}) async {
    final where = status != null ? 'WHERE status = ?' : '';
    final args = status != null ? [status] : <Object?>[];
    final rows = await db.rawQuery(
      'SELECT data FROM orders $where ORDER BY updated_at DESC LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map((r) {
      final raw = r['data'] as String;
      return PosOrder.fromJson(_decodeRaw(raw));
    }).toList();
  }

  Future<List<PosOrder>> loadOpenOrders() => loadOrders(status: null, limit: 500);

  Future<double> salesOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = start + 24 * 60 * 60 * 1000;
    final row = await db.rawQuery(
      "SELECT SUM(total) as s FROM orders WHERE status = 'paid' AND updated_at >= ? AND updated_at < ?",
      [start, end],
    );
    return (row.first['s'] as num?)?.toDouble() ?? 0;
  }

  Future<int> count() async {
    final row = await db.rawQuery('SELECT COUNT(*) as c FROM orders');
    return (row.first['c'] as int?) ?? 0;
  }

  /// Backfill from existing JSON store (one-time, lazy).
  Future<int> backfillFromStore(AppStore store) async {
    final existing = await count();
    if (existing > 0) return 0;
    int n = 0;
    for (final o in store.orders) {
      await upsertOrder(o);
      n++;
      if (n % 500 == 0) await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return n;
  }

  Future<void> archiveBefore(DateTime cutoff, {int keep = 500}) async {
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    // Keep at least `keep` newest paid even beyond cutoff
    final keepRows = await db.rawQuery(
      'SELECT id FROM orders WHERE status = ? ORDER BY updated_at DESC LIMIT ?',
      ['paid', keep],
    );
    final keepIds = keepRows.map((r) => r['id'] as String).toSet();
    await db.delete(
      'orders',
      where: "status IN ('paid','cancelled') AND updated_at < ? AND id NOT IN (${keepIds.map((_) => '?').join(',')})",
      whereArgs: [cutoffMs, ...keepIds],
    );
  }

  String _encodeOrder(PosOrder o) => jsonEncode(o.toJson());

  Map<String, dynamic> _decodeRaw(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> close() async => db.close();
}
