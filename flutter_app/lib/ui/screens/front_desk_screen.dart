import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import 'floor_screen.dart';

class FrontDeskScreen extends ConsumerWidget {
  const FrontDeskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('role_desk')),
        actions: [
          StatusChip(ref.snap.connected ? s.t('connected') : s.t('disconnected'),
              color: ref.snap.connected ? OfColors.mint : OfColors.danger),
          IconButton(onPressed: () => ref.ctrl.leaveRole(), icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final store = ref.snap.store;
          final order = PosOrder(
            id: newId(),
            ticketNo: '',
            type: OrderType.service,
            taxRate: store.profile.taxRate,
          );
          await ref.ctrl.dispatch(NetCommand(name: 'createOrder', payload: {'order': order.toJson()}));
          if (context.mounted) context.push('/order/${order.id}');
        },
        icon: const Icon(Icons.receipt_long),
        label: Text(s.t('walk_in')),
      ),
      body: const FloorScreen(manage: false),
    );
  }
}
