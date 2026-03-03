import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../config/constants.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(
          height: AppConstants.contentRowHeight,
          child: isLoading
              ? _buildShimmer()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: children.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => children[index],
                ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: NullFeedTheme.cardColor,
      highlightColor: NullFeedTheme.cardHoverColor,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
