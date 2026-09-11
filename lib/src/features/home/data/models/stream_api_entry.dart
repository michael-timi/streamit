import 'package:equatable/equatable.dart';
import 'package:streamit/src/features/home/data/models/stream_playback_headers.dart';

/// One IPTV Org `streams.json` row grouped by API channel id.
class StreamApiEntry extends Equatable {
  const StreamApiEntry({
    required this.url,
    required this.headers,
  });

  final String url;
  final StreamPlaybackHeaders headers;

  @override
  List<Object?> get props => [url, headers];
}
