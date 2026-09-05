// Plan & license extras (v1.1.59).
//
// Everything in this file is ADDITIVE: legacy stores without these fields
// parse to safe defaults, and a license key without plan data keeps every
// feature unlocked exactly like before.

import 'models_enums.dart';

/// A feature the admin can switch on/off per license key.
class FeatureInfo {
  const FeatureInfo(this.key, this.labelEn, this.labelUr);
  final String key;
  final String labelEn;
  final String labelUr;
}

/// The gated extras catalog. Keys are stable — they are stored in the
/// license DB, so never rename one. Features NOT in this list are always on.
const kFeatureCatalog = <FeatureInfo>[
  FeatureInfo('multi_terminal', 'Connect extra station devices', 'اضافی اسٹیشن ڈیوائسز جوڑیں'),
  FeatureInfo('station_printers', 'Per-station printers & auto kitchen print', 'فی اسٹیشن پرنٹرز اور خودکار کچن پرنٹ'),
  FeatureInfo('qr_ordering', 'QR table ordering & self-order', 'کیو آر ٹیبل آرڈرنگ اور سیلف آرڈر'),
  FeatureInfo('loyalty', 'Loyalty points & store credit', 'وفاداری پوائنٹس اور اسٹور کریڈٹ'),
  FeatureInfo('split_payment', 'Split payment (two methods)', 'تقسیم ادائیگی (دو طریقے)'),
  FeatureInfo('refunds', 'Refund paid orders', 'اداشدہ آرڈرز کی رقم واپسی'),
  FeatureInfo('customer_display', 'Customer display screen', 'کسٹمر ڈسپلے اسکرین'),
  FeatureInfo('reservations', 'Reservations / appointments', 'ریزرویشن / اپائنٹمنٹس'),
  FeatureInfo('recipe_costing', 'Recipe costing & food margins', 'ریسیپی کاسٹنگ اور فوڈ مارجن'),
  FeatureInfo('wastage', 'Wastage log', 'ویسٹیج لاگ'),
  FeatureInfo('purchases', 'Suppliers & purchase orders', 'سپلائرز اور پرچیز آرڈرز'),
  FeatureInfo('advanced_reports', 'Insights: best sellers, profit, staff', 'انسائٹ: بیسٹ سیلرز، منافع، اسٹاف'),
  FeatureInfo('eighty_six', '86 board (sellable control)', '۸۶ بورڈ'),
];

final Set<String> _kFeatureKeys = kFeatureCatalog.map((f) => f.key).toSet();
bool isGatedFeature(String key) => _kFeatureKeys.contains(key);

/// Per-license plan & entitlements. Lives on AppStore so it syncs to every
/// station automatically, and on LicenseRecord as the cache of the last
/// online check.
class Entitlements {
  Entitlements({
    this.allOn = true,
    this.plan = '',
    List<String>? models,
    List<String>? features,
  })  : models = models ?? <String>[],
        features = features ?? <String>[];

  /// true = legacy key / no plan set → every feature allowed (nothing breaks).
  bool allOn;
  /// starter | growth | custom | '' — display only.
  String plan;
  /// Allowed BusinessModel names; empty = all allowed.
  List<String> models;
  /// Enabled gated feature keys; when allOn is false only these are on.
  List<String> features;

  bool allowsFeature(String key) {
    if (allOn) return true;
    if (!_kFeatureKeys.contains(key)) return true;
    return features.contains(key);
  }

  bool allowsModel(String model) {
    if (allOn || models.isEmpty) return true;
    return models.contains(model);
  }

  String get planLabel => plan.isEmpty ? 'full' : plan;

  Map<String, dynamic> toJson() => {
        'allOn': allOn,
        'plan': plan,
        'models': models,
        'features': features,
      };

  factory Entitlements.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const <String, dynamic>{};
    final modelsRaw = m['models'];
    final featsRaw = m['features'];
    return Entitlements(
      allOn: parseBool(m['allOn'], true),
      plan: parseStr(m['plan']) ?? '',
      models: modelsRaw is List
          ? modelsRaw.map((e) => e.toString()).toList()
          : <String>[],
      features: featsRaw is List
          ? featsRaw.map((e) => e.toString()).toList()
          : <String>[],
    );
  }

  bool sameAs(Entitlements o) =>
      allOn == o.allOn &&
      plan == o.plan &&
      models.join(',') == o.models.join(',') &&
      features.join(',') == o.features.join(',');

  /// Build entitlements from a license validation response.
  /// Null/absent lists mean "no plan set" → everything stays on.
  factory Entitlements.fromLicense({
    String plan = '',
    List<String>? allowedModels,
    List<String>? allowedFeatures,
  }) {
    final hasPlan = allowedModels != null || allowedFeatures != null;
    return Entitlements(
      allOn: !hasPlan,
      plan: hasPlan ? plan : (plan.isEmpty ? 'full' : plan),
      models: allowedModels ?? <String>[],
      features: hasPlan
          ? allowedFeatures!.where(isGatedFeature).toList()
          : <String>[],
    );
  }
}

/// Ingredient link for recipe costing (added to MenuProduct, v1.1.59).
class RecipeLine {
  RecipeLine({
    required this.stockId,
    this.quantity = 1,
  });

  String stockId;
  double quantity;

  Map<String, dynamic> toJson() => {
        'stockId': stockId,
        'quantity': quantity,
      };

  factory RecipeLine.fromJson(Map<String, dynamic> j) => RecipeLine(
        stockId: parseStr(j['stockId']) ?? '',
        quantity: parseNum(j['quantity'], 1),
      );
}

class WastageEntry {
  WastageEntry({
    required this.id,
    required this.stockId,
    required this.quantity,
    this.cost = 0,
    this.reason = '',
    DateTime? at,
    this.actor = '',
  }) : at = at ?? DateTime.now();

  String id;
  String stockId;
  double quantity;
  /// Total money lost; 0 → computed live from stock cost.
  double cost;
  String reason;
  DateTime at;
  String actor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'stockId': stockId,
        'quantity': quantity,
        'cost': cost,
        'reason': reason,
        'at': at.toIso8601String(),
        'actor': actor,
      };

  factory WastageEntry.fromJson(Map<String, dynamic> j) => WastageEntry(
        id: parseStr(j['id']) ?? '',
        stockId: parseStr(j['stockId']) ?? '',
        quantity: parseNum(j['quantity']),
        cost: parseNum(j['cost']),
        reason: parseStr(j['reason']) ?? '',
        at: parseTime(j['at']),
        actor: parseStr(j['actor']) ?? '',
      );
}

class Supplier {
  Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String id;
  String name;
  String phone;
  String notes;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? '',
        phone: parseStr(j['phone']) ?? '',
        notes: parseStr(j['notes']) ?? '',
        createdAt: parseTime(j['createdAt']),
      );
}

class PurchaseLine {
  PurchaseLine({
    required this.stockId,
    this.quantity = 1,
    this.cost = 0,
  });

  String stockId;
  double quantity;
  double cost;

  double get lineCost => quantity * cost;

  Map<String, dynamic> toJson() => {
        'stockId': stockId,
        'quantity': quantity,
        'cost': cost,
      };

  factory PurchaseLine.fromJson(Map<String, dynamic> j) => PurchaseLine(
        stockId: parseStr(j['stockId']) ?? '',
        quantity: parseNum(j['quantity'], 1),
        cost: parseNum(j['cost']),
      );
}

class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.poNo,
    this.supplierId = '',
    this.supplierName = '',
    List<PurchaseLine>? lines,
    this.status = 'ordered',
    this.notes = '',
    DateTime? createdAt,
    this.receivedAt,
    this.createdBy = '',
  }) : lines = lines ?? <PurchaseLine>[],
       createdAt = createdAt ?? DateTime.now();

  String id;
  String poNo;
  String supplierId;
  String supplierName;
  List<PurchaseLine> lines;
  /// ordered | received | cancelled
  String status;
  String notes;
  DateTime createdAt;
  DateTime? receivedAt;
  String createdBy;

  double get total => lines.fold<double>(0, (s, l) => s + l.lineCost);

  Map<String, dynamic> toJson() => {
        'id': id,
        'poNo': poNo,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'lines': lines.map((e) => e.toJson()).toList(),
        'status': status,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'receivedAt': receivedAt?.toIso8601String(),
        'createdBy': createdBy,
      };

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: parseStr(j['id']) ?? '',
        poNo: parseStr(j['poNo']) ?? '',
        supplierId: parseStr(j['supplierId']) ?? '',
        supplierName: parseStr(j['supplierName']) ?? '',
        lines: ((j['lines'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PurchaseLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        status: parseStr(j['status']) ?? 'ordered',
        notes: parseStr(j['notes']) ?? '',
        createdAt: parseTime(j['createdAt']),
        receivedAt: j['receivedAt'] == null ? null : parseTime(j['receivedAt']),
        createdBy: parseStr(j['createdBy']) ?? '',
      );
}
