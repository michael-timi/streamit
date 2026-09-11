import 'package:equatable/equatable.dart';
import 'package:streamit/src/features/player/domain/playback_source.dart';

/// Route extra for [StreamPlayerScreen].
class StreamPlayerArgs extends Equatable {
  const StreamPlayerArgs({
    required this.streamUrl,
    required this.title,
    this.logoUrl,
    this.referrer,
    this.userAgent,
    this.additionalSources,
  });

  final String streamUrl;
  final String title;
  final String? logoUrl;

  /// From IPTV Org `streams.json` when merged (HTTP `Referer`).
  final String? referrer;

  /// From IPTV Org `streams.json` when merged (HTTP `User-Agent`).
  final String? userAgent;

  /// Extra IPTV Org API URLs for the same channel (after primary fails).
  final List<PlaybackSource>? additionalSources;

  @override
  List<Object?> get props =>
      [streamUrl, title, logoUrl, referrer, userAgent, additionalSources];
}
