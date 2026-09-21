import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import '../widgets/station_printer.dart';

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  Timer? _tick;
  final _seen = <String>{};
  final _lateAlerted = <String>{};
  String q = '';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _alert(Set<String> ids) {
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final orders = ref.snap.store.orders
        .where((o) =>
            (o.status == OrderStatus.open ||
                o.status == OrderStatus.preparing ||
                o.status == OrderStatus.ready) &&
            o.matchesQuery(q))
        .toList();
    final ids = orders.map((o) => o.id).toSet();
    final fresh = ids.difference(_seen);
    if (_seen.isNotEmpty && fresh.isNotEmpty) {
      _alert(fresh);
    }
    _seen
      ..addAll(ids)
      ..removeWhere((id) => !ids.contains(id));
    _lateAlerted.removeWhere((id) => !ids.contains(id));
    final justLate = <String>{};
    for (final o in orders) {
      final mins = DateTime.now().difference(o.sentAt ?? o.createdAt).inMinutes;
      if (mins >= 20 && _lateAlerted.add(o.id)) justLate.add(o.id);
    }
    if (justLate.isNotEmpty) _alert(justLate);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('kitchen_queue'), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              '${orders.length}  ·  ${ref.snap.session.displayName}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: StatusChip(
                ref.snap.connected || ref.snap.isMain ? 'ONLINE' : 'OFFLINE',
                color: (ref.snap.connected || ref.snap.isMain) ? OfColors.mint : OfColors.warn,
              ),
            ),
          ),
          const StationActions(),
          IconButton(
            tooltip: s.t('station_printer'),
            onPressed: () => showStationPrinterSheet(context, ref),
            icon: const Icon(Icons.print),
          ),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          TicketSearchField(onChanged: (v) => setState(() => q = v)),
          Expanded(
            child: orders.isEmpty
          ? EmptyState(icon: Icons.soup_kitchen, message: s.t('no_orders'))
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCount(context, phone: 1, tablet: 3),
                mainAxisExtent: 380,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: orders.length,
              itemBuilder: (_, i) {
                final o = orders[i];
                final mins = DateTime.now().difference(o.sentAt ?? o.createdAt).inMinutes;
                final ageColor = mins >= 20
                    ? OfColors.danger
                    : mins >= 10
                        ? OfColors.warn
                        : OfColors.mint;
                final lines = (List<OrderLine>.from(o.lines))
                  ..sort((a, b) => a.course.compareTo(b.course));
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: ageColor.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${o.ticketNo}${o.tableName == null || o.tableName!.isEmpty ? '' : '  ·  ${o.tableName}'}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                            ),
                            StatusChip(_age(o), color: ageColor),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          children: lines
                              .map(
                                (l) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${l.qty % 1 == 0 ? l.qty.toInt() : l.qty}  ${l.name}${l.notes.isEmpty ? '' : ' — ${l.notes}'}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          children: [
                            if (o.status == OrderStatus.open)
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _set(ref, o, OrderStatus.preparing),
                                  child: Text(s.t('mark_preparing')),
                                ),
                              ),
                            if (o.status == OrderStatus.preparing)
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _set(ref, o, OrderStatus.ready),
                                  child: Text(s.t('mark_ready')),
                                ),
                              ),
                            if (o.status == OrderStatus.ready)
                              Expanded(
                                child: FilledButton.tonal(
                                  onPressed: () => _set(ref, o, OrderStatus.served),
                                  child: Text(s.t('mark_served')),
                                ),
                              ),
                            IconButton(
                              onPressed: () async {
                                try {
                                  await ref.ctrl.printer.kitchenTicket(
                                    ref.snap.store,
                                    o,
                                    role: ref.snap.session.role,
                                    prefer: ref.ctrl.deviceLocalPrinter(),
                                  );
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.print),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _age(PosOrder o) {
    final start = o.sentAt ?? o.createdAt;
    final d = DateTime.now().difference(start);
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    if (m <= 0) return '${sec}s';
    return '${m}m';
  }

  Future<void> _set(WidgetRef ref, PosOrder o, OrderStatus status) {
    return ref.ctrl.dispatch(NetCommand(name: 'setOrderStatus', payload: {
      'id': o.id,
      'status': status.name,
    }));
  }
}
