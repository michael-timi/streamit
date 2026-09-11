import 'package:streamit/src/imports/core_imports.dart';
import 'package:streamit/src/imports/packages_imports.dart';
import 'package:streamit/src/features/auth/presentation/providers/session_provider.dart';
import 'package:streamit/src/features/home/domain/entities/live_channel.dart';
import 'package:streamit/src/features/home/presentation/providers/live_channels_provider.dart';
import 'package:streamit/src/features/player/domain/playback_source.dart';
import 'package:streamit/src/features/player/domain/stream_player_args.dart';
import 'package:streamit/src/services/url_launcher_service.dart';

/// Playlist rows without `group-title` — filter sentinel (not a real M3U value).
const String _kCategoryUncategorized = '__streamit_uncategorized__';

bool _channelMatchesCategory(LiveChannel channel, String? selectedCategory) {
  if (selectedCategory == null) return true;
  final g = channel.groupTitle?.trim();
  if (selectedCategory == _kCategoryUncategorized) {
    return g == null || g.isEmpty;
  }
  return g == selectedCategory;
}

/// Sorted unique `group-title` values plus [uncategorized] when needed.
List<String> _categoryFilterIds(List<LiveChannel> channels) {
  final named = channels
      .map((c) => c.groupTitle?.trim())
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final hasUncategorized = channels.any(
    (c) =>
        c.groupTitle == null ||
        (c.groupTitle != null && c.groupTitle!.trim().isEmpty),
  );

  return <String>[
    if (hasUncategorized) _kCategoryUncategorized,
    ...named,
  ];
}

String _categoryChipDisplayLabel(String id) {
  if (id == _kCategoryUncategorized) {
    return 'home.category_uncategorized'.tr();
  }
  return id;
}

String _categorySelectionTitle(String? selectedCategory) {
  if (selectedCategory == null) {
    return 'home.all_categories'.tr();
  }
  return _categoryChipDisplayLabel(selectedCategory);
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final SessionState session = ref.watch(sessionProvider);
    final user = session.user;

    final countryCode = ref.watch(selectedCountryCodeProvider);
    final channelsAsync = ref.watch(liveChannelsByCountryProvider(countryCode));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppTopBar(
        title: 'home.home_title'.tr(),
        showLeading: false,
        actions: [
          IconButton(
            tooltip: 'settings.title'.tr(),
            onPressed: () => context.push(AppRoutes.homeSettings),
            icon: Icon(
              Icons.settings_outlined,
              color: colorScheme.onSurface,
            ),
          ),
        ],
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
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  final String userName;
  final String subtitle;
  final String countryCode;
  final List<LiveChannel> channels;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final String? selectedCategory;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final categoryIds = _categoryFilterIds(channels);
    final filteredChannels = channels
        .where((c) => _channelMatchesCategory(c, selectedCategory))
        .toList();

    if (channels.isEmpty) {
      return const AppEmptyState(
        title: 'No channels available',
        subtitle: 'Try a different country code or retry later.',
      );
    }

    final header = _HomeBrowseHeader(
      userName: userName,
      subtitle: subtitle,
      filteredCount: filteredChannels.length,
      countryCode: countryCode,
      textTheme: textTheme,
      colorScheme: colorScheme,
      selectedCategory: selectedCategory,
      categoryIds: categoryIds,
      onCategoryChanged: onCategoryChanged,
    );

    final channelTiles = <Widget>[
      for (var i = 0; i < filteredChannels.length; i++) ...[
        if (i > 0) SizedBox(height: AppSpacing.md.h),
        _ChannelTile(channel: filteredChannels[i]),
      ],
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl.w,
        AppSpacing.md.h,
        AppSpacing.xl.w,
        AppSpacing.xl.w,
      ),
      children: [
        header,
        if (filteredChannels.isEmpty && channels.isNotEmpty) ...[
          SizedBox(height: AppSpacing.xl.h),
          Text(
            'home.no_channels_in_category'.tr(),
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.sm.h),
          Text(
            'home.try_another_category'.tr(),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ] else
          ...channelTiles,
      ],
    );
  }
}

class _HomeBrowseHeader extends StatelessWidget {
  const _HomeBrowseHeader({
    required this.userName,
    required this.subtitle,
    required this.filteredCount,
    required this.countryCode,
    required this.textTheme,
    required this.colorScheme,
    required this.selectedCategory,
    required this.categoryIds,
    required this.onCategoryChanged,
  });

  final String userName;
  final String subtitle;
  final int filteredCount;
  final String countryCode;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final String? selectedCategory;
  final List<String> categoryIds;
  final ValueChanged<String?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          userName,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: AppSpacing.xs.h),
        Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: AppSpacing.lg.h),
        Row(
          children: [
            Icon(
              Icons.public_rounded,
              size: 20.sp,
              color: colorScheme.primary,
            ),
            SizedBox(width: AppSpacing.sm.w),
            Expanded(
              child: Text(
                'home.channels_region_summary'.tr(
                  args: [
                    '$filteredCount',
                    countryCode.toUpperCase(),
                  ],
                ),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.lg.h),
        Divider(height: 1.h, color: colorScheme.outlineVariant),
        SizedBox(height: AppSpacing.md.h),
        Text(
          'home.filter_by_category'.tr(),
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSpacing.sm.h),
        SizedBox(
          width: double.infinity,
          child: PopupMenuButton<String?>(
            tooltip: 'home.filter_by_category'.tr(),
            position: PopupMenuPosition.under,
            offset: Offset(0, AppSpacing.xs.h),
            onSelected: onCategoryChanged,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            itemBuilder: (context) => <PopupMenuEntry<String?>>[
              PopupMenuItem<String?>(
                value: null,
                child: _CategoryMenuRow(
                  label: 'home.all_categories'.tr(),
                  selected: selectedCategory == null,
                  colorScheme: colorScheme,
                ),
              ),
              if (categoryIds.isNotEmpty) const PopupMenuDivider(),
              for (final id in categoryIds)
                PopupMenuItem<String?>(
                  value: id,
                  child: _CategoryMenuRow(
                    label: _categoryChipDisplayLabel(id),
                    selected: selectedCategory == id,
                    colorScheme: colorScheme,
                  ),
                ),
            ],
            child: Material(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12.r),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md.w,
                  vertical: AppSpacing.sm.h,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 22.sp,
                      color: colorScheme.primary,
                    ),
                    SizedBox(width: AppSpacing.sm.w),
                    Expanded(
                      child: Text(
                        _categorySelectionTitle(selectedCategory),
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.lg.h),
      ],
    );
  }
}

class _CategoryMenuRow extends StatelessWidget {
  const _CategoryMenuRow({
    required this.label,
    required this.selected,
    required this.colorScheme,
  });

  final String label;
  final bool selected;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24.sp,
          child: Icon(
            Icons.check_rounded,
            size: 20.sp,
            color: selected ? colorScheme.primary : Colors.transparent,
          ),
        ),
        SizedBox(width: AppSpacing.sm.w),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
            additionalSources: channel.playbackAlternates
                ?.map(
                  (a) => PlaybackSource(
                    streamUrl: a.streamUrl,
                    referrer: a.referrer,
                    userAgent: a.userAgent,
                  ),
                )
                .toList(),
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
