// jathol.org hero — Flutter port of the site hero's living layer.
// Pure CustomPaint/Animation — zero assets, zero deps. Everything is sized
// proportionally (width/height fractions) so it fills & fits ANY screen:
// phone, tablet, folded, landscape, desktop window resize.
// Honors accessibility: if the OS requests reduced motion, renders one static
// composed frame (no ticking controller).
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Full-bleed ambient background — rising bubbles, two glow orbs drifting,
/// periodic diagonal "wipe" sheen. Place with Positioned.fill(
/// child: IgnorePointer(child: OfHeroAmbient())).
class OfHeroAmbient extends StatefulWidget {
  const OfHeroAmbient({super.key});
  @override
  State<OfHeroAmbient> createState() => _OfHeroAmbientState();
}

class _OfHeroAmbientState extends State<OfHeroAmbient> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduce && _c.isAnimating) { _c.stop(); _c.value = 0.35; }
    if (!_reduce && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _HeroAmbientPainter(_c, reduce: _reduce)),
    );
  }
}

class _HeroAmbientPainter extends CustomPainter {
  _HeroAmbientPainter(this.t, {required this.reduce}) : super(repaint: t);
  final Animation<double> t;
  final bool reduce;

  // Deterministic pseudo-random bubbles (same layout every run — the site
  // used Math.random once at boot; deterministic is fine and renders identically).
  static final List<_Bubble> _bubbles = [
    for (var i = 0; i < 22; i++)
      _Bubble(
        x: _fr(i * 7937 + 31),
        size: (0.3 + 0.7 * _fr(i * 104743 + 17)) / 100, // fraction of width
        dur: 9 + 10 * _fr(i * 9973 + 101),               // seconds
        delay: -14 * _fr(i * 7919 + 13),
      ),
  ];

  static double _fr(int seed) {
    final v = math.sin(seed.toDouble()) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Deep canvas gradient (site's radial #0D2420→#020404 vibe on license bg)
    final bg = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.10),
        radius: 1.35,
        colors: const [Color(0xFF0E2A21), Color(0xFF071711), Color(0xFF04100C)],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bg);

    final ph = reduce ? 0.35 : t.value;

    // Two glow orbs — mint top-left, gold bottom-right — slow drift.
    _orb(canvas, Offset(w * (-0.08) + math.sin(ph * math.pi * 2) * w * 0.015, h * (-0.10) + math.cos(ph * math.pi * 2) * h * 0.02), w * 0.30, const Color(0xFF5BE3AE), 0.16);
    _orb(canvas, Offset(w * 0.60 + math.cos(ph * math.pi * 2 + 1.3) * w * 0.02, h * 0.30 + math.sin(ph * math.pi * 2 + 1.3) * h * 0.025), w * 0.34, const Color(0xFFF4B942), 0.10);

    // Rising bubbles (mint sparks), proportional speed so tall screens match phones.
    for (final b in _bubbles) {
      final cycle = ((ph * 14.0 + b.delay.abs()) % b.dur) / b.dur; // 0..1
      final y = h * (1.10 - cycle * 1.15);
      final opacity = (math.sin(cycle * math.pi) * 0.16).clamp(0.0, 1.0);
      final r = b.size * w;
      final driftX = math.sin(cycle * math.pi * 2 + b.x * 9) * w * 0.012;
      final paint = Paint()..color = const Color(0xFF5BE3AE).withValues(alpha: opacity);
      canvas.drawCircle(Offset(w * b.x + driftX, y), r, paint);
    }

    // Diagonal wipe sheen every ~6s (matches the site's scene-change wipe).
    final wipePhase = ((ph * 14) % 6) / 6;
    if (wipePhase < 0.55) {
      final k = wipePhase / 0.55;
      final band = w * 0.55;
      final center = -band + (w + 2 * band) * k;
      final fade = math.sin(k * math.pi) * 0.10;
      canvas.save();
      canvas.translate(center, 0);
      canvas.transform((Matrix4.identity()..setEntry(0, 1, -0.35)).storage); // slight shear
      final p = Paint()
        ..shader = LinearGradient(colors: [Colors.transparent, Color(0xFFF4B942).withValues(alpha: fade), Colors.transparent])
            .createShader(Rect.fromLTWH(-band / 2, 0, band, h));
      canvas.drawRect(Rect.fromLTWH(-band / 2, -h * 0.2, band, h * 1.4), p);
      canvas.restore();
    }

    // Vignette — keeps the form readable on every device size.
    final vg = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.25,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), vg);
  }

  void _orb(Canvas canvas, Offset c, double r, Color color, double alpha) {
    final p = Paint()
      ..color = color.withValues(alpha: alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.35);
    canvas.drawCircle(c, r, p);
  }

  @override
  bool shouldRepaint(covariant _HeroAmbientPainter old) => old.t != t || old.reduce != reduce;
}

class _Bubble {
  final double x, size, dur, delay;
  const _Bubble({required this.x, required this.size, required this.dur, required this.delay});
}

/// Kinetic brand block — logo springs in with a glow, "Order Flow" letters
/// cascade in one-by-one and idle in a gentle wave, tagline slides up.
/// Drop in place of the static logo+title+tagline rows (visual only).
class OfHeroBrandBlock extends StatefulWidget {
  const OfHeroBrandBlock({super.key, this.tagline = 'The shop that keeps selling.'});
  final String tagline;
  @override
  State<OfHeroBrandBlock> createState() => _OfHeroBrandBlockState();
}

class _OfHeroBrandBlockState extends State<OfHeroBrandBlock> with TickerProviderStateMixin {
  static const _word = 'Order Flow';
  late final AnimationController _intro;
  late final AnimationController _wave;
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
    _wave = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduce) {
      _intro.value = 1;
      _wave.stop();
    } else {
      if (!_intro.isCompleted) _intro.forward();
      if (!_wave.isAnimating) _wave.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _wave.dispose();
    super.dispose();
  }

  double _stagger(int i, double delay, double span) {
    // returns eased 0..1 progression for a letter starting at `delay` over `span`
    final x = ((_intro.value * 1900 - delay) / span).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(x);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final avail = cons.maxWidth.isFinite ? cons.maxWidth : MediaQuery.of(context).size.width;
      final s = (avail / 360).clamp(0.72, 2.4); // adaptive scale: 360dp baseline, tablets/desktops scale up
      final fs = 30 * s;
      final letterH = 0.08 * avail; // letter rise amplitude ≈ cqw feel
      return AnimatedBuilder(
        animation: Listenable.merge([_intro, _wave]),
        builder: (context, _) {
          final lp = Curves.easeOutBack.transform(_interval(_intro.value, 0.0, 0.42)); // logo
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Transform.scale(
              scale: 0.4 + 0.6 * lp,
              child: Transform.rotate(
                angle: (-8.0 + 9.5 * lp) * math.pi / 180,
                child: Opacity(
                  opacity: lp,
                  child: Container(
                    width: 72 * s, height: 72 * s,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18 * s),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF2FFFA0).withValues(alpha: 0.38 * lp), blurRadius: 34 * s, spreadRadius: 2),
                        BoxShadow(color: const Color(0xFFF4B942).withValues(alpha: 0.10 * lp), blurRadius: 64 * s),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18 * s),
                      child: Image.asset('assets/brand/logo.png', fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.storefront, size: 48 * s, color: const Color(0xFF2EA771))),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16 * s),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < _word.length; i++)
                  _letter(i, fs, letterH),
              ]),
            ),
            SizedBox(height: 10 * s),
            Opacity(
              opacity: _stagger(0, 1150, 500).toDouble(),
              child: Transform.translate(
                offset: Offset(0, (1 - _stagger(0, 1150, 500)) * 14 * s),
                child: Text(
                  widget.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: const Color(0xFF9BB5A8), fontSize: 14 * s, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
            ),
          ]);
        },
      );
    });
  }

  double _interval(double p, double a, double b) => ((p - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  Widget _letter(int i, double fs, double rise) {
    final ch = _word[i];
    final inP = _stagger(i, 260 + i * 55, 420).toDouble();
    final idle = _reduce ? 0.0 : math.sin(_wave.value * math.pi * 2 + i * 0.55) * fs * 0.018;
    return Opacity(
      opacity: inP,
      child: Transform.translate(
        offset: Offset(0, (1 - inP) * rise + idle),
        child: Transform.rotate(
          angle: (1 - inP) * -0.10,
          child: SizedBox(
            width: ch == ' ' ? fs * 0.34 : null,
            child: Text(
              ch,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs, letterSpacing: -fs * 0.02, height: 1.1),
            ),
          ),
        ),
      ),
    );
  }
}
