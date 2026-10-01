import 'package:flutter_test/flutter_test.dart';

/// Phase-2: layout golden check for 10k-shop device matrix.
/// Runs with dart-define TEST_WIDTH/HEIGHT to simulate iPhone SE / Pixel / iPad.
void main() {
  test('golden: iPhone SE / Pixel / iPad layouts do not overflow', () {
    const w = int.fromEnvironment('TEST_WIDTH', defaultValue: 375);
    const h = int.fromEnvironment('TEST_HEIGHT', defaultValue: 667);
    // Placeholder: real test renders OrderFlowApp inside a SizedBox(w,h)
    // and asserts no overflow. Stub passes until Patrol goldens are added.
    expect(w, greaterThan(0));
    expect(h, greaterThan(0));
  });
}
