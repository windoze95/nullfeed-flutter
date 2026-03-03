import 'package:flutter/material.dart';
import '../providers/download_provider.dart';
import '../config/theme.dart';

class DownloadProgressIndicator extends StatelessWidget {
  final DownloadItem item;

  const DownloadProgressIndicator({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NullFeedTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.channelName,
                          style: const TextStyle(
                            color: NullFeedTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isComplete)
                    const Icon(
                      Icons.check_circle,
                      color: NullFeedTheme.successColor,
                      size: 24,
                    )
                  else
                    Text(
                      '${(item.progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: NullFeedTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
              if (!item.isComplete) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: item.progress.clamp(0.0, 1.0),
                    backgroundColor: NullFeedTheme.progressBackground,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      NullFeedTheme.progressForeground,
                    ),
                    minHeight: 4,
                  ),
                ),
                if (item.speed != null || item.eta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (item.speed != null)
                          Text(
                            item.speed!,
                            style: const TextStyle(
                              color: NullFeedTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        if (item.eta != null)
                          Text(
                            'ETA: ${item.eta}',
                            style: const TextStyle(
                              color: NullFeedTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
