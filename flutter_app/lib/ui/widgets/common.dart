import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/shop_keepalive.dart';
import '../../state/app_controller.dart';

extension OfX on WidgetRef {
  L10n get s {
    final code = watch(appControllerProvider).session.locale;
    return L10n(code);
  }

  AppSnapshot get snap => watch(appControllerProvider);
  AppController get ctrl => read(appControllerProvider.notifier);
}

String moneyOf(AppSnapshot snap, num amount) => money(
      amount,
      snap.store.profile.currencySymbol,
      prefix: snap.store.profile.currencyPrefix,
    );

class MoneyText extends ConsumerWidget {
  const MoneyText(this.amount, {super.key, this.style, this.color});
  final num amount;
  final TextStyle? style;
  final Color? color;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.snap;
    return Text(
      moneyOf(snap, amount),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(color: color, fontWeight: FontWeight.w800),
    );
  }
}

class OfScaffold extends ConsumerWidget {
  const OfScaffold({super.key, required this.title, required this.body, this.actions, this.fab, this.bottom, this.leading, this.subtitle});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  final Widget? leading;
  final String? subtitle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: subtitle == null
            ? Text(title)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title),
                Text(subtitle!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70)),
              ]),
        leading: leading,
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: OfColors.mint.withValues(alpha: 0.55)),
        ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: bottom,
      body: body,
    );
  }
}

class StationActions extends ConsumerWidget {
  const StationActions({super.key, this.extra = const []});
  final List<Widget> extra;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final snap = ref.snap;
    final up = snap.connected || snap.serverOn;
    final pending = snap.pendingSync;
    final label = !up && pending > 0
        ? '${s.t('working_offline')} · $pending'
        : up && pending > 0
            ? '${s.t('syncing_back')} $pending'
            : (up ? s.t('connected') : s.t('disconnected'));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.only(right: 4), child: StatusChip(label, color: up ? (pending > 0 ? OfColors.warn : OfColors.mint) : OfColors.danger)),
      const DutyChip(),
      ...extra,
    ]);
  }
}

class DutyChip extends ConsumerWidget {
  const DutyChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final id = ref.snap.session.staffId;
    final st = ref.snap.store.staffById(id);
    if (id == null && !ref.snap.isMain && !ref.snap.isManager) return const SizedBox.shrink();
    final duty = st?.duty ?? StaffDuty.onShift;
    return IconButton(
      tooltip: s.t('duty_${duty.name}'),
      onPressed: () => _pickDuty(context, ref),
      icon: Icon(duty == StaffDuty.onShift ? Icons.badge : duty == StaffDuty.mealBreak ? Icons.restaurant : duty == StaffDuty.teaBreak ? Icons.emoji_food_beverage : Icons.cloud_off),
    );
  }
  Future<void> _pickDuty(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    var staffId = ref.snap.session.staffId;
    if (staffId == null && (ref.snap.isMain || ref.snap.isManager) && ref.snap.store.staff.isNotEmpty) staffId = ref.snap.store.staff.first.id;
    if (staffId == null) return;
    final next = await showModalBottomSheet<StaffDuty>(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(s.t('duty_onShift')), leading: const Icon(Icons.badge), onTap: () => Navigator.pop(ctx, StaffDuty.onShift)),
        ListTile(title: Text(s.t('duty_mealBreak')), leading: const Icon(Icons.restaurant), onTap: () => Navigator.pop(ctx, StaffDuty.mealBreak)),
        ListTile(title: Text(s.t('duty_teaBreak')), leading: const Icon(Icons.emoji_food_beverage), onTap: () => Navigator.pop(ctx, StaffDuty.teaBreak)),
        ListTile(title: Text(s.t('duty_offline')), leading: const Icon(Icons.cloud_off), onTap: () => Navigator.pop(ctx, StaffDuty.offline)),
      ])),
    );
    if (next == null) return;
    await ref.ctrl.dispatch(NetCommand(name: 'setStaffDuty', payload: {'id': staffId, 'duty': next.name}));
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => unawaited(launchUrl(Uri.parse('https://jathol.pages.dev'), mode: LaunchMode.externalApplication)),
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/brand/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.flash_on, size: size, color: OfColors.mint),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action, this.actionLabel});
  final IconData icon;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: OfColors.mute(context)),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: TextStyle(color: OfColors.mute(context), fontSize: 16)),
      if (action != null && actionLabel != null) ...[const SizedBox(height: 16), FilledButton(onPressed: action, child: Text(actionLabel!))],
    ])));
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class OfCard extends StatelessWidget {
  const OfCard({super.key, required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.all(20), this.color});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
    final inner = onTap == null && onLongPress == null
        ? Padding(padding: padding, child: child)
        : InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, onLongPress: onLongPress, splashColor: OfColors.mint.withValues(alpha: 0.18), child: Padding(padding: padding, child: child));
    return Card(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, child: inner),
    );
  }
}

class ProductImage extends StatelessWidget {
  const ProductImage(this.b64, {super.key, this.size = 56});
  final String? b64;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (b64 == null || b64!.isEmpty) {
      return Container(width: size, height: size, decoration: BoxDecoration(color: OfColors.mute(context).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.image_not_supported, color: OfColors.mute(context)));
    }
    try {
      final bytes = base64Decode(b64!);
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover));
    } catch (_) {
      return Container(width: size, height: size, decoration: BoxDecoration(color: OfColors.mute(context).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.broken_image));
    }
  }
}

bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide >= 600;
int gridCount(BuildContext context, {int phone = 2, int tablet = 3}) => isTablet(context) ? tablet : phone;

class BusyBarrier extends StatelessWidget {
  const BusyBarrier({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      if (busy) const Positioned.fill(child: ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator()))),
    ]);
  }
}

class ReadyBannerHost extends ConsumerStatefulWidget {
  const ReadyBannerHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ReadyBannerHost> createState() => _ReadyBannerHostState();
}

class _ReadyBannerHostState extends ConsumerState<ReadyBannerHost> {
  String? _alertedId;

  @override
  void initState() {
    super.initState();
    unawaited(Permission.notification.request());
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(appControllerProvider.select((s) => s.notices));
    final top = notices.isEmpty ? null : notices.first;
    if (top != null && top.id != _alertedId) {
      _alertedId = top.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(ShopKeepAlive.alert(title: top.title, text: top.body));
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      });
    }
    return Stack(
      children: [
        widget.child,
        if (top != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Material(
                  color: top.kind == 'kitchen' ? const Color(0xFFE6A23C) : OfColors.mint,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    leading: Icon(top.kind == 'kitchen' ? Icons.outdoor_grill : Icons.notifications_active, color: Colors.black87),
                    title: Text(top.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
                    subtitle: Text(top.body, style: const TextStyle(color: Colors.black87)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.black87),
                      onPressed: () => ref.read(appControllerProvider.notifier).dismissNotice(top.id),
                    ),
                    onTap: () {
                      ref.read(appControllerProvider.notifier).dismissNotice(top.id);
                      if (top.orderId != null) context.push('/order/${top.orderId}');
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Color statusColor(OrderStatus s) => switch (s) {
      OrderStatus.open => OfColors.info,
      OrderStatus.preparing => OfColors.warn,
      OrderStatus.ready => OfColors.mint,
      OrderStatus.served => OfColors.emerald,
      OrderStatus.paid => OfColors.forest,
      OrderStatus.cancelled => OfColors.danger,
    };

Color tableColor(TableStatus s) => switch (s) {
      TableStatus.free => OfColors.emerald,
      TableStatus.ordered => OfColors.warn,
      TableStatus.ready => OfColors.mint,
    };

Color stockColor(StockLevel s) => switch (s) {
      StockLevel.ok => OfColors.emerald,
      StockLevel.low => OfColors.warn,
      StockLevel.out => OfColors.danger,
    };
