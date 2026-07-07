import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/video.dart';
import '../providers/queue_provider.dart';
import '../services/api_service.dart';
import 'unplayable_badge.dart';

/// Adds or removes [video] from the watch-later queue and reports the outcome
/// with a snackbar via the nearest [ScaffoldMessenger].
///
/// The queue updates optimistically inside the notifier, so the change is on
/// screen before this future completes; a failed server call rolls it back and
/// the snackbar surfaces the error instead.
Future<void> toggleVideoQueue(
  BuildContext context,
  WidgetRef ref,
  Video video,
) {
  return _applyToggle(
    ScaffoldMessenger.of(context),
    ref.read(queueProvider.notifier),
    video,
    wasQueued: ref.read(queueProvider).isQueued(video.id),
  );
}

Future<void> _applyToggle(
  ScaffoldMessengerState messenger,
  QueueNotifier notifier,
  Video video, {
  required bool wasQueued,
}) async {
  try {
    await (wasQueued ? notifier.remove(video.id) : notifier.add(video));
    messenger.showSnackBar(
      SnackBar(
        content: Text(wasQueued ? 'Removed from queue' : 'Added to queue'),
      ),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// A bottom-sheet row that toggles [video]'s queue membership; its label and
/// icon track the live queue state. Pass [onTap] to dismiss the surrounding
/// sheet — it runs first, before the (optimistic) toggle is applied.
class QueueActionTile extends ConsumerWidget {
  const QueueActionTile({super.key, required this.video, this.onTap});

  final Video video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isQueued = ref.watch(
      queueProvider.select((s) => s.isQueued(video.id)),
    );
    return ListTile(
      leading: Icon(isQueued ? Icons.playlist_add_check : Icons.playlist_add),
      title: Text(isQueued ? 'Remove from Queue' : 'Add to Queue'),
      onTap: () {
        // Capture everything that outlives this tile before the sheet pops —
        // the messenger and notifier survive the dismissal, the element does
        // not.
        final messenger = ScaffoldMessenger.of(context);
        final notifier = ref.read(queueProvider.notifier);
        final wasQueued = ref.read(queueProvider).isQueued(video.id);
        onTap?.call();
        unawaited(
          _applyToggle(messenger, notifier, video, wasQueued: wasQueued),
        );
      },
    );
  }
}

/// Shows the standard per-video actions sheet — an optional Play row, the queue
/// toggle, and an optional "Go to channel" row — for surfaces without a bespoke
/// menu of their own (video cards, search results).
Future<void> showVideoActionsSheet(
  BuildContext context, {
  required Video video,
  VoidCallback? onPlay,
  VoidCallback? onOpenChannel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: NullFeedTheme.cardColor,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              video.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NullFeedTheme.textMuted),
            ),
          ),
          if (video.activeUnplayableReason != null)
            UnplayableReasonTile(reason: video.activeUnplayableReason!),
          if (onPlay != null)
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(sheetContext);
                onPlay();
              },
            ),
          QueueActionTile(
            video: video,
            onTap: () => Navigator.pop(sheetContext),
          ),
          if (onOpenChannel != null)
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Go to channel'),
              onTap: () {
                Navigator.pop(sheetContext);
                onOpenChannel();
              },
            ),
        ],
      ),
    ),
  );
}
