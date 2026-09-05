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

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _mark;
  late final AnimationController _type;
  late final AnimationController _blink;
  late final Animation<double> _scale;
  String _typed = '';
  static const _word = kBrandName;

  @override
  void initState() {
    super.initState();
    _mark = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();
    _type = AnimationController(vsync: this, duration: const Duration(milliseconds: 780));
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 480))..repeat(reverse: true);
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
    keyCtrl.text = ref.read(appControllerProvider).session.license.key;
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
              child: Opacity(
                opacity: 0.12,
                child: Center(child: Image.asset('assets/brand/bolt.png', width: 420, height: 420, fit: BoxFit.contain)),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset('assets/brand/logo.png', width: 72, height: 72, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.storefront, size: 56, color: OfColors.mint)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(s.t('app'), textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 30, letterSpacing: -0.6)),
                      const SizedBox(height: 8),
                      Text(s.t('license_enter_key'), textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF9BB5A8), fontSize: 15, height: 1.35)),
                      const SizedBox(height: 28),
                      Text(s.t('license_key'), style: const TextStyle(color: Color(0xFF9BB5A8), fontSize: 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyCtrl,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white, letterSpacing: 2.2, fontWeight: FontWeight.w700, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.28), letterSpacing: 2.2),
                          filled: true,
                          fillColor: const Color(0x22000000),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x553DDC97), width: 1.4)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: OfColors.mint, width: 1.6)),
                        ),
                      ),
                      if (snap.error != null) ...[
                        const SizedBox(height: 12),
                        Text(s.t(snap.error!), textAlign: TextAlign.center, style: const TextStyle(color: OfColors.danger, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: OfColors.mint, foregroundColor: const Color(0xFF042016), minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
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
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70), minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                        onPressed: () => context.push('/connect'),
                        child: Text(s.t('connect_main')),
                      ),
                      const SizedBox(height: 10),
                      Text(s.t('no_key_needed'), textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted, fontSize: 12)),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                        onPressed: () => launchUrl(Uri.parse(kLicenseWhatsAppUrl()), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.chat),
                        label: Text(s.t('whatsapp_support')),
                      ),
                      const SizedBox(height: 6),
                      Text(kWhatsAppHandle, textAlign: TextAlign.center, style: const TextStyle(color: OfColors.mint, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 28),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        ChoiceChip(label: Text(s.t('english')), selected: snap.session.locale == 'en', onSelected: (_) => ref.ctrl.setLocale('en')),
                        const SizedBox(width: 10),
                        ChoiceChip(label: Text(s.t('urdu')), selected: snap.session.locale == 'ur', onSelected: (_) => ref.ctrl.setLocale('ur')),
                      ]),
                      const SizedBox(height: 36),
                      const Text(kBrandName, textAlign: TextAlign.center, style: TextStyle(color: OfColors.mint, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
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

class LockedScreen extends ConsumerWidget {
  const LockedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      backgroundColor: OfColors.deep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 72, color: OfColors.danger),
              const SizedBox(height: 18),
              Text(s.t('locked_title'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(s.t('locked_body'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.4)),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: () => launchUrl(Uri.parse(kWhatsAppUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat),
                label: Text(s.t('open_whatsapp')),
              ),
              const SizedBox(height: 12),
              Text(kWhatsAppHandle, style: const TextStyle(color: OfColors.mint, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleScreen extends ConsumerStatefulWidget {
  const RoleScreen({super.key});
  @override
  ConsumerState<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends ConsumerState<RoleScreen> {
  final name = TextEditingController();
  final pin = TextEditingController();
  AppRole? selected;

  @override
  void dispose() {
    name.dispose();
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final model = ref.snap.store.model;
    final roles = _rolesFor(model);
    return OfScaffold(
      title: s.t('choose_role'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: name, decoration: InputDecoration(labelText: s.t('your_name'))),
          if (selected != null && selected != AppRole.manager) ...[
            const SizedBox(height: 8),
            TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s.t('staff_pin'))),
          ],
          const SizedBox(height: 12),
          ...roles.map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OfCard(
                color: selected == r.$1 ? OfColors.emerald.withValues(alpha: 0.15) : null,
                onTap: () => setState(() => selected = r.$1),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.$2, color: OfColors.emerald),
                  title: Text(s.t(r.$3), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.t(r.$4)),
                ),
              ),
            );
          }),
          FilledButton(
            onPressed: selected == null
                ? null
                : () async {
                    if (selected == AppRole.manager) {
                      final ok = await confirmManagerPin(context, ref, requiredForCashier: true);
                      if (!ok) return;
                      await ref.ctrl.chooseClientRole(selected!, name.text);
                      return;
                    }
                    final n = name.text.trim();
                    final p = pin.text.trim();
                    if (n.isEmpty || p.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('staff_login_need'))));
                      return;
                    }
                    StaffMember? match;
                    for (final st in ref.snap.store.staff) {
                      if (st.active && st.name.toLowerCase() == n.toLowerCase() && st.pin == p) {
                        match = st;
                        break;
                      }
                    }
                    if (match == null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('staff_pin_wrong'))));
                      return;
                    }
                    await ref.ctrl.chooseClientRole(selected!, match.name, staffId: match.id);
                  },
            child: Text(s.t('continue')),
          ),
        ],
      ),
    );
  }

  List<(AppRole, IconData, String, String)> _rolesFor(BusinessModel model) {
    switch (model) {
      case BusinessModel.restaurant:
        return const [
          (AppRole.manager, Icons.manage_accounts, 'role_manager', 'role_manager_hint'),
          (AppRole.orderTaker, Icons.room_service, 'role_taker', 'role_taker_hint'),
          (AppRole.kitchen, Icons.soup_kitchen, 'role_kitchen', 'role_kitchen_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
          (AppRole.driver, Icons.delivery_dining, 'role_driver', 'role_driver_hint'),
        ];
      case BusinessModel.retail:
        return const [
          (AppRole.manager, Icons.manage_accounts, 'role_manager', 'role_manager_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
          (AppRole.stockClerk, Icons.inventory_2, 'role_stock', 'role_stock_hint'),
        ];
      case BusinessModel.fastfood:
        return const [
          (AppRole.manager, Icons.manage_accounts, 'role_manager', 'role_manager_hint'),
          (AppRole.orderTaker, Icons.fastfood, 'role_taker', 'role_taker_hint'),
          (AppRole.kitchen, Icons.soup_kitchen, 'role_kitchen', 'role_kitchen_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
        ];
      case BusinessModel.services:
        return const [
          (AppRole.manager, Icons.manage_accounts, 'role_manager', 'role_manager_hint'),
          (AppRole.frontDesk, Icons.desk, 'role_desk', 'role_desk_hint'),
          (AppRole.specialist, Icons.badge, 'role_specialist', 'role_specialist_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
        ];
    }
  }
}

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final models = <(BusinessModel, String, String, IconData)>[
      (BusinessModel.restaurant, 'restaurant', 'model_restaurant_hint', Icons.restaurant),
      (BusinessModel.retail, 'retail', 'model_retail_hint', Icons.storefront),
      (BusinessModel.fastfood, 'fastfood', 'model_fastfood_hint', Icons.fastfood),
      (BusinessModel.services, 'services_model', 'model_services_hint', Icons.spa),
    ];
    return OfScaffold(
      title: s.t('pick_model'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('get_started'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...models.map((m) {
            final allowed = ref.snap.canModel(m.$1);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OfCard(
                onTap: allowed ? () => ref.ctrl.pickModel(m.$1) : null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.$4,
                      color: allowed ? OfColors.emerald : OfColors.muted, size: 32),
                  title: Text(s.t(m.$2),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: allowed ? null : OfColors.muted)),
                  subtitle: Text(s.t(m.$3)),
                  trailing: allowed
                      ? const Icon(Icons.chevron_right)
                      : const Icon(Icons.lock_outline, color: OfColors.muted),
                ),
              ),
            );
          }),
          if (models.every((m) => !ref.snap.canModel(m.$1)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.t('plan_model_none_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OfColors.warn, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}
