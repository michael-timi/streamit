import 'package:streamit/src/features/home/domain/entities/live_channel.dart';
import 'package:streamit/src/utils/utils.dart';

abstract class LiveChannelsRepository {
  FutureEither<List<LiveChannel>> fetchByCountry({
    required String countryCode,
    int limit = 100,
  });

  FutureEitherVoid clearCountryCache({
    required String countryCode,
  });

  /// Clears cached IPTV Org `streams.json` (merged Referer / User-Agent index).
  FutureEitherVoid clearStreamsApiCache();
}
