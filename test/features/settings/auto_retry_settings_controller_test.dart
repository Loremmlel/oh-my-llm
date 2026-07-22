import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart'
    show AutoRetrySettings, RetryMode;

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
      expect(settings.retryMode, RetryMode.perMinuteWindow);
      expect(settings.retryOnAbnormalFinishReason, isFalse);

      container.dispose();
    });

    test('loads stored settings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'settings.auto_retry':
            '{"maxJitterSeconds": 30, "maxRetryCount": 5, "retryMode": "fixedInterval", "retryOnAbnormalFinishReason": true}',
      });
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 30);
      expect(settings.maxRetryCount, 5);
      expect(settings.retryMode, RetryMode.fixedInterval);
      expect(settings.retryOnAbnormalFinishReason, isTrue);

      container.dispose();
    });

    test('loads old JSON without retryMode defaults to perMinuteWindow',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings.auto_retry':
            '{"maxJitterSeconds": 20, "maxRetryCount": 2}',
      });
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.retryMode, RetryMode.perMinuteWindow);

      container.dispose();
    });

    test('loads old JSON without retryOnAbnormalFinishReason defaults to false',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings.auto_retry':
            '{"maxJitterSeconds": 20, "maxRetryCount": 2}',
      });
      final preferences = await SharedPreferences.getInstance();
      final container = await createContainer(preferences);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.retryOnAbnormalFinishReason, isFalse);

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
        retryMode: RetryMode.fixedInterval,
        retryOnAbnormalFinishReason: true,
      ));

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings.maxJitterSeconds, 10);
      expect(settings.maxRetryCount, 3);
      expect(settings.retryMode, RetryMode.fixedInterval);
      expect(settings.retryOnAbnormalFinishReason, isTrue);

      // Verify persistence in SharedPreferences
      final storedJson = preferences.getString('settings.auto_retry');
      expect(storedJson, contains('"maxJitterSeconds":10'));
      expect(storedJson, contains('"maxRetryCount":3'));
      expect(storedJson, contains('"retryMode":"fixedInterval"'));
      expect(storedJson, contains('"retryOnAbnormalFinishReason":true'));

      container.dispose();
    });

  });
}
