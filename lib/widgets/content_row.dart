import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'adaptive_layout.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isLoading;

  /// When non-null, renders an inline error state instead of [children].
  final String? errorText;

  /// Retry callback shown alongside [errorText].
  final VoidCallback? onRetry;

  const ContentRow({
    super.key,
    required this.title,
    required this.children,
    this.isLoading = false,
    this.errorText,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.contentPadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 24, padding, 12),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: AppConstants.contentRowHeight,
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
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
