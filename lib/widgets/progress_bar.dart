import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class NullFeedProgressBar extends StatefulWidget {
  /// Interactive seek bars keep a full touch-sized hit target while the
  /// painted track remains visually compact. Passive card bars still use
  /// [height] as their total height.
  static const double interactiveHeight = 48;

  static const double _thumbDiameter = 16;

  final double progress;
  final double height;
  final Color? foregroundColor;
  final Color? backgroundColor;

  /// Called once per interaction — on tap release, or when a drag lets go —
  /// with the final 0–1 fraction. Never called while the finger is still
  /// moving: issuing a native seek on every drag tick cancels and restarts the
  /// player's in-flight seek dozens of times a second, which on a
  /// still-buffering source wedges it (stutter → freeze → crash). While
  /// dragging, the bar tracks the finger locally and reports the would-be
  /// target through [onSeekPreview] instead.
  final void Function(double)? onSeek;

  /// Called with the 0–1 fraction under the finger on every drag update, so
  /// the caller can preview the target (e.g. a live timestamp) without any
  /// seek being issued. Only used when [onSeek] is set.
  final void Function(double)? onSeekPreview;

  /// Called as soon as the viewer puts a pointer down on the seek bar, and when
  /// that pointer is released or cancelled. Lets the player pin its controls
  /// and suspend sponsor auto-skip before Flutter has recognized a tap or drag.
  /// Only used when [onSeek] is set.
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;

  /// Accessibility label for the seek slider. Only used when [onSeek] is set.
  final String? semanticLabel;

  /// Formats a 0–1 position into the value a screen reader announces (e.g.
  /// "1:23 of 4:56"). Falls back to a percentage. Only used when [onSeek] is
  /// set — the slider's increase/decrease values are derived from it too.
  final String Function(double fraction)? semanticValueBuilder;

  const NullFeedProgressBar({
    super.key,
    required this.progress,
    this.height = 4,
    this.foregroundColor,
    this.backgroundColor,
    this.onSeek,
    this.onSeekPreview,
    this.onSeekStart,
    this.onSeekEnd,
    this.semanticLabel,
    this.semanticValueBuilder,
  });

  @override
  State<NullFeedProgressBar> createState() => _NullFeedProgressBarState();
}

class _NullFeedProgressBarState extends State<NullFeedProgressBar> {
  /// The fraction under the finger while a drag is in progress; null when
  /// idle. Drives the bar's fill during the drag so it follows the finger
  /// rather than the (still-playing) playhead.
  double? _dragFraction;

  double _fractionAt(Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (localPosition.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _updateDrag(Offset localPosition) {
    final fraction = _fractionAt(localPosition);
    setState(() => _dragFraction = fraction);
    widget.onSeekPreview?.call(fraction);
  }

  void _endDrag({required bool commit}) {
    final fraction = _dragFraction;
    setState(() => _dragFraction = null);
    if (commit && fraction != null) widget.onSeek?.call(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final shown = (_dragFraction ?? widget.progress).clamp(0.0, 1.0);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: LinearProgressIndicator(
          value: shown,
          backgroundColor:
              widget.backgroundColor ?? NullFeedTheme.progressBackground,
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.foregroundColor ?? NullFeedTheme.progressForeground,
          ),
        ),
      ),
    );

    if (widget.onSeek != null) {
      final seek = widget.onSeek!;
      final clamped = widget.progress.clamp(0.0, 1.0);
      // Let assistive tech step through the track in 5% increments when fine
      // touch isn't an option.
      final up = (clamped + 0.05).clamp(0.0, 1.0);
      final down = (clamped - 0.05).clamp(0.0, 1.0);
      String valueFor(double fraction) =>
          widget.semanticValueBuilder?.call(fraction) ??
          '${(fraction * 100).round()}%';
      return Semantics(
        slider: true,
        label: widget.semanticLabel ?? 'Seek bar',
        value: valueFor(clamped),
        increasedValue: valueFor(up),
        decreasedValue: valueFor(down),
        onIncrease: () => seek(up),
        onDecrease: () => seek(down),
        excludeSemantics: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.onSeekStart?.call(),
          onPointerUp: (_) => widget.onSeekEnd?.call(),
          onPointerCancel: (_) => widget.onSeekEnd?.call(),
          child: GestureDetector(
            // The painted track is intentionally slim. Make the full 48dp
            // wrapper participate in hit testing so users do not have to land
            // exactly on a 4dp line to start a scrub.
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            // Seek on release (not press) so a press that turns into a drag
            // never fires a stray seek at the touch-down point.
            onTapUp: (details) => seek(_fractionAt(details.localPosition)),
            onHorizontalDragStart: (details) =>
                _updateDrag(details.localPosition),
            onHorizontalDragUpdate: (details) =>
                _updateDrag(details.localPosition),
            onHorizontalDragEnd: (_) => _endDrag(commit: true),
            onHorizontalDragCancel: () => _endDrag(commit: false),
            child: SizedBox(
              height: NullFeedProgressBar.interactiveHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxThumbLeft =
                      constraints.maxWidth - NullFeedProgressBar._thumbDiameter;
                  final thumbLeft =
                      (shown * constraints.maxWidth -
                              NullFeedProgressBar._thumbDiameter / 2)
                          .clamp(0.0, maxThumbLeft < 0 ? 0.0 : maxThumbLeft);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top:
                            (NullFeedProgressBar.interactiveHeight -
                                widget.height) /
                            2,
                        child: bar,
                      ),
                      Positioned(
                        left: thumbLeft,
                        top:
                            (NullFeedProgressBar.interactiveHeight -
                                NullFeedProgressBar._thumbDiameter) /
                            2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                widget.foregroundColor ??
                                NullFeedTheme.progressForeground,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const SizedBox.square(
                            dimension: NullFeedProgressBar._thumbDiameter,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return bar;
  }
}
