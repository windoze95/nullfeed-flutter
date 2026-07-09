import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'adaptive_layout.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isLoading;

  /// Optional context that explains why the row exists or what tapping does.
  final String? subtitle;

  /// Optional labelled action at the end of the section heading.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// When non-null, renders an inline error state instead of [children].
  final String? errorText;

  /// Retry callback shown alongside [errorText].
  final VoidCallback? onRetry;

  const ContentRow({
    super.key,
    required this.title,
    required this.children,
    this.isLoading = false,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.errorText,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.contentPadding(context);
    // Give larger text extra metadata room without doubling the artwork too.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final rowHeight =
        AppConstants.contentRowHeight +
        (textScale > 1 ? (textScale - 1) * 76 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 30, padding, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  iconAlignment: IconAlignment.end,
                  label: Text(actionLabel!),
                ),
            ],
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: errorText != null
              ? _buildError(context, padding)
              : isLoading
              ? _buildShimmer(padding)
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  itemCount: children.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => children[index],
                ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: NullFeedTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 32,
              color: NullFeedTheme.errorColor,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                errorText!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer(double padding) {
    return Shimmer.fromColors(
      baseColor: NullFeedTheme.cardColor,
      highlightColor: NullFeedTheme.cardHoverColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: AppConstants.videoCardWidth,
          decoration: BoxDecoration(
            color: NullFeedTheme.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NullFeedTheme.borderColor),
          ),
        ),
      ),
    );
  }
}
