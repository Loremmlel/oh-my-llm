import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';

void main() {
  group('AutoRetrySettingsController', () {
    Future<ProviderContainer> createContainer(
      SharedPreferences preferences,
    ) async {
      return ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
    }

    test('returns default values when no stored settings', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 15);
      expect(settings.maxRetryCount, 0);

      container.dispose();
    });

    test('loads stored settings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'settings.auto_retry': '{"maxJitterSeconds": 30, "maxRetryCount": 5}',
      });
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 30);
      expect(settings.maxRetryCount, 5);

      container.dispose();
    });

    test('save round-trips correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final notifier = container.read(autoRetrySettingsProvider.notifier);
      await notifier.save(const AutoRetrySettings(
        maxJitterSeconds: 10,
        maxRetryCount: 3,
      ));

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 10);
      expect(settings.maxRetryCount, 3);

      // Verify persistence in SharedPreferences
      final storedJson = preferences.getString('settings.auto_retry');
      expect(storedJson, contains('"maxJitterSeconds":10'));
      expect(storedJson, contains('"maxRetryCount":3'));

      container.dispose();
    });

    test('copyWith preserves defaults when clearing', () {
      const settings = AutoRetrySettings(maxJitterSeconds: 30, maxRetryCount: 5);

      final clearedJitter = settings.copyWith(clearMaxJitterSeconds: true);
      expect(clearedJitter.maxJitterSeconds, 15);
      expect(clearedJitter.maxRetryCount, 5);

      final clearedRetry = settings.copyWith(clearMaxRetryCount: true);
      expect(clearedRetry.maxJitterSeconds, 30);
      expect(clearedRetry.maxRetryCount, 0);
    });
  });
}
