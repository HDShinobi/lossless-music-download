import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user has finished (or skipped) the first-launch onboarding.
/// Persisted so the flow is shown exactly once. Defaults to false (not seen).
class OnboardingSeenNotifier extends Notifier<bool> {
  static const _key = 'onboarding_seen';

  @override
  bool build() => false;

  /// Loads the persisted flag. Call once at startup before building the router.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getBool(_key) ?? false;
  }

  /// Marks onboarding as done and persists it.
  Future<void> complete() async {
    state = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
  }
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingSeenNotifier, bool>(OnboardingSeenNotifier.new);

/// The onboarding route path (a top-level route outside the main shell).
const kOnboardingPath = '/onboarding';

/// The location the app lands on after onboarding.
const kPostOnboardingPath = '/search';

/// Pure redirect decision for the onboarding gate — extracted so it can be
/// unit-tested without a live [GoRouter]. Returns the path to redirect to, or
/// null to stay put.
///
///   • an unseen user anywhere but onboarding → sent to onboarding
///   • a user who has finished onboarding but is still on it → sent onward
///   • everything else stays
String? onboardingRedirect({required bool seen, required String location}) {
  final atOnboarding = location == kOnboardingPath;
  if (!seen && !atOnboarding) return kOnboardingPath;
  if (seen && atOnboarding) return kPostOnboardingPath;
  return null;
}
