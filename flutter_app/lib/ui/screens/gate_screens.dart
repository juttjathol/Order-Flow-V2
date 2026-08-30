import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import '../widgets/pin_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mark;
  late final AnimationController _type;
  late final AnimationController _blink;
  late final Animation<double> _scale;
  String _typed = '';

  static const _word = kBrandName;

  @override
  void initState() {
    super.initState();
    _mark = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..forward();
    _type = AnimationController(vsync: this, duration: const Duration(milliseconds: 780));
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 480))
      ..repeat(reverse: true);
    _scale = CurvedAnimation(parent: _mark, curve: Curves.easeOutCubic);
    _type.addListener(() {
      final n = (_type.value * _word.length).ceil().clamp(0, _word.length);
      final next = _word.substring(0, n);
      if (next != _typed) setState(() => _typed = next);
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _type.forward();
    });
  }

  @override
  void dispose() {
    _mark.dispose();
    _type.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(_scale),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/brand/bolt.png',
                width: 56,
                height: 72,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                color: null,
                isAntiAlias: true,
                errorBuilder: (_, __, ___) => const SizedBox(width: 56, height: 72),
              ),
              const SizedBox(width: 12),
              Text(
                _typed,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 42,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
              FadeTransition(
                opacity: _blink,
                child: Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 3,
                  height: 36,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});
  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final keyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final snap = ref.read(appControllerProvider);
    keyCtrl.text = snap.session.license.key;
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final snap = ref.snap;
    return Scaffold(
      backgroundColor: const Color(0xFF051912),
      body: BusyBarrier(
        busy: snap.busy,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: OverflowBox(
                maxWidth: 980,
                maxHeight: 980,
                child: Opacity(
                  opacity: 0.16,
                  child: Image.asset(
                    'assets/brand/bolt.png',
                    width: 980,
                    height: 980,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
                    children: [
                      const SizedBox(height: 24),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/brand/logo.png',
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.storefront, size: 56, color: OfColors.mint),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.t('app'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.t('license_enter_key'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF9BB5A8), fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 28),
                      Text(s.t('license_key'), style: const TextStyle(color: Color(0xFF9BB5A8), fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyCtrl,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          color: Colors.white,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28), letterSpacing: 2.2),
                          filled: true,
                          fillColor: const Color(0x22000000),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0x553DDC97), width: 1.4),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: OfColors.mint, width: 1.6),
                          ),
                        ),
                      ),
                      if (snap.error != null) ...[
                        const SizedBox(height: 12),
                        Text(s.t(snap.error!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: OfColors.danger, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: OfColors.mint,
                          foregroundColor: const Color(0xFF042016),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: () async {
                          final err = await ref.ctrl.activateLicense(keyCtrl.text);
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(err))));
                          }
                        },
                        child: Text(s.t('activate')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: () => context.push('/connect'),
                        child: Text(s.t('connect_main')),
                      ),
                      const SizedBox(height: 10),
                      Text(s.t('no_key_needed'),
                          textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(kLicenseWhatsAppUrl()),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.chat),
                        label: Text(s.t('whatsapp_support')),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kWhatsAppHandle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: OfColors.mint, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: Text(s.t('english')),
                            selected: snap.session.locale == 'en',
                            onSelected: (_) => ref.ctrl.setLocale('en'),
                          ),
                          const SizedBox(width: 10),
                          ChoiceChip(
                            label: Text(s.t('urdu')),
                            selected: snap.session.locale == 'ur',
                            onSelected: (_) => ref.ctrl.setLocale('ur'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      const Text(
                        kBrandName,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: OfColors.mint, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
