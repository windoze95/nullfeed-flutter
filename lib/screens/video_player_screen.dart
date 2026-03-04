import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/video.dart';
import '../providers/video_provider.dart';
import '../services/api_service.dart';
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
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  bool _showControls = true;
  bool _isInitialized = false;
  String? _error;
  late final ApiService _api;

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
      final video = await _api.getVideo(widget.videoId);
      if (video.status != VideoStatus.complete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video is not downloaded yet')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      final streamUrl = _api.getVideoStreamUrl(widget.videoId);
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
      );

      await _controller!.initialize();

      // Rewind 10s on resume so user can re-orient
      if (video.watchPositionSeconds > 0) {
        final resumePos = (video.watchPositionSeconds - 10).clamp(0, video.durationSeconds);
        await _controller!.seekTo(
          Duration(seconds: resumePos),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
      return;
    }

    await _controller!.play();
    setState(() => _isInitialized = true);

    _progressTimer = Timer.periodic(
      const Duration(seconds: AppConstants.progressSaveIntervalSeconds),
      (_) => _saveProgress(),
    );

    _scheduleHideControls();
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
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    // Save final position directly (can't use ref after dispose)
    if (_controller != null && _controller!.value.isInitialized) {
      final position = _controller!.value.position.inSeconds;
      _api.updateProgress(widget.videoId, position);
    }
    _controller?.pause();
    _controller?.dispose();
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
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
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
              padding: EdgeInsets.symmetric(
                horizontal: isTv ? 60.0 : 8.0,
              ),
              child: Row(
                children: [
                  if (!isTv)
                    IconButton(
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white),
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
                    icon:
                        const Icon(Icons.forward_10, color: Colors.white),
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
                            ? position.inMilliseconds /
                                duration.inMilliseconds
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back_ios,
                                    color: NullFeedTheme.primaryColor,
                                    size: 14),
                                const SizedBox(width: 4),
                                const Text(
                                  'Swipe to seek',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios,
                                    color: NullFeedTheme.primaryColor,
                                    size: 14),
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
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
