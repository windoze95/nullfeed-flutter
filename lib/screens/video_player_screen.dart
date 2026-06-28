import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/video.dart';
import '../providers/queue_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../services/websocket_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../widgets/progress_bar.dart';
import '../widgets/queue_action.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  Timer? _previewTimeout;
  Timer? _previewPollTimer;
  Timer? _previewMaxWait;
  bool _showControls = true;
  bool _isInitialized = false;
  bool _isPreviewMode = false;
  bool _isOfflinePlayback = false;
  bool _startingPlayback = false;
  bool _pendingHqSwitch = false;
  bool _progressSavedOnExit = false;

  /// When playback resumed from a saved position, the position (in seconds) the
  /// viewer left off at — surfaced in the dismissible "Resuming at …" banner so
  /// they can jump back to the start. Null when starting from the top.
  int? _resumeFromSeconds;
  bool _showResumeBanner = false;
  Timer? _resumeBannerTimer;

  /// Set once auto-advance has fired so a stream of post-completion ticks can't
  /// trigger it again.
  bool _advancing = false;

  /// The loaded video, once known. Backs the Add/Remove-from-Queue control and
  /// the auto-advance bookkeeping. Null until the metadata fetch lands (it may
  /// stay null for offline playback when the server is unreachable).
  Video? _video;

  String? _error;
  late final ApiService _api;
  late final OfflineService _offline;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiServiceProvider);
    _offline = ref.read(offlineServiceProvider);
    _applyImmersiveMode();
    // Auto-advance replaces this route with the next player in the same frame,
    // which disposes the previous player — and its dispose() resets the system
    // UI to edge-to-edge / all-orientations. Re-assert after the frame so the
    // incoming player always wins that race.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyImmersiveMode();
    });
    _initPlayer();
  }

  void _applyImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initPlayer() async {
    try {
      // Path 0: Offline — play the local file without requiring network.
      if (_offline.isAvailableOffline(widget.videoId)) {
        final localPath = _offline.getLocalPath(widget.videoId);
        if (localPath != null) {
          await _startOfflinePlayback(localPath);
          return;
        }
      }

      final video = await _api.getVideo(widget.videoId);

      // Path 1: HQ complete — play directly
      if (video.status == VideoStatus.complete) {
        final streamUrl = _api.getVideoStreamUrl(widget.videoId);
        await _startPlayback(streamUrl, video);
        return;
      }

      // Path 2: Preview already ready — play preview, listen for HQ
      if (video.hasPreviewReady) {
        final previewUrl = _api.getPreviewStreamUrl(widget.videoId);
        await _startPlayback(previewUrl, video, isPreview: true);
        _listenForHqReady();
        return;
      }

      // Path 3: No preview yet — request one, show spinner, listen for it
      try {
        await _api.requestPreview(widget.videoId);
      } catch (_) {
        // Preview request may fail; continue listening anyway
      }
      _listenForPreviewReady(video);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
    }
  }

  Future<void> _startOfflinePlayback(String localPath) async {
    final controller = VideoPlayerController.file(File(localPath));
    try {
      await controller.initialize();
    } catch (e) {
      controller.dispose();
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
      return;
    }

    _isOfflinePlayback = true;
    controller.addListener(_onControllerUpdate);

    // Prefer the server's resume position (3s budget) but never block
    // playback on the network — fall back to the locally cached position.
    var resumeSeconds = _offline.getWatchPosition(widget.videoId);
    var fullyWatched = false;
    try {
      final video = await _api
          .getVideo(widget.videoId)
          .timeout(const Duration(seconds: 3));
      _video = video;
      resumeSeconds = video.watchPositionSeconds;
      fullyWatched = video.isWatched;
    } catch (_) {
      // Offline or slow server — use the local position.
    }

    // Resume from the saved spot unless it's been fully watched (then start
    // over). A rewind gives the viewer a moment of context.
    if (resumeSeconds > 0 && !fullyWatched) {
      final resumePos = (resumeSeconds - AppConstants.skipBackwardSeconds)
          .clamp(0, controller.value.duration.inSeconds);
      await controller.seekTo(Duration(seconds: resumePos));
      _resumeFromSeconds = resumeSeconds;
    }

    await controller.play();

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _isInitialized = true;
    });
    // Playback has started — keep the screen awake until the player closes.
    unawaited(WakelockPlus.enable());

    _maybeShowResumeBanner();
    _startProgressTimer();
    _scheduleHideControls();
  }

  Future<void> _startPlayback(
    String url,
    Video video, {
    bool isPreview = false,
  }) async {
    // A WS event and a poll tick can race to start playback; only the first
    // caller proceeds (checked-and-set synchronously, before any await).
    if (_startingPlayback || _isInitialized) return;
    _startingPlayback = true;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
    } catch (e) {
      controller.dispose();
      _startingPlayback = false;
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
      return;
    }

    controller.addListener(_onControllerUpdate);

    // Resume from where the viewer left off (rewound a little so they can
    // re-orient). A fresh or fully-watched video starts from the top.
    if (video.canResume) {
      await controller.seekTo(Duration(seconds: video.resumeSeekSeconds));
      _resumeFromSeconds = video.watchPositionSeconds;
    }

    await controller.play();

    if (!mounted) {
      controller.dispose();
      _startingPlayback = false;
      return;
    }

    setState(() {
      _controller = controller;
      _isInitialized = true;
      _isPreviewMode = isPreview;
      _video = video;
    });
    _startingPlayback = false;
    // Playback has started — keep the screen awake until the player closes.
    unawaited(WakelockPlus.enable());

    // An HQ-ready event may have arrived while the preview was initializing.
    if (isPreview && _pendingHqSwitch) {
      _pendingHqSwitch = false;
      unawaited(_switchToHq());
    }

    _maybeShowResumeBanner();
    _startProgressTimer();
    _scheduleHideControls();
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: AppConstants.progressSaveIntervalSeconds),
      (_) => _saveProgress(),
    );
  }

  void _listenForPreviewReady(Video video) {
    _wsSubscription?.cancel();
    final wsService = ref.read(webSocketServiceProvider);

    // After 90s without a preview keep the WS subscription alive but also
    // poll the API as a fallback in case the WebSocket event was missed.
    _previewTimeout?.cancel();
    _previewTimeout = Timer(const Duration(seconds: 90), () {
      if (!mounted || _isInitialized) return;
      _startPreviewPolling();
    });

    // Hard cap on the wait. If the preview never arrives, stop spinning forever
    // and surface a graceful message instead of leaving the user on a black
    // screen indefinitely.
    _previewMaxWait?.cancel();
    _previewMaxWait = Timer(
      const Duration(seconds: AppConstants.previewMaxWaitSeconds),
      () {
        if (!mounted || _isInitialized) return;
        _stopWaiting();
        setState(() {
          _error =
              'This video is taking longer than expected to prepare. '
              'Please try again in a moment.';
        });
      },
    );

    _wsSubscription = wsService.events.listen((event) {
      if (event.type == WebSocketEventType.previewReady &&
          event.data['video_id'] == widget.videoId) {
        _stopWaiting();
        final previewUrl = _api.getPreviewStreamUrl(widget.videoId);
        _startPlayback(previewUrl, video, isPreview: true);
        _listenForHqReady();
      } else if (event.type == WebSocketEventType.downloadComplete &&
          event.data['video_id'] == widget.videoId) {
        // HQ finished before preview — play HQ directly
        _stopWaiting();
        final streamUrl = _api.getVideoStreamUrl(widget.videoId);
        _startPlayback(streamUrl, video);
      }
    });
  }

  void _startPreviewPolling() {
    _previewPollTimer?.cancel();
    _previewPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _isInitialized) {
        _previewPollTimer?.cancel();
        _previewPollTimer = null;
        return;
      }
      try {
        final latest = await _api.getVideo(widget.videoId);
        if (!mounted || _isInitialized) return;
        if (latest.status == VideoStatus.complete) {
          _stopWaiting();
          await _startPlayback(_api.getVideoStreamUrl(widget.videoId), latest);
        } else if (latest.hasPreviewReady) {
          _stopWaiting();
          await _startPlayback(
            _api.getPreviewStreamUrl(widget.videoId),
            latest,
            isPreview: true,
          );
          _listenForHqReady();
        }
      } catch (_) {
        // Server unreachable — try again on the next tick.
      }
    });
  }

  void _stopWaiting() {
    _previewTimeout?.cancel();
    _previewTimeout = null;
    _previewPollTimer?.cancel();
    _previewPollTimer = null;
    _previewMaxWait?.cancel();
    _previewMaxWait = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
  }

  void _listenForHqReady() {
    _wsSubscription?.cancel();
    final wsService = ref.read(webSocketServiceProvider);
    _wsSubscription = wsService.events.listen((event) {
      if (event.type == WebSocketEventType.downloadComplete &&
          event.data['video_id'] == widget.videoId) {
        _wsSubscription?.cancel();
        _switchToHq();
      }
    });
  }

  Future<void> _switchToHq() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      // Preview is still initializing — queue the upgrade instead of
      // dropping it (the WS subscription is already cancelled by now).
      _pendingHqSwitch = true;
      return;
    }

    // Capture current position and the user's chosen speed so the upgrade is
    // seamless.
    final currentPosition = _controller!.value.position;
    final currentSpeed = _controller!.value.playbackSpeed;

    try {
      final streamUrl = _api.getVideoStreamUrl(widget.videoId);
      final hqController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
      );
      await hqController.initialize();
      hqController.addListener(_onControllerUpdate);
      await hqController.seekTo(currentPosition);
      await hqController.setPlaybackSpeed(currentSpeed);
      await hqController.play();

      if (!mounted) {
        hqController.dispose();
        return;
      }

      final oldController = _controller;
      setState(() {
        _controller = hqController;
        _isPreviewMode = false;
      });

      // Tear down the preview controller only after this frame has rendered
      // with the HQ controller — disposing it synchronously can leave the
      // outgoing VideoPlayer reading a disposed controller mid-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController?.removeListener(_onControllerUpdate);
        oldController?.pause();
        oldController?.dispose();
      });
    } catch (e) {
      // HQ switch failed — keep playing preview (silent fallback)
      debugPrint('HQ switch failed, continuing preview: $e');
    }
  }

  /// Saves the current position. Network failures are swallowed; when the
  /// video is also stored on this device the position is mirrored to Hive so
  /// offline resume keeps working.
  Future<void> _saveProgress() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final position = controller.value.position.inSeconds;
    if (position <= 0) return;

    if (_isOfflinePlayback) {
      unawaited(
        _offline.setWatchPosition(widget.videoId, position).catchError((_) {}),
      );
    }
    try {
      await _api.updateProgress(widget.videoId, position);
    } catch (_) {
      // Offline or server unreachable — retried on the next interval.
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  /// Surfaces the dismissible "Resuming at …" banner when playback picked up
  /// from a saved position. Auto-hides after a few seconds; [_restartFromStart]
  /// and [_dismissResumeBanner] retire it early.
  void _maybeShowResumeBanner() {
    if (_resumeFromSeconds == null) return;
    setState(() => _showResumeBanner = true);
    _resumeBannerTimer?.cancel();
    _resumeBannerTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showResumeBanner = false);
    });
  }

  /// Abandons the resumed position and plays from the top. Reached from the
  /// banner's "Start over" action.
  void _restartFromStart() {
    _resumeBannerTimer?.cancel();
    _controller?.seekTo(Duration.zero);
    setState(() {
      _showResumeBanner = false;
      _showControls = true;
    });
    _scheduleHideControls();
  }

  void _dismissResumeBanner() {
    _resumeBannerTimer?.cancel();
    setState(() => _showResumeBanner = false);
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      // Save on pause so progress isn't lost if the app gets killed.
      unawaited(_saveProgress());
    } else {
      _controller!.play();
    }
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  /// Controller listener that watches for end-of-video to drive queue
  /// auto-advance. It fires on every value change, so the actual work is
  /// guarded by [_advancing].
  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isCompleted) _handleCompletion();
  }

  /// When the video plays through to the end, advance into the queue: consume
  /// the finished video if it was queued, then play the next queued item.
  /// Stays put when there's nothing to advance to. Only end-of-video reaches
  /// here — manual back-out ([_navigateBack]) never auto-advances.
  void _handleCompletion() {
    if (_advancing) return;
    _advancing = true;

    final notifier = ref.read(queueProvider.notifier);
    // Capture the next target before consuming the finished video, so removal
    // can't shift it out from under us.
    final nextId = notifier.nextAfter(widget.videoId);
    final wasQueued = ref.read(queueProvider).isQueued(widget.videoId);

    // Watch-later semantics: a queued video that finishes is consumed.
    // Fire-and-forget — a failed removal must not block advancing.
    if (wasQueued) {
      unawaited(notifier.remove(widget.videoId).catchError((_) {}));
    }

    if (nextId == null) return; // Nothing queued after this — stay put.

    // Persist the finished video's final position before moving on; the exit
    // guard stops dispose() saving it a second time.
    _progressSavedOnExit = true;
    unawaited(_saveProgress());

    if (!mounted) return;
    context.pushReplacement('/player/$nextId');
  }

  void _toggleQueue() {
    final video = _video;
    if (video == null) return;
    unawaited(toggleVideoQueue(context, ref, video));
  }

  void _navigateBack() {
    // Fire-and-forget the final save so leaving is instant even on a slow or
    // dead network. The guard stops dispose() from saving a second time, so
    // teardown sends exactly one /progress PUT.
    _progressSavedOnExit = true;
    unawaited(_saveProgress());
    _controller?.pause();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    _controller!.seekTo(target);
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.mediaPlayPause:
        _togglePlayPause();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        _seekRelative(-AppConstants.skipBackwardSeconds);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        _seekRelative(AppConstants.skipForwardSeconds);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        _navigateBack();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        _toggleControls();
        return KeyEventResult.handled;

      default:
        if (!_showControls) {
          setState(() => _showControls = true);
          _scheduleHideControls();
        }
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _resumeBannerTimer?.cancel();
    _previewTimeout?.cancel();
    _previewPollTimer?.cancel();
    _previewMaxWait?.cancel();
    // Save final position (fire-and-forget; a failed save must never throw
    // out of dispose). Skipped when _navigateBack already fired the save on
    // the way out, so teardown sends exactly one /progress PUT.
    final controller = _controller;
    if (!_progressSavedOnExit &&
        controller != null &&
        controller.value.isInitialized) {
      final position = controller.value.position.inSeconds;
      if (position > 0) {
        if (_isOfflinePlayback) {
          unawaited(
            _offline
                .setWatchPosition(widget.videoId, position)
                .catchError((_) {}),
          );
        }
        unawaited(
          _api.updateProgress(widget.videoId, position).catchError((_) {}),
        );
      }
    }
    controller?.removeListener(_onControllerUpdate);
    controller?.pause();
    controller?.dispose();
    // Re-allow the screen to sleep now that playback is over.
    unawaited(WakelockPlus.disable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    // Drives the Add/Remove-from-Queue control; null hides it until the video
    // metadata is known.
    final isQueued = video == null
        ? null
        : ref.watch(queueProvider.select((s) => s.isQueued(video.id)));
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < screenWidth / 2) {
              _seekRelative(-AppConstants.skipBackwardSeconds);
            } else {
              _seekRelative(AppConstants.skipForwardSeconds);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _navigateBack,
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isInitialized && _controller != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Preparing your video…',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),

              // Buffering spinner while the player stalls mid-playback.
              if (_isInitialized && _controller != null)
                ValueListenableBuilder(
                  valueListenable: _controller!,
                  builder: (_, value, __) => value.isBuffering
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),

              // Back button while waiting for the player to come up — the
              // controls overlay only exists once playback started.
              if (_error == null && !_isInitialized)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back',
                      onPressed: _navigateBack,
                    ),
                  ),
                ),

              // 360p preview badge
              if (_isPreviewMode && _isInitialized)
                Positioned(
                  top: 16,
                  right: 16,
                  child: SafeArea(
                    child: Semantics(
                      label: 'Playing preview quality, 360p',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '360p',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Controls overlay
              if (_showControls && _isInitialized)
                _ControlsOverlay(
                  controller: _controller!,
                  onBack: _navigateBack,
                  onSeekRelative: _seekRelative,
                  onPlayPause: _togglePlayPause,
                  onInteraction: _scheduleHideControls,
                  isQueued: isQueued,
                  onToggleQueue: video == null ? null : _toggleQueue,
                ),

              // Resume affordance: playback auto-resumed from a saved position
              // (possibly set on another device) — offer a one-tap jump back to
              // the start. Sits above the controls so it stays tappable, and
              // clear of the back button / preview badge at the top corners.
              if (_showResumeBanner &&
                  _isInitialized &&
                  _resumeFromSeconds != null)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: _ResumeBanner(
                        position: Duration(seconds: _resumeFromSeconds!),
                        onRestart: _restartFromStart,
                        onDismiss: _dismissResumeBanner,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats a playback timestamp as M:SS, or H:MM:SS once it crosses an hour.
String _formatTimestamp(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Brief, dismissible banner shown when playback auto-resumed from a saved
/// position (which may have been set on another device). Reports where the
/// viewer left off and offers a one-tap jump back to the start; a close button
/// dismisses it, and the player also auto-hides it on a timer.
class _ResumeBanner extends StatelessWidget {
  final Duration position;
  final VoidCallback onRestart;
  final VoidCallback onDismiss;

  const _ResumeBanner({
    required this.position,
    required this.onRestart,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              'Resuming at ${_formatTimestamp(position)}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRestart,
              style: TextButton.styleFrom(
                foregroundColor: NullFeedTheme.primaryColor,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Start over'),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onBack;
  final void Function(int) onSeekRelative;
  final VoidCallback onPlayPause;
  final VoidCallback onInteraction;

  /// Whether the current video is in the watch-later queue. Null hides the
  /// queue control (the video isn't known yet).
  final bool? isQueued;
  final VoidCallback? onToggleQueue;

  const _ControlsOverlay({
    required this.controller,
    required this.onBack,
    required this.onSeekRelative,
    required this.onPlayPause,
    required this.onInteraction,
    this.isQueued,
    this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
            Colors.transparent,
            Colors.black54,
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  if (onToggleQueue != null)
                    IconButton(
                      icon: Icon(
                        (isQueued ?? false)
                            ? Icons.playlist_add_check
                            : Icons.playlist_add,
                        color: Colors.white,
                      ),
                      tooltip: (isQueued ?? false)
                          ? 'Remove from Queue'
                          : 'Add to Queue',
                      onPressed: () {
                        onToggleQueue!();
                        onInteraction();
                      },
                    ),
                  _SpeedButton(
                    controller: controller,
                    onInteraction: onInteraction,
                  ),
                ],
              ),
            ),
          ),

          // Center controls
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 48,
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    tooltip:
                        'Skip back ${AppConstants.skipBackwardSeconds} seconds',
                    onPressed: () {
                      onSeekRelative(-AppConstants.skipBackwardSeconds);
                      onInteraction();
                    },
                  ),
                  const SizedBox(width: 32),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (_, value, __) => IconButton(
                      iconSize: 64,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                      tooltip: value.isPlaying ? 'Pause' : 'Play',
                      onPressed: () {
                        onPlayPause();
                        onInteraction();
                      },
                    ),
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    iconSize: 48,
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    tooltip:
                        'Skip forward ${AppConstants.skipForwardSeconds} seconds',
                    onPressed: () {
                      onSeekRelative(AppConstants.skipForwardSeconds);
                      onInteraction();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom bar with progress
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8,
              ),
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, value, __) {
                  final position = value.position;
                  final duration = value.duration;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NullFeedProgressBar(
                        progress: duration.inMilliseconds > 0
                            ? position.inMilliseconds / duration.inMilliseconds
                            : 0,
                        height: 4,
                        semanticLabel: 'Video position',
                        semanticValueBuilder: (fraction) {
                          final at = Duration(
                            milliseconds: (fraction * duration.inMilliseconds)
                                .round(),
                          );
                          return '${_formatTimestamp(at)} of '
                              '${_formatTimestamp(duration)}';
                        },
                        onSeek: (fraction) {
                          final target = Duration(
                            milliseconds: (fraction * duration.inMilliseconds)
                                .round(),
                          );
                          controller.seekTo(target);
                          onInteraction();
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTimestamp(position),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatTimestamp(duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Playback-speed picker shown in the controls overlay. Reflects the
/// controller's current speed live and lets the viewer pick 0.5x–2x.
class _SpeedButton extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onInteraction;

  const _SpeedButton({required this.controller, required this.onInteraction});

  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String _label(double speed) {
    final value = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '${value}x';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (_, value, __) => PopupMenuButton<double>(
        tooltip: 'Playback speed',
        initialValue: value.playbackSpeed,
        color: NullFeedTheme.surfaceColor,
        onSelected: (speed) {
          controller.setPlaybackSpeed(speed);
          onInteraction();
        },
        itemBuilder: (_) => [
          for (final speed in _speeds)
            PopupMenuItem<double>(
              value: speed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 18,
                    color: value.playbackSpeed == speed
                        ? NullFeedTheme.primaryColor
                        : Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _label(speed),
                    style: const TextStyle(color: NullFeedTheme.textPrimary),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          // vertical: 12 keeps the tap target at the 44pt minimum (20pt icon +
          // 24pt padding).
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed, color: Colors.white, size: 20),
              const SizedBox(width: 4),
              Text(
                _label(value.playbackSpeed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
