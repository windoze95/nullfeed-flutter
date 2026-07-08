import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'nf_playback_controller.dart';

NfPlaybackController createNfPlaybackController(NfSource source) =>
    VideoPlayerNfController(source);

/// Web (and default) implementation backed by the official `video_player`.
///
/// Picture-in-Picture and background audio are iOS-only features handled by the
/// `better_player_plus` implementation; here they are no-ops. Web has no
/// on-device files, so only network sources are used.
class VideoPlayerNfController extends NfPlaybackController {
  VideoPlayerNfController(this._source);

  final NfSource _source;
  VideoPlayerController? _vp;

  VideoPlayerController _create(String url) =>
      VideoPlayerController.networkUrl(Uri.parse(url));

  @override
  Future<void> initialize() async {
    final controller = _create(_source.url);
    await controller.initialize();
    controller.addListener(_onValue);
    _vp = controller;
  }

  void _onValue() => notifyListeners();

  VideoPlayerValue? get _value => _vp?.value;

  @override
  bool get isInitialized => _value?.isInitialized ?? false;

  @override
  bool get isPlaying => _value?.isPlaying ?? false;

  @override
  bool get isBuffering => _value?.isBuffering ?? false;

  @override
  bool get isCompleted => _value?.isCompleted ?? false;

  @override
  Duration get position => _value?.position ?? Duration.zero;

  @override
  Duration get duration => _value?.duration ?? Duration.zero;

  @override
  double get speed => _value?.playbackSpeed ?? 1.0;

  @override
  Future<void> play() async => _vp?.play();

  @override
  Future<void> pause() async => _vp?.pause();

  @override
  Future<void> seekTo(Duration position) async => _vp?.seekTo(position);

  @override
  Future<void> setSpeed(double speed) async => _vp?.setPlaybackSpeed(speed);

  @override
  Future<void> switchSource(String url) async {
    final old = _vp;
    final currentPosition = old?.value.position ?? Duration.zero;
    final currentSpeed = old?.value.playbackSpeed ?? 1.0;
    final wasPlaying = old?.value.isPlaying ?? true;

    // Fully initialize the replacement before swapping so the cut is seamless.
    final next = _create(url);
    await next.initialize();
    await next.seekTo(currentPosition);
    await next.setPlaybackSpeed(currentSpeed);
    if (wasPlaying) await next.play();

    next.addListener(_onValue);
    _vp = next;
    notifyListeners();

    // Tear down the old controller after this frame so the outgoing VideoPlayer
    // isn't left reading a disposed controller mid-frame.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old
          ..removeListener(_onValue)
          ..pause()
          ..dispose();
      });
    }
  }

  @override
  Future<bool> isPipSupported() async => false;

  @override
  Future<void> enterPip() async {}

  @override
  Future<void> exitPip() async {}

  @override
  Widget buildView() {
    final controller = _vp;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  void dispose() {
    _vp
      ?..removeListener(_onValue)
      ..pause()
      ..dispose();
    super.dispose();
  }
}
