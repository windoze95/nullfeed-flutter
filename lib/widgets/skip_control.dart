import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Skip-back / skip-forward control for the player overlay: a trio of
/// chevrons, replacing the stock replay_10 / forward_10 icons.
///
/// A tap fires [onTap] (one fixed skip) and plays a single brightness sweep
/// across the chevrons in the skip direction. Press-and-hold fires
/// [onHoldStart]; while the hold is active the caller passes the accumulated
/// amount (e.g. "+45s") as [holdLabel], which appears while seeking and keeps
/// the sweep animating on repeat until [onHoldEnd].
class SkipControl extends StatefulWidget {
  /// Points the chevrons (and the sweep) right when true, left when false.
  final bool forward;

  /// The fixed skip size a tap performs, used in the accessibility label and
  /// tooltip while the visual control remains chevrons-only at rest.
  final int seconds;

  /// Accumulated hold-to-seek amount while a hold is active; null when idle.
  final String? holdLabel;

  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const SkipControl({
    super.key,
    required this.forward,
    required this.seconds,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.holdLabel,
  });

  @override
  State<SkipControl> createState() => _SkipControlState();
}

class _SkipControlState extends State<SkipControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  bool get _holding => widget.holdLabel != null;

  @override
  void initState() {
    super.initState();
    if (_holding) _sweep.repeat();
    // After a one-shot tap sweep, snap back to the idle (uniform) look.
    _sweep.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_holding) {
        _sweep.value = 0;
      }
    });
  }

  @override
  void didUpdateWidget(SkipControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasHolding = oldWidget.holdLabel != null;
    if (_holding && !wasHolding) {
      _sweep.repeat();
    } else if (!_holding && wasHolding) {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _handleTap() {
    _sweep.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.forward ? 'forward' : 'back';
    final holdVerb = widget.forward ? 'fast-forward' : 'rewind';
    return Semantics(
      button: true,
      label:
          'Skip $direction ${widget.seconds} seconds. '
          'Press and hold to $holdVerb.',
      child: Tooltip(
        message: 'Skip $direction ${widget.seconds}s — hold to $holdVerb',
        // Never trigger on long-press (the touch default): that would race
        // the hold-to-seek gesture in the arena. Hover still shows it.
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onLongPressStart: (_) => widget.onHoldStart(),
          onLongPressEnd: (_) => widget.onHoldEnd(),
          onLongPressCancel: widget.onHoldEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _holding ? Colors.white12 : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            // The chevrons and optional hold label are decorative; the outer
            // Semantics node carries the full control description.
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (_, __) => CustomPaint(
                      size: const Size(52, 22),
                      painter: _ChevronSweepPainter(
                        wave: _sweep.isAnimating ? _sweep.value : null,
                        forward: widget.forward,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (widget.holdLabel case final holdLabel?) ...[
                    const SizedBox(height: 4),
                    Text(
                      holdLabel,
                      style: const TextStyle(
                        color: NullFeedTheme.primaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three stroked chevrons with a brightness peak that sweeps across them in
/// the skip direction. [wave] is the 0–1 sweep position; null renders the
/// idle state (all chevrons at uniform brightness).
class _ChevronSweepPainter extends CustomPainter {
  final double? wave;
  final bool forward;
  final Color color;

  const _ChevronSweepPainter({
    required this.wave,
    required this.forward,
    required this.color,
  });

  static const int _count = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final armWidth = size.width * 0.2;
    final step = (size.width - armWidth) / _count;
    final top = size.height * 0.08;
    final bottom = size.height * 0.92;
    final mid = size.height / 2;

    for (var i = 0; i < _count; i++) {
      final x = i * step + step / 2;
      final tip = forward ? x + armWidth : x;
      final base = forward ? x : x + armWidth;

      double opacity;
      final w = wave;
      if (w == null) {
        opacity = 0.9;
      } else {
        // The peak enters before the first chevron and exits past the last,
        // travelling in the skip direction.
        final order = forward ? i : _count - 1 - i;
        final peak = w * (_count + 1) - 1;
        final glow = (1 - (peak - order).abs()).clamp(0.0, 1.0);
        opacity = 0.30 + 0.70 * glow;
      }
      paint.color = color.withValues(alpha: opacity);

      final path = Path()
        ..moveTo(base, top)
        ..lineTo(tip, mid)
        ..lineTo(base, bottom);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ChevronSweepPainter oldDelegate) =>
      wave != oldDelegate.wave ||
      forward != oldDelegate.forward ||
      color != oldDelegate.color;
}
