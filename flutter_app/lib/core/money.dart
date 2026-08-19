import 'package:intl/intl.dart';

/// Formats money using the configured currency symbol. Never hardcodes `$`.
String money(num amount, String symbol, {bool prefix = true, int decimals = 2}) {
  final formatted = NumberFormat.currency(
    symbol: '',
    decimalDigits: decimals,
  ).format(amount);
  final trimmed = formatted.trim();
  if (symbol.isEmpty) return trimmed;
  return prefix ? '$symbol$trimmed' : '$trimmed $symbol';
}

double asMoney(num? value) => (value ?? 0).toDouble();
