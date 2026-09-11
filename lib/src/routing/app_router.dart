import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:streamit/src/routing/global_navigator.dart';
import 'package:streamit/src/routing/app_routes.dart';

import 'package:streamit/src/features/auth/presentation/screens/login_screen.dart';
import 'package:streamit/src/features/auth/presentation/screens/signup_screen.dart';
import 'package:streamit/src/features/auth/presentation/screens/forgot_password_screen.dart';

import 'package:streamit/src/features/home/presentation/screens/home_page.dart';
import 'package:streamit/src/features/settings/presentation/screens/home_settings_screen.dart';
import 'package:streamit/src/features/onboarding/presentation/screens/onboarding_page.dart';
import 'package:streamit/src/config/onboarding_storage.dart';
import 'package:streamit/src/features/player/domain/stream_player_args.dart';
import 'package:streamit/src/features/player/presentation/screens/stream_player_screen.dart';


final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.onboarding,
  redirect: (context, state) async {
    final completed = await OnboardingStorage.isCompleted();
    if (completed && state.matchedLocation == AppRoutes.onboarding) {
      return AppRoutes.home;
    }
    return null;
  },
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.signup,
      name: 'signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      name: 'forgotPassword',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: AppRoutes.homeSettings,
      name: 'homeSettings',
      builder: (context, state) => const HomeSettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.player,
      name: 'player',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is StreamPlayerArgs) {
          return StreamPlayerScreen(args: extra);
        }
        return const Scaffold(
          body: Center(child: Text('Missing stream arguments')),
        );
      },
    ),
  ],
);
