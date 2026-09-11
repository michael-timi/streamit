import 'dart:async';

import 'package:streamit/src/config/onboarding_storage.dart';
import 'package:streamit/src/imports/core_imports.dart';
import 'package:streamit/src/imports/packages_imports.dart';

class OnboardingPage extends HookWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final pageController = usePageController();
    final currentIndex = useState(0);

    final onboardingData = useMemoized(() => _OnboardingSlide.pages());

    Future<void> completeOnboarding() async {
      await OnboardingStorage.markCompleted();
      if (context.mounted) {
        context.go(AppRoutes.home);
      }
    }

    void onGetStarted() {
      unawaited(completeOnboarding());
    }

    return _OnboardingView(
      colorScheme: colorScheme,
      textTheme: textTheme,
      pageController: pageController,
      currentIndex: currentIndex.value,
      onboardingData: onboardingData,
      onPageChanged: (index) => currentIndex.value = index,
      onGetStarted: onGetStarted,
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
  });

  final String titleKey;
  final String subtitleKey;
  final List<List<dynamic>> icon;

  static List<_OnboardingSlide> pages() => const [
        _OnboardingSlide(
          titleKey: 'onboarding.onboarding_title_1',
          subtitleKey: 'onboarding.onboarding_subtitle_1',
          icon: HugeIcons.strokeRoundedTv01,
        ),
        _OnboardingSlide(
          titleKey: 'onboarding.onboarding_title_2',
          subtitleKey: 'onboarding.onboarding_subtitle_2',
          icon: HugeIcons.strokeRoundedGlobe02,
        ),
        _OnboardingSlide(
          titleKey: 'onboarding.onboarding_title_3',
          subtitleKey: 'onboarding.onboarding_subtitle_3',
          icon: HugeIcons.strokeRoundedPlayCircle,
        ),
      ];
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView({
    required this.colorScheme,
    required this.textTheme,
    required this.pageController,
    required this.currentIndex,
    required this.onboardingData,
    required this.onPageChanged,
    required this.onGetStarted,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final PageController pageController;
  final int currentIndex;
  final List<_OnboardingSlide> onboardingData;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onGetStarted;

  bool get _isLastSlide => currentIndex >= onboardingData.length - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl.w,
                AppSpacing.lg.h,
                AppSpacing.xl.w,
                AppSpacing.md.h,
              ),
              child: Row(
                children: [
                  CommonImage(
                    imageUrl: AppAssets.streamitLogoSvg,
                    height: 40.h,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: AppSpacing.md.w),
                  Expanded(
                    child: Text(
                      'onboarding.app_name'.tr(),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        fontSize: 22.sp,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: onboardingData.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  final slide = onboardingData[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: _SlideIllustration(
                              colorScheme: colorScheme,
                              icon: slide.icon,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md.w,
                          ),
                          child: Column(
                            children: [
                              Text(
                                slide.titleKey.tr(),
                                textAlign: TextAlign.center,
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                  height: 1.2,
                                  fontSize: 24.sp,
                                ),
                              ),
                              SizedBox(height: AppSpacing.md.h),
                              Text(
                                slide.subtitleKey.tr(),
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.5,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.w),
              child: Column(
                children: [
                  SmoothPageIndicator(
                    controller: pageController,
                    count: onboardingData.length,
                    effect: WormEffect(
                      dotColor: colorScheme.outlineVariant,
                      activeDotColor: colorScheme.primary,
                      dotHeight: 8.h,
                      dotWidth: 8.w,
                      spacing: 8.w,
                    ),
                    onDotClicked: (index) {
                      pageController.animateToPage(
                        index,
                        duration: AppDurations.normal,
                        curve: AppCurves.standard,
                      );
                    },
                  ),
                  SizedBox(height: AppSpacing.xl.h),
                  AppButton(
                    label: _isLastSlide
                        ? 'shared.get_started'.tr()
                        : 'shared.next'.tr(),
                    onPressed: _isLastSlide
                        ? onGetStarted
                        : () {
                            pageController.nextPage(
                              duration: AppDurations.normal,
                              curve: AppCurves.standard,
                            );
                          },
                    variant: ButtonVariant.primary,
                    isFullWidth: true,
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

class _SlideIllustration extends StatelessWidget {
  const _SlideIllustration({
    required this.colorScheme,
    required this.icon,
  });

  final ColorScheme colorScheme;
  final List<List<dynamic>> icon;

  @override
  Widget build(BuildContext context) {
    final size = 200.w;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Center(
        child: HugeIcon(
          icon: icon,
          size: 88.sp,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
