import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the Main Android process alive while the LAN shop server is on.
/// Desktop Main needs none of this: a running window already holds the
/// process; the broadcast bell in-app covers announcements.
class ShopKeepAlive {
  static const _ch = MethodChannel('jathol/shop_keepalive');

  static Future<void> start({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('start', {'title': title, 'text': text});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  static Future<void> alert({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('alert', {'title': title, 'text': text});
    } catch (_) {}
  }
}
