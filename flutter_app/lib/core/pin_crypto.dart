import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'sanitize.dart';

/// Manager PIN at rest — Phase-1 hardened for 10k shops.
/// 
/// Old: `sha256$<saltHex>$<digestHex>`  (single SHA-256, brute-forced in ms)
/// New: `pbkdf2-sha256$50000$<saltHex>$<hashHex>` (PBKDF2 50k, ~300ms per guess)
/// Plaintext from ancient installs still accepted once, then rehashed.
/// 
/// Leaking even PBKDF2 hash to a stolen station is still risky (4-digit =
/// 10k combos), so LAN server strips the hash for web-console and Phase-2
/// will move verification server-side entirely.
class PinCrypto {
  static const int _iters = 50000;
  static const String _prefixPbkdf2 = 'pbkdf2-sha256';

  static bool isHashed(String stored) =>
      stored.startsWith('sha256\$') || stored.startsWith('$_prefixPbkdf2\$');

  static bool isPbkdf2(String stored) => stored.startsWith('$_prefixPbkdf2\$');

  static String hash(String pin, {String? saltHex, int iterations = _iters}) {
    final salt = saltHex ?? _salt();
    final hashHex = _pbkdf2Hex(pin, salt, iterations);
    return '$_prefixPbkdf2\$$iterations\$$salt\$$hashHex';
  }

  static String _salt() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  static String _pbkdf2Hex(String password, String saltHex, int iterations) {
    final salt = _hexToBytes(saltHex);
    final pwdBytes = utf8.encode(password);
    final hmac = Hmac(sha256, pwdBytes);
    // PBKDF2 with 1 block (32 bytes)
    final blockIndex = Uint8List(4)..[3] = 1;
    final input = Uint8List(salt.length + 4);
    input.setRange(0, salt.length, salt);
    input.setRange(salt.length, salt.length + 4, blockIndex);
    Uint8List u = Uint8List.fromList(hmac.convert(input).bytes);
    Uint8List result = Uint8List.fromList(u);
    for (int i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return _bytesToHex(result);
  }

  static bool verify(String stored, String pin) {
    if (pin.isEmpty || stored.isEmpty) return false;
    if (!isHashed(stored)) return safeEq(stored, pin);
    // Legacy single-SHA
    if (stored.startsWith('sha256\$')) {
      final parts = stored.split('\$');
      if (parts.length != 3) return false;
      final salt = parts[1];
      final digest = sha256.convert(utf8.encode('$salt|$pin')).toString();
      return safeEq('sha256\$$salt\$$digest', stored);
    }
    // PBKDF2
    if (stored.startsWith('$_prefixPbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final iters = int.tryParse(parts[1]) ?? _iters;
      final salt = parts[2];
      final expected = parts[3].toLowerCase();
      // Clamp iters to avoid DoS via huge value
      final clamped = iters.clamp(1000, 100000);
      final calc = _pbkdf2Hex(pin, salt, clamped);
      return safeEq(calc.toLowerCase(), expected);
    }
    return false;
  }
}
