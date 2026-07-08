import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/video.dart';
import '../providers/queue_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../services/playback/nf_playback_controller.dart';
import '../services/websocket_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../widgets/progress_bar.dart';
import '../widgets/queue_action.dart';
import '../widgets/unplayable_badge.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  NfPlaybackController? _player;

  /// Whether this device can show Picture-in-Picture (iPhone iOS 14+); gates the
  /// PiP button. Set once playback starts.
  bool _pipSupported = false;

  /// True while the video is fullscreen (device in landscape, or forced via the
  /// fullscreen button). Portrait is the normal windowed view.
  bool _isFullscreen = false;

  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  Timer? _previewTimeout;
  Timer? _previewPollTimer;
  Timer? _previewMaxWait;
  Timer? _hqPollTimer;
  bool _showControls = true;
  bool _isInitialized = false;
  bool _isPreviewMode = false;
  bool _isOfflinePlayback = false;
  bool _startingPlayback = false;
  bool _pendingHqSwitch = false;
  bool _switchingToHq = false;
  bool _progressSavedOnExit = false;

  /// When playback resumed from a saved position, the position (in seconds) the
  /// viewer left off at — surfaced in the dismissible "Resuming at …" banner so
  /// they can jump back to the start. Null when starting from the top.
  int? _resumeFromSeconds;
  bool _showResumeBanner = false;
  Timer? _resumeBannerTimer;

  /// Detected sponsor/ad segments (seconds); the playhead seeks past any it
  /// enters. Empty until loaded, or when there are none / detection is pending.
  List<({double start, double end})> _adSegments = const [];
  bool _showSkipToast = false;
  Timer? _skipToastTimer;

  /// Set once auto-advance has fired so a stream of post-completion ticks can't
  /// trigger it again.
  bool _advancing = false;

  /// The loaded video, once known. Backs the Add/Remove-from-Queue control and
  /// the auto-advance bookkeeping. Null until the metadata fetch lands (it may
  /// stay null for offline playback when the server is unreachable).
  Video? _video;

  String? _error;

  /// Why this video can't play (age-restricted, members-only, …), when the
  /// server has it labeled. Renders an explanatory screen with a "Try anyway"
  /// escape hatch instead of spinning through doomed stream attempts.
  UnplayableReason? _blockedReason;

  /// Set by "Try anyway": skip the [_blockedReason] gate for this screen so a
  /// stale label can heal (the backend clears it on a successful resolve).
  bool _ignoreUnplayableGate = false;

  late final ApiService _api;
  late final OfflineService _offline;
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  /// Separate, long-lived subscription used only to pick up sponsor segments
  /// that finish detecting after playback has already started (first play).
  StreamSubscription<WebSocketEvent>? _adWsSubscription;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiServiceProvider);
    _offline = ref.read(offlineServiceProvider);
    // Don't force fullscreen on start: open windowed and allow rotation, then
    // let orientation drive it — landscape is fullscreen, portrait is the normal
    // view (see _syncFullscreenToOrientation, called from didChangeDependencies,
    // which upgrades to immersive if we're already in landscape).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFullscreenToOrientation();
  }

  /// Fullscreen (immersive, status bar hidden) whenever the device is in
  /// landscape; a normal windowed view in portrait. Runs on every orientation
  /// change — so rotating the phone enters/exits fullscreen — and on the first
  /// build, so opening a video while already holding the phone in landscape
  /// starts fullscreen.
  void _syncFullscreenToOrientation() {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape == _isFullscreen) return;
    setState(() => _isFullscreen = isLandscape);
    SystemChrome.setEnabledSystemUIMode(
      isLandscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// The fullscreen button. Rotating the phone already toggles fullscreen; this
  /// covers holding the phone upright: from portrait it forces landscape
  /// (fullscreen), and from fullscreen it re-allows rotation (dropping back to
  /// portrait when the phone is held upright).
  void _toggleFullscreen() {
    SystemChrome.setPreferredOrientations(
      _isFullscreen
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    _scheduleHideControls();
  }

  /// After playback starts, ask the player whether this device supports PiP
  /// (iPhone needs iOS 14+) and surface the PiP control accordingly.
  void _checkPipSupport() {
    _player?.isPipSupported().then((supported) {
      if (mounted && supported != _pipSupported) {
        setState(() => _pipSupported = supported);
      }
    });
  }

  /// Builds the playback source for [url], attaching the video's title, channel
  /// and thumbnail so iOS can populate the lock-screen / Control Center "Now
  /// Playing" panel while audio plays in the background.
  NfSource _sourceFor(String url, Video? video, {required bool isFile}) {
    final title = video?.title;
    final author = (video != null && video.channelName.isNotEmpty)
        ? video.channelName
        : null;
    final youtubeId = video?.youtubeVideoId ?? '';
    final imageUrl = youtubeId.isNotEmpty
        ? 'https://img.youtube.com/vi/$youtubeId/mqdefault.jpg'
        : null;
    return isFile
        ? NfSource.file(url, title: title, author: author, imageUrl: imageUrl)
        : NfSource.network(
            url,
            title: title,
            author: author,
            imageUrl: imageUrl,
          );
  }

  /// "Try anyway" on the blocked screen: retry with the gate off. If YouTube
  /// now serves the video (cookies fixed, premiere aired) the server clears
  /// the label and playback just starts; otherwise the normal error/timeout
  /// paths report the failure.
  void _tryAnyway() {
    setState(() {
      _ignoreUnplayableGate = true;
      _blockedReason = null;
    });
    _initPlayer();
  }

  /// Full-screen explanation for a video YouTube refuses (age-restricted,
  /// members-only, …), replacing the generic failure the doomed stream
  /// attempts would eventually produce.
  Widget _buildBlockedView(UnplayableReason reason) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unplayableReasonIcon(reason),
              color: unplayableReasonColor(reason),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              reason.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                reason.description,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _tryAnyway,
                  child: const Text('Try anyway'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _navigateBack,
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initPlayer() async {
    try {
      // Path 0: Offline — play the local file without requiring network.
      // Skipped on web, which has no on-device files (and no dart:io File).
      if (!kIsWeb && _offline.isAvailableOffline(widget.videoId)) {
        final localPath = _offline.getLocalPath(widget.videoId);
        if (localPath != null) {
          await _startOfflinePlayback(localPath);
          return;
        }
      }

      final video = await _api.getVideo(widget.videoId);

      // A video the server knows YouTube refuses (age-restricted,
      // members-only, …) can't stream; explain instead of spinning through
      // doomed attempts. Local files (paths 0-2 below) are unaffected —
      // activeUnplayableReason is null whenever a playable file exists.
      if (!_ignoreUnplayableGate && video.activeUnplayableReason != null) {
        if (mounted) {
          setState(() {
            _video = video;
            _blockedReason = video.activeUnplayableReason;
          });
        }
        return;
      }

      // Path 1: HQ complete — play directly
      if (video.status == VideoStatus.complete) {
        final streamUrl = await _api.getVideoStreamUrl(widget.videoId);
        await _startPlayback(streamUrl, video);
        return;
      }

      // Path 2: Preview already ready — play preview, listen for HQ. A warmed
      // preview (prewarm) means nothing has enqueued the HQ download yet, so
      // request it — without this the HQ listener waits forever. Idempotent
      // and best-effort, like the instant-stream path below.
      if (video.hasPreviewReady) {
        unawaited(_api.cacheVideo(widget.videoId).catchError((_) {}));
        final previewUrl = await _api.getPreviewStreamUrl(widget.videoId);
        await _startPlayback(previewUrl, video, isPreview: true);
        _listenForHqReady();
        return;
      }

      // Path 3: Not downloaded yet — start instantly by proxying a progressive
      // source stream, then listen for an HQ download to swap in if one lands.
      // This replaces waiting for a preview file to be generated on a cold
      // press; the preview path below stays as a fallback.
      try {
        final instantUrl = await _api.getInstantStreamUrl(widget.videoId);
        if (await _startPlayback(
          instantUrl,
          video,
          isPreview: true,
          reportErrors: false,
        )) {
          // Cache the HQ version in the background (evictable, not a library
          // download) so the player can swap preview -> HQ. Best-effort.
          unawaited(_api.cacheVideo(widget.videoId).catchError((_) {}));
          _listenForHqReady();
          return;
        }
      } on ApiException {
        // Couldn't mint a ticket / reach the server — fall back to a preview.
      }

      // The failed instant attempt may have just taught the server why this
      // video can't stream (it classifies and stores the reason on a failed
      // resolve) — re-check, so the viewer gets the explanation instead of a
      // preview spinner doomed to time out the same way.
      if (!_ignoreUnplayableGate && !_isInitialized) {
        try {
          final refreshed = await _api.getVideo(widget.videoId);
          final reason = refreshed.activeUnplayableReason;
          if (reason != null) {
            if (mounted) {
              setState(() {
                _video = refreshed;
                _blockedReason = reason;
              });
            }
            return;
          }
        } on ApiException {
          // Server unreachable — continue to the preview fallback.
        }
      }

      // Fallback: request a preview, show spinner, and listen for it.
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
    final player = createNfPlaybackController(
      _sourceFor(localPath, _video, isFile: true),
    );
    try {
      await player.initialize();
    } catch (e) {
      player.dispose();
      if (mounted) {
        setState(() => _error = 'Failed to load video: $e');
      }
      return;
    }

    _isOfflinePlayback = true;
    player.addListener(_onPlayerUpdate);

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
          .clamp(0, player.duration.inSeconds);
      await player.seekTo(Duration(seconds: resumePos));
      _resumeFromSeconds = resumeSeconds;
    }

    await player.play();

    if (!mounted) {
      player.dispose();
      return;
    }

    setState(() {
      _player = player;
      _isInitialized = true;
    });
    // Playback has started — keep the screen awake until the player closes.
    unawaited(WakelockPlus.enable());
    _checkPipSupport();

    _maybeShowResumeBanner();
    _startProgressTimer();
    _scheduleHideControls();
  }

  /// Starts playback from [url]. Returns true once playback has started, false
  /// if it was superseded (a start race lost) or the source failed to load.
  /// When [reportErrors] is false a failure is returned silently without
  /// surfacing an error screen, so the caller can fall back to another source.
  Future<bool> _startPlayback(
    String url,
    Video video, {
    bool isPreview = false,
    bool reportErrors = true,
    Duration initTimeout = const Duration(
      seconds: AppConstants.playbackInitTimeoutSeconds,
    ),
  }) async {
    // A WS event and a poll tick can race to start playback; only the first
    // caller proceeds (checked-and-set synchronously, before any await).
    if (_startingPlayback || _isInitialized) return false;
    _startingPlayback = true;

    final player = createNfPlaybackController(
      _sourceFor(url, video, isFile: false),
    );

    try {
      // Bound init so a stalled source (e.g. a wedged instant-stream proxy)
      // can't leave the player spinning forever — on timeout we treat it as a
      // load failure so the caller can fall back / surface an error.
      await player.initialize().timeout(initTimeout);
    } catch (e) {
      player.dispose();
      _startingPlayback = false;
      if (mounted && reportErrors) {
        setState(() => _error = 'Failed to load video: $e');
      }
      return false;
    }

    player.addListener(_onPlayerUpdate);

    // Resume from where the viewer left off (rewound a little so they can
    // re-orient). A fresh or fully-watched video starts from the top.
    if (video.canResume) {
      await player.seekTo(Duration(seconds: video.resumeSeekSeconds));
      _resumeFromSeconds = video.watchPositionSeconds;
    }

    await player.play();

    if (!mounted) {
      player.dispose();
      _startingPlayback = false;
      return false;
    }

    setState(() {
      _player = player;
      _isInitialized = true;
      _isPreviewMode = isPreview;
      _video = video;
    });
    _startingPlayback = false;
    // Playback has started — keep the screen awake until the player closes.
    unawaited(WakelockPlus.enable());
    _checkPipSupport();

    // An HQ-ready event may have arrived while the preview was initializing.
    if (isPreview && _pendingHqSwitch) {
      _pendingHqSwitch = false;
      unawaited(_switchToHq());
    }

    _maybeShowResumeBanner();
    _startProgressTimer();
    _scheduleHideControls();
    unawaited(_loadAdSegments());
    return true;
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

    _wsSubscription = wsService.events.listen((event) async {
      if (event.type == WebSocketEventType.previewReady &&
          event.data['video_id'] == widget.videoId) {
        _stopWaiting();
        try {
          // The preview request alone never enqueues the HQ download — ask for
          // it here so the swap the HQ listener waits for can actually happen.
          unawaited(_api.cacheVideo(widget.videoId).catchError((_) {}));
          final previewUrl = await _api.getPreviewStreamUrl(widget.videoId);
          if (!mounted) return;
          // Fire-and-forget so the HQ listener is registered before the preview
          // finishes initializing — that's what lets an early HQ-ready event be
          // picked up via _pendingHqSwitch.
          _startPlayback(previewUrl, video, isPreview: true);
          _listenForHqReady();
        } on ApiException catch (e) {
          if (mounted) setState(() => _error = e.message);
        }
      } else if (event.type == WebSocketEventType.downloadComplete &&
          event.data['video_id'] == widget.videoId) {
        // HQ finished before preview — play HQ directly
        _stopWaiting();
        try {
          final streamUrl = await _api.getVideoStreamUrl(widget.videoId);
          if (!mounted) return;
          _startPlayback(streamUrl, video);
        } on ApiException catch (e) {
          if (mounted) setState(() => _error = e.message);
        }
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
          final streamUrl = await _api.getVideoStreamUrl(widget.videoId);
          await _startPlayback(streamUrl, latest);
        } else if (latest.hasPreviewReady) {
          _stopWaiting();
          // Same as the WS preview-ready path: enqueue the HQ download the
          // upcoming listener waits for.
          unawaited(_api.cacheVideo(widget.videoId).catchError((_) {}));
          final previewUrl = await _api.getPreviewStreamUrl(widget.videoId);
          await _startPlayback(previewUrl, latest, isPreview: true);
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

    // The download_complete event fires exactly once; a WS drop/reconnect at
    // the wrong moment would leave the preview playing for the whole session.
    // Poll slowly as a safety net (mirrors _startPreviewPolling).
    _hqPollTimer?.cancel();
    _hqPollTimer = Timer.periodic(
      const Duration(seconds: AppConstants.hqPollIntervalSeconds),
      (_) async {
        // Done: the swap already happened (or the screen is gone). While the
        // preview is still initializing (_isInitialized false) just keep
        // waiting — _pendingHqSwitch covers an early completion.
        if (!mounted || (_isInitialized && !_isPreviewMode)) {
          _hqPollTimer?.cancel();
          _hqPollTimer = null;
          return;
        }
        try {
          final latest = await _api.getVideo(widget.videoId);
          if (!mounted || (_isInitialized && !_isPreviewMode)) return;
          if (latest.status == VideoStatus.complete) {
            _wsSubscription?.cancel();
            await _switchToHq();
          }
        } catch (_) {
          // Server unreachable — try again on the next tick.
        }
      },
    );
  }

  Future<void> _switchToHq() async {
    if (_switchingToHq || (_isInitialized && !_isPreviewMode)) return;
    final player = _player;
    if (player == null || !player.isInitialized) {
      // Preview is still initializing — queue the upgrade instead of
      // dropping it (the WS subscription is already cancelled by now).
      _pendingHqSwitch = true;
      return;
    }
    _switchingToHq = true;

    try {
      final streamUrl = await _api.getVideoStreamUrl(widget.videoId);
      // The player swaps the source in place, preserving position and speed;
      // our listener stays attached across the swap.
      await player.switchSource(streamUrl);

      if (!mounted) return;

      _hqPollTimer?.cancel();
      _hqPollTimer = null;
      setState(() => _isPreviewMode = false);
    } catch (e) {
      // HQ switch failed — keep playing preview; the poll fallback retries
      // on its next tick.
      debugPrint('HQ switch failed, continuing preview: $e');
    } finally {
      _switchingToHq = false;
    }
  }

  /// Saves the current position. Network failures are swallowed; when the
  /// video is also stored on this device the position is mirrored to Hive so
  /// offline resume keeps working.
  Future<void> _saveProgress() async {
    final player = _player;
    if (player == null || !player.isInitialized) return;
    final position = player.position.inSeconds;
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
    _player?.seekTo(Duration.zero);
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
    final player = _player;
    if (player == null) return;
    if (player.isPlaying) {
      player.pause();
      // Save on pause so progress isn't lost if the app gets killed.
      unawaited(_saveProgress());
    } else {
      player.play();
    }
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  /// Enter Picture-in-Picture from the controls button. Unlike auto-PiP this
  /// fires while the app is foregrounded, so iOS reliably starts it.
  void _enterPipFromButton() {
    final player = _player;
    if (player == null) return;
    unawaited(player.enterPip());
    _scheduleHideControls();
  }

  /// Player listener that watches for end-of-video to drive queue auto-advance.
  /// It fires on every playback tick, so the actual work is guarded by
  /// [_advancing].
  void _onPlayerUpdate() {
    final player = _player;
    if (player == null || !player.isInitialized) return;
    _maybeSkipAd();
    if (player.isCompleted) _handleCompletion();
  }

  /// Seek past any sponsor segment the playhead has entered, flashing a brief
  /// "Skipped sponsor" toast. The 0.5s tail margin stops a seek to a segment's
  /// end from immediately re-triggering the same segment.
  void _maybeSkipAd() {
    final player = _player;
    if (player == null || _adSegments.isEmpty) return;
    final pos = player.position.inMilliseconds / 1000.0;
    for (final seg in _adSegments) {
      if (pos >= seg.start && pos < seg.end - 0.5) {
        player.seekTo(Duration(milliseconds: (seg.end * 1000).round()));
        _flashSkipToast();
        break;
      }
    }
  }

  /// Best-effort: fetch detected sponsor segments for this video. No skipping
  /// happens if detection is still pending, finds none, or is unavailable.
  Future<void> _loadAdSegments() async {
    try {
      final segments = await _api.getAdSegments(widget.videoId);
      if (!mounted) return;
      setState(() => _adSegments = segments);
      // None yet means detection is still running (first play). Apply them when
      // the backend signals they're ready so this session skips too.
      if (segments.isEmpty) _listenForAdSegmentsReady();
    } catch (_) {
      // Best-effort; leave _adSegments empty.
    }
  }

  void _listenForAdSegmentsReady() {
    _adWsSubscription?.cancel();
    final wsService = ref.read(webSocketServiceProvider);
    _adWsSubscription = wsService.events.listen((event) async {
      if (event.type == WebSocketEventType.adSegmentsReady &&
          event.data['video_id'] == widget.videoId) {
        _adWsSubscription?.cancel();
        _adWsSubscription = null;
        try {
          final segments = await _api.getAdSegments(widget.videoId);
          if (mounted) setState(() => _adSegments = segments);
        } catch (_) {
          // Best-effort.
        }
      }
    });
  }

  void _flashSkipToast() {
    if (!mounted) return;
    if (!_showSkipToast) setState(() => _showSkipToast = true);
    _skipToastTimer?.cancel();
    _skipToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSkipToast = false);
    });
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
    _player?.pause();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _seekRelative(int seconds) {
    final player = _player;
    if (player == null) return;
    final target = player.position + Duration(seconds: seconds);
    player.seekTo(target);
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
    _adWsSubscription?.cancel();
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _resumeBannerTimer?.cancel();
    _skipToastTimer?.cancel();
    _previewTimeout?.cancel();
    _previewPollTimer?.cancel();
    _previewMaxWait?.cancel();
    _hqPollTimer?.cancel();
    // Save final position (fire-and-forget; a failed save must never throw
    // out of dispose). Skipped when _navigateBack already fired the save on
    // the way out, so teardown sends exactly one /progress PUT.
    final player = _player;
    if (!_progressSavedOnExit && player != null && player.isInitialized) {
      final position = player.position.inSeconds;
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
    player?.removeListener(_onPlayerUpdate);
    player?.dispose();
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
          // opaque so taps anywhere over the video (which passes pointers
          // through) reach onTap, not just where a child is hit.
          behavior: HitTestBehavior.opaque,
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
              if (_blockedReason != null)
                _buildBlockedView(_blockedReason!)
              else if (_error != null)
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
              else if (_isInitialized && _player != null)
                _player!.buildView()
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
              if (_isInitialized && _player != null)
                ListenableBuilder(
                  listenable: _player!,
                  builder: (_, __) => _player!.isBuffering
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),

              // Back button while waiting for the player to come up — the
              // controls overlay only exists once playback started.
              if (_error == null && _blockedReason == null && !_isInitialized)
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
                  player: _player!,
                  onBack: _navigateBack,
                  onSeekRelative: _seekRelative,
                  onPlayPause: _togglePlayPause,
                  onInteraction: _scheduleHideControls,
                  isQueued: isQueued,
                  onToggleQueue: video == null ? null : _toggleQueue,
                  onPip: _pipSupported ? _enterPipFromButton : null,
                  isFullscreen: _isFullscreen,
                  onFullscreen: _toggleFullscreen,
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

              // Sponsor-skip toast: shown briefly after auto-skipping a segment.
              if (_showSkipToast && _isInitialized)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Skipped sponsor',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
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
  final NfPlaybackController player;
  final VoidCallback onBack;
  final void Function(int) onSeekRelative;
  final VoidCallback onPlayPause;
  final VoidCallback onInteraction;

  /// Whether the current video is in the watch-later queue. Null hides the
  /// queue control (the video isn't known yet).
  final bool? isQueued;
  final VoidCallback? onToggleQueue;

  /// Enters Picture-in-Picture. Null hides the PiP control (unsupported device).
  final VoidCallback? onPip;

  /// Whether the video is currently fullscreen (picks the button's icon).
  final bool isFullscreen;

  /// Toggles fullscreen (forces landscape, or releases rotation).
  final VoidCallback onFullscreen;

  const _ControlsOverlay({
    required this.player,
    required this.onBack,
    required this.onSeekRelative,
    required this.onPlayPause,
    required this.onInteraction,
    required this.isFullscreen,
    required this.onFullscreen,
    this.isQueued,
    this.onToggleQueue,
    this.onPip,
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
                  if (onPip != null)
                    IconButton(
                      icon: const Icon(
                        Icons.picture_in_picture_alt,
                        color: Colors.white,
                      ),
                      tooltip: 'Picture in Picture',
                      onPressed: onPip,
                    ),
                  _SpeedButton(player: player, onInteraction: onInteraction),
                  IconButton(
                    icon: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                    onPressed: onFullscreen,
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
                  ListenableBuilder(
                    listenable: player,
                    builder: (_, __) => IconButton(
                      iconSize: 64,
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                      tooltip: player.isPlaying ? 'Pause' : 'Play',
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
              child: ListenableBuilder(
                listenable: player,
                builder: (_, __) {
                  final position = player.position;
                  final duration = player.duration;
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
                          player.seekTo(target);
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

/// Playback-speed picker shown in the controls overlay. Reflects the player's
/// current speed live and lets the viewer pick 0.5x–2x.
class _SpeedButton extends StatelessWidget {
  final NfPlaybackController player;
  final VoidCallback onInteraction;

  const _SpeedButton({required this.player, required this.onInteraction});

  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String _label(double speed) {
    final value = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return '${value}x';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (_, __) => PopupMenuButton<double>(
        tooltip: 'Playback speed',
        initialValue: player.speed,
        color: NullFeedTheme.surfaceColor,
        onSelected: (speed) {
          player.setSpeed(speed);
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
                    color: player.speed == speed
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
                _label(player.speed),
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
