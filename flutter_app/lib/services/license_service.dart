import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/models.dart';

class LicenseResult {
  LicenseResult({
    required this.ok,
    required this.valid,
    this.error = '',
    this.message = '',
    this.customerName = '',
    this.businessName = '',
    this.expiresAt,
    this.boundDeviceId = '',
    this.plan = '',
    this.allowedModels,
    this.allowedFeatures,
  });

  final bool ok;
  final bool valid;
  final String error;
  final String message;
  final String customerName;
  final String businessName;
  final DateTime? expiresAt;
  final String boundDeviceId;
  /// ── v1.1.59 plan data (null lists = legacy key, everything stays on) ──
  final String plan;
  final List<String>? allowedModels;
  final List<String>? allowedFeatures;

  bool get notFound => error == 'not_found';
  bool get revoked => error == 'revoked';
  bool get boundOther => error == 'bound_to_other_device';
  bool get expired => error == 'expired';
}

class LicenseService {
  Future<LicenseResult> validate({
    required String apiBase,
    required String licenseKey,
    required String deviceId,
  }) async {
    final base = apiBase.trim().isNotEmpty ? apiBase.trim() : kDefaultApiBase;
    final uri = Uri.parse(_join(base, '/api/v1/license/validate'));
    try {
      final res = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'licenseKey': licenseKey.trim(),
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final body = _decode(res.body);
      var error = (body['error'] ?? '').toString();
      if (res.statusCode >= 500) {
        return LicenseResult(ok: false, valid: false, error: 'network', message: 'server');
      }
      if (res.statusCode == 404 && error.isEmpty) {
        return LicenseResult(ok: false, valid: false, error: 'network', message: 'not_json');
      }
      if (!_sigOk(body, licenseKey.trim(), deviceId) && (body['signature'] != null || kLicenseRequireSig)) {
        return LicenseResult(ok: false, valid: false, error: 'bad_sig');
      }
      final valid = body['valid'] == true && res.statusCode < 400;
      return LicenseResult(
        ok: body['ok'] == true || valid,
        valid: valid,
        error: error.isNotEmpty
            ? error
            : (valid ? '' : 'invalid'),
        message: (body['message'] ?? '').toString(),
        customerName: _nested(body, 'customer', 'name'),
        businessName: _nested(body, 'customer', 'businessName'),
        expiresAt: body['expiresAt'] == null
            ? null
            : DateTime.tryParse(body['expiresAt'].toString()),
        boundDeviceId: (body['boundDeviceId'] ?? '').toString(),
        plan: (body['plan'] ?? '').toString(),
        allowedModels: _stringList(body['allowedModels']),
        allowedFeatures: _stringList(body['allowedFeatures']),
      );
    } catch (e) {
      return LicenseResult(
        ok: false,
        valid: false,
        error: 'network',
        message: e.toString(),
      );
    }
  }

  LicenseRecord applyOnlineResult(LicenseRecord current, LicenseResult result) {
    if (result.valid) {
      // v1.1.82: the payload is the source of truth. Write it even when it
      // carries explicitly-empty lists (a Starter plan really is []), and
      // derive hasPlanData from THIS payload only — a null payload clears a
      // sticky flag so the key falls back to all-on instead of keeping the
      // last plan's restrictions forever.
      final hasPlan = result.allowedModels != null || result.allowedFeatures != null;
      return LicenseRecord(
        key: current.key,
        valid: true,
        locked: false,
        lockReason: '',
        customerName: result.customerName,
        businessName: result.businessName,
        expiresAt: result.expiresAt,
        lastValidatedAt: DateTime.now(),
        message: result.message,
        plan: result.plan,
        allowedModels: hasPlan ? result.allowedModels : current.allowedModels,
        allowedFeatures: hasPlan ? result.allowedFeatures : current.allowedFeatures,
        hasPlanData: hasPlan,
      );
    }
    // v1.1.82: network failures, server rate-limits (slow_down) and
    // signature hiccups (bad_sig) are transient — they share the offline
    // grace path and must NEVER hard-lock the device. Only
    // not_found/revoked/expired (below) may lock.
    if (result.error == 'network' ||
        result.error == 'slow_down' ||
        result.error == 'bad_sig') {
      if (current.valid && current.lastValidatedAt != null) {
        final limit = current.lastValidatedAt!
            .add(const Duration(hours: kOfflineGraceHours));
        if (DateTime.now().isBefore(limit)) {
          current.message = 'offline_grace';
          return current;
        }
      }
      current.valid = false;
      current.message = 'offline_expired';
      return current;
    }
    if (result.notFound || result.revoked || result.expired) {
      return LicenseRecord(
        key: current.key,
        valid: false,
        locked: true,
        lockReason: result.notFound
            ? 'deleted'
            : (result.revoked ? 'revoked' : 'expired'),
        customerName: current.customerName,
        businessName: current.businessName,
        expiresAt: current.expiresAt,
        lastValidatedAt: current.lastValidatedAt,
        message: result.message,
      );
    }
    current.valid = false;
    current.message = result.message.isEmpty ? result.error : result.message;
    return current;
  }

  bool _sigOk(Map<String, dynamic> body, String licenseKey, String deviceId) {
    final sig = (body['signature'] ?? '').toString();
    if (sig.isEmpty) return !kLicenseRequireSig;
    if (kLicensePubKey.isEmpty) return !kLicenseRequireSig;
    final features = _stringList(body['allowedFeatures']) ?? const <String>[];
    final models = _stringList(body['allowedModels']) ?? const <String>[];
    final f = [...features]..sort();
    final m = [...models]..sort();
    final canonical =
        'v1|$licenseKey|$deviceId|${body['status'] ?? 'active'}|${body['expiresAt'] ?? ''}|${body['plan'] ?? ''}|${f.join(',')}|${m.join(',')}|${body['signedAt'] ?? ''}|${body['nonce'] ?? ''}';
    try {
      final der = base64Decode(kLicensePubKey);
      final raw = Uint8List.fromList(der.sublist(der.length - 32));
      final pub = ed.PublicKey(raw);
      return ed.verify(
        pub,
        Uint8List.fromList(utf8.encode(canonical)),
        Uint8List.fromList(base64Decode(sig)),
      );
    } catch (_) {
      return false;
    }
  }

  String _join(String base, String path) {
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return '$base$path';
  }

  Map<String, dynamic> _decode(String raw) {
    if (raw.isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }

  List<String>? _stringList(Object? raw) {
    if (raw is! List) return null;
    return raw.map((e) => e.toString()).toList();
  }

  String _nested(Map<String, dynamic> body, String a, String b) {
    final n = body[a];
    if (n is Map) return (n[b] ?? '').toString();
    return (body[b] ?? '').toString();
  }

  Future<List<BroadcastItem>> fetchBroadcasts({String apiBase = ''}) async {
    final base = apiBase.trim().isNotEmpty ? apiBase.trim() : kDefaultApiBase;
    final uri = Uri.parse(_join(base, '/api/v1/broadcasts'));
    try {
      final res = await http.get(uri, headers: const {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final body = _decode(res.body);
      final list = body['broadcasts'];
      if (list is List) {
        return list
            .whereType<Map>()
            .map((m) => BroadcastItem.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
