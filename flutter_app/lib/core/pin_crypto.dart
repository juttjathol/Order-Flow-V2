import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'sanitize.dart';

/// Manager PIN at rest: `sha256$<saltHex>$<digestHex>`. Plaintext from older
/// installs is still accepted once, then rehashed on success.
class PinCrypto {
  static bool isHashed(String stored) => stored.startsWith('sha256\$');

  static String hash(String pin, {String? saltHex}) {
    final salt = saltHex ?? _salt();
    final digest = sha256.convert(utf8.encode('$salt|$pin')).toString();
    return 'sha256\$$salt\$$digest';
  }

  static bool verify(String stored, String pin) {
    if (pin.isEmpty || stored.isEmpty) return false;
    if (!isHashed(stored)) return safeEq(stored, pin);
    final parts = stored.split('\$');
    if (parts.length != 3) return false;
    return safeEq(hash(pin, saltHex: parts[1]), stored);
  }

  static String _salt() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}
