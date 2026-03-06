import 'package:flutter/material.dart';
import '../config/theme.dart';

class NullFeedProgressBar extends StatelessWidget {
  final double progress;
  final double height;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final void Function(double)? onSeek;

  const NullFeedProgressBar({
    super.key,
    required this.progress,
    this.height = 4,
    this.foregroundColor,
    this.backgroundColor,
    this.onSeek,
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
      return GestureDetector(
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final fraction = (details.localPosition.dx / box.size.width).clamp(
              0.0,
              1.0,
            );
            onSeek!(fraction);
          }
        },
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final fraction = (details.localPosition.dx / box.size.width).clamp(
              0.0,
              1.0,
            );
            onSeek!(fraction);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: bar,
        ),
      );
    }

    return bar;
  }
}
