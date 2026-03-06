import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import 'adaptive_layout.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isLoading;

  const ContentRow({
    super.key,
    required this.title,
    required this.children,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = AdaptiveLayout.isTv(context);
    final padding = AdaptiveLayout.contentPadding(context);
    final rowHeight = isTv
        ? AppConstants.tvContentRowHeight
        : AppConstants.contentRowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 24, padding, 12),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: rowHeight,
          child: isLoading
              ? _buildShimmer(padding)
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  itemCount: children.length,
                  separatorBuilder: (_, __) => SizedBox(width: isTv ? 20 : 12),
                  itemBuilder: (_, index) => children[index],
                ),
        ),
      ],
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
