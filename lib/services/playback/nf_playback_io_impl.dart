import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
// AspectRatioTypeIOS isn't re-exported by the package barrel; import it directly
// so PiP letterboxes (aspect-fit) rather than cropping (the config default is
// aspect-fill). The dependency is version-pinned, so this internal path is
// stable.
// ignore: implementation_imports
import 'package:better_player_plus/src/enum/aspect_enum.dart';
import 'package:flutter/widgets.dart';

import 'nf_playback_controller.dart';

NfPlaybackController createNfPlaybackController(NfSource source) =>
    BetterPlayerNfController(source);

/// iOS/Android implementation backed by `better_player_plus`.
///
/// It wraps a single [BetterPlayerController] with built-in controls disabled
/// (the screen renders its own overlay). Background audio + lock-screen controls
/// come from the data source's notification config; Picture-in-Picture is driven
/// through a [GlobalKey] shared with the [BetterPlayer] widget.
class BetterPlayerNfController extends NfPlaybackController {
  BetterPlayerNfController(this._source) {
    _controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoPlay: false,
        looping: false,
        fit: BoxFit.contain,
        // Letterbox rather than crop the PiP layer (default is aspect-fill).
        aspectRatioIOS: AspectRatioTypeIOS.aspect,
        expandToFill: true,
        allowedScreenSleep: false,
        // The screen owns lifecycle (background audio + manual PiP); combined
        // with showNotification this stops better_player pausing on background.
        handleLifecycle: false,
        // The screen owns the controller's lifetime.
        autoDispose: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
    );
    _controller.setBetterPlayerGlobalKey(_viewKey);
  }

  final NfSource _source;
  late final BetterPlayerController _controller;
  final GlobalKey _viewKey = GlobalKey();

  bool _initialized = false;

  /// better_player's value object has no `isCompleted`; track the end-of-video
  /// `finished` event instead, cleared when playback moves off the end.
  bool _completed = false;

  BetterPlayerDataSource _dataSourceFor(String url) => BetterPlayerDataSource(
    _source.isFile
        ? BetterPlayerDataSourceType.file
        : BetterPlayerDataSourceType.network,
    url,
    notificationConfiguration: BetterPlayerNotificationConfiguration(
      // Sets up the AVAudioSession + Now Playing / remote controls, which is
      // what keeps audio playing when the app is backgrounded or locked.
      showNotification: true,
      title: _source.title,
      author: _source.author,
      imageUrl: _source.imageUrl,
    ),
  );

  @override
  Future<void> initialize() async {
    // setupDataSource may resolve before or after the `initialized` event, so
    // wait for whichever comes second (and surface load failures as an error).
    final ready = Completer<void>();
    void onSetup(BetterPlayerEvent event) {
      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.initialized:
          if (!ready.isCompleted) ready.complete();
        case BetterPlayerEventType.exception:
          if (!ready.isCompleted) {
            ready.completeError(
              StateError('better_player failed to initialize the source'),
            );
          }
        default:
          break;
      }
    }

    _controller.addEventsListener(onSetup);
    try {
      await _controller.setupDataSource(_dataSourceFor(_source.url));
      if (!(_controller.isVideoInitialized() ?? false)) {
        await ready.future;
      }
    } finally {
      _controller.removeEventsListener(onSetup);
    }

    _initialized = true;
    _controller.videoPlayerController?.addListener(_onValue);
    _controller.addEventsListener(_onEvent);
  }

  void _onValue() => notifyListeners();

  void _onEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.finished:
        if (!_completed) {
          _completed = true;
          notifyListeners();
        }
      case BetterPlayerEventType.play:
      case BetterPlayerEventType.seekTo:
        if (_completed) {
          _completed = false;
          notifyListeners();
        }
      default:
        break;
    }
  }

  @override
  bool get isInitialized =>
      _initialized && (_controller.isVideoInitialized() ?? false);

  @override
  bool get isPlaying => _controller.isPlaying() ?? false;

  @override
  bool get isBuffering => _controller.isBuffering() ?? false;

  @override
  bool get isCompleted => _completed;

  @override
  Duration get position =>
      _controller.videoPlayerController?.value.position ?? Duration.zero;

  @override
  Duration get duration =>
      _controller.videoPlayerController?.value.duration ?? Duration.zero;

  @override
  double get speed => _controller.videoPlayerController?.value.speed ?? 1.0;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setSpeed(double speed) => _controller.setSpeed(speed);

  @override
  Future<void> switchSource(String url) async {
    // setResolution swaps the source in place and restores position + play state
    // but not speed, so capture and re-apply it.
    final currentSpeed = speed;
    await _controller.setResolution(url);
    if (currentSpeed != 1.0) await _controller.setSpeed(currentSpeed);
  }

  @override
  Future<bool> isPipSupported() => _controller.isPictureInPictureSupported();

  @override
  Future<void> enterPip() async {
    final future = _controller.enablePictureInPicture(_viewKey);
    if (future != null) await future;
  }

  @override
  Future<void> exitPip() async {
    final future = _controller.disablePictureInPicture();
    if (future != null) await future;
  }

  @override
  Widget buildView() =>
      // IgnorePointer so taps fall through to the screen's own GestureDetector
      // (BetterPlayer otherwise swallows them); our controls are a separate
      // overlay, and PiP uses native layers, so the video needs no gestures.
      IgnorePointer(
        child: BetterPlayer(controller: _controller, key: _viewKey),
      );

  @override
  void dispose() {
    _controller.videoPlayerController?.removeListener(_onValue);
    _controller.removeEventsListener(_onEvent);
    _controller.dispose(forceDispose: true);
    super.dispose();
  }
}
