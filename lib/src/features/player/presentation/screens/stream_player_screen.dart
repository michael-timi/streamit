import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart'
    hide MapExtension, TextDirection;
import 'package:streamit/src/features/player/domain/playback_source.dart';
import 'package:streamit/src/features/player/domain/stream_player_args.dart';
import 'package:streamit/src/imports/packages_imports.dart';
import 'package:streamit/src/shared/shared.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Long enough for poor networks while still bounded so fallbacks can run.
const Duration _kInitializeTimeout = Duration(seconds: 90);

/// After this much continuous buffering, nudge playback (helps some HLS stacks).
const Duration _kStallNudgeAfter = Duration(seconds: 38);

/// Show weak-connection guidance if still buffering past this point.
const Duration _kSlowNetworkHintAfter = Duration(seconds: 55);

/// Avoid infinite reconnect loops when the native player errors repeatedly.
const int _kMaxMidPlaybackRecoveries = 2;

/// Live stream playback using [video_player]: playback ladder, immersive
/// fullscreen, system volume controls, wake lock while playing, and share /
/// open / copy actions.
class StreamPlayerScreen extends StatefulWidget {
  const StreamPlayerScreen({
    super.key,
    required this.args,
  });

  final StreamPlayerArgs args;

  @override
  State<StreamPlayerScreen> createState() => _StreamPlayerScreenState();
}

class _StreamPlayerScreenState extends State<StreamPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  String? _errorMessage;
  bool _volumePluginAvailable = !kIsWeb;
  bool _wakelockPluginAvailable = true;

  bool _fullscreen = false;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  double _volume = 0.7;
  bool _playing = false;

  bool _wasBuffering = false;
  Timer? _stallNudgeTimer;
  Timer? _slowNetworkHintTimer;
  bool _showSlowNetworkBanner = false;

  bool _recoveringFromError = false;
  int _midPlaybackRecoveries = 0;

  @override
  void initState() {
    super.initState();
    _initVolumePluginSafely();
    _runPlaybackLadder();
  }

  void _initVolumePluginSafely() {
    if (kIsWeb) return;
    try {
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.addListener(_onSystemVolumeChanged);
      unawaited(_loadInitialVolume());
    } catch (e, st) {
      _volumePluginAvailable = false;
      AppLogger.warning('Volume plugin unavailable: $e');
      if (kDebugMode) AppLogger.error('Volume plugin detail', e, st);
    }
  }

  Future<void> _loadInitialVolume() async {
    try {
      final v = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  void _onSystemVolumeChanged(double value) {
    if (!mounted) return;
    setState(() => _volume = value.clamp(0.0, 1.0));
  }

  List<PlaybackSource> _orderedSources() {
    return <PlaybackSource>[
      PlaybackSource(
        streamUrl: widget.args.streamUrl,
        referrer: widget.args.referrer,
        userAgent: widget.args.userAgent,
      ),
      ...?widget.args.additionalSources,
    ];
  }

  /// Android: hint HLS for `.m3u8` so ExoPlayer picks the right pipeline sooner.
  VideoFormat? _hlsFormatHintForUri(Uri uri) {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final p = uri.path.toLowerCase();
    if (p.endsWith('.m3u8') || p.contains('.m3u8')) {
      return VideoFormat.hls;
    }
    return null;
  }

  VideoPlayerController _networkControllerFor(
    Uri uri,
    Map<String, String>? headers,
  ) {
    final hint = _hlsFormatHintForUri(uri);
    if (headers == null || headers.isEmpty) {
      return VideoPlayerController.networkUrl(uri, formatHint: hint);
    }
    return VideoPlayerController.networkUrl(
      uri,
      httpHeaders: headers,
      formatHint: hint,
    );
  }

  Future<void> _runPlaybackLadder() async {
    setState(() {
      _initializing = true;
      _errorMessage = null;
      _showSlowNetworkBanner = false;
    });

    final sources = _orderedSources();
    Object? lastError;
    var attemptIndex = 0;

    for (var s = 0; s < sources.length; s++) {
      final source = sources[s];
      final headerPasses = _httpHeaderPasses(source);

      for (var p = 0; p < headerPasses.length; p++) {
        final headers = headerPasses[p];
        attemptIndex += 1;

        await _disposeControllerQuietly();

        final uri = Uri.tryParse(source.streamUrl.trim());
        if (uri == null || !uri.hasScheme) {
          lastError = Exception('Invalid stream URL.');
          AppLogger.warning(
            'Playback ladder attempt $attemptIndex: bad URL ${source.streamUrl}',
          );
          continue;
        }

        try {
          final mode = _headerAttemptLabel(headers);
          AppLogger.info(
            'Playback ladder attempt $attemptIndex: host=${uri.host} mode=$mode',
          );

          final VideoPlayerController controller =
              _networkControllerFor(uri, headers);

          if (!mounted) {
            await controller.dispose();
            return;
          }

          setState(() {
            _controller = controller;
          });

          controller.addListener(_onPlaybackTick);
          try {
            await controller
                .initialize()
                .timeout(_kInitializeTimeout);
          } on TimeoutException catch (e, st) {
            AppLogger.warning(
              'Playback ladder attempt $attemptIndex: initialize timed out',
            );
            if (kDebugMode) AppLogger.error('Timeout detail', e, st);
            controller.removeListener(_onPlaybackTick);
            if (mounted) {
              setState(() => _controller = null);
            }
            await controller.dispose();
            lastError = TimeoutException(
              'Opening the stream timed out.',
              _kInitializeTimeout,
            );
            continue;
          }

          await controller.play();

          if (!mounted) {
            await controller.dispose();
            return;
          }

          AppLogger.success('Playback ladder succeeded on attempt $attemptIndex');
          _midPlaybackRecoveries = 0;
          setState(() {
            _initializing = false;
            _errorMessage = null;
          });
          _syncWakeLockAndPlaying();
          _scheduleHideControls();
          return;
        } catch (e, st) {
          lastError = e;
          AppLogger.warning(
            'Playback ladder attempt $attemptIndex failed: $e',
          );
          if (kDebugMode) {
            AppLogger.error('Playback detail', e, st);
          }
        }
      }
    }

    if (!mounted) return;
    await _setWakelockEnabled(false);
    setState(() {
      _initializing = false;
      _errorMessage = lastError != null
          ? _userFacingPlaybackError(lastError)
          : 'Playback failed after $attemptIndex attempts.';
    });
  }

  void _onBufferingStateChanged(bool buffering) {
    _stallNudgeTimer?.cancel();
    _slowNetworkHintTimer?.cancel();
    if (buffering) {
      _stallNudgeTimer = Timer(_kStallNudgeAfter, () async {
        if (!mounted) return;
        final c = _controller;
        if (c != null && c.value.isInitialized && c.value.isBuffering) {
          await _nudgeStalledPlayback();
        }
      });
      _slowNetworkHintTimer = Timer(_kSlowNetworkHintAfter, () {
        if (!mounted) return;
        final c = _controller;
        if (c != null && c.value.isInitialized && c.value.isBuffering) {
          setState(() => _showSlowNetworkBanner = true);
        }
      });
    } else if (_showSlowNetworkBanner) {
      setState(() => _showSlowNetworkBanner = false);
    }
  }

  Future<void> _nudgeStalledPlayback() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !mounted) return;
    try {
      AppLogger.info('Stall recovery: seekTo current position');
      final pos = c.value.position;
      await c.seekTo(pos);
      if (!mounted) return;
      if (!c.value.isPlaying) await c.play();
    } catch (e, st) {
      AppLogger.warning('Stall nudge failed: $e');
      if (kDebugMode) AppLogger.error('Stall nudge detail', e, st);
    }
  }

  Future<void> _maybeRecoverFromPlaybackError() async {
    if (_recoveringFromError || !mounted) return;
    if (_midPlaybackRecoveries >= _kMaxMidPlaybackRecoveries) return;
    _recoveringFromError = true;
    _midPlaybackRecoveries++;
    try {
      AppLogger.warning(
        'Playback player error; auto-recovery '
        '$_midPlaybackRecoveries/$_kMaxMidPlaybackRecoveries',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await _retry(resetRecoveryBudget: false);
    } finally {
      _recoveringFromError = false;
    }
  }

  void _onPlaybackTick() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    if (v.hasError && (v.errorDescription?.isNotEmpty ?? false)) {
      unawaited(_maybeRecoverFromPlaybackError());
      return;
    }

    if (!v.isInitialized) return;

    final buffering = v.isBuffering;
    if (buffering != _wasBuffering) {
      _wasBuffering = buffering;
      _onBufferingStateChanged(buffering);
      if (mounted) setState(() {});
    }

    final nowPlaying = v.isPlaying;
    if (nowPlaying != _playing) {
      _playing = nowPlaying;
      _syncWakeLockAndPlaying();
      if (mounted) setState(() {});
      if (nowPlaying) {
        _scheduleHideControls();
      } else {
        _hideControlsTimer?.cancel();
        if (mounted) setState(() => _controlsVisible = true);
      }
    }
  }

  void _syncWakeLockAndPlaying() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    unawaited(_setWakelockEnabled(c.value.isPlaying));
  }

  Future<void> _setWakelockEnabled(bool enabled) async {
    if (!_wakelockPluginAvailable) return;
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (e, st) {
      _wakelockPluginAvailable = false;
      AppLogger.warning('Wakelock plugin unavailable: $e');
      if (kDebugMode) AppLogger.error('Wakelock plugin detail', e, st);
    }
  }

  String _headerAttemptLabel(Map<String, String>? headers) {
    if (headers == null) return 'plain';
    if (_mapsEqual(headers, _defaultPlaybackHeaders())) return 'fallback_ua';
    if (_isReferrerPlusDefaultUa(headers)) return 'referrer_plus_fallback_ua';
    return 'merged';
  }

  bool _isReferrerPlusDefaultUa(Map<String, String> h) {
    final referer = h['Referer'];
    final ua = h['User-Agent'];
    if (referer == null || referer.isEmpty) return false;
    return ua == _defaultStreamUserAgent();
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  List<Map<String, String>?> _httpHeaderPasses(PlaybackSource source) {
    final full = _buildHttpHeadersMap(
      source.referrer?.trim(),
      source.userAgent?.trim(),
    );
    final fallbackUa = _defaultPlaybackHeaders();

    final passes = <Map<String, String>?>[];
    if (full != null && full.isNotEmpty) {
      passes.add(full);
      final ref = source.referrer?.trim();
      if (ref != null && ref.isNotEmpty) {
        final referrerPlusDefaultUa = <String, String>{
          'Referer': ref,
          'User-Agent': _defaultStreamUserAgent(),
        };
        if (!_mapsEqual(referrerPlusDefaultUa, full)) {
          passes.add(referrerPlusDefaultUa);
        }
      }
    }
    passes.add(fallbackUa);
    passes.add(null);
    return passes;
  }

  Map<String, String> _defaultPlaybackHeaders() {
    return <String, String>{
      'User-Agent': _defaultStreamUserAgent(),
    };
  }

  String _defaultStreamUserAgent() {
    if (PlatformInfo.isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 '
          'Mobile/15E148 Safari/604.1';
    }
    if (PlatformInfo.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  String _userFacingPlaybackError(Object error) {
    if (error is TimeoutException) {
      return 'This stream is taking too long to open on your network. '
          'Try again with a stronger connection, choose another channel, '
          'or open the link in an external player.';
    }
    final raw = error.toString();
    if (raw.contains('CoreMediaErrorDomain') ||
        raw.contains('-12884') ||
        raw.contains('resource unavailable')) {
      return 'This stream could not be opened. The link may be offline, '
          'geo-blocked, or blocked for in-app playback. Try another channel '
          'or use Open externally from the list.';
    }
    if (raw.contains('VideoError') || raw.contains('PlatformException')) {
      return 'Playback failed. The stream may be unsupported or unavailable '
          'on this device.';
    }
    if (raw.length > 280) {
      return '${raw.substring(0, 280)}…';
    }
    return raw;
  }

  Map<String, String>? _buildHttpHeadersMap(String? referrer, String? userAgent) {
    if ((referrer == null || referrer.isEmpty) &&
        (userAgent == null || userAgent.isEmpty)) {
      return null;
    }
    final headers = <String, String>{};
    if (referrer != null && referrer.isNotEmpty) {
      headers['Referer'] = referrer;
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }
    return headers.isEmpty ? null : headers;
  }

  Future<void> _disposeControllerQuietly() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onPlaybackTick);
      await c.dispose();
    }
  }

  Future<void> _retry({bool resetRecoveryBudget = true}) async {
    if (resetRecoveryBudget) {
      _midPlaybackRecoveries = 0;
    }
    _stallNudgeTimer?.cancel();
    _slowNetworkHintTimer?.cancel();
    await _setWakelockEnabled(false);
    await _disposeControllerQuietly();
    setState(() {
      _initializing = true;
      _errorMessage = null;
      _playing = false;
      _wasBuffering = false;
      _showSlowNetworkBanner = false;
    });
    await _runPlaybackLadder();
  }

  Future<void> _setFullscreen(bool value) async {
    setState(() => _fullscreen = value);
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _exitFullscreen() => _setFullscreen(false);

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    final c = _controller;
    if (!_controlsVisible || c == null || !c.value.isPlaying) return;
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _setVolumeLevel(double next) async {
    if (kIsWeb) return;
    final v = next.clamp(0.0, 1.0);
    try {
      await VolumeController.instance.setVolume(v);
      if (mounted) setState(() => _volume = v);
    } catch (_) {}
  }

  Future<void> _adjustVolume(double delta) =>
      _setVolumeLevel(_volume + delta);

  Future<void> _toggleMute() async {
    if (kIsWeb) return;
    try {
      final muted = await VolumeController.instance.isMuted();
      await VolumeController.instance.setMute(!muted);
      final v = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> _openExternalStream() async {
    final uri = Uri.tryParse(widget.args.streamUrl.trim());
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyStreamUrl() async {
    await Clipboard.setData(ClipboardData(text: widget.args.streamUrl));
    if (!mounted) return;
    showToast(context, message: 'player.copied'.tr(), status: 'success');
  }

  Future<void> _shareStream() async {
    await SharePlus.instance.share(
      ShareParams(
        text: widget.args.streamUrl,
        subject: widget.args.title,
      ),
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _stallNudgeTimer?.cancel();
    _slowNetworkHintTimer?.cancel();
    if (_volumePluginAvailable) {
      VolumeController.instance.removeListener();
    }
    unawaited(_setWakelockEnabled(false));
    unawaited(_disposeControllerQuietly());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _fullscreen) {
          await _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                iconTheme: const IconThemeData(color: Colors.white),
                titleTextStyle: context.theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
                title: Text(
                  widget.args.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  if (_controller != null && _controller!.value.isInitialized)
                    IconButton(
                      tooltip: _controller!.value.isPlaying
                          ? 'player.pause'.tr()
                          : 'player.play'.tr(),
                      onPressed: () async {
                        final c = _controller!;
                        if (c.value.isPlaying) {
                          await c.pause();
                        } else {
                          await c.play();
                        }
                        setState(() {});
                        _scheduleHideControls();
                      },
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  _PlayerPopupMenu(
                    onShare: _shareStream,
                    onOpenExternal: _openExternalStream,
                    onCopyUrl: _copyStreamUrl,
                  ),
                ],
              ),
        body: SafeArea(
          top: !_fullscreen,
          bottom: !_fullscreen,
          child: _buildBody(cs),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_initializing) {
      return Padding(
        padding: EdgeInsets.all(AppSpacing.xl.w),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: AppSpacing.lg.h),
              Text(
                'player.connecting'.tr(),
                textAlign: TextAlign.center,
                style: context.theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: AppSpacing.sm.h),
              Text(
                'player.slow_network_detail'.tr(),
                textAlign: TextAlign.center,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return AppErrorWidget(
        title: 'Playback failed',
        message: _errorMessage,
        onRetry: _retry,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return AppErrorWidget(
        title: 'Playback unavailable',
        message: 'The video could not be prepared.',
        onRetry: _retry,
      );
    }

    final ar = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              if (!_fullscreen &&
                  (widget.args.logoUrl?.isNotEmpty ?? false))
                Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                  child: AppCachedImage(
                    imageUrl: widget.args.logoUrl!,
                    height: 48,
                    fit: BoxFit.contain,
                    useSkeleton: false,
                  ),
                ),
              Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: ar,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(controller),
                          if (controller.value.isBuffering &&
                              controller.value.isInitialized)
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.38),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                    SizedBox(height: AppSpacing.md.h),
                                    Text(
                                      'player.buffering'.tr(),
                                      style: context.theme.textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_showSlowNetworkBanner && !_fullscreen)
                Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm.h),
                  child: Material(
                    color: const Color(0xCC8B4513),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md.w,
                        vertical: AppSpacing.sm.h,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_find_rounded,
                            color: Colors.white,
                            size: 22.sp,
                          ),
                          SizedBox(width: AppSpacing.sm.w),
                          Expanded(
                            child: Text(
                              'player.weak_connection'.tr(),
                              style: context.theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _retry(resetRecoveryBudget: true),
                            child: Text(
                              'player.refresh_stream'.tr(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_fullscreen && _controlsVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm.w,
                      vertical: AppSpacing.xs.h,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () async {
                            await _exitFullscreen();
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                        ),
                        Expanded(
                          child: Text(
                            widget.args.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                        if (_controller != null &&
                            _controller!.value.isInitialized)
                          IconButton(
                            tooltip: _controller!.value.isPlaying
                                ? 'player.pause'.tr()
                                : 'player.play'.tr(),
                            color: Colors.white,
                            onPressed: () async {
                              final c = _controller!;
                              if (c.value.isPlaying) {
                                await c.pause();
                              } else {
                                await c.play();
                              }
                              setState(() {});
                              _scheduleHideControls();
                            },
                            icon: Icon(
                              _controller!.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        _PlayerPopupMenu(
                          iconColor: Colors.white,
                          onShare: _shareStream,
                          onOpenExternal: _openExternalStream,
                          onCopyUrl: _copyStreamUrl,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _controlsVisible
                  ? Material(
                      key: const ValueKey('panel'),
                      color: Colors.transparent,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xE6000000),
                              Color(0x66000000),
                              Color(0x00000000),
                            ],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.md.w,
                              AppSpacing.lg.h,
                              AppSpacing.md.w,
                              AppSpacing.sm.h,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: _controller!.value.isPlaying
                                          ? 'player.pause'.tr()
                                          : 'player.play'.tr(),
                                      onPressed: () async {
                                        final c = _controller!;
                                        if (c.value.isPlaying) {
                                          await c.pause();
                                        } else {
                                          await c.play();
                                        }
                                        setState(() {});
                                        _scheduleHideControls();
                                      },
                                      icon: Icon(
                                        _controller!.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                    SizedBox(width: AppSpacing.sm.w),
                                    Expanded(
                                      child: VideoProgressIndicator(
                                        controller,
                                        allowScrubbing: true,
                                        colors: VideoProgressColors(
                                          playedColor: cs.primary,
                                          bufferedColor: cs.onSurface
                                              .withValues(alpha: 0.35),
                                          backgroundColor: cs.onSurface
                                              .withValues(alpha: 0.2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: AppSpacing.sm.w),
                                    IconButton(
                                      tooltip: _fullscreen
                                          ? 'player.fullscreen_exit'.tr()
                                          : 'player.fullscreen_enter'.tr(),
                                      onPressed: () async {
                                        await _setFullscreen(!_fullscreen);
                                        if (mounted) {
                                          setState(() => _controlsVisible = true);
                                        }
                                      },
                                      icon: Icon(
                                        _fullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_volumePluginAvailable) ...[
                                  SizedBox(height: AppSpacing.sm.h),
                                  Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'player.mute'.tr(),
                                        onPressed: _toggleMute,
                                        icon: Icon(
                                          _volume <= 0.001
                                              ? Icons.volume_off_rounded
                                              : Icons.volume_up_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'player.volume_down'.tr(),
                                        onPressed: () =>
                                            _adjustVolume(-0.06),
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                            trackHeight: 3,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                              enabledThumbRadius: 8,
                                            ),
                                          ),
                                          child: Slider(
                                            value: _volume.clamp(0.0, 1.0),
                                            activeColor: cs.primary,
                                            inactiveColor: Colors.white24,
                                            onChanged: _setVolumeLevel,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'player.volume_up'.tr(),
                                        onPressed: () =>
                                            _adjustVolume(0.06),
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : GestureDetector(
                      key: const ValueKey('thin'),
                      onTap: _toggleControls,
                      child: Container(
                        color: Colors.transparent,
                        padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: cs.primary,
                            bufferedColor:
                                cs.onSurface.withValues(alpha: 0.35),
                            backgroundColor:
                                cs.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerPopupMenu extends StatelessWidget {
  const _PlayerPopupMenu({
    required this.onShare,
    required this.onOpenExternal,
    required this.onCopyUrl,
    this.iconColor,
  });

  final VoidCallback onShare;
  final VoidCallback onOpenExternal;
  final VoidCallback onCopyUrl;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'player.more'.tr(),
      icon: Icon(Icons.more_vert_rounded, color: iconColor ?? Colors.white),
      color: context.theme.colorScheme.surfaceContainerHigh,
      onSelected: (value) {
        switch (value) {
          case 'share':
            onShare();
          case 'external':
            onOpenExternal();
          case 'copy':
            onCopyUrl();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: const Icon(Icons.share_rounded),
            title: Text('player.share_stream'.tr()),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'external',
          child: ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text('player.open_externally'.tr()),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text('player.copy_url'.tr()),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
