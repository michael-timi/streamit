import 'package:equatable/equatable.dart';

/// A stream URL plus optional HTTP headers for [VideoPlayerController].
class PlaybackSource extends Equatable {
  const PlaybackSource({
    required this.streamUrl,
    this.referrer,
    this.userAgent,
  });

  final String streamUrl;
  final String? referrer;
  final String? userAgent;

  @override
  List<Object?> get props => [streamUrl, referrer, userAgent];
}
