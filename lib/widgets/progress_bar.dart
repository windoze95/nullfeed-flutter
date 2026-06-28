import 'package:flutter/material.dart';
import '../config/theme.dart';

class NullFeedProgressBar extends StatelessWidget {
  final double progress;
  final double height;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final void Function(double)? onSeek;

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
    this.semanticLabel,
    this.semanticValueBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: backgroundColor ?? NullFeedTheme.progressBackground,
          valueColor: AlwaysStoppedAnimation<Color>(
            foregroundColor ?? NullFeedTheme.progressForeground,
          ),
        ),
      ),
    );

    if (onSeek != null) {
      final seek = onSeek!;
      final clamped = progress.clamp(0.0, 1.0);
      // Let assistive tech step through the track in 5% increments when fine
      // touch isn't an option.
      final up = (clamped + 0.05).clamp(0.0, 1.0);
      final down = (clamped - 0.05).clamp(0.0, 1.0);
      String valueFor(double fraction) =>
          semanticValueBuilder?.call(fraction) ??
          '${(fraction * 100).round()}%';
      return Semantics(
        slider: true,
        label: semanticLabel ?? 'Seek bar',
        value: valueFor(clamped),
        increasedValue: valueFor(up),
        decreasedValue: valueFor(down),
        onIncrease: () => seek(up),
        onDecrease: () => seek(down),
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              final fraction = (details.localPosition.dx / box.size.width)
                  .clamp(0.0, 1.0);
              seek(fraction);
            }
          },
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              final fraction = (details.localPosition.dx / box.size.width)
                  .clamp(0.0, 1.0);
              seek(fraction);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: bar,
          ),
        ),
      );
    }

    return bar;
  }
}
