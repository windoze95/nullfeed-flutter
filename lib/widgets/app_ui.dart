import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'adaptive_layout.dart';

/// A restrained ambient backdrop shared by the main product surfaces.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: NullFeedTheme.ambientGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: _AmbientGlow()),
          child,
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AmbientGlowPainter());
  }
}

class _AmbientGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final primaryPaint = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x187C4DFF), Color(0x007C4DFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.84, size.height * 0.06),
              radius: size.width * 0.44,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.06),
      size.width * 0.44,
      primaryPaint,
    );

    final accentPaint = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x10B8FF5C), Color(0x00B8FF5C)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.08, size.height * 0.72),
              radius: size.width * 0.46,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.72),
      size.width * 0.46,
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact product mark used in onboarding and the desktop shell.
class NullFeedMark extends StatelessWidget {
  const NullFeedMark({
    super.key,
    this.showWordmark = true,
    this.compact = false,
  });

  final bool showWordmark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 44.0;
    return Semantics(
      label: 'NullFeed',
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: NullFeedTheme.primaryColor,
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2E7C4DFF),
                  blurRadius: 24,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Icon(
              Icons.graphic_eq_rounded,
              size: compact ? 22 : 27,
              color: Colors.white,
            ),
          ),
          if (showWordmark) ...[
            const SizedBox(width: 12),
            ExcludeSemantics(
              child: Text(
                'NULLFEED',
                style: TextStyle(
                  color: NullFeedTheme.textPrimary,
                  fontSize: compact ? 16 : 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? 0.7 : 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Large, plain-language introduction at the top of a primary screen.
class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.trailing,
    this.bottom,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.contentPadding(context);
    final wide = AdaptiveLayout.isWide(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, wide ? 42 : 24, padding, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        color: NullFeedTheme.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: wide
                          ? Theme.of(context).textTheme.headlineLarge
                          : Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 20), trailing!],
            ],
          ),
          if (bottom != null) ...[const SizedBox(height: 22), bottom!],
        ],
      ),
    );
  }
}

/// A visible shortcut with both an icon and a label. It intentionally avoids
/// mystery-meat icon buttons for primary journeys.
class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized ? Colors.white : NullFeedTheme.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: emphasized
            ? NullFeedTheme.primaryColor
            : NullFeedTheme.cardColor.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: emphasized
                ? NullFeedTheme.primaryColor
                : NullFeedTheme.borderColor,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 19),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An actionable state panel for empty, error, and first-run moments.
class EmptyStatePanel extends StatelessWidget {
  const EmptyStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.eyebrow,
    this.steps = const [],
    this.primaryAction,
    this.primaryLabel,
    this.secondaryAction,
    this.secondaryLabel,
    this.maxWidth = 680,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? eyebrow;
  final List<String> steps;
  final VoidCallback? primaryAction;
  final String? primaryLabel;
  final VoidCallback? secondaryAction;
  final String? secondaryLabel;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: NullFeedTheme.cardColor.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: NullFeedTheme.borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: NullFeedTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: NullFeedTheme.primaryColor.withValues(alpha: 0.26),
                  ),
                ),
                child: Icon(icon, color: NullFeedTheme.primaryColor, size: 25),
              ),
              const SizedBox(height: 20),
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: const TextStyle(
                    color: NullFeedTheme.primaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              if (steps.isNotEmpty) ...[
                const SizedBox(height: 22),
                for (var index = 0; index < steps.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == steps.length - 1 ? 0 : 12,
                    ),
                    child: _OnboardingStep(
                      number: index + 1,
                      label: steps[index],
                    ),
                  ),
              ],
              if (primaryAction != null || secondaryAction != null) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (primaryAction != null && primaryLabel != null)
                      ElevatedButton.icon(
                        onPressed: primaryAction,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(primaryLabel!),
                      ),
                    if (secondaryAction != null && secondaryLabel != null)
                      OutlinedButton(
                        onPressed: secondaryAction,
                        child: Text(secondaryLabel!),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({required this.number, required this.label});

  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: NullFeedTheme.elevatedSurfaceColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: NullFeedTheme.primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.color = NullFeedTheme.primaryColor,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.55,
            ),
          ),
        ],
      ),
    );
  }
}
