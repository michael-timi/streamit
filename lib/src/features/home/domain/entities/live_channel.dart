import 'package:equatable/equatable.dart';

class LiveChannel extends Equatable {
  const LiveChannel({
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.groupTitle,
    this.channelId,
    this.referrer,
    this.userAgent,
  });

  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? groupTitle;

  /// IPTV Org channel id from M3U `tvg-id` (when present).
  final String? channelId;

  /// Optional playback headers merged from IPTV Org `streams.json`.
  final String? referrer;
  final String? userAgent;

  LiveChannel copyWith({
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? groupTitle,
    String? channelId,
    String? referrer,
    String? userAgent,
  }) {
    return LiveChannel(
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      groupTitle: groupTitle ?? this.groupTitle,
      channelId: channelId ?? this.channelId,
      referrer: referrer ?? this.referrer,
      userAgent: userAgent ?? this.userAgent,
    );
  }

  @override
  List<Object?> get props =>
      [name, streamUrl, logoUrl, groupTitle, channelId, referrer, userAgent];
}
