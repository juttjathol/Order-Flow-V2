// Stock & recipes engine (gated add-on key: stock_engine).
//
// Pure functions over AppStore — no Flutter imports — so the same math drives:
//  • the order-taker "N left" badge (makeable),
//  • the Buy list screen (7-day demand forecast vs on-hand stock).
//
// Semantics (user spec, 2026-10-30):
//   makeability = min over every ingredient of floor(on-hand / per-dish usage).
//   e.g. buns=3, patties=2 → burger makeable = 2 (even though buns have 3).
library;

import '../models/models.dart';

class BuySuggestion {
  BuySuggestion({
    required this.stock,
    required this.onHand,
    required this.perDay,
    required this.suggest,
  });

  final StockItem stock;
  final double onHand;

  /// Average daily usage over the trailing window.
  final double perDay;

  /// Units to purchase so on-hand covers [StockEngine.coverDays] of demand.
  final double suggest;
}

class StockEngine {
  StockEngine._();

  /// Order-taker badge threshold (user spec: warn when ≤ 5).
  static const int lowAt = 5;

  /// Forecast: trailing window + target coverage window.
  static const int windowDays = 7;
  static const int coverDays = 7;

  static Map<String, StockItem> _byId(List<StockItem> stock) =>
      {for (final e in stock) e.id: e};

  /// How many full units of [p] the current stock can still produce.
  ///
  /// Returns null when the product is NOT stock-linked (no inventory link and
  /// no recipe lines) — unlimited, show no badge. Direct inventory links and
  /// recipe lines BOTH cap the count, and the tightest bottleneck wins.
  /// A recipe line pointing at a missing/unknown ingredient means the dish
  /// cannot be made at all (0).
  static int? makeable(MenuProduct p, List<StockItem> stock) {
    int? best;
    final byId = _byId(stock);
    void cap(double have, double perUnit) {
      if (perUnit <= 0) return;
      final can = (have / perUnit).floor();
      best = (best == null || can < best!) ? can : best;
    }

    final link = p.inventoryId;
    if (link != null && link.isNotEmpty && byId.containsKey(link)) {
      final per = p.deductQty > 0 ? p.deductQty : 1.0;
      cap(byId[link]!.quantity, per);
    }
    for (final r in p.recipe) {
      final ing = byId[r.stockId];
      if (ing == null) {
        return 0; // recipe references an ingredient that no longer exists
      }
      cap(ing.quantity, r.quantity);
    }
    return best;
  }

  /// Badge count on order-taker tiles when the add-on is ON and the product
  /// is nearly out (≤ [lowAt]). Null = no badge.
  static int? badgeCount(MenuProduct p, AppStore store) {
    if (!store.entitlements.allowsFeature('stock_engine')) return null;
    final m = makeable(p, store.stock);
    if (m == null || m > lowAt) return null;
    return m < 0 ? 0 : m;
  }

  /// Add one sold line's ingredient usage into [usage] (stockId → units).
  static void _accumUsage(
      MenuProduct p, double qtySold, Map<String, double> usage) {
    final link = p.inventoryId;
    if (link != null && link.isNotEmpty) {
      final per = p.deductQty > 0 ? p.deductQty : 1.0;
      usage[link] = (usage[link] ?? 0) + per * qtySold;
    }
    for (final r in p.recipe) {
      usage[r.stockId] = (usage[r.stockId] ?? 0) + r.quantity * qtySold;
    }
  }

  /// Trailing-[windowDays] sales demand per ingredient, extended to cover
  /// [coverDays]; only ingredients whose on-hand stock falls short are listed.
  /// Sorted busiest-first so the top rows are what to buy today.
  static List<BuySuggestion> buyList(AppStore store,
      {int days = windowDays, int coverDays = coverDays}) {
    if (days <= 0) days = windowDays;
    if (coverDays <= 0) coverDays = windowDays;
    final from = DateTime.now().subtract(Duration(days: days));
    final prodById = {for (final p in store.products) p.id: p};
    final usage = <String, double>{};
    for (final o in store.reportableOrders) {
      if (o.createdAt.isBefore(from)) continue;
      for (final l in o.lines) {
        final p = prodById[l.productId];
        if (p == null) continue;
        _accumUsage(p, l.qty, usage);
      }
    }
    final out = <BuySuggestion>[];
    for (final item in store.stock) {
      final used = usage[item.id] ?? 0.0;
      if (used <= 0) continue; // no recent demand → nothing to forecast
      final perDay = used / days;
      final need = perDay * coverDays;
      final short = need - item.quantity;
      if (short <= 0) continue; // current stock already covers the window
      out.add(BuySuggestion(
          stock: item,
          onHand: item.quantity,
          perDay: perDay,
          suggest: (short * 10).ceilToDouble() / 10));
    }
    out.sort((a, b) => b.perDay.compareTo(a.perDay));
    return out;
  }

  /// Shareable plain-text buy list (WhatsApp to the supplier).
  static String buyListText(AppStore store, {bool urdu = false}) {
    final rows = buyList(store);
    if (rows.isEmpty) return '';
    final b = StringBuffer();
    b.writeln(urdu ? 'خریداری لسٹ — Order Flow' : 'BUY LIST — Order Flow');
    b.writeln(DateTime.now().toString().substring(0, 16));
    for (final r in rows) {
      final pd = r.perDay >= 10
          ? r.perDay.toStringAsFixed(0)
          : r.perDay.toStringAsFixed(1);
      b.writeln(
          '• ${r.stock.name}: +${_num(r.suggest)} ${r.stock.unit}  (${urdu ? 'موجودہ' : 'on hand'} ${_num(r.onHand)}, ≈$pd/${urdu ? 'دن' : 'day'})');
    }
    return b.toString().trimRight();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
