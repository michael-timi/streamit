import 'package:streamit/src/imports/core_imports.dart';
import 'package:streamit/src/imports/packages_imports.dart';
import 'package:streamit/src/features/auth/presentation/providers/session_provider.dart';
import 'package:streamit/src/features/home/domain/entities/live_channel.dart';
import 'package:streamit/src/features/home/presentation/providers/live_channels_provider.dart';
import 'package:streamit/src/features/player/domain/stream_player_args.dart';
import 'package:streamit/src/services/url_launcher_service.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final SessionState session = ref.watch(sessionProvider);
    final user = session.user;

    final countryCode = ref.watch(selectedCountryCodeProvider);
    final countryInputController = useTextEditingController();
    useEffect(() {
      countryInputController.text = countryCode.toUpperCase();
      return null;
    }, [countryCode]);
    final channelsAsync = ref.watch(liveChannelsByCountryProvider(countryCode));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppTopBar(
        title: 'home.home_title'.tr(),
      ),
      body: SafeArea(
        child: channelsAsync.when(
          loading: () => const AppLoading(),
          error: (error, _) => AppErrorWidget(
            title: 'Failed to load channels',
            message: error.toString(),
            onRetry: () =>
                ref.invalidate(liveChannelsByCountryProvider(countryCode)),
          ),
          data: (channels) => _HomeChannelsView(
            userName: user?.name ?? user?.email ?? ('home.welcome_home'.tr()),
            subtitle: user?.email != null && user?.name != null
                ? user!.email
                : ('home.home_subtitle'.tr()),
            countryCode: countryCode,
            channels: channels,
            textTheme: textTheme,
            colorScheme: colorScheme,
            onCountryChanged: (value) {
              ref.read(selectedCountryCodeProvider.notifier).state = value;
              ref.read(selectedCategoryProvider.notifier).state = null;
            },
            countryInputController: countryInputController,
            onApplyCustomCountry: () {
              final rawValue = countryInputController.text.trim().toLowerCase();
              final isValidCountryCode =
                  RegExp(r'^[a-z]{2}$').hasMatch(rawValue);
              if (!isValidCountryCode) {
                showToast(
                  context,
                  message:
                      'Use a valid 2-letter country code (e.g. us, gb, in).',
                  status: 'warning',
                );
                return;
              }

              ref.read(selectedCountryCodeProvider.notifier).state = rawValue;
              ref.read(selectedCategoryProvider.notifier).state = null;
            },
            onHardRefresh: () async {
              final repository = ref.read(liveChannelsRepositoryProvider);
              final countryResult =
                  await repository.clearCountryCache(countryCode: countryCode);
              if (!context.mounted) return;
              final countryFailure =
                  countryResult.fold((failure) => failure, (_) => null);
              if (countryFailure != null) {
                showToast(
                  context,
                  message: countryFailure.message,
                  status: 'error',
                );
                return;
              }

              final streamsResult = await repository.clearStreamsApiCache();
              if (!context.mounted) return;
              streamsResult.fold(
                (failure) => showToast(
                  context,
                  message: failure.message,
                  status: 'error',
                ),
                (_) {
                  ref.invalidate(liveChannelsByCountryProvider(countryCode));
                  showToast(
                    context,
                    message:
                        'Hard refresh: playlist + streams API for ${countryCode.toUpperCase()}',
                    status: 'success',
                  );
                },
              );
            },
            selectedCategory: ref.watch(selectedCategoryProvider),
            onCategoryChanged: (value) {
              ref.read(selectedCategoryProvider.notifier).state = value;
            },
          ),
        ),
      ),
    );
  }
}

class _HomeChannelsView extends StatelessWidget {
  const _HomeChannelsView({
    required this.userName,
    required this.subtitle,
    required this.countryCode,
    required this.channels,
    required this.textTheme,
    required this.colorScheme,
    required this.onCountryChanged,
    required this.countryInputController,
    required this.onApplyCustomCountry,
    required this.onHardRefresh,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  final String userName;
  final String subtitle;
  final String countryCode;
  final List<LiveChannel> channels;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final ValueChanged<String> onCountryChanged;
  final TextEditingController countryInputController;
  final VoidCallback onApplyCustomCountry;
  final VoidCallback onHardRefresh;
  final String? selectedCategory;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final categories = channels
        .map((channel) => channel.groupTitle)
        .whereType<String>()
        .where((category) => category.trim().isNotEmpty)
        .map((category) => category.trim())
        .toSet()
        .toList()
      ..sort();

    final filteredChannels = selectedCategory == null
        ? channels
        : channels
            .where((channel) => channel.groupTitle == selectedCategory)
            .toList();

    if (channels.isEmpty) {
      return const AppEmptyState(
        title: 'No channels available',
        subtitle: 'Try a different country code or retry later.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(AppSpacing.xl.w),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _HeaderCard(
            userName: userName,
            subtitle: subtitle,
            channelsCount: filteredChannels.length,
            textTheme: textTheme,
            colorScheme: colorScheme,
            countryCode: countryCode,
            onCountryChanged: onCountryChanged,
            countryInputController: countryInputController,
            onApplyCustomCountry: onApplyCustomCountry,
            onHardRefresh: onHardRefresh,
            selectedCategory: selectedCategory,
            categories: categories,
            onCategoryChanged: onCategoryChanged,
          );
        }

        final channel = filteredChannels[index - 1];
        return _ChannelTile(channel: channel);
      },
      separatorBuilder: (_, __) => SizedBox(height: AppSpacing.md.h),
      itemCount: filteredChannels.length + 1,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.userName,
    required this.subtitle,
    required this.channelsCount,
    required this.textTheme,
    required this.colorScheme,
    required this.countryCode,
    required this.onCountryChanged,
    required this.countryInputController,
    required this.onApplyCustomCountry,
    required this.onHardRefresh,
    required this.selectedCategory,
    required this.categories,
    required this.onCategoryChanged,
  });

  final String userName;
  final String subtitle;
  final int channelsCount;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final String countryCode;
  final ValueChanged<String> onCountryChanged;
  final TextEditingController countryInputController;
  final VoidCallback onApplyCustomCountry;
  final VoidCallback onHardRefresh;
  final String? selectedCategory;
  final List<String> categories;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                size: 28.sp,
                color: colorScheme.primary,
              ),
              SizedBox(width: AppSpacing.md.w),
              Expanded(
                child: Text(
                  userName,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm.h),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: AppSpacing.md.h),
          Wrap(
            spacing: AppSpacing.sm.w,
            runSpacing: AppSpacing.sm.h,
            children: [
              _CountryChip(
                code: 'us',
                selected: countryCode == 'us',
                onTap: onCountryChanged,
              ),
              _CountryChip(
                code: 'gb',
                selected: countryCode == 'gb',
                onTap: onCountryChanged,
              ),
              _CountryChip(
                code: 'in',
                selected: countryCode == 'in',
                onTap: onCountryChanged,
              ),
              _CountryChip(
                code: 'fr',
                selected: countryCode == 'fr',
                onTap: onCountryChanged,
              ),
              _CountryChip(
                code: 'de',
                selected: countryCode == 'de',
                onTap: onCountryChanged,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md.h),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: countryInputController,
                  hint: 'Country code (e.g. us)',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onApplyCustomCountry(),
                ),
              ),
              SizedBox(width: AppSpacing.sm.w),
              AppButton(
                label: 'Apply',
                height: ButtonSize.small,
                onPressed: onApplyCustomCountry,
              ),
              SizedBox(width: AppSpacing.sm.w),
              AppButton(
                label: 'Hard Refresh',
                height: ButtonSize.small,
                variant: ButtonVariant.outline,
                onPressed: onHardRefresh,
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            SizedBox(height: AppSpacing.md.h),
            SizedBox(
              height: 38.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ChoiceChip(
                      label: const Text('All'),
                      selected: selectedCategory == null,
                      onSelected: (_) => onCategoryChanged(null),
                    );
                  }

                  final category = categories[index - 1];
                  return ChoiceChip(
                    label: Text(category),
                    selected: selectedCategory == category,
                    onSelected: (_) => onCategoryChanged(category),
                  );
                },
                separatorBuilder: (_, __) => SizedBox(width: AppSpacing.sm.w),
                itemCount: categories.length + 1,
              ),
            ),
          ],
          SizedBox(height: AppSpacing.md.h),
          Text(
            'Top $channelsCount IPTV Org channels (${countryCode.toUpperCase()})',
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(code.toUpperCase()),
      selected: selected,
      onSelected: (_) => onTap(code),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final tt = context.theme.textTheme;

    return AppCard(
      onTap: () {
        context.push(
          AppRoutes.player,
          extra: StreamPlayerArgs(
            streamUrl: channel.streamUrl,
            title: channel.name,
            logoUrl: channel.logoUrl,
            referrer: channel.referrer,
            userAgent: channel.userAgent,
          ),
        );
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: (channel.logoUrl?.isNotEmpty ?? false)
                ? AppCachedImage(
                    imageUrl: channel.logoUrl!,
                    width: 64,
                    height: 40,
                    fit: BoxFit.contain,
                    useSkeleton: false,
                  )
                : Container(
                    width: 64.w,
                    height: 40.h,
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.tv_rounded,
                      size: 18.sp,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (channel.groupTitle?.isNotEmpty ?? false) ...[
                  SizedBox(height: 2.h),
                  Text(
                    channel.groupTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm.w),
          IconButton(
            tooltip: 'Open externally',
            onPressed: () async {
              final result =
                  await UrlLauncherService.instance.launch(channel.streamUrl);
              if (context.mounted) {
                result.fold(
                  (failure) => showToast(
                    context,
                    message: failure.message,
                    status: 'error',
                  ),
                  (_) {},
                );
              }
            },
            icon: Icon(Icons.open_in_new_rounded, color: cs.primary),
          ),
        ],
      ),
    );
  }
}
