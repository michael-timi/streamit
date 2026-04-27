import 'package:equatable/equatable.dart';

/// HTTP headers from IPTV Org [streams.json](https://iptv-org.github.io/api/streams.json).
class StreamPlaybackHeaders extends Equatable {
  const StreamPlaybackHeaders({
    this.referrer,
    this.userAgent,
  });

  final String? referrer;
  final String? userAgent;

  @override
  List<Object?> get props => [referrer, userAgent];
}
