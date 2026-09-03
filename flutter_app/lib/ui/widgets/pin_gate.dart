import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/app_controller.dart';
import 'common.dart';

Future<bool> confirmManagerPin(BuildContext context, WidgetRef ref, {bool requiredForCashier = false}) async {
  final pin = ref.read(appControllerProvider).store.profile.managerPin;
  if (pin.isEmpty) return true;
  final s = ref.s;
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.t('manager_pin')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(requiredForCashier ? s.t('pin_for_cashier') : s.t('pin_required'), style: const TextStyle(color: OfColors.muted)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: s.t('manager_pin')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == pin),
          child: Text(s.t('continue')),
        ),
      ],
    ),
  );
  if (ok != true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('pin_wrong'))));
  }
  return ok == true;
}

Future<void> leaveRoleWithPin(BuildContext context, WidgetRef ref) async {
  if (!ref.read(appControllerProvider).isMain) {
    final ok = await confirmManagerPin(context, ref);
    if (!ok) return;
  }
  await ref.ctrl.leaveRole();
}
