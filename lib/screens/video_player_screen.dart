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
import '../config/theme.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/progress_bar.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  VideoPlayerController? _hqController;
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  bool _showControls = true;
  bool _isInitialized = false;
  bool _isPreviewMode = false;
  String? _error;
  late final ApiService _api;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiServiceProvider);
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTv = AdaptiveLayout.isTv(context);
    if (!isTv) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _initPlayer() async {
    try {
      // Path 0: Offline — play from local file
      final offlineService = ref.read(offlineServiceProvider);
      if (offlineService.isAvailableOffline(widget.videoId)) {
        final localPath = offlineService.getLocalPath(widget.videoId);
        if (localPath != null) {
          final controller = VideoPlayerController.file(File(localPath));
          await controller.initialize();

          // Resume from saved position if available
          final video = await _api.getVideo(widget.videoId);
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
            return;
          }

          setState(() {
            _controller = controller;
            _isInitialized = true;
          });

          _progressTimer?.cancel();
          _progressTimer = Timer.periodic(
            const Duration(seconds: AppConstants.progressSaveIntervalSeconds),
            (_) => _saveProgress(),
          );
          _scheduleHideControls();
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
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
    }
  }

  Future<void> _startPlayback(
    String url,
    Video video, {
    bool isPreview = false,
  }) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
    } catch (e) {
      controller.dispose();
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
      return;
    }

    setState(() {
      _controller = controller;
      _isInitialized = true;
      _isPreviewMode = isPreview;
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: AppConstants.progressSaveIntervalSeconds),
      (_) => _saveProgress(),
    );

    _scheduleHideControls();
  }

  void _listenForPreviewReady(Video video) {
    _wsSubscription?.cancel();
    final wsService = ref.read(webSocketServiceProvider);

    // Timeout after 30s if no preview arrives
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 30), () {
      _wsSubscription?.cancel();
      if (mounted && !_isInitialized) {
        setState(() => _error = 'Preview download timed out. Try again later.');
      }
    });

    _wsSubscription = wsService.events.listen((event) {
      if (event.type == WebSocketEventType.previewReady &&
          event.data['video_id'] == widget.videoId) {
        timeout?.cancel();
        _wsSubscription?.cancel();
        final previewUrl = _api.getPreviewStreamUrl(widget.videoId);
        _startPlayback(previewUrl, video, isPreview: true);
        _listenForHqReady();
      } else if (event.type == WebSocketEventType.downloadComplete &&
          event.data['video_id'] == widget.videoId) {
        // HQ finished before preview — play HQ directly
        timeout?.cancel();
        _wsSubscription?.cancel();
        final streamUrl = _api.getVideoStreamUrl(widget.videoId);
        _startPlayback(streamUrl, video);
      }
    });
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
    if (_controller == null || !_controller!.value.isInitialized) return;

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

      oldController?.pause();
      oldController?.dispose();
    } catch (e) {
      // HQ switch failed — keep playing preview (silent fallback)
      debugPrint('HQ switch failed, continuing preview: $e');
    }
  }

  void _saveProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final position = _controller!.value.position.inSeconds;
    if (position > 0) {
      _api.updateProgress(widget.videoId, position);
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
    } else {
      _controller!.play();
    }
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  Future<void> _navigateBack() async {
    // Save progress before leaving, then invalidate so lists refresh
    if (_controller != null && _controller!.value.isInitialized) {
      final position = _controller!.value.position.inSeconds;
      if (position > 0) {
        await _api.updateProgress(widget.videoId, position);
      }
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
    // Save final position directly (can't use ref after dispose)
    if (_controller != null && _controller!.value.isInitialized) {
      final position = _controller!.value.position.inSeconds;
      _api.updateProgress(widget.videoId, position);
    }
    _controller?.pause();
    _controller?.dispose();
    _hqController?.dispose();
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
    final isTv = AdaptiveLayout.isTv(context);

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
              padding: EdgeInsets.symmetric(horizontal: isTv ? 60.0 : 8.0),
              child: Row(
                children: [
                  if (!isTv)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onBack,
                    ),
                  if (isTv)
                    const Text(
                      'Press Menu to go back',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
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
                    iconSize: isTv ? 64 : 48,
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () {
                      onSeekRelative(-AppConstants.skipBackwardSeconds);
                      onInteraction();
                    },
                  ),
                  SizedBox(width: isTv ? 48 : 32),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (_, value, __) => IconButton(
                      iconSize: isTv ? 80 : 64,
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
                  SizedBox(width: isTv ? 48 : 32),
                  IconButton(
                    iconSize: isTv ? 64 : 48,
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
              padding: EdgeInsets.symmetric(
                horizontal: isTv ? 60.0 : 16.0,
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
                        height: isTv ? 6 : 4,
                        onSeek: isTv
                            ? null
                            : (fraction) {
                                final target = Duration(
                                  milliseconds:
                                      (fraction * duration.inMilliseconds)
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
                            _formatDuration(position),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isTv ? 16 : 12,
                            ),
                          ),
                          if (isTv)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_ios,
                                  color: NullFeedTheme.primaryColor,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Swipe to seek',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: NullFeedTheme.primaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isTv ? 16 : 12,
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
