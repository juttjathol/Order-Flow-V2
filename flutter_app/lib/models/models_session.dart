import 'package:uuid/uuid.dart';

import '../core/constants.dart';

import 'models_enums.dart';
import 'models_plans.dart';
import 'models_types_a.dart';
import 'models_types_b.dart';

class NetCommand {
  NetCommand({
    required this.name,
    Map<String, dynamic>? payload,
    this.actor = '',
    this.role = '',
    String? id,
    DateTime? at,
  })  : payload = payload ?? <String, dynamic>{},
        id = id ?? newId(),
        at = at ?? DateTime.now();

  final String id;
  final String name;
  final Map<String, dynamic> payload;
  final String actor;
  final String role;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'payload': payload,
        'actor': actor,
        'role': role,
        'at': at.toIso8601String(),
      };

  factory NetCommand.fromJson(Map<String, dynamic> j) => NetCommand(
        id: parseStr(j['id']),
        name: parseStr(j['name']) ?? '',
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : <String, dynamic>{},
        actor: parseStr(j['actor']) ?? '',
        role: parseStr(j['role']) ?? '',
        at: parseTime(j['at']),
      );
}

class LicenseRecord {
  LicenseRecord({
    this.key = '',
    this.valid = false,
    this.locked = false,
    this.lockReason = '',
    this.customerName = '',
    this.businessName = '',
    this.expiresAt,
    this.lastValidatedAt,
    this.message = '',
    this.plan = '',
    List<String>? allowedModels,
    List<String>? allowedFeatures,
    this.hasPlanData = false,
  })  : allowedModels = allowedModels ?? <String>[],
        allowedFeatures = allowedFeatures ?? <String>[];

  String key;
  bool valid;
  bool locked;
  String lockReason;
  String customerName;
  String businessName;
  DateTime? expiresAt;
  DateTime? lastValidatedAt;
  String message;
  /// starter | growth | custom | '' — display only (v1.1.59).
  String plan;
  /// Business models this key may use; empty list + hasPlanData = none set → all.
  List<String> allowedModels;
  /// Gated features enabled for this key (v1.1.59).
  List<String> allowedFeatures;
  /// False for legacy responses without plan data → everything stays on.
  bool hasPlanData;

  Entitlements get entitlements => Entitlements.fromLicense(
        plan: plan,
        allowedModels: hasPlanData ? allowedModels : null,
        allowedFeatures: hasPlanData ? allowedFeatures : null,
      );

  bool get inGrace {
    if (locked || !valid || lastValidatedAt == null) return false;
    final limit = lastValidatedAt!.add(const Duration(hours: kOfflineGraceHours));
    return DateTime.now().isBefore(limit);
  }

  Duration? get graceLeft {
    if (lastValidatedAt == null) return null;
    final limit = lastValidatedAt!.add(const Duration(hours: kOfflineGraceHours));
    final d = limit.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'valid': valid,
        'locked': locked,
        'lockReason': lockReason,
        'customerName': customerName,
        'businessName': businessName,
        'expiresAt': expiresAt?.toIso8601String(),
        'lastValidatedAt': lastValidatedAt?.toIso8601String(),
        'message': message,
        'plan': plan,
        'allowedModels': allowedModels,
        'allowedFeatures': allowedFeatures,
        'hasPlanData': hasPlanData,
      };

  factory LicenseRecord.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return LicenseRecord(
      key: parseStr(m['key']) ?? '',
      valid: parseBool(m['valid']),
      locked: parseBool(m['locked']),
      lockReason: parseStr(m['lockReason']) ?? '',
      customerName: parseStr(m['customerName']) ?? '',
      businessName: parseStr(m['businessName']) ?? '',
      expiresAt: m['expiresAt'] == null ? null : parseTime(m['expiresAt']),
      lastValidatedAt:
          m['lastValidatedAt'] == null ? null : parseTime(m['lastValidatedAt']),
      message: parseStr(m['message']) ?? '',
      plan: parseStr(m['plan']) ?? '',
      allowedModels: (m['allowedModels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[],
      allowedFeatures: (m['allowedFeatures'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[],
      hasPlanData: parseBool(m['hasPlanData']),
    );
  }
}

class SessionPrefs {
  SessionPrefs({
    this.deviceId = '',
    this.role = AppRole.none,
    this.displayName = '',
    this.locale = 'en',
    this.theme = ThemeChoice.light,
    this.apiBase = kDefaultApiBase,
    this.mainHost = '',
    this.pairedDriverId,
    this.staffId,
    this.modelPicked = false,
    this.lastReceiptOrderId,
    this.localBtAddress = '',
    this.localBtName = '',
    this.localBtEnabled = false,
    this.localNetHost = '',
    this.localNetPort = kEscPosPort,
    this.localNetEnabled = false,
    LicenseRecord? license,
  }) : license = license ?? LicenseRecord();

  String deviceId;
  AppRole role;
  String displayName;
  String locale;
  ThemeChoice theme;
  String apiBase;
  String mainHost;
  String? pairedDriverId;
  String? staffId;
  bool modelPicked;
  String? lastReceiptOrderId;
  String localBtAddress;
  String localBtName;
  bool localBtEnabled;
  String localNetHost;
  int localNetPort;
  bool localNetEnabled;
  LicenseRecord license;

  bool get hasLocalBtPrinter =>
      localBtEnabled && localBtAddress.trim().isNotEmpty;

  bool get hasLocalNetPrinter =>
      localNetEnabled && localNetHost.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'role': role.name,
        'displayName': displayName,
        'locale': locale,
        'theme': theme.name,
        'apiBase': apiBase,
        'mainHost': mainHost,
        'pairedDriverId': pairedDriverId,
        'staffId': staffId,
        'modelPicked': modelPicked,
        'lastReceiptOrderId': lastReceiptOrderId,
        'localBtAddress': localBtAddress,
        'localBtName': localBtName,
        'localBtEnabled': localBtEnabled,
        'localNetHost': localNetHost,
        'localNetPort': localNetPort,
        'localNetEnabled': localNetEnabled,
        'license': license.toJson(),
      };

  factory SessionPrefs.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const {};
    return SessionPrefs(
      deviceId: parseStr(m['deviceId']) ?? '',
      role: enumParse(AppRole.values, m['role'], AppRole.none),
      displayName: parseStr(m['displayName']) ?? '',
      locale: parseStr(m['locale']) ?? 'en',
      theme: enumParse(ThemeChoice.values, m['theme'], ThemeChoice.light),
      apiBase: parseStr(m['apiBase']) ?? kDefaultApiBase,
      mainHost: parseStr(m['mainHost']) ?? '',
      pairedDriverId: parseStr(m['pairedDriverId']),
      staffId: parseStr(m['staffId']),
      modelPicked: parseBool(m['modelPicked']),
      lastReceiptOrderId: parseStr(m['lastReceiptOrderId']),
      localBtAddress: parseStr(m['localBtAddress']) ?? '',
      localBtName: parseStr(m['localBtName']) ?? '',
      localBtEnabled: parseBool(m['localBtEnabled']),
      localNetHost: parseStr(m['localNetHost']) ?? '',
      localNetPort: parseInt(m['localNetPort'], kEscPosPort),
      localNetEnabled: parseBool(m['localNetEnabled']),
      license: LicenseRecord.fromJson(
        m['license'] is Map ? Map<String, dynamic>.from(m['license'] as Map) : null,
      ),
    );
  }
}

class ClientInfo {
  ClientInfo({
    required this.deviceId,
    required this.name,
    required this.role,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String deviceId;
  final String name;
  final String role;
  DateTime lastSeen;
}
