import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/video.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../services/websocket_service.dart';
import '../config/constants.dart';
import '../widgets/progress_bar.dart';

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
  bool _showControls = true;
  bool _isInitialized = false;
  bool _isPreviewMode = false;
  bool _isOfflinePlayback = false;
  bool _startingPlayback = false;
  bool _pendingHqSwitch = false;
  String? _error;
  late final ApiService _api;
  late final OfflineService _offline;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiServiceProvider);
    _offline = ref.read(offlineServiceProvider);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
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

    // Prefer the server's resume position (3s budget) but never block
    // playback on the network — fall back to the locally cached position.
    var resumeSeconds = _offline.getWatchPosition(widget.videoId);
    try {
      final video = await _api
          .getVideo(widget.videoId)
          .timeout(const Duration(seconds: 3));
      resumeSeconds = video.watchPositionSeconds;
    } catch (_) {
      // Offline or slow server — use the local position.
    }

    if (resumeSeconds > 0) {
      final resumePos = (resumeSeconds - 10).clamp(
        0,
        controller.value.duration.inSeconds,
      );
      await controller.seekTo(Duration(seconds: resumePos));
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

    // Rewind 10s on resume so user can re-orient
    if (video.watchPositionSeconds > 0) {
      final resumePos = (video.watchPositionSeconds - 10).clamp(
        0,
        video.durationSeconds,
      );
      await controller.seekTo(Duration(seconds: resumePos));
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
    });
    _startingPlayback = false;

    // An HQ-ready event may have arrived while the preview was initializing.
    if (isPreview && _pendingHqSwitch) {
      _pendingHqSwitch = false;
      unawaited(_switchToHq());
    }

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

    // Capture current position
    final currentPosition = _controller!.value.position;

    try {
      final streamUrl = _api.getVideoStreamUrl(widget.videoId);
      final hqController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
      );
      await hqController.initialize();
      await hqController.seekTo(currentPosition);
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

      Future.microtask(() {
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

  Future<void> _navigateBack() async {
    // Save progress before leaving, but never block navigation on a failure.
    try {
      await _saveProgress();
    } catch (_) {
      // Ignore — progress save is best-effort.
    }
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
    _previewTimeout?.cancel();
    _previewPollTimer?.cancel();
    // Save final position (fire-and-forget; a failed save must never throw
    // out of dispose).
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
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
    controller?.pause();
    controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                const Center(child: CircularProgressIndicator()),

              // Back button while waiting for the player to come up — the
              // controls overlay only exists once playback started.
              if (_error == null && !_isInitialized)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
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

              // Controls overlay
              if (_showControls && _isInitialized)
                _ControlsOverlay(
                  controller: _controller!,
                  onBack: _navigateBack,
                  onSeekRelative: _seekRelative,
                  onPlayPause: _togglePlayPause,
                  onInteraction: _scheduleHideControls,
                ),
            ],
          ),
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

  const _ControlsOverlay({
    required this.controller,
    required this.onBack,
    required this.onSeekRelative,
    required this.onPlayPause,
    required this.onInteraction,
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
                    onPressed: onBack,
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
                        onSeek: (fraction) {
                          final target = Duration(
                            milliseconds:
                                (fraction * duration.inMilliseconds).round(),
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
                            _formatDuration(position),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
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

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
