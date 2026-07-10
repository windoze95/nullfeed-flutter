import 'package:flutter/widgets.dart';

// Platform-selected implementation. `better_player_plus` (iOS: native
// Picture-in-Picture + background audio) has no web support, so the web build
// resolves to the `video_player` implementation instead and never compiles it.
import 'nf_playback_web_impl.dart'
    if (dart.library.io) 'nf_playback_io_impl.dart'
    as impl;

/// A media source plus the metadata iOS shows on the lock screen / Control
/// Center ("Now Playing") while audio keeps playing in the background.
@immutable
class NfSource {
  /// A network URL, or an absolute on-device file path when [isFile] is true.
  final String url;
  final bool isFile;
  final String? title;
  final String? author;

  /// Thumbnail URL for the Now Playing artwork (network only).
  final String? imageUrl;

  const NfSource.network(this.url, {this.title, this.author, this.imageUrl})
    : isFile = false;

  const NfSource.file(this.url, {this.title, this.author, this.imageUrl})
    : isFile = true;
}

/// Platform-agnostic video playback surface used by the player screen.
///
/// Two implementations back this: `video_player` on web (and as the default),
/// and `better_player_plus` on iOS, which adds native Picture-in-Picture and
/// background audio. Construct one with [createNfPlaybackController].
///
/// It is a [ChangeNotifier]: listeners fire on every underlying playback tick
/// (position, buffering, play/pause, completion) so the controls overlay and
/// sponsor-skip logic stay live. Read state through the getters — the two
/// backends expose different value classes, so nothing else is shared.
abstract class NfPlaybackController extends ChangeNotifier {
  bool get isInitialized;
  bool get isPlaying;
  bool get isBuffering;

  /// True once playback has reached the end. On iOS this is synthesized from
  /// the player's `finished` event (its value object has no `isCompleted`).
  bool get isCompleted;

  Duration get position;

  /// Total duration, or [Duration.zero] until known.
  Duration get duration;

  /// Current playback speed (1.0 = normal).
  double get speed;

  /// Whether this device can show Picture-in-Picture (iPhone needs iOS 14+).
  /// Always false on web / non-iOS.
  Future<bool> isPipSupported();

  /// Start Picture-in-Picture now. No-op where unsupported.
  Future<void> enterPip();

  /// Leave Picture-in-Picture. No-op where unsupported.
  Future<void> exitPip();

  /// Load the source and complete once the video is initialized. Some
  /// progressive sources still report an unknown/zero duration at this point;
  /// callers must not treat that as a real upper bound. Throws if the source
  /// fails to load; callers bound this with a timeout and dispose on failure.
  Future<void> initialize();

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);

  /// Swap the media URL in place, preserving position and speed — the
  /// preview→HQ upgrade. On web this cross-fades a freshly-initialized
  /// controller; on iOS it uses the player's in-place source swap.
  Future<void> switchSource(String url);

  /// The video surface, letterboxed on black. The screen rebuilds after
  /// [switchSource] so a replaced surface re-renders.
  Widget buildView();
}

/// Creates the right [NfPlaybackController] for the current platform.
NfPlaybackController createNfPlaybackController(NfSource source) =>
    impl.createNfPlaybackController(source);
