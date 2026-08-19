import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    return Scaffold(
      backgroundColor: OfColors.deep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Logo(),
            const SizedBox(height: 18),
            Text(
              s.t('app'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(s.t('tagline'), style: const TextStyle(color: OfColors.mint)),
            const SizedBox(height: 28),
            const CircularProgressIndicator(color: OfColors.mint),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: OfColors.forest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OfColors.mint, width: 2),
      ),
      child: const Icon(Icons.point_of_sale, color: OfColors.mint, size: 42),
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
    apiCtrl.text = snap.session.apiBase;
  }

  @override
  void dispose() {
    keyCtrl.dispose();
    apiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final snap = ref.snap;
    return Scaffold(
      body: BusyBarrier(
        busy: snap.busy,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const _Logo(),
              const SizedBox(height: 16),
              Text(s.t('app'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(s.t('tagline'), style: const TextStyle(color: OfColors.muted)),
              const SizedBox(height: 24),
              Text(s.t('main_needs_key'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(s.t('need_internet_first')),
              const SizedBox(height: 16),
              TextField(
                controller: keyCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: s.t('paste_key'),
                  prefixIcon: const Icon(Icons.vpn_key),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apiCtrl,
                decoration: InputDecoration(
                  labelText: s.t('api_base'),
                  prefixIcon: const Icon(Icons.cloud),
                ),
                onSubmitted: (v) => ref.ctrl.setApiBase(v),
              ),
              if (snap.error != null) ...[
                const SizedBox(height: 12),
                Text(s.t(snap.error!), style: const TextStyle(color: OfColors.danger, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await ref.ctrl.setApiBase(apiCtrl.text);
                  final err = await ref.ctrl.activateLicense(keyCtrl.text);
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(err))));
                  }
                },
                icon: const Icon(Icons.verified),
                label: Text(s.t('activate')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.push('/connect'),
                icon: const Icon(Icons.wifi),
                label: Text(s.t('connect_main')),
              ),
              const SizedBox(height: 8),
              Text(s.t('no_key_needed'), textAlign: TextAlign.center, style: const TextStyle(color: OfColors.muted)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('${s.t('device_id')}: '),
                  Flexible(
                    child: Text(
                      snap.session.deviceId,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: snap.session.deviceId));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(s.t('english')),
                    selected: snap.session.locale == 'en',
                    onSelected: (_) => ref.ctrl.setLocale('en'),
                  ),
                  ChoiceChip(
                    label: Text(s.t('urdu')),
                    selected: snap.session.locale == 'ur',
                    onSelected: (_) => ref.ctrl.setLocale('ur'),
                  ),
                ],
              ),
            ],
          ),
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
              Text(
                s.t('locked_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                s.t('locked_body'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: () => launchUrl(
                  Uri.parse(kWhatsAppUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.chat),
                label: Text(s.t('open_whatsapp')),
              ),
              const SizedBox(height: 12),
              Text(
                kWhatsAppHandle,
                style: const TextStyle(color: OfColors.mint, fontSize: 20, fontWeight: FontWeight.w800),
              ),
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
  AppRole? selected;

  @override
  void dispose() {
    name.dispose();
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
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: s.t('your_name')),
          ),
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
                : () => ref.ctrl.chooseClientRole(selected!, name.text),
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
          (AppRole.orderTaker, Icons.room_service, 'role_taker', 'role_taker_hint'),
          (AppRole.kitchen, Icons.soup_kitchen, 'role_kitchen', 'role_kitchen_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
          (AppRole.driver, Icons.delivery_dining, 'role_driver', 'role_driver_hint'),
        ];
      case BusinessModel.retail:
        return const [
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
          (AppRole.stockClerk, Icons.inventory_2, 'role_stock', 'role_stock_hint'),
        ];
      case BusinessModel.fastfood:
        return const [
          (AppRole.orderTaker, Icons.fastfood, 'role_taker', 'role_taker_hint'),
          (AppRole.kitchen, Icons.soup_kitchen, 'role_kitchen', 'role_kitchen_hint'),
          (AppRole.cashier, Icons.point_of_sale, 'role_cashier', 'role_cashier_hint'),
        ];
      case BusinessModel.services:
        return const [
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OfCard(
                onTap: () => ref.ctrl.pickModel(m.$1),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.$4, color: OfColors.emerald, size: 32),
                  title: Text(s.t(m.$2), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.t(m.$3)),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
