import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:streamit/src/features/auth/presentation/providers/session_provider.dart';
import 'package:streamit/src/imports/core_imports.dart';

class SessionListenerWrapper extends ConsumerWidget {
  final Widget child;
  const SessionListenerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next.status != SessionStatus.unknown) {
        FlutterNativeSplash.remove();
        if (next.status == SessionStatus.authenticated) {
          appRouter.go(AppRoutes.home);
        }
        // Anonymous use: no redirect when unauthenticated (no forced login / onboarding).
      }
    });

    return child;
  }
}
