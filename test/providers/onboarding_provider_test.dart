import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingSeenProvider', () {
    test('defaults to false', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(onboardingSeenProvider), false);
    });

    test('load reads a persisted true', () async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(onboardingSeenProvider.notifier).load();
      expect(c.read(onboardingSeenProvider), true);
    });

    test('load defaults to false when the key is absent', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(onboardingSeenProvider.notifier).load();
      expect(c.read(onboardingSeenProvider), false);
    });

    test('complete flips the state and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(onboardingSeenProvider.notifier).complete();
      expect(c.read(onboardingSeenProvider), true);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('onboarding_seen'), true);
    });
  });

  group('onboardingRedirect', () {
    test('unseen user is sent to onboarding', () {
      expect(
        onboardingRedirect(seen: false, location: '/search'),
        kOnboardingPath,
      );
    });

    test('unseen user already on onboarding stays', () {
      expect(
        onboardingRedirect(seen: false, location: kOnboardingPath),
        isNull,
      );
    });

    test('finished user still on onboarding is sent onward', () {
      expect(
        onboardingRedirect(seen: true, location: kOnboardingPath),
        kPostOnboardingPath,
      );
    });

    test('finished user elsewhere stays', () {
      expect(onboardingRedirect(seen: true, location: '/library'), isNull);
    });
  });
}
