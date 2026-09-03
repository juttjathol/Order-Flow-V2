import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';
import '../widgets/station_printer.dart';
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
          const StationActions(),
          IconButton(
            tooltip: s.t('station_printer'),
            onPressed: () => showStationPrinterSheet(context, ref),
            icon: const Icon(Icons.print),
          ),
          IconButton(onPressed: () => leaveRoleWithPin(context, ref), icon: const Icon(Icons.logout)),
        ],
      ),
      body: const StockScreen(),
    );
  }
}
