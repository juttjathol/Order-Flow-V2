import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Lightweight celebration burst painted over a child.
/// No plugins — pure CustomPainter + AnimationController.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    required this.child,
    this.particleCount = 90,
    this.duration = const Duration(milliseconds: 2200),
  });

  final Widget child;
  final int particleCount;
  final Duration duration;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final List<_Particle> _parts;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(42);
    const colors = [
      OfColors.mint,
      OfColors.emerald,
      OfColors.gold,
      OfColors.info,
      OfColors.danger,
      Color(0xFFB48CEA),
    ];
    _parts = List.generate(widget.particleCount, (i) {
      return _Particle(
        dx: rnd.nextDouble(),
        dy: -0.05 - rnd.nextDouble() * 0.15,
        spin: (rnd.nextDouble() - 0.5) * 10,
        sway: (rnd.nextDouble() - 0.5) * 120,
        swaySpeed: 2 + rnd.nextDouble() * 4,
        size: 5 + rnd.nextDouble() * 7,
        color: colors[i % colors.length],
        delay: rnd.nextDouble() * 0.25,
        round: rnd.nextBool(),
      );
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _ConfettiPainter(_parts, _c.value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Particle {
  _Particle({
    required this.dx,
    required this.dy,
    required this.spin,
    required this.sway,
    required this.swaySpeed,
    required this.size,
    required this.color,
    required this.delay,
    required this.round,
  });
  final double dx;
  final double dy;
  final double spin;
  final double sway;
  final double swaySpeed;
  final double size;
  final Color color;
  final double delay;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.parts, this.t);
  final List<_Particle> parts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in parts) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final fall = Curves.easeIn.transform(local);
      final x = p.dx * size.width + p.sway * math.sin(local * p.swaySpeed * math.pi);
      final y = fall * size.height * 1.25 + p.dy * size.height;
      final fade = (1 - local).clamp(0.0, 1.0).toDouble();
      paint.color = p.color.withValues(alpha: 0.9 * fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local * 2);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
