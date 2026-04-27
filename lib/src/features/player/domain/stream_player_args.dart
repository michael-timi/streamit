import 'package:equatable/equatable.dart';

/// Route extra for [StreamPlayerScreen].
class StreamPlayerArgs extends Equatable {
  const StreamPlayerArgs({
    required this.streamUrl,
    required this.title,
    this.logoUrl,
    this.referrer,
    this.userAgent,
  });

  final String streamUrl;
  final String title;
  final String? logoUrl;

  /// From IPTV Org `streams.json` when merged (HTTP `Referer`).
  final String? referrer;

  /// From IPTV Org `streams.json` when merged (HTTP `User-Agent`).
  final String? userAgent;

  @override
  List<Object?> get props => [streamUrl, title, logoUrl, referrer, userAgent];
}
