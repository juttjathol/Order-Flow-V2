import 'dart:async';
import 'dart:developer' as dev;

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

  static Future<void> init() async {
    _initialized = true;
    // TODO(phase-1): uncomment when sentry_flutter is added to pubspec
    // await SentryFlutter.init((o) {
    //   o.dsn = const String.fromEnvironment('SENTRY_DSN');
    //   o.tracesSampleRate = 0.1;
    //   o.attachStacktrace = true;
    // });
    dev.log('[ErrorReporter] initialized (stub, buffer=$_maxBuffer)');
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

    // TODO: Sentry
    // unawaited(Sentry.captureException(error, stackTrace: stack,
    //   withScope: (s) {
    //     tags?.forEach((k, v) => s.setTag(k, v));
    //     extra?.forEach((k, v) => s.setExtra(k, v));
    //   },
    // ));
  }

  /// For health endpoint / debug sheet — not PII
  static List<Map<String, dynamic>> get bufferedEvents =>
      _buffer.map((e) => e.toJson()).toList();

  static Map<String, dynamic> get health => {
        'initialized': _initialized,
        'buffered': _buffer.length,
        'lastBreadcrumb': _lastBreadcrumb,
        'lastError': _buffer.isEmpty ? null : _buffer.last.error,
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
