import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class SpecialistScreen extends ConsumerWidget {
  const SpecialistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final name = ref.snap.session.displayName.toLowerCase();
    final mine = ref.snap.store.appointments.where((a) {
      final staff = ref.snap.store.staff.where((st) => st.id == a.staffId).firstOrNull;
      if (name.isEmpty) return true;
      return (staff?.name.toLowerCase() ?? '').contains(name) || a.staffId == name;
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('specialist_queue')),
        actions: [
          StatusChip(ref.snap.connected ? s.t('connected') : s.t('disconnected'),
              color: ref.snap.connected ? OfColors.mint : OfColors.danger),
          IconButton(onPressed: () => ref.ctrl.leaveRole(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: mine.isEmpty
          ? EmptyState(icon: Icons.badge, message: s.t('no_appts'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: mine.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = mine[i];
                final svc = ref.snap.store.services.where((e) => e.id == a.serviceId).firstOrNull;
                return OfCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a.customerName} · ${svc?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${a.start.hour.toString().padLeft(2, '0')}:${a.start.minute.toString().padLeft(2, '0')}'),
                    trailing: FilledButton(
                      onPressed: () async {
                        a.status = a.status == 'booked' ? 'inProgress' : 'done';
                        await ref.ctrl.dispatch(NetCommand(name: 'upsertAppointment', payload: {'appointment': a.toJson()}));
                      },
                      child: Text(a.status == 'booked' ? s.t('start') : s.t('finish')),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
