import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
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
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.color,
  });

  final num amount;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.snap;
    return Text(
      moneyOf(snap, amount),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class OfScaffold extends ConsumerWidget {
  const OfScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.fab,
    this.bottom,
    this.leading,
    this.subtitle,
  });

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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
                  ),
                ],
              ),
        leading: leading,
        actions: actions,
      ),
      floatingActionButton: fab,
      bottomNavigationBar: bottom,
      body: body,
    );
  }
}

/// Shared chrome for role stations: live status + leave.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: StatusChip(
            label,
            color: up
                ? (pending > 0 ? OfColors.warn : OfColors.mint)
                : OfColors.danger,
          ),
        ),
        ...extra,
      ],
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        'assets/brand/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: OfColors.mint,
          alignment: Alignment.center,
          child: const Text('J', style: TextStyle(fontWeight: FontWeight.w900, color: OfColors.deep)),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OfColors.mint.withValues(alpha: 0.14),
                border: Border.all(color: OfColors.mint.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 40, color: OfColors.emerald),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: OfColors.mute(context),
                    height: 1.4,
                    fontSize: 16,
                  ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: action, child: Text(actionLabel ?? 'Add')),
            ],
          ],
        ),
      ),
    );
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class OfCard extends StatelessWidget {
  const OfCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && onLongPress == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
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
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: OfColors.emerald.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.restaurant, color: OfColors.emerald),
      );
    }
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          base64Decode(b64!),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } catch (_) {
      return Icon(Icons.broken_image, size: size * 0.6);
    }
  }
}

class BusyBarrier extends StatelessWidget {
  const BusyBarrier({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (busy)
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
        if (busy)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class ReadyBannerHost extends ConsumerStatefulWidget {
  const ReadyBannerHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReadyBannerHost> createState() => _ReadyBannerHostState();
}

class _ReadyBannerHostState extends ConsumerState<ReadyBannerHost> {
  String? _lastId;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.snap.notices;
    final first = notices.isEmpty ? null : notices.first;
    if (first != null && first.id != _lastId) {
      _lastId = first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void ping() {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        }
        ping();
        Timer(const Duration(milliseconds: 700), ping);
        Timer(const Duration(milliseconds: 1400), ping);
        _hide?.cancel();
        _hide = Timer(const Duration(seconds: 10), () {
          if (mounted) ref.ctrl.dismissNotice(first.id);
        });
      });
    }
    return Stack(
      children: [
        widget.child,
        if (first != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Material(
                  elevation: 16,
                  borderRadius: BorderRadius.circular(20),
                  color: OfColors.forest,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: OfColors.mint, width: 2),
                    ),
                    child: InkWell(
                    onTap: () {
                      final id = first.orderId;
                      ref.ctrl.dismissNotice(first.id);
                      if (id != null) context.push('/order/$id');
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active, color: OfColors.mint, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                first.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
                              ),
                              const SizedBox(height: 4),
                              Text(first.body, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.3)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => ref.ctrl.dismissNotice(first.id),
                        ),
                      ],
                    ),
                    ),
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

Future<void> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required VoidCallback onYes,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
      ],
    ),
  );
  if (ok == true) onYes();
}

bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= 700;

int gridCount(BuildContext context, {int phone = 2, int tablet = 4}) =>
    isTablet(context) ? tablet : phone;
