import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// The brand celebration files are hand-authored, so CI verifies they
/// parse into real compositions (duration, non-empty) before we ship.
void main() {
  for (final name in ['pay_check', 'kitchen_burst']) {
    test('$name parses as a valid Lottie composition', () async {
      final bytes = File('assets/animations/$name.json').readAsBytesSync();
      final comp = await LottieComposition.fromByteData(
        ByteData.view(Uint8List.fromList(bytes).buffer),
      );
      expect(comp.duration > Duration.zero, isTrue);
      expect(comp.size.height, greaterThan(0));
    });
  }
}
