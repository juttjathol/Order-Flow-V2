/// Web ↔ Flutter cloud-state translator (v1.1.91).
///
/// The web app (jathol.org) and this app grew as two codebases with two
/// store shapes. Over the cloud relay both sides now accept each other's
/// snapshots by translating at the receive boundary:
///
///   * Flutter device receives a web backup  → [webBackupToAppStoreJson]
///   * Web device receives a Flutter store   → handled in app.js (mirror)
///
/// Money differs: web keeps integer cents (`priceCents`), Flutter keeps
/// double whole-units (`price`). Everything converting a price divides or
/// multiplies by 100 exactly once, here or in the web mirror — never both.
library cloud_xlate;

import '../models/models_enums.dart';

// ---------------------------------------------------------------------------
// Shape detection
// ---------------------------------------------------------------------------

/// True when the incoming cloud snapshot is a web-app backup rather than a
/// Flutter AppStore. AppStore json always carries `schemaVersion`+`profile`;
/// a web backup carries a top-level `kv` map and no `profile`.
bool looksLikeWebBackup(Map<String, dynamic> j) {
  if (j['kv'] is Map) return true;
  return j['profile'] == null && j['schemaVersion'] == null;
}

// ---------------------------------------------------------------------------
// web backup → AppStore json
// ---------------------------------------------------------------------------

Map<String, dynamic> webBackupToAppStoreJson(Map<String, dynamic> w) {
  final kv = (w['kv'] is Map) ? Map<String, dynamic>.from(w['kv'] as Map) : const <String, dynamic>{};
  final shop = (kv['shop'] is Map) ? Map<String, dynamic>.from(kv['shop'] as Map) : const <String, dynamic>{};
  final prof = (shop['profile'] is Map) ? Map<String, dynamic>.from(shop['profile'] as Map) : const <String, dynamic>{};
  final ents = (kv['entitlements'] is Map) ? Map<String, dynamic>.from(kv['entitlements'] as Map) : null;

  double dollarsOf(dynamic cents, dynamic fallbackDollars) {
    if (cents is num) return cents.toDouble() / 100;
    if (fallbackDollars is num) return fallbackDollars.toDouble();
    return 0;
  }

  String isoOf(dynamic ms) {
    if (ms is num) {
      return DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toIso8601String();
    }
    if (ms is String) return ms;
    return '';
  }

  // --- profile -------------------------------------------------------------
  final profile = <String, dynamic>{
    'businessName': '${prof['name'] ?? shop['brand'] ?? 'My Shop'}',
    'address': '${prof['address'] ?? ''}',
    'phone': '${prof['phone'] ?? ''}',
    'footer': '${prof['receiptFoot'] ?? 'THANK YOU!'}',
    'currencySymbol': '${prof['currency'] ?? 'RM'}',
    'taxRate': prof['tax'] is num ? (prof['tax'] as num).toDouble() : 0,
    'serviceRate': prof['svc'] is num ? (prof['svc'] as num).toDouble() : 0,
    'managerPin': '${prof['managerPin'] ?? ''}',
    'payQrBase64': prof['payQr'] is String && (prof['payQr'] as String).isNotEmpty ? prof['payQr'] : null,
  };

  // --- tables --------------------------------------------------------------
  final tables = <Map<String, dynamic>>[];
  for (final t in _rows(w['tables'])) {
    final state = '${t['state'] ?? 'free'}';
    tables.add(<String, dynamic>{
      'id': _idOrNew(t['id']),
      'name': '${t['label'] ?? t['name'] ?? 'T'}',
      'seats': t['seats'] is num ? (t['seats'] as num).toInt() : 4,
      'status': state == 'free' ? 'free' : 'ordered', // web busy/held → ordered
      'currentOrderId': t['orderId'] is String ? t['orderId'] : (t['currentOrderId'] is String ? t['currentOrderId'] : null),
      'occupiedAt': t['since'] != null ? isoOf(t['since']) : null,
    });
  }

  // --- categories + products ------------------------------------------------
  // Web products carry a plain-string `cat`; Flutter wants a categories list.
  final products = <Map<String, dynamic>>[];
  final catIds = <String>{'uncat'};
  final seenCatNames = <String>{};
  for (final p in _rows(w['products'])) {
    final catId = '${p['categoryId'] ?? p['cat'] ?? 'uncat'}';
    catIds.add(catId);
    products.add(<String, dynamic>{
      'id': _idOrNew(p['id']),
      'categoryId': catId.isEmpty ? 'uncat' : catId,
      'name': '${p['name'] ?? ''}',
      'nameUr': '${p['nameUr'] ?? ''}',
      'description': '${p['description'] ?? ''}',
      'price': dollarsOf(p['priceCents'], p['price']),
      'imageBase64': p['imageBase64'] is String && (p['imageBase64'] as String).isNotEmpty ? p['imageBase64'] : null,
      'available': p['available'] ?? p['avail'] ?? true,
      'sku': '${p['sku'] ?? ''}',
      'inventoryId': p['inventoryId'] is String ? p['inventoryId'] : null,
      'deductQty': p['deductQty'] is num ? (p['deductQty'] as num).toDouble() : 1,
      'course': '${p['course'] ?? 'main'}',
      'mods': p['mods'] is List ? p['mods'] : const <dynamic>[],
      'recipe': p['recipe'] is List ? p['recipe'] : const <dynamic>[],
    });
    _catNameOf(p, catIds, seenCatNames);
  }
  final categories = <Map<String, dynamic>>[];
  var sort = 0;
  for (final c in catIds) {
    categories.add(<String, dynamic>{
      'id': c,
      // Web has no separate category store — the id often IS the label.
      'name': _catLabel(c, seenCatNames),
      'nameUr': '',
      'sort': sort++,
    });
  }

  // --- stock -----------------------------------------------------------------
  final stock = <Map<String, dynamic>>[];
  for (final sRow in _rows(w['stock'])) {
    stock.add(<String, dynamic>{
      'id': _idOrNew(sRow['id']),
      'name': '${sRow['name'] ?? ''}',
      'sku': '${sRow['sku'] ?? ''}',
      'quantity': sRow['qty'] is num ? (sRow['qty'] as num).toDouble() : (sRow['quantity'] is num ? (sRow['quantity'] as num).toDouble() : 0),
      'lowStockAt': sRow['lowStockAt'] ?? 5,
      'unit': '${sRow['unit'] ?? 'pcs'}',
      'cost': dollarsOf(sRow['costCents'], sRow['cost']),
      'sellPrice': dollarsOf(sRow['sellCents'], null),
    });
  }

  // --- staff (web salt/pinHash survive verbatim — see staffPinMatches) -------
  final staff = <Map<String, dynamic>>[];
  for (final e in _rows(w['staff'])) {
    final roles = e['roles'];
    staff.add(<String, dynamic>{
      'id': _idOrNew(e['id']),
      'name': '${e['name'] ?? ''}',
      'roleLabel': roles is List ? roles.join(' · ') : (e['roleLabel'] ?? ''),
      'pin': '${e['pin'] ?? ''}',
      'pinHash': e['pinHash'] is String ? e['pinHash'] : null,
      'salt': e['salt'] is String ? e['salt'] : null,
      'active': e['active'] ?? true,
    });
  }

  // --- customers -------------------------------------------------------------
  final customers = <Map<String, dynamic>>[];
  for (final c in _rows(w['customers'])) {
    customers.add(<String, dynamic>{
      'id': _idOrNew(c['id']),
      'name': '${c['name'] ?? ''}',
      'phone': '${c['phone'] ?? ''}',
      'address': '${c['address'] ?? ''}',
      'notes': '${c['notes'] ?? c['note'] ?? ''}',
      'points': c['points'] ?? 0,
      'credit': dollarsOf(c['creditCents'], c['credit']),
    });
  }

  // --- drivers ---------------------------------------------------------------
  final drivers = <Map<String, dynamic>>[];
  for (final d in _rows(w['drivers'])) {
    final st = '${d['status'] ?? 'free'}';
    drivers.add(<String, dynamic>{
      'id': _idOrNew(d['id']),
      'name': '${d['name'] ?? ''}',
      'phone': '${d['phone'] ?? ''}',
      'status': (st == 'busy' || st == 'offline') ? st : 'free',
    });
  }

  // --- orders -----------------------------------------------------------------
  final orders = <Map<String, dynamic>>[];
  for (final o in _rows(w['orders'])) {
    orders.add(webOrderToPosOrderJson(o));
  }

  // --- waste (web 'wastage' rows carry name, Flutter carries stockId) --------
  final waste = <Map<String, dynamic>>[];
  for (final e in _rows(w['wastage'] ?? w['waste'])) {
    waste.add(<String, dynamic>{
      'id': _idOrNew(e['id']),
      'stockId': '${e['stockId'] ?? ''}',
      'quantity': e['qty'] is num ? (e['qty'] as num).toDouble() : (e['quantity'] ?? 0),
      'cost': dollarsOf(e['costCents'], e['cost']),
      'reason': '${e['reason'] ?? ''}',
      'actor': '${e['actor'] ?? ''}',
    });
  }

  // --- suppliers / purchases (pass-through where fields already align) -------
  final suppliers = <Map<String, dynamic>>[];
  for (final s2 in _rows(w['suppliers'])) {
    suppliers.add(<String, dynamic>{
      'id': _idOrNew(s2['id']),
      'name': '${s2['name'] ?? ''}',
      'phone': '${s2['phone'] ?? ''}',
      'notes': '${s2['notes'] ?? ''}',
    });
  }

  return <String, dynamic>{
    'schemaVersion': 1,
    // Web dates used as rev are millis — keep them so the freshness guard
    // (`store.revision < state.store.revision`) behaves monotonically.
    'revision': kv['rev'] is num ? kv['rev'] : DateTime.now().millisecondsSinceEpoch,
    'model': _normModel('${prof['model'] ?? 'restaurant'}'),
    'profile': profile,
    'tables': tables,
    'categories': categories,
    'products': products,
    'stock': stock,
    'orders': orders,
    'drivers': drivers,
    'staff': staff,
    'customers': customers,
    'waste': waste,
    'suppliers': suppliers,
    'purchases': const <dynamic>[], // web shape diverges; left out on purpose
    'entitlements': ents ??
        const <String, dynamic>{'allOn': true, 'plan': 'full', 'models': <String>[], 'features': <String>[]},
    'seeded': true,
  };
}

/// A single web order row → PosOrder.toJson shape. Exported because the
/// cloud-command bridge (web `{type:'order'}` → NetCommand) reuses it.
Map<String, dynamic> webOrderToPosOrderJson(Map<String, dynamic> o) {
  String isoOf(dynamic ms) {
    if (ms is num) {
      return DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toIso8601String();
    }
    return '';
  }

  double cut(dynamic cents, dynamic fallback) {
    if (cents is num) return cents.toDouble() / 100;
    if (fallback is num) return fallback.toDouble();
    return 0;
  }

  final lines = <Map<String, dynamic>>[];
  for (final l in _rows(o['lines'])) {
    lines.add(<String, dynamic>{
      'id': _idOrNew(l['id']),
      'productId': '${l['productId'] ?? ''}',
      'name': '${l['name'] ?? ''}',
      'unitPrice': cut(l['priceCents'], l['price'] ?? l['unitPrice']),
      'qty': l['qty'] is num ? (l['qty'] as num).toDouble() : 1,
      'notes': '${l['notes'] ?? ''}',
      'inventoryId': l['inventoryId'] is String ? l['inventoryId'] : null,
      'deductQty': l['deductQty'] is num ? (l['deductQty'] as num).toDouble() : 1,
      'course': '${l['course'] ?? 'main'}',
      'fired': l['fired'] ?? false,
    });
  }

  // Web type vocab: dineIn/takeaway/delivery (+ retail/service hinted).
  // Web status vocab adds 'sent'/'out' — map onto the Flutter enum set.
  final rawType = '${o['type'] ?? 'dineIn'}';
  final rawStatus = '${o['status'] ?? 'open'}';
  final type = const ['dineIn', 'takeaway', 'delivery', 'retail', 'service'].contains(rawType)
      ? rawType
      : (o['tableId'] != null ? 'dineIn' : 'takeaway');
  var status = rawStatus;
  if (rawStatus == 'sent') {
    status = 'preparing';
  } else if (rawStatus == 'out') {
    status = 'ready'; // out-for-delivery shows green/ready to the counter
  } else if (rawStatus == 'void' || rawStatus == 'cancelled' || rawStatus == 'canceled') {
    status = 'cancelled';
  } else if (!const ['open', 'preparing', 'ready', 'served', 'paid', 'cancelled'].contains(rawStatus)) {
    status = 'open';
  }

  final payRaw = o['payment'];
  String? payment;
  if (payRaw is Map) {
    final m = '${payRaw['method'] ?? ''}';
    if (const ['cash', 'card', 'wallet', 'other', 'complimentary'].contains(m)) payment = m;
  } else if (payRaw is String && const ['cash', 'card', 'wallet', 'other', 'complimentary'].contains(payRaw)) {
    payment = payRaw;
  }

  return <String, dynamic>{
    'id': _idOrNew(o['id']),
    'ticketNo': '${o['ticketNo'] ?? ''}',
    'type': type,
    'status': status,
    'tableId': o['tableId'] is String ? o['tableId'] : null,
    'tableName': '${o['tableName'] ?? ''}',
    'customerName': '${o['customerName'] ?? ''}',
    'customerPhone': '${o['customerPhone'] ?? ''}',
    'address': '${o['address'] ?? ''}',
    'driverId': o['driverId'] is String ? o['driverId'] : null,
    'lines': lines,
    'discount': cut(o['discountCents'], o['discount']),
    'taxRate': o['taxRate'] ?? 0,
    'serviceRate': o['serviceRate'] ?? 0,
    'tip': cut(o['tipCents'], o['tip']),
    'payment': payment,
    'loyaltyAwarded': o['loyaltyAwarded'] ?? false,
    'notes': '${o['notes'] ?? ''}',
    'createdAt': isoOf(o['createdAt']),
    'updatedAt': isoOf(o['updatedAt']),
    'createdBy': '${o['createdBy'] ?? ''}',
    'stockDeducted': o['stockDeducted'] ?? false,
    'held': o['held'] ?? false,
    'voidReason': '${o['voidReason'] ?? ''}',
    'sentAt': o['sentAt'] != null ? isoOf(o['sentAt']) : null,
    'channel': '${o['channel'] ?? ''}',
    'staffId': o['staffId'] is String ? o['staffId'] : null,
    'shiftNo': o['shiftNo'] ?? 0,
  };
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _rows(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String _idOrNew(dynamic raw) {
  final s = raw == null ? '' : raw.toString();
  return s.isEmpty ? newId() : s;
}

void _catNameOf(Map<String, dynamic> p, Set<String> catIds, Set<String> seenNames) {
  final name = '${p['categoryName'] ?? ''}';
  if (name.isNotEmpty) seenNames.add(name);
}

String _catLabel(String id, Set<String> seenNames) {
  if (id == 'uncat') return 'Uncategorized';
  // Web ids like 'Drinks'/'Mains' are human labels already (seeded that way).
  if (id.length <= 24 && id.isNotEmpty) return id;
  return id;
}

String _normModel(String m) {
  const known = ['restaurant', 'retail', 'fastfood', 'services'];
  return known.contains(m) ? m : 'restaurant';
}
