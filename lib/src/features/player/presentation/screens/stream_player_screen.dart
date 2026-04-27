import 'package:flutter/material.dart';
import 'package:streamit/src/features/player/domain/stream_player_args.dart';
import 'package:streamit/src/imports/packages_imports.dart';
import 'package:streamit/src/shared/shared.dart';
import 'package:video_player/video_player.dart';

/// Full-screen live stream playback using [video_player].
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

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final uri = Uri.tryParse(widget.args.streamUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _initializing = false;
        _errorMessage = 'Invalid stream URL.';
      });
      return;
    }

    final httpHeaders = _buildHttpHeaders();
    final VideoPlayerController controller = httpHeaders == null
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.networkUrl(uri, httpHeaders: httpHeaders);
    setState(() {
      _controller = controller;
    });

    try {
      await controller.initialize();
      await controller.play();
      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Map<String, String>? _buildHttpHeaders() {
    final referrer = widget.args.referrer?.trim();
    final userAgent = widget.args.userAgent?.trim();
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

  Future<void> _retry() async {
    await _controller?.dispose();
    setState(() {
      _controller = null;
      _initializing = true;
      _errorMessage = null;
    });
    await _initPlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle:
            context.theme.textTheme.titleMedium?.copyWith(color: Colors.white),
        title: Text(
          widget.args.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_controller != null && _controller!.value.isInitialized)
            IconButton(
              tooltip: _controller!.value.isPlaying ? 'Pause' : 'Play',
              onPressed: () {
                setState(() {
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
                });
              },
              icon: Icon(
                _controller!.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context.theme.colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(),
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

    return Column(
      children: [
        if (widget.args.logoUrl?.isNotEmpty ?? false)
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
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md.w,
            vertical: AppSpacing.sm.h,
          ),
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: cs.primary,
              bufferedColor: cs.onSurface.withValues(alpha: 0.3),
              backgroundColor: cs.onSurface.withValues(alpha: 0.15),
            ),
          ),
        ),
      ],
    );
  }
}
