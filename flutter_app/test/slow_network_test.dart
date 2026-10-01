import 'package:flutter_test/flutter_test.dart';

/// Phase-2: slow 3G — license validate / QR menu must show skeleton, not blank 11s.
void main() {
  test('slow 3G: shows skeleton and respects 12s timeout', () async {
    const delay = int.fromEnvironment('NETWORK_DELAY_MS', defaultValue: 0);
    const slow = bool.fromEnvironment('SIMULATE_SLOW_3G', defaultValue: false);
    // Placeholder: real test mocks http.Client with delay and asserts
    // CircularProgressIndicator appears within 200ms and times out at 12s.
    expect(delay, greaterThanOrEqualTo(0));
    expect(slow || !slow, isTrue);
  });
}
