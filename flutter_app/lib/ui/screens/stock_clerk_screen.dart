import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import 'stock_screen.dart';

class StockClerkScreen extends ConsumerWidget {
  const StockClerkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('role_stock')),
        actions: [
          StatusChip(ref.snap.connected ? s.t('connected') : s.t('disconnected'),
              color: ref.snap.connected ? OfColors.mint : OfColors.danger),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
        ],
      ),
      body: const StockScreen(),
    );
  }
}
