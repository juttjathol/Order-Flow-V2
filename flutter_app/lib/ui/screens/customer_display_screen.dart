import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Customer-facing display: giant total, animated on every change,
/// so the buyer sees the running order like a till's second screen.
class CustomerDisplayScreen extends ConsumerWidget {
  const CustomerDisplayScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final order = ref.snap.store.orderById(orderId);
    final total = order?.total ?? 0;
    final lines = order?.lines ?? const <OrderLine>[];
    final last = lines.isEmpty ? null : lines.last;
    final shop = ref.snap.store.profile.businessName;

    return Scaffold(
      backgroundColor: const Color(0xFF051912),
      appBar: AppBar(
        backgroundColor: const Color(0xFF051912),
        elevation: 0,
        title: Text(s.t('customer_display'), style: const TextStyle(fontSize: 16, color: Colors.white70)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      shop,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9ADCC0),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Icon(Icons.bolt, color: OfColors.mint, size: 34),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.elasticOut,
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        moneyOf(ref.snap, total),
                        key: ValueKey(total.toStringAsFixed(2)),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: OfColors.mint,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (last != null) ...[
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => SlideTransition(
                          position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Text(
                          '${last.qty % 1 == 0 ? last.qty.toInt() : last.qty} × ${last.name}',
                          key: ValueKey(last.id),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Text(
                      lines.isEmpty ? s.t('customer_display_empty') : '${s.t('items')}: ${lines.fold<int>(0, (n, l) => n + l.qty.round())}',
                      style: const TextStyle(color: Color(0xFF7FB59C), fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.t('customer_display_footer'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF7FB59C), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
