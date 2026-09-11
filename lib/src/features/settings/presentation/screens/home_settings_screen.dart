import 'package:streamit/src/features/home/presentation/providers/live_channels_provider.dart';
import 'package:streamit/src/imports/core_imports.dart';
import 'package:streamit/src/imports/packages_imports.dart';

/// Region playlist source and cache controls (moved off [HomePage]).
class HomeSettingsScreen extends HookConsumerWidget {
  const HomeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final countryCode = ref.watch(selectedCountryCodeProvider);
    final countryInputController = useTextEditingController();
    useEffect(() {
      countryInputController.text = countryCode.toUpperCase();
      return null;
    }, [countryCode]);

    Future<void> applyCustomCountry() async {
      final rawValue = countryInputController.text.trim().toLowerCase();
      final isValid = RegExp(r'^[a-z]{2}$').hasMatch(rawValue);
      if (!isValid) {
        showToast(
          context,
          message: 'settings.invalid_country'.tr(),
          status: 'warning',
        );
        return;
      }
      ref.read(selectedCountryCodeProvider.notifier).state = rawValue;
      ref.read(selectedCategoryProvider.notifier).state = null;
    }

    Future<void> hardRefresh() async {
      final repository = ref.read(liveChannelsRepositoryProvider);
      final countryResult =
          await repository.clearCountryCache(countryCode: countryCode);
      if (!context.mounted) return;
      final countryFailure =
          countryResult.fold((failure) => failure, (_) => null);
      if (countryFailure != null) {
        showToast(context, message: countryFailure.message, status: 'error');
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
            message: 'settings.hard_refresh_done'.tr(
              args: [countryCode.toUpperCase()],
            ),
            status: 'success',
          );
        },
      );
    }

    void selectCountry(String code) {
      ref.read(selectedCountryCodeProvider.notifier).state = code;
      ref.read(selectedCategoryProvider.notifier).state = null;
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppTopBar(
        title: 'settings.title'.tr(),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.xl.w),
          children: [
            Text(
              'settings.region_section'.tr(),
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            SizedBox(height: AppSpacing.xs.h),
            Text(
              'settings.region_help'.tr(),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            SizedBox(height: AppSpacing.lg.h),
            Text(
              'settings.quick_countries'.tr(),
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppSpacing.sm.h),
            Wrap(
              spacing: AppSpacing.sm.w,
              runSpacing: AppSpacing.sm.h,
              children: [
                for (final code in const ['us', 'gb', 'in', 'fr', 'de'])
                  _QuickCountryChip(
                    code: code,
                    selected: countryCode == code,
                    onTap: selectCountry,
                  ),
              ],
            ),
            SizedBox(height: AppSpacing.xl.h),
            Text(
              'settings.custom_country'.tr(),
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppSpacing.sm.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: countryInputController,
                    hint: 'settings.custom_country_hint'.tr(),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => applyCustomCountry(),
                  ),
                ),
                SizedBox(width: AppSpacing.sm.w),
                AppButton(
                  label: 'settings.apply'.tr(),
                  height: ButtonSize.small,
                  onPressed: applyCustomCountry,
                ),
              ],
            ),
            SizedBox(height: AppSpacing.xl.h),
            AppCard(
              padding: EdgeInsets.all(AppSpacing.lg.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.cache_section'.tr(),
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  SizedBox(height: AppSpacing.sm.h),
                  Text(
                    'settings.hard_refresh_help'.tr(),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  SizedBox(height: AppSpacing.md.h),
                  AppButton(
                    label: 'settings.hard_refresh'.tr(),
                    variant: ButtonVariant.outline,
                    onPressed: hardRefresh,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCountryChip extends StatelessWidget {
  const _QuickCountryChip({
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
