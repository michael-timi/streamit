import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user finished the intro flow (no auth required).
abstract final class OnboardingStorage {
  OnboardingStorage._();

  static const String _key = 'streamit_onboarding_completed';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
