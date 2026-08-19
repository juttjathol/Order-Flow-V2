import 'dart:convert';

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
  });

  final bool ok;
  final bool valid;
  final String error;
  final String message;
  final String customerName;
  final String businessName;
  final DateTime? expiresAt;
  final String boundDeviceId;

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
    final base = apiBase.trim().isEmpty ? kDefaultApiBase : apiBase.trim();
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
      final error = (body['error'] ?? '').toString();
      final valid = body['valid'] == true && res.statusCode < 400;
      return LicenseResult(
        ok: body['ok'] == true || valid,
        valid: valid,
        error: error.isNotEmpty
            ? error
            : (valid ? '' : (res.statusCode == 404 ? 'not_found' : 'invalid')),
        message: (body['message'] ?? '').toString(),
        customerName: _nested(body, 'customer', 'name'),
        businessName: _nested(body, 'customer', 'businessName'),
        expiresAt: body['expiresAt'] == null
            ? null
            : DateTime.tryParse(body['expiresAt'].toString()),
        boundDeviceId: (body['boundDeviceId'] ?? '').toString(),
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
      );
    }
    if (result.error == 'network') {
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

  String _nested(Map<String, dynamic> body, String a, String b) {
    final n = body[a];
    if (n is Map) return (n[b] ?? '').toString();
    return (body[b] ?? '').toString();
  }
}
