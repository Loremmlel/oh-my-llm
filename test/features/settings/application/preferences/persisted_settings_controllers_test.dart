import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/features/settings/application/preferences/auto_retry_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/custom_headers_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/font_size_settings_controller.dart';
import 'package:oh_my_llm/features/settings/application/preferences/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/font_size_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/output_processing_settings.dart';

Future<({SharedPreferences preferences, ProviderContainer container})> _boot(
  Map<String, Object> initial,
) async {
  SharedPreferences.setMockInitialValues(initial);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  return (preferences: preferences, container: container);
}

ProviderContainer _revive(SharedPreferences preferences) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
}

ProviderContainer _withRejectingStore() {
  return ProviderContainer(
    overrides: [
      settingsKeyValueStoreProvider.overrideWithValue(
        const _RejectingSettingsKeyValueStore(),
      ),
    ],
  );
}

OutputRegexRule _rule({String id = 'rule-1', String title = '规则 A'}) {
  return OutputRegexRule(id: id, title: title, pattern: '极其');
}

void main() {
  group('CustomHeadersController', () {
    test('missing storage starts with an empty configuration', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);

      expect(container.read(customHeadersProvider).headers, isEmpty);
      expect(preferences.getString(customHeadersStorageKey), isNull);
    });

    test('corrupt storage falls back to an empty configuration', () async {
      final (:container, preferences: _) = await _boot({
        customHeadersStorageKey: 'not-json',
      });
      addTearDown(container.dispose);

      expect(container.read(customHeadersProvider).headers, isEmpty);
    });

    test('multiple additions preserve order and survive a rebuild', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);

      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      expect(
        container.read(customHeadersProvider).headers.map((entry) => entry.key),
        ['X-A', 'X-B'],
      );
      final revived = _revive(preferences);
      addTearDown(revived.dispose);
      expect(revived.read(customHeadersProvider).toHeaderMap(), {
        'X-A': '1',
        'X-B': '2',
      });
    });

    test('removeHeader removes the selected entry', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);
      await controller.addHeader('X-A', '1');
      await controller.addHeader('X-B', '2');

      await controller.removeHeader(0);

      expect(container.read(customHeadersProvider).toHeaderMap(), {'X-B': '2'});
    });

    test('removeHeader ignores negative and high indexes', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);
      await controller.addHeader('X-A', '1');

      for (final index in [-1, 99]) {
        await controller.removeHeader(index);
        expect(
          container.read(customHeadersProvider).toHeaderMap(),
          {'X-A': '1'},
          reason: 'index $index',
        );
      }
    });

    test('updateHeader replaces the selected entry', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);
      await controller.addHeader('X-Old', 'old');

      await controller.updateHeader(0, 'X-New', 'new');

      expect(container.read(customHeadersProvider).toHeaderMap(), {
        'X-New': 'new',
      });
    });

    test('updateHeader ignores negative and high indexes', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);
      await controller.addHeader('X-A', '1');

      for (final index in [-1, 99]) {
        await controller.updateHeader(index, 'X-New', 'new');
        expect(
          container.read(customHeadersProvider).toHeaderMap(),
          {'X-A': '1'},
          reason: 'index $index',
        );
      }
    });

    test('a rejected write propagates and preserves the old state', () async {
      final container = _withRejectingStore();
      addTearDown(container.dispose);
      final controller = container.read(customHeadersProvider.notifier);

      await expectLater(
        controller.addHeader('X-Fail', 'value'),
        throwsA(isA<StateError>()),
      );
      expect(container.read(customHeadersProvider).headers, isEmpty);
    });
  });

  group('FontSizeSettingsController', () {
    test('missing storage returns the default size', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);

      expect(
        container.read(fontSizeSettingsProvider),
        const FontSizeSettings(),
      );
    });

    test('corrupt storage falls back to the default size', () async {
      final (:container, preferences: _) = await _boot({
        fontSizeSettingsStorageKey: '{bad json',
      });
      addTearDown(container.dispose);

      expect(
        container.read(fontSizeSettingsProvider),
        const FontSizeSettings(),
      );
    });

    test('updateLocal changes memory without writing storage', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);
      final controller = container.read(fontSizeSettingsProvider.notifier);

      controller.updateLocal(const FontSizeSettings(bodyFontSize: 20));

      expect(
        container.read(fontSizeSettingsProvider),
        const FontSizeSettings(bodyFontSize: 20),
      );
      expect(preferences.getString(fontSizeSettingsStorageKey), isNull);
    });

    test('save updates current state and survives a rebuild', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);
      const saved = FontSizeSettings(bodyFontSize: 22);

      await container.read(fontSizeSettingsProvider.notifier).save(saved);

      expect(container.read(fontSizeSettingsProvider), saved);
      final revived = _revive(preferences);
      addTearDown(revived.dispose);
      expect(revived.read(fontSizeSettingsProvider), saved);
    });

    test('a rejected write propagates and preserves the old state', () async {
      final container = _withRejectingStore();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(fontSizeSettingsProvider.notifier)
            .save(const FontSizeSettings(bodyFontSize: 20)),
        throwsA(isA<StateError>()),
      );
      expect(
        container.read(fontSizeSettingsProvider),
        const FontSizeSettings(),
      );
    });
  });

  group('OutputProcessingSettingsController', () {
    test('missing storage returns an empty rule list', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);

      expect(container.read(outputProcessingSettingsProvider).rules, isEmpty);
    });

    test('corrupt storage falls back to an empty rule list', () async {
      final (:container, preferences: _) = await _boot({
        outputProcessingSettingsStorageKey: '{不是合法 JSON',
      });
      addTearDown(container.dispose);

      expect(container.read(outputProcessingSettingsProvider).rules, isEmpty);
    });

    test('save updates current state and survives a rebuild', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);
      final saved = OutputProcessingSettings(
        rules: [
          _rule(id: 'a'),
          _rule(id: 'b', title: '规则 B'),
        ],
      );

      await container
          .read(outputProcessingSettingsProvider.notifier)
          .save(saved);

      expect(container.read(outputProcessingSettingsProvider), saved);
      final revived = _revive(preferences);
      addTearDown(revived.dispose);
      expect(revived.read(outputProcessingSettingsProvider), saved);
    });

    test('a rejected write propagates and preserves the old state', () async {
      final container = _withRejectingStore();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(outputProcessingSettingsProvider.notifier)
            .save(OutputProcessingSettings(rules: [_rule()])),
        throwsA(isA<StateError>()),
      );
      expect(container.read(outputProcessingSettingsProvider).rules, isEmpty);
    });
  });

  group('AutoRetrySettingsController', () {
    test('missing storage returns all default values', () async {
      final (:container, preferences: _) = await _boot({});
      addTearDown(container.dispose);

      expect(
        container.read(autoRetrySettingsProvider),
        const AutoRetrySettings(),
      );
    });

    test('历史裸 JSON 不再被接受，读取回退到全部默认值', () async {
      final (:container, preferences: _) = await _boot({
        autoRetrySettingsStorageKey:
            '{"maxJitterSeconds":20,"maxRetryCount":2}',
      });
      addTearDown(container.dispose);

      final settings = container.read(autoRetrySettingsProvider);
      expect(settings, const AutoRetrySettings());
    });

    test('save updates current state and survives a rebuild', () async {
      final (:container, :preferences) = await _boot({});
      addTearDown(container.dispose);
      const saved = AutoRetrySettings(
        maxJitterSeconds: 10,
        maxRetryCount: 3,
        retryMode: RetryMode.fixedInterval,
        retryOnAbnormalFinishReason: true,
        retryOnTimeout: true,
        timeoutSeconds: 45,
      );

      await container.read(autoRetrySettingsProvider.notifier).save(saved);

      expect(container.read(autoRetrySettingsProvider), saved);
      final revived = _revive(preferences);
      addTearDown(revived.dispose);
      expect(revived.read(autoRetrySettingsProvider), saved);
    });

    test('a rejected write propagates and preserves the old state', () async {
      final container = _withRejectingStore();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(autoRetrySettingsProvider.notifier)
            .save(const AutoRetrySettings(maxRetryCount: 2)),
        throwsA(isA<StateError>()),
      );
      expect(
        container.read(autoRetrySettingsProvider),
        const AutoRetrySettings(),
      );
    });
  });
}

final class _RejectingSettingsKeyValueStore implements SettingsKeyValueStore {
  const _RejectingSettingsKeyValueStore();

  @override
  String? getString(String key) => null;

  @override
  int? getInt(String key) => null;

  @override
  Future<bool> setInt(String key, int value) async => false;

  @override
  Future<bool> setString(String key, String value) async => false;
}
