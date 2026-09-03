import 'package:uuid/uuid.dart';

import '../core/constants.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

enum BusinessModel { restaurant, retail, fastfood, services }

enum AppRole {
  none,
  main,
  manager,
  orderTaker,
  kitchen,
  cashier,
  driver,
  stockClerk,
  frontDesk,
  specialist,
}

enum TableStatus { free, ordered, ready }

enum OrderType { dineIn, takeaway, delivery, retail, service }

enum OrderStatus { open, preparing, ready, served, paid, cancelled }

enum PaymentMethod { cash, card, wallet, other, complimentary }

enum DriverStatus { free, busy, offline }

enum StaffDuty { offline, onShift, mealBreak, teaBreak }

enum ThemeChoice { system, light, dark }

enum LicenseGate { boot, license, locked, setup, ready }

enum StockLevel { ok, low, out }

T enumParse<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw == null) return fallback;
  final name = raw.toString();
  for (final v in values) {
    if (v.name == name || v.toString() == name) return v;
  }
  return fallback;
}

DateTime parseTime(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw) ?? DateTime.now();
  }
  return DateTime.now();
}

String? parseStr(Object? raw) => raw?.toString();

double parseNum(Object? raw, [double fallback = 0]) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

int parseInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

bool parseBool(Object? raw, [bool fallback = false]) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final v = raw.toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}
