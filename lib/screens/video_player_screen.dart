import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../providers/video_provider.dart';
import '../services/api_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final api = ref.read(apiServiceProvider);
    final streamUrl = api.getVideoStreamUrl(widget.videoId);

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
    );

    await _controller!.initialize();

    // Seek to saved position
    try {
      final video = await api.getVideo(widget.videoId);
      if (video.watchPositionSeconds > 0) {
        await _controller!.seekTo(
          Duration(seconds: video.watchPositionSeconds),
        );
      }
    } catch (_) {
      // Continue playback from start if we can't load position
    }

    await _controller!.play();
    setState(() => _isInitialized = true);

    // Save progress periodically
    _progressTimer = Timer.periodic(
      const Duration(seconds: AppConstants.progressSaveIntervalSeconds),
      (_) => _saveProgress(),
    );

    _scheduleHideControls();
  }

  void _saveProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final position = _controller!.value.position.inSeconds;
    ref.read(videoProgressProvider(widget.videoId).notifier)
      ..setPosition(position)
      ..saveProgress();
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

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final current = _controller!.value.position;
    final target = current + Duration(seconds: seconds);
    _controller!.seekTo(target);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _saveProgress();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            if (_isInitialized && _controller != null)
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
                onBack: () => Navigator.of(context).pop(),
                onSeekRelative: _seekRelative,
                onInteraction: _scheduleHideControls,
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
  final VoidCallback onInteraction;

  const _ControlsOverlay({
    required this.controller,
    required this.onBack,
    required this.onSeekRelative,
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        value.isPlaying
                            ? controller.pause()
                            : controller.play();
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
