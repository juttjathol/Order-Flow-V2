// Menu engineering (volume × margin quadrants).
//
// 30-day paid sales per product + recipe costing per dish → each item lands
// in one quadrant: star / plowhorse / puzzle / dog. Dishes without recipe
// lines report margin=null and are listed separately ("needs costing").
library;

import '../models/models.dart';

class MenuEngRow {
  MenuEngRow({
    required this.product,
    required this.qty,
    required this.cashMarginPct,
  });

  final MenuProduct product;
  final double qty;

  /// Sales margin % across the window; null when the product has no recipe
  /// (cost unknown — listed under "needs costing").
  final double? cashMarginPct;

  /// star | plowhorse | puzzle | dog | ''
  String klass = '';
}

class MenuEngineering {
  MenuEngineering._();

  static const int windowDays = 30;

  /// Ingredient cost of one dish from its recipe lines. Null when no recipe.
  static double? dishCost(MenuProduct p, AppStore store) {
    if (p.recipe.isEmpty) return null;
    double sum = 0;
    for (final r in p.recipe) {
      final ing = store.stockById(r.stockId);
      if (ing == null) return null;
      sum += ing.cost * r.quantity;
    }
    return sum;
  }

  static List<MenuEngRow> compute(AppStore store, {int days = windowDays}) {
    final from = DateTime.now().subtract(Duration(days: days));
    final prodById = {for (final p in store.products) p.id: p};
    final sold = <String, double>{};
    for (final o in store.reportableOrders) {
      if (o.createdAt.isBefore(from)) continue;
      for (final l in o.lines) {
        sold[l.productId] = (sold[l.productId] ?? 0) + l.qty;
      }
    }
    final rows = <MenuEngRow>[];
    for (final e in sold.entries) {
      final p = prodById[e.key];
      if (p == null || e.value <= 0) continue;
      final cost = dishCost(p, store);
      double? margin;
      if (cost != null && p.price > 0) {
        margin = (p.price - cost) / p.price * 100;
      }
      rows.add(MenuEngRow(product: p, qty: e.value, cashMarginPct: margin));
    }
    final classed = rows.where((r) => r.cashMarginPct != null).toList();
    if (classed.isNotEmpty) {
      final vols = classed.map((r) => r.qty).toList()..sort();
      final mars = classed.map((r) => r.cashMarginPct!).toList()..sort();
      double median(List<double> v) => v.length.isOdd
          ? v[v.length ~/ 2]
          : (v[(v.length - 1) ~/ 2] + v[v.length ~/ 2]) / 2;
      final medVol = median(vols);
      final medMar = median(mars);
      for (final r in classed) {
        final hiVol = r.qty >= medVol;
        final hiMar = r.cashMarginPct! >= medMar;
        r.klass = hiVol
            ? (hiMar ? 'star' : 'plowhorse')
            : (hiMar ? 'puzzle' : 'dog');
      }
    }
    rows.sort((a, b) => b.qty.compareTo(a.qty));
    return rows;
  }
}
