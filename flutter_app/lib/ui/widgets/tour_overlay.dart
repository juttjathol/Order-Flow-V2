import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';

/// v1.1.92 — in-app guided tour: a dark scrim with a bubble card that steps
/// through the app's big surfaces (hero → room pairing → floor → menu → more).
/// `pos` nudges the bubble toward the thing it describes (top / centre / bottom).
/// Runs once per device (session.tourSeen); replayable from More → Guided tour.
class TourOverlay {
  TourOverlay._();

  static bool _running = false;

  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    if (_running) return;
    // `read` (not watch): we run post-frame, outside a build phase.
    final snap = ref.read(appControllerProvider);
    if (!snap.isMain || snap.session.tourSeen) return;
    _running = true;
    await _show(context, ref);
  }

  static Future<void> show(BuildContext context, WidgetRef ref) =>
      _show(context, ref, force: true);

  static Future<void> _show(BuildContext context, WidgetRef ref,
      {bool force = false}) async {
    // Event-handler read, not watch (post-frame / tap callbacks).
    final s = L10n(ref.read(appControllerProvider).session.locale);
    final steps = <_Step>[
      _Step(s.t('tour_home_t'), s.t('tour_home_b'), _Pos.top),
      _Step(s.t('tour_room_t'), s.t('tour_room_b'), _Pos.top),
      _Step(s.t('tour_floor_t'), s.t('tour_floor_b'), _Pos.centre),
      _Step(s.t('tour_menu_t'), s.t('tour_menu_b'), _Pos.centre),
      _Step(s.t('tour_more_t'), s.t('tour_more_b'), _Pos.centre),
      _Step(s.t('tour_done_t'), s.t('tour_done_b'), _Pos.bottom),
    ];

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'tour',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, _, __) => _TourDialog(steps: steps, locale: s),
    );

    await ref.ctrl.markTourSeen();
    _running = false;
  }
}

enum _Pos { top, centre, bottom }

class _Step {
  _Step(this.title, this.body, this.pos);
  final String title;
  final String body;
  final _Pos pos;
}

class _TourDialog extends StatefulWidget {
  const _TourDialog({required this.steps, required this.locale});
  final List<_Step> steps;
  final L10n locale;

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  int i = 0;

  void _next() {
    if (i == widget.steps.length - 1) {
      Navigator.of(context).pop();
    } else {
      setState(() => i++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.locale;
    final step = widget.steps[i];
    final isDark = OfColors.isDark(context);
    final ink = isDark ? const Color(0xFFF3F7F2) : OfColors.ink;
    final quiet = isDark ? const Color(0xFFA9C6B7) : OfColors.muted;
    final card = isDark ? OfColors.cardDark : OfColors.creamSurface;

    final alignment = switch (step.pos) {
      _Pos.top => const Alignment(0, -0.62),
      _Pos.centre => Alignment.center,
      _Pos.bottom => const Alignment(0, 0.68),
    };

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // dim everything, gentle tap-through guard
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              child: Container(color: Colors.black.withValues(alpha: 0.58)),
            ),
          ),
          Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                child: Container(
                  key: ValueKey(i),
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark ? OfColors.cardDarkAlt : OfColors.creamBorder,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 34,
                        offset: Offset(0, 14),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        step.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.body,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: quiet,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: quiet,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            child: Text(s.t('tour_skip')),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var d = 0; d < widget.steps.length; d++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: d == i ? 18 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: d == i
                                          ? OfColors.mint
                                          : d < i
                                              ? OfColors.mint.withValues(alpha: 0.45)
                                              : (isDark
                                                  ? OfColors.cardDarkAlt
                                                  : OfColors.creamBorder),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: OfColors.mint,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(76, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                            child: Text(
                              i == widget.steps.length - 1
                                  ? s.t('tour_end')
                                  : s.t('tour_next'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
