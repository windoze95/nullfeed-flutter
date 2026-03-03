import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_provider.dart';
import '../widgets/download_progress_indicator.dart';
import '../config/theme.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);

    final active = downloads.where((d) => !d.isComplete).toList();
    final completed = downloads.where((d) => d.isComplete).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Downloads'),
            backgroundColor: NullFeedTheme.backgroundColor,
            actions: [
              if (completed.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear completed',
                  onPressed: () =>
                      ref.read(downloadProvider.notifier).removeCompleted(),
                ),
            ],
          ),
          if (downloads.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.download_outlined,
                      size: 64,
                      color: NullFeedTheme.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No active downloads',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Downloads will appear here when new videos are being fetched.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (active.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Active',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = active[index];
                    return DownloadProgressIndicator(item: item);
                  },
                  childCount: active.length,
                ),
              ),
            ],
            if (completed.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Completed',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = completed[index];
                    return DownloadProgressIndicator(item: item);
                  },
                  childCount: completed.length,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
