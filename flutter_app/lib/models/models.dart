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

class SlipTemplate {
  SlipTemplate({
    this.heading = 'CASH RECEIPT',
    this.showLogo = true,
    this.showAddress = true,
    this.showPhone = true,
    this.showPrices = true,
    this.showTotals = true,
    this.showPayment = true,
    this.showQr = true,
    this.showCustomer = true,
  });

  String heading;
  bool showLogo;
  bool showAddress;
  bool showPhone;
  bool showPrices;
  bool showTotals;
  bool showPayment;
  bool showQr;
  bool showCustomer;

  SlipTemplate copy() => SlipTemplate(
        heading: heading,
        showLogo: showLogo,
        showAddress: showAddress,
        showPhone: showPhone,
        showPrices: showPrices,
        showTotals: showTotals,
        showPayment: showPayment,
        showQr: showQr,
        showCustomer: showCustomer,
      );

  Map<String, dynamic> toJson() => {
        'heading': heading,
        'showLogo': showLogo,
        'showAddress': showAddress,
        'showPhone': showPhone,
        'showPrices': showPrices,
        'showTotals': showTotals,
        'showPayment': showPayment,
        'showQr': showQr,
        'showCustomer': showCustomer,
      };

  factory SlipTemplate.fromJson(Map<String, dynamic>? j, SlipTemplate fallback) {
    final m = j ?? const {};
    return SlipTemplate(
      heading: parseStr(m['heading']) ?? fallback.heading,
      showLogo: parseBool(m['showLogo'], fallback.showLogo),
      showAddress: parseBool(m['showAddress'], fallback.showAddress),
      showPhone: parseBool(m['showPhone'], fallback.showPhone),
      showPrices: parseBool(m['showPrices'], fallback.showPrices),
      showTotals: parseBool(m['showTotals'], fallback.showTotals),
      showPayment: parseBool(m['showPayment'], fallback.showPayment),
      showQr: parseBool(m['showQr'], fallback.showQr),
      showCustomer: parseBool(m['showCustomer'], fallback.showCustomer),
    );
  }

  static SlipTemplate kitchen() => SlipTemplate(
        heading: 'KITCHEN TICKET',
        showLogo: false,
        showAddress: false,
        showPhone: false,
        showPrices: false,
        showTotals: false,
        showPayment: false,
        showQr: false,
        showCustomer: true,
      );

  static SlipTemplate counter() => SlipTemplate(heading: 'CASH RECEIPT');

  static SlipTemplate takeaway() => SlipTemplate(heading: 'TAKEAWAY RECEIPT');

  static SlipTemplate delivery() => SlipTemplate(heading: 'DELIVERY RECEIPT');
}
