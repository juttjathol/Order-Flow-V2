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
import '../../core/platform_check.dart';
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
                Text(subtitle!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: OfColors.mute(context))),
              ]),
        leading: leading,
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: OfColors.line),
        ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: bottom,
      body: body,
    );
  }
}

class BroadcastBell extends ConsumerWidget {
  const BroadcastBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final unread = ref.snap.unreadBroadcastCount;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: s.t('broadcasts_title'),
          icon: Icon(
            unread > 0 ? Icons.notifications_active : Icons.notifications_outlined,
            color: unread > 0
                ? OfColors.gold
                : (OfColors.isDark(context) ? Colors.white : OfColors.forest),
          ),
          onPressed: () {
            ref.ctrl.markBroadcastsRead();
            showBroadcastsSheet(context, ref);
          },
        ),
        if (unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: OfColors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showBroadcastsSheet(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final broadcasts = ref.snap.broadcasts;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final isDark = OfColors.isDark(ctx);
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OfColors.forest.withValues(alpha: isDark ? 0.25 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign, color: OfColors.forest, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t('broadcasts_title'),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        Text(
                          s.t('broadcasts_subtitle'),
                          style: TextStyle(color: OfColors.mute(ctx), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (broadcasts.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        ref.ctrl.markBroadcastsRead();
                        Navigator.pop(ctx);
                      },
                      child: Text(s.t('broadcasts_mark_read')),
                    ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: broadcasts.isEmpty
                    ? EmptyState(
                        icon: Icons.notifications_none,
                        message: s.t('broadcasts_empty'),
                      )
                    : ListView.separated(
                        itemCount: broadcasts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final b = broadcasts[i];
                          final tagColor = switch (b.tag) {
                            'plan' => OfColors.gold,
                            'tip' => OfColors.info,
                            'announcement' => OfColors.warn,
                            _ => OfColors.forest,
                          };
                          final tagLabel = switch (b.tag) {
                            'plan' => s.t('broadcast_tag_plan'),
                            'tip' => s.t('broadcast_tag_tip'),
                            'announcement' => s.t('broadcast_tag_announcement'),
                            _ => s.t('broadcast_tag_feature'),
                          };
                          final dateStr =
                              '${b.createdAt.day}/${b.createdAt.month} ${b.createdAt.hour.toString().padLeft(2, '0')}:${b.createdAt.minute.toString().padLeft(2, '0')}';
                          return OfCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusChip(tagLabel, color: tagColor),
                                    const Spacer(),
                                    Text(dateStr,
                                        style: TextStyle(color: OfColors.mute(ctx), fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  b.title,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  b.message,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: isDark ? const Color(0xFFD6E3DC) : const Color(0xFF2E3E35),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
        : _TapScale(onTap: onTap, onLongPress: onLongPress, child: Padding(padding: padding, child: child));
    return Card(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, child: inner),
    );
  }
}

/// v1.1.64 · press feedback for every tappable card: a quick scale dip
/// plus a haptic tick — the whole app feels physical without plugins.
class _TapScale extends StatefulWidget {
  const _TapScale({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        _set(false);
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.955 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
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
    // Bell + shouting banner are the alert on desktop; the notification
    // permission only exists on Android/iOS.
    if (OfPlatform.isMobile) unawaited(Permission.notification.request());
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
                    leading: Icon(
                      top.kind == 'kitchen'
                          ? Icons.outdoor_grill
                          : top.kind == 'device'
                              ? Icons.phonelink
                              : Icons.notifications_active,
                      color: Colors.black87,
                    ),
                    title: Text(top.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
                    subtitle: Text(top.body, style: const TextStyle(color: Colors.black87)),
                    trailing: top.kind == 'device' && top.orderId != null
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(
                              onPressed: () {
                                final id = top.orderId!;
                                ref.read(appControllerProvider.notifier).dismissNotice(top.id);
                                unawaited(ref.read(appControllerProvider.notifier).approveDevice(id));
                              },
                              child: Text(ref.s.t('approve')),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.black87),
                              onPressed: () {
                                final id = top.orderId;
                                ref.read(appControllerProvider.notifier).dismissNotice(top.id);
                                if (id != null) unawaited(ref.read(appControllerProvider.notifier).denyDevice(id));
                              },
                            ),
                          ])
                        : IconButton(
                            icon: const Icon(Icons.close, color: Colors.black87),
                            onPressed: () => ref.read(appControllerProvider.notifier).dismissNotice(top.id),
                          ),
                    onTap: () {
                      if (top.kind == 'device') return;
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

class TicketSearchField extends ConsumerWidget {
  const TicketSearchField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: ref.s.t('search'),
          prefixIcon: const Icon(Icons.search),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

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
