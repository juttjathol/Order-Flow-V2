import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

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
  static bool _initialized = false;
  static final List<_BufferedEvent> _buffer = [];
  static const int _maxBuffer = 50;
  static String? _lastBreadcrumb;

  static String _sentryDsn = '';
  static int _lastSentMs = 0;
  static int _sentInMinute = 0;

  static Future<void> init() async {
    _initialized = true;
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
    try {
      final uri = Uri.parse('$kDefaultApiBase/api/v1/events');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'kind': level == 'crash' ? 'crash' : 'error',
              'route': tags?['where'] ?? _lastBreadcrumb ?? 'unknown',
              'detail': error.length > 2000 ? error.substring(0, 2000) : error,
              'deviceId': extra?['deviceId']?.toString() ?? '',
              'licenseKey': extra?['licenseKey']?.toString() ?? '',
            }),
          )
          .timeout(const Duration(seconds: 5));
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
