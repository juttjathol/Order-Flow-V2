import 'package:flutter_test/flutter_test.dart';
import 'package:order_flow/core/money.dart';

void main() {
  test('formats with the configured symbol and never assumes dollars', () {
    final prefixed = money(120, 'Rs');
    final suffixed = money(120, '€', prefix: false);
    expect(prefixed.startsWith('Rs'), isTrue);
    expect(prefixed.contains('120'), isTrue);
    expect(suffixed.contains('€'), isTrue);
    expect(money(10, 'Rs').contains(r'$'), isFalse);
  });
}
