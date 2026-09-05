import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import 'common.dart';

/// Small bottom sheet shown when a plan does not include a feature.
/// Purely informational — the real enforcement is in StoreGuard / Main.
Future<void> showPlanLock(
  BuildContext context,
  WidgetRef ref, {
  required String featureKey,
}) async {
  final s = ref.s;
  final info = kFeatureCatalog.where((f) => f.key == featureKey);
  final label = info.isEmpty
      ? featureKey
      : (s.isUrdu ? info.first.labelUr : info.first.labelEn);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: OfColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(s.t('plan_locked_body'),
              style: const TextStyle(color: OfColors.muted, height: 1.45)),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(kLicenseWhatsAppUrl()),
                  mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.chat),
            label: Text(s.t('ask_jathol_upgrade')),
          ),
        ],
      ),
    ),
  );
}

/// Row that shows a lock badge when the plan does not include [feature];
/// tapping still opens the sheet so the shop can ask for an upgrade.
Widget planAwareRow({
  required WidgetRef ref,
  required BuildContext context,
  required String feature,
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  String? subtitle,
}) {
  final locked = !ref.snap.canFeature(feature);
  return ListTile(
    leading: Icon(locked ? Icons.lock_outline : icon,
        color: locked ? OfColors.muted : OfColors.emerald),
    title: Text(title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: locked ? OfColors.muted : null,
        )),
    subtitle: subtitle == null
        ? null
        : Text(subtitle, style: TextStyle(fontSize: 12, color: OfColors.muted)),
    trailing: locked
        ? const Icon(Icons.workspace_premium, color: OfColors.gold, size: 20)
        : const Icon(Icons.chevron_right),
    onTap: () => locked
        ? showPlanLock(context, ref, featureKey: feature)
        : onTap(),
  );
}
