import 'package:streamit/src/features/home/data/models/stream_playback_headers.dart';

/// Result of parsing IPTV Org `streams.json`: URL-keyed lookup plus optional channel-id fallback.
class StreamsLookupIndex {
  const StreamsLookupIndex({
    required this.byUrlKey,
    required this.byChannelId,
  });

  /// Multiple normalized keys per logical URL → headers.
  final Map<String, StreamPlaybackHeaders> byUrlKey;

  /// First headers seen per IPTV Org channel id (`channel` field), for fallback matching.
  final Map<String, StreamPlaybackHeaders> byChannelId;
}
