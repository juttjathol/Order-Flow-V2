import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final snap = ref.snap;
    final store = snap.store;
    final today = store.salesOn(DateTime.now());
    final open = store.openOrders.length;
    final low = store.lowStock.length;
    final ready = store.orders.where((o) => o.status == OrderStatus.ready).length;
    final wide = isTablet(context);

    final stats = [
      _Stat(s.t('today_sales'), moneyOf(snap, today), Icons.payments, OfColors.mint),
      _Stat(s.t('open_orders'), '$open', Icons.receipt_long, OfColors.gold),
      _Stat(s.t('low_stock'), '$low', Icons.inventory_2, OfColors.warn),
      _Stat(s.t('ready_to_serve'), '$ready', Icons.notifications_active, OfColors.info),
    ];

    return RefreshIndicator(
      onRefresh: () => ref.ctrl.refreshIp(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ServerCard(snap: snap, s: s, onRefresh: () => ref.ctrl.refreshIp()),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: wide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: wide ? 1.6 : 1.45,
            children: stats
                .map((st) => OfCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(st.icon, color: st.color),
                          const Spacer(),
                          Text(st.label, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(st.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          Text(s.t('charts'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _SalesChart(store: store, snap: snap, title: s.t('sales_chart')),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _StockChart(store: store, title: s.t('stock_chart'))),
                const SizedBox(width: 12),
                Expanded(child: _StaffChart(store: store, title: s.t('staff_chart'), s: s)),
              ],
            )
          else ...[
            _StockChart(store: store, title: s.t('stock_chart')),
            const SizedBox(height: 12),
            _StaffChart(store: store, title: s.t('staff_chart'), s: s),
          ],
          const SizedBox(height: 18),
          Text(s.t('open_orders'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (store.openOrders.isEmpty)
            EmptyState(icon: Icons.receipt_long, message: s.t('no_orders'))
          else
            ...store.openOrders.take(8).map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OfCard(
                    onTap: () => context.push('/order/${o.id}'),
                    child: Row(
                      children: [
                        StatusChip(s.t(o.status.name), color: statusColor(o.status)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${o.ticketNo}  ${o.tableName ?? o.type.name}',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('${o.lines.length} ${s.t('items')}'),
                            ],
                          ),
                        ),
                        MoneyText(o.total),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _Stat {
  _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.snap, required this.s, required this.onRefresh});
  final AppSnapshot snap;
  final dynamic s;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ip = snap.lanIp ?? '—';
    final join = snap.lanIp == null ? 'orderflow://join?host=0.0.0.0&port=$kLanPort' : snap.session.role == AppRole.main
        ? 'orderflow://join?host=$ip&port=$kLanPort'
        : 'orderflow://join?host=${snap.session.mainHost}&port=$kLanPort';
    return OfCard(
      color: OfColors.forest,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(snap.store.profile.businessName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 6),
                  Text('${s.t('wifi_ip')}: $ip'),
                  Text('${s.t('port')}: $kLanPort'),
                  const SizedBox(height: 6),
                  StatusChip(
                    snap.serverOn
                        ? s.t('server_on')
                        : (snap.connected ? s.t('connected') : s.t('server_off')),
                    color: (snap.serverOn || snap.connected) ? OfColors.mint : OfColors.warn,
                  ),
                  if (snap.session.license.valid && snap.session.license.message == 'offline_grace')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(s.t('offline_grace'), style: const TextStyle(color: OfColors.gold)),
                    ),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, color: OfColors.mint),
                    label: Text(s.t('refresh'), style: const TextStyle(color: OfColors.mint)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: join, size: 112, backgroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.store, required this.snap, required this.title});
  final AppStore store;
  final AppSnapshot snap;
  final String title;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      return (d, store.salesOn(d));
    });
    final maxY = days.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    return OfCard(
      child: SizedBox(
        height: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Expanded(
              child: maxY == 0
                  ? Center(child: Text(title))
                  : BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i > 6) return const SizedBox.shrink();
                                return Text('${days[i].$1.day}', style: const TextStyle(fontSize: 10));
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < days.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: days[i].$2,
                                color: OfColors.emerald,
                                width: 14,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ]),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockChart extends StatelessWidget {
  const _StockChart({required this.store, required this.title});
  final AppStore store;
  final String title;

  @override
  Widget build(BuildContext context) {
    final items = store.stock.take(6).toList();
    return OfCard(
      child: SizedBox(
        height: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('—'))
                  : BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= items.length) return const SizedBox.shrink();
                                final n = items[i].name;
                                return Text(n.length > 6 ? n.substring(0, 6) : n, style: const TextStyle(fontSize: 9));
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < items.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: items[i].quantity,
                                color: stockColor(items[i].level),
                                width: 14,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ]),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffChart extends StatelessWidget {
  const _StaffChart({required this.store, required this.title, required this.s});
  final AppStore store;
  final String title;
  final dynamic s;

  @override
  Widget build(BuildContext context) {
    final open = store.orders.where((o) => o.status == OrderStatus.open).length.toDouble();
    final prep = store.orders.where((o) => o.status == OrderStatus.preparing).length.toDouble();
    final ready = store.orders.where((o) => o.status == OrderStatus.ready).length.toDouble();
    final paid = store.orders.where((o) => o.status == OrderStatus.paid).length.toDouble();
    final sections = <PieChartSectionData>[
      if (open > 0) PieChartSectionData(value: open, color: OfColors.info, title: '${open.toInt()}'),
      if (prep > 0) PieChartSectionData(value: prep, color: OfColors.warn, title: '${prep.toInt()}'),
      if (ready > 0) PieChartSectionData(value: ready, color: OfColors.mint, title: '${ready.toInt()}'),
      if (paid > 0) PieChartSectionData(value: paid, color: OfColors.emerald, title: '${paid.toInt()}'),
    ];
    return OfCard(
      child: SizedBox(
        height: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Expanded(
              child: sections.isEmpty
                  ? Center(child: Text(s.t('charts_empty')))
                  : PieChart(PieChartData(sections: sections, centerSpaceRadius: 28)),
            ),
          ],
        ),
      ),
    );
  }
}
