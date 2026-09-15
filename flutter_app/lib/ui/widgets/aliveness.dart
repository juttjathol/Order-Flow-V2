import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// v1.1.64 · Aliveness — one-shot brand-Lottie celebrations for the
/// money moments (kitchen fire, paid). Files are tiny (~6 KB), bundled in
/// the APK (works with the internet dead), tinted to the shop palette,
/// and every path here is a silent no-op when the OS requests reduced
/// motion — the haptic tick still lands.
class Aliveness {
  Aliveness._();

  static const String payCheck = 'assets/animations/pay_check.json';
  static const String kitchenBurst = 'assets/animations/kitchen_burst.json';

  /// Plays a short, non-interactive animation above everything.
  static void celebrate(BuildContext context, String asset, {int holdMs = 1250}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      HapticFeedback.mediumImpact();
      return;
    }
    late final OverlayEntry entry;
    var alive = true;
    entry = OverlayEntry(
      builder: (_) => _Celebration(
        asset: asset,
        holdMs: holdMs,
        onDone: () {
          if (!alive) return;
          alive = false;
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
    HapticFeedback.mediumImpact();
  }

  /// A Lottie sized like an icon — for embedding inside dialogs/cards.
  static Widget animation(String asset, {double size = 64}) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(asset, repeat: false, fit: BoxFit.contain),
    );
  }
}

class _Celebration extends StatefulWidget {
  const _Celebration({required this.asset, required this.holdMs, required this.onDone});

  final String asset;
  final int holdMs;
  final VoidCallback onDone;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> {
  Timer? _timer;
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
    _timer = Timer(Duration(milliseconds: widget.holdMs), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _in ? 0.30 : 0,
            duration: const Duration(milliseconds: 160),
            child: const ColoredBox(color: Color(0xFF02100A)),
          ),
          Center(
            child: AnimatedScale(
              scale: _in ? 1 : 0.8,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              child: Aliveness.animation(widget.asset, size: 230),
            ),
          ),
        ],
      ),
    );
  }
}
