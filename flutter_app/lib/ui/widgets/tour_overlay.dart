import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../../state/nav_tab.dart';

/// v1.1.93 — element-level guided tour. Each step points at a real control:
/// the overlay waits for the owning tab, scrolls the target into view, cuts a
/// spotlight hole in the scrim around its measured rect and docks the bubble
/// beside it. `pos` is only used as a fallback when the target hasn't rendered
/// (e.g. an empty floor has no table tile yet, or a small screen clipped it).
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
      _Step(s.t('tour_home_t'), s.t('tour_home_b'),
          key: TourKeys.homeHero, tab: 0, fallback: _Pos.top),
      _Step(s.t('tour_room_t'), s.t('tour_room_b'),
          key: TourKeys.roomQr, tab: 0, fallback: _Pos.top),
      _Step(s.t('tour_floor_t'), s.t('tour_floor_b'),
          key: TourKeys.floorTile, tab: 1, fallback: _Pos.centre),
      _Step(s.t('tour_menu_t'), s.t('tour_menu_b'),
          key: TourKeys.menuCard, tab: 2, fallback: _Pos.centre),
      _Step(s.t('tour_more_t'), s.t('tour_more_b'),
          key: TourKeys.moreFolder, tab: 4, fallback: _Pos.centre),
      _Step(s.t('tour_done_t'), s.t('tour_done_b'), fallback: _Pos.bottom),
    ];

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'tour',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, _, __) => _TourDialog(steps: steps, locale: s),
    );

    // Leave the user where they started.
    mainTabIndex.value = 0;
    await ref.read(appControllerProvider.notifier).markTourSeen();
    _running = false;
  }
}

/// Global keys pinned on the real controls the tour highlights. Screens attach
/// them (first card only, to stay unique); [`TourKeys._`] prevents creation.
class TourKeys {
  TourKeys._();
  static final homeHero = GlobalKey();
  static final roomQr = GlobalKey();
  static final floorTile = GlobalKey();
  static final menuCard = GlobalKey();
  static final moreFolder = GlobalKey();
}

enum _Pos { top, centre, bottom }

class _Step {
  _Step(this.title, this.body, {this.key, this.tab, required this.fallback});
  final String title;
  final String body;

  /// Real control this step spotlights, if it is on screen.
  final GlobalKey? key;

  /// Main-shell tab owning the target; the tour switches to it first.
  final int? tab;
  final _Pos fallback;
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
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  _Step get _step => widget.steps[i];

  void _next() {
    if (i == widget.steps.length - 1) {
      Navigator.of(context).pop();
    } else {
      _goTo(i + 1);
    }
  }

  void _goTo(int ni) {
    setState(() => i = ni);
    _locate();
  }

  /// Switch to the owning tab, scroll the target into view, measure its rect.
  /// Retries briefly: a tab change takes a frame to build its content.
  Future<void> _locate() async {
    final step = _step;
    if (step.tab != null && mainTabIndex.value != step.tab) {
      mainTabIndex.value = step.tab!;
    }
    if (step.key == null) {
      if (mounted) setState(() => _hole = null);
      return;
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final ctx = step.key?.currentContext;
      if (ctx == null) {
        // Content not built yet (first paint of a new tab) — wait and retry.
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 140));
          continue;
        }
        if (mounted) setState(() => _hole = null);
        return;
      }
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.45,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // Not inside a Scrollable — measuring still works.
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size.width > 2) {
        final pos = box.localToGlobal(Offset.zero);
        final rect = pos & box.size;
        // Off-screen or absurd rect → fall back to a centred bubble.
        final screen = MediaQuery.of(context).size;
        if (rect.bottom > 0 &&
            rect.top < screen.height &&
            rect.width < screen.width * 1.2) {
          if (mounted) setState(() => _hole = rect);
          return;
        }
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    }
    if (mounted) setState(() => _hole = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.locale;
    final step = widget.steps[i];
    final isDark = OfColors.isDark(context);
    final ink = isDark ? const Color(0xFFF3F7F2) : OfColors.ink;
    final quiet = isDark ? const Color(0xFFA9C6B7) : OfColors.muted;
    final card = isDark ? OfColors.cardDark : OfColors.creamSurface;
    final media = MediaQuery.of(context);
    final screen = media.size;

    final hole = _hole;
    // Bubble docking: below the hole when there is space, above otherwise,
    // centred on the hole horizontally. No hole → legacy _Pos alignment.
    double bubbleTop;
    double bubbleLeft = 22;
    double bubbleRight = 22;
    if (hole != null) {
      const bubbleH = 190.0;
      final below = hole.bottom + 14;
      final above = hole.top - 14 - bubbleH;
      final spaceAfter = screen.height - hole.bottom;
      bubbleTop = (spaceAfter >= bubbleH + 28 || above < media.padding.top)
          ? below.clamp(media.padding.top + 8, screen.height - bubbleH - 10)
          : above.clamp(media.padding.top + 8, screen.height - bubbleH - 10);
      final idealLeft = hole.center.dx - 200;
      bubbleLeft = idealLeft.clamp(16.0, (screen.width - 422).clamp(16.0, screen.width));
      bubbleRight = (screen.width - bubbleLeft - 400).clamp(16.0, screen.width);
    } else {
      switch (step.fallback) {
        case _Pos.top:
          bubbleTop = media.padding.top + 90;
        case _Pos.centre:
          bubbleTop = (screen.height - 200) / 2;
        case _Pos.bottom:
          bubbleTop = screen.height - 300;
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // dim everything except the spotlight hole; gentle tap-through guard
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: CustomPaint(painter: _ScrimPainter(hole)),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: bubbleTop,
            left: bubbleLeft,
            right: bubbleRight,
            child: Center(
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

/// Dark scrim with a rounded spotlight hole around [_ScrimPainter.hole].
/// Even-odd fill keeps it cheap (one path, no image layers); a mint rim marks
/// the control the current step is talking about.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.66);
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    final padded = RRect.fromRectAndRadius(
      hole!.inflate(8),
      const Radius.circular(18),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(padded);
    canvas.drawPath(path, scrim);
    canvas.drawRRect(
      padded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = OfColors.mint,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
