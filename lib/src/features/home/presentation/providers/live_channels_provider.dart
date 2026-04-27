import 'package:streamit/src/features/home/data/repositories/iptv_org_live_channels_repository.dart';
import 'package:streamit/src/features/home/domain/entities/live_channel.dart';
import 'package:streamit/src/features/home/domain/repositories/live_channels_repository.dart';
import 'package:streamit/src/imports/packages_imports.dart';

final selectedCountryCodeProvider = StateProvider<String>((ref) => 'us');
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final liveChannelsRepositoryProvider = Provider<LiveChannelsRepository>((ref) {
  return IptvOrgLiveChannelsRepository();
});

final liveChannelsByCountryProvider =
    FutureProvider.family<List<LiveChannel>, String>((ref, countryCode) async {
  final repository = ref.watch(liveChannelsRepositoryProvider);
  final result =
      await repository.fetchByCountry(countryCode: countryCode, limit: 120);

  return result.fold(
    (failure) => throw Exception(failure.message),
    (channels) => channels,
  );
});
