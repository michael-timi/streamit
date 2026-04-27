import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamit/src/features/home/data/services/iptv_org_streams_index_loader.dart';
import 'package:streamit/src/features/home/domain/entities/live_channel.dart';
import 'package:streamit/src/features/home/domain/repositories/live_channels_repository.dart';
import 'package:streamit/src/utils/utils.dart';

class IptvOrgLiveChannelsRepository implements LiveChannelsRepository {
  IptvOrgLiveChannelsRepository({
    Dio? dio,
    IptvOrgStreamsIndexLoader? streamsIndexLoader,
  })  : _dio = dio ?? Dio(),
        _streamsIndexLoader = streamsIndexLoader ?? IptvOrgStreamsIndexLoader();

  final Dio _dio;
  final IptvOrgStreamsIndexLoader _streamsIndexLoader;

  @override
  FutureEither<List<LiveChannel>> fetchByCountry({
    required String countryCode,
    int limit = 100,
  }) {
    return runTask(() async {
      final normalizedCode = countryCode.trim().toLowerCase();
      final cacheKey = _cacheKey(normalizedCode);
      final cachedChannels = await _readCache(cacheKey);
      final playlistUrl =
          'https://iptv-org.github.io/iptv/countries/$normalizedCode.m3u';

      try {
        final response = await _dio.get<String>(
          playlistUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: <String, String>{'Accept': 'text/plain'},
          ),
        );

        final playlist = response.data ?? '';
        if (playlist.trim().isEmpty) {
          return <LiveChannel>[];
        }

        final parsed = _parseM3u(playlist, limit: limit);
        final channels = await _mergeStreamsApi(parsed);
        await _writeCache(cacheKey, channels);
        return channels;
      } on DioException {
        if (cachedChannels != null) {
          return cachedChannels.take(limit).toList();
        }
        rethrow;
      }
    });
  }

  @override
  FutureEitherVoid clearCountryCache({required String countryCode}) {
    return runTask(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey(countryCode.trim().toLowerCase()));
    });
  }

  @override
  FutureEitherVoid clearStreamsApiCache() {
    return runTask(() async {
      await _streamsIndexLoader.clearCache();
    });
  }

  Future<List<LiveChannel>> _mergeStreamsApi(List<LiveChannel> channels) async {
    if (channels.isEmpty) return channels;

    try {
      final index = await _streamsIndexLoader.load();
      return channels.map((channel) {
        final headers = lookupPlaybackHeaders(
          index,
          channel.streamUrl,
          channel.channelId,
        );
        if (headers == null) return channel;
        return channel.copyWith(
          referrer: headers.referrer,
          userAgent: headers.userAgent,
        );
      }).toList();
    } catch (_) {
      return channels;
    }
  }

  List<LiveChannel> _parseM3u(String content, {required int limit}) {
    final lines = content.split('\n');
    final channels = <LiveChannel>[];

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    String? currentChannelId;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        currentName = _extractName(line);
        currentLogo = _extractAttr(line, 'tvg-logo');
        currentGroup = _extractAttr(line, 'group-title');
        currentChannelId = _extractAttr(line, 'tvg-id');
        continue;
      }

      if (line.startsWith('#')) continue;

      final uri = Uri.tryParse(line);
      if (uri == null || !uri.hasScheme) continue;
      if (currentName == null || currentName.isEmpty) continue;

      channels.add(
        LiveChannel(
          name: currentName,
          streamUrl: line,
          logoUrl: (currentLogo?.isNotEmpty ?? false) ? currentLogo : null,
          groupTitle: (currentGroup?.isNotEmpty ?? false) ? currentGroup : null,
          channelId:
              (currentChannelId?.isNotEmpty ?? false) ? currentChannelId : null,
        ),
      );

      if (channels.length >= limit) break;
    }

    return channels;
  }

  String _extractName(String extInfLine) {
    final commaIndex = extInfLine.lastIndexOf(',');
    if (commaIndex == -1 || commaIndex == extInfLine.length - 1) {
      return 'Unknown Channel';
    }
    return extInfLine.substring(commaIndex + 1).trim();
  }

  String? _extractAttr(String extInfLine, String key) {
    final regex = RegExp('$key="([^"]*)"');
    final match = regex.firstMatch(extInfLine);
    return match?.group(1);
  }

  String _cacheKey(String countryCode) => 'iptv_channels_cache_$countryCode';

  Future<void> _writeCache(String key, List<LiveChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = channels
        .map(
          (channel) => <String, dynamic>{
            'name': channel.name,
            'streamUrl': channel.streamUrl,
            'logoUrl': channel.logoUrl,
            'groupTitle': channel.groupTitle,
            'channelId': channel.channelId,
            'referrer': channel.referrer,
            'userAgent': channel.userAgent,
          },
        )
        .toList();

    await prefs.setString(key, jsonEncode(payload));
  }

  Future<List<LiveChannel>?> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => LiveChannel(
            name: (item['name'] ?? '').toString(),
            streamUrl: (item['streamUrl'] ?? '').toString(),
            logoUrl: item['logoUrl']?.toString(),
            groupTitle: item['groupTitle']?.toString(),
            channelId: item['channelId']?.toString(),
            referrer: item['referrer']?.toString(),
            userAgent: item['userAgent']?.toString(),
          ),
        )
        .where((channel) =>
            channel.name.isNotEmpty && channel.streamUrl.isNotEmpty)
        .toList();
  }
}
