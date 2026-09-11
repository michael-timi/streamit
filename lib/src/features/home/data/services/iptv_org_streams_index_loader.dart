import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamit/src/features/home/data/models/stream_api_entry.dart';
import 'package:streamit/src/features/home/data/models/stream_playback_headers.dart';
import 'package:streamit/src/features/home/data/models/streams_lookup_index.dart';

/// Downloads and caches IPTV Org `streams.json`, then builds lookup indexes.
class IptvOrgStreamsIndexLoader {
  IptvOrgStreamsIndexLoader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _apiUrl = 'https://iptv-org.github.io/api/streams.json';
  static const String _cacheFileName = 'iptv_org_streams.json';
  static const String _prefsTsKey = 'iptv_org_streams_cache_ts';
  static const Duration _ttl = Duration(hours: 24);

  Future<StreamsLookupIndex> load() async {
    final file = await _cacheFile();
    final prefs = await SharedPreferences.getInstance();
    final tsMillis = prefs.getInt(_prefsTsKey) ?? 0;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(tsMillis);
    final stale = tsMillis == 0 ||
        DateTime.now().difference(fetchedAt) > _ttl ||
        !await file.exists();

    if (stale) {
      await _downloadTo(file);
      await prefs.setInt(_prefsTsKey, DateTime.now().millisecondsSinceEpoch);
    }

    final raw = await file.readAsString();
    return compute(_parseStreamsJsonIsolate, raw);
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTsKey);
    final file = await _cacheFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<void> _downloadTo(File file) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await _dio.download(
      _apiUrl,
      file.path,
      options: Options(
        responseType: ResponseType.stream,
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
  }
}

/// Isolate entry: builds URL-key map (with normalized keys) + channel-id fallback map.
StreamsLookupIndex _parseStreamsJsonIsolate(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! List) {
    return const StreamsLookupIndex(
      byUrlKey: {},
      byChannelId: {},
      streamsByChannelId: {},
    );
  }

  final byUrlKey = <String, StreamPlaybackHeaders>{};
  final byChannelId = <String, StreamPlaybackHeaders>{};
  final streamsByChannelId = <String, List<StreamApiEntry>>{};

  for (final item in decoded) {
    if (item is! Map) continue;
    final row = Map<String, dynamic>.from(item);
    final url = row['url']?.toString();
    if (url == null || url.isEmpty) continue;

    final referrer = row['referrer']?.toString();
    final userAgent = row['user_agent']?.toString();

    final headers = StreamPlaybackHeaders(
      referrer: (referrer?.isNotEmpty ?? false) ? referrer : null,
      userAgent: (userAgent?.isNotEmpty ?? false) ? userAgent : null,
    );

    for (final key in streamUrlLookupKeys(url)) {
      byUrlKey[key] = headers;
    }

    final channel = row['channel']?.toString().trim();
    if (channel != null && channel.isNotEmpty) {
      byChannelId.putIfAbsent(channel, () => headers);
      streamsByChannelId.putIfAbsent(channel, () => []).add(
            StreamApiEntry(url: url.trim(), headers: headers),
          );
    }
  }

  return StreamsLookupIndex(
    byUrlKey: byUrlKey,
    byChannelId: byChannelId,
    streamsByChannelId: streamsByChannelId,
  );
}

/// Candidate URL strings for matching playlist URLs to API rows (order: cheap → thorough).
List<String> streamUrlLookupKeys(String raw) {
  final out = <String>[];
  final seen = <String>{};

  void add(String? s) {
    if (s == null) return;
    final t = s.trim();
    if (t.isEmpty) return;
    if (seen.add(t)) out.add(t);
  }

  add(raw);

  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) return out;

  add(parsed.toString());

  final noFragment = parsed.replace(fragment: '');
  add(noFragment.toString());

  Uri u = noFragment;
  if (u.host.isNotEmpty) {
    final lower = u.host.toLowerCase();
    if (lower != u.host) {
      u = u.replace(host: lower);
      add(u.toString());
    }
  }

  // Trailing slash variants (common mismatch between CDN configs).
  final path = u.path;
  if (path.length > 1 && path.endsWith('/')) {
    add(u.replace(path: path.substring(0, path.length - 1)).toString());
  } else if (path.isNotEmpty && !path.endsWith('/')) {
    add(u.replace(path: '$path/').toString());
  }

  return out;
}

/// Resolves playback headers: try normalized URL keys first, then IPTV Org channel id (M3U `tvg-id`).
StreamPlaybackHeaders? lookupPlaybackHeaders(
  StreamsLookupIndex index,
  String streamUrl,
  String? iptvOrgChannelId,
) {
  for (final key in streamUrlLookupKeys(streamUrl)) {
    final hit = index.byUrlKey[key];
    if (hit != null) return hit;
  }

  final id = iptvOrgChannelId?.trim();
  if (id != null && id.isNotEmpty) {
    return index.byChannelId[id];
  }

  return null;
}
