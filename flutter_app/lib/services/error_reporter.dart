import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Phase-1 production error reporter — stub that works without Sentry.
/// Swap `Sentry.captureException` in `_send` when `sentry_flutter` is added.
///
/// Usage:
/// ```dart
///   await ErrorReporter.init(); // in main()
///   ErrorReporter.capture(e, stack, tags: {'where': 'license.validate'});
/// ```
class ErrorReporter {
  static final WidgetsBindingObserver _lifecycle = _ReporterLifecycle();
  static bool _initialized = false;
  static final List<_BufferedEvent> _buffer = [];
  static const int _maxBuffer = 50;
  static String? _lastBreadcrumb;

  static String _sentryDsn = '';
  static int _lastSentMs = 0;
  static int _sentInMinute = 0;

  static Future<void> init() async {
    _initialized = true;
    WidgetsBinding.instance.addObserver(_lifecycle);
    _sentryDsn = kSentryDsn;
    // Phase-3: if SENTRY_DSN is provided at build, init Sentry
    if (_sentryDsn.isNotEmpty) {
      try {
        // ignore: avoid_dynamic_calls
        // await SentryFlutter.init((o) {
        //   o.dsn = _sentryDsn;
        //   o.tracesSampleRate = 0.1;
        //   o.attachStacktrace = true;
        // });
        dev.log('[ErrorReporter] Sentry DSN present, would init (uncomment when sentry imported)');
      } catch (_) {}
    }
    dev.log('[ErrorReporter] initialized (stub, buffer=$_maxBuffer, sentry=${_sentryDsn.isNotEmpty})');
    unawaited(_restoreOutbox());
  }

  static void breadcrumb(String message, {Map<String, dynamic>? data}) {
    _lastBreadcrumb = message;
    dev.log('[breadcrumb] $message ${data ?? ''}');
  }

  static void capture(
    Object error,
    StackTrace? stack, {
    String level = 'error',
    Map<String, String>? tags,
    Map<String, dynamic>? extra,
  }) {
    if (!_initialized) {
      dev.log('[ErrorReporter] not yet initialized, buffering: $error');
    }
    final evt = _BufferedEvent(
      error: error.toString(),
      stack: stack?.toString() ?? '',
      level: level,
      tags: tags ?? const {},
      extra: {
        if (_lastBreadcrumb != null) 'breadcrumb': _lastBreadcrumb!,
        ...?extra,
      },
      at: DateTime.now().toIso8601String(),
    );
    _buffer.add(evt);
    if (_buffer.length > _maxBuffer) _buffer.removeAt(0);

    // Always log locally — survives without network
    dev.log(
      '[capture][$level] $error tags=$tags breadcrumb=$_lastBreadcrumb',
      error: error,
      stackTrace: stack,
    );

    // Phase-3: also POST to D1 app_events (throttled 10/min) for 10k ops dashboard
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSentMs > 60000) {
      _sentInMinute = 0;
      _lastSentMs = nowMs;
    }
    if (_sentInMinute < 10) {
      _sentInMinute++;
      unawaited(_postToSaaS(error.toString(), level, tags, extra));
    }

    // TODO: Sentry when DSN set
    // if (_sentryDsn.isNotEmpty) {
    //   unawaited(Sentry.captureException(error, stackTrace: stack,
    //     withScope: (s) {
    //       tags?.forEach((k, v) => s.setTag(k, v));
    //       extra?.forEach((k, v) => s.setExtra(k, v));
    //     },
    //   ));
    // }
  }

  static Future<void> _postToSaaS(
    String error, String level, Map<String, String>? tags, Map<String, dynamic>? extra) async {
    final payload = jsonEncode({
      'kind': level == 'crash' ? 'crash' : 'error',
      'route': tags?['where'] ?? _lastBreadcrumb ?? 'unknown',
      'detail': error.length > 2000 ? error.substring(0, 2000) : error,
      'deviceId': extra?['deviceId']?.toString() ?? '',
      'licenseKey': extra?['licenseKey']?.toString() ?? '',
    });
    try {
      final uri = Uri.parse('$kDefaultApiBase/api/v1/events');
      final res = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: payload)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode >= 300) {
        await _enqueueOutbox(payload);
      } else {
        // Sent OK — a working line also drains anything parked earlier.
        unawaited(_flushOutbox());
      }
    } catch (_) {
      // Offline/blocked — park it, never crash the caller.
      await _enqueueOutbox(payload);
    }
  }

  // ---- R2: durable outbox (offline-first reliability) -------------------
  static const String _outboxKey = 'of_err_outbox_v1';
  static const int _outboxMax = 100;
  static int _outboxCount = 0;

  /// Events parked waiting for network (surfaced via [health]).
  static int get outboxPending => _outboxCount;

  /// Called by the lifecycle observer and available to app/test harnesses.
  static Future<void> flushPending() => _flushOutbox();

  static Future<void> _restoreOutbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      _outboxCount = p.getStringList(_outboxKey)?.length ?? 0;
      if (_outboxCount > 0) unawaited(_flushOutbox());
    } catch (_) {}
  }

  static Future<void> _enqueueOutbox(String payload) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = [...(p.getStringList(_outboxKey) ?? const <String>[])];
      list.add(payload);
      while (list.length > _outboxMax) {
        list.removeAt(0);
      }
      await p.setStringList(_outboxKey, list);
      _outboxCount = list.length;
    } catch (_) {}
  }

  static Future<void> _flushOutbox() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = [...(p.getStringList(_outboxKey) ?? const <String>[])];
      if (list.isEmpty) return;
      final uri = Uri.parse('$kDefaultApiBase/api/v1/events');
      final kept = <String>[];
      for (var i = 0; i < list.length; i++) {
        try {
          final res = await http
              .post(uri, headers: {'Content-Type': 'application/json'}, body: list[i])
              .timeout(const Duration(seconds: 5));
          if (res.statusCode >= 300) kept.add(list[i]);
        } catch (_) {
          // Still offline: keep this and everything after it, in order.
          kept.addAll(list.sublist(i));
          break;
        }
      }
      await p.setStringList(_outboxKey, kept);
      _outboxCount = kept.length;
    } catch (_) {}
  }

  /// For health endpoint / debug sheet — not PII
  static List<Map<String, dynamic>> get bufferedEvents =>
      _buffer.map((e) => e.toJson()).toList();

  static Map<String, dynamic> get health => {
        'initialized': _initialized,
        'buffered': _buffer.length,
        'lastBreadcrumb': _lastBreadcrumb,
        'lastError': _buffer.isEmpty ? null : _buffer.last.error,
        'sentry': _sentryDsn.isNotEmpty,
        'outbox': _outboxCount,
      };
}

class _BufferedEvent {
  _BufferedEvent({
    required this.error,
    required this.stack,
    required this.level,
    required this.tags,
    required this.extra,
    required this.at,
  });
  final String error;
  final String stack;
  final String level;
  final Map<String, String> tags;
  final Map<String, dynamic> extra;
  final String at;

  Map<String, dynamic> toJson() => {
        'error': error,
        'level': level,
        'tags': tags,
        'at': at,
      };
}


class _ReporterLifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ErrorReporter.flushPending());
    }
  }
}
