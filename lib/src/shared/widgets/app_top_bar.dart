import '../../imports/core_imports.dart';
import '../../imports/packages_imports.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.actions,
    this.centerTitle = true,
    this.onPressed,
    this.isTransparent = false,
    this.showLeading = true,
  });

  final String title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final VoidCallback? onPressed;
  final bool? centerTitle;
  final bool isTransparent;

  /// When `false` (e.g. root [HomePage]), no back control is shown.
  final bool showLeading;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    
    // Check if we can pop
    final bool canPop = context.canPop();

    void handleBack() {
      if (onPressed != null) {
        onPressed!();
      } else if (canPop) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
    }

    return AppBar(
      centerTitle: centerTitle,
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: isTransparent ? Colors.transparent : null,
      shadowColor: Colors.transparent,
      title: titleWidget ??
          Text(
            title,
            style: theme.appBarTheme.titleTextStyle?.copyWith(
              fontWeight: FontWeight.w600,
            ) ?? theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
      leadingWidth: showLeading ? 40.w : 0,
      leading: showLeading
          ? GestureDetector(
              onTap: handleBack,
              child: const ColoredBox(
                color: Colors.transparent,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  size: 24,
                ),
              ),
            )
          : const SizedBox.shrink(),
      iconTheme: theme.appBarTheme.iconTheme,
      actions: actions ?? [],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
