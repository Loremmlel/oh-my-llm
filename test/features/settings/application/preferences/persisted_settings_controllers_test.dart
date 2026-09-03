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

void main() {
  test('自定义请求头支持按索引增删改并持久化有序结果', () async {
    final (:container, :preferences) = await _boot({});
    addTearDown(container.dispose);
    final controller = container.read(customHeadersProvider.notifier);

    await controller.addHeader('X-A', '1');
    await controller.addHeader('X-B', '2');
    await controller.updateHeader(0, 'X-Updated', '3');
    await controller.removeHeader(1);
    await controller.updateHeader(-1, 'X-Ignored', '4');
    await controller.removeHeader(99);

    expect(container.read(customHeadersProvider).toHeaderMap(), {
      'X-Updated': '3',
    });
    final revived = _revive(preferences);
    addTearDown(revived.dispose);
    expect(revived.read(customHeadersProvider).toHeaderMap(), {
      'X-Updated': '3',
    });
  });

  test('持久化写入失败时抛出异常且不提前发布状态', () async {
    final container = ProviderContainer(
      overrides: [
        settingsKeyValueStoreProvider.overrideWithValue(
          const _RejectingSettingsKeyValueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(customHeadersProvider.notifier);

    await expectLater(
      controller.addHeader('X-Fail', 'value'),
      throwsA(isA<StateError>()),
    );
    expect(container.read(customHeadersProvider).headers, isEmpty);
  });

  test('字体大小可仅更新内存，也可保存后由新容器恢复', () async {
    final (:container, :preferences) = await _boot({});
    addTearDown(container.dispose);
    final controller = container.read(fontSizeSettingsProvider.notifier);

    controller.updateLocal(const FontSizeSettings(bodyFontSize: 20));
    expect(preferences.getString(fontSizeSettingsStorageKey), isNull);

    const saved = FontSizeSettings(bodyFontSize: 22);
    await controller.save(saved);
    final revived = _revive(preferences);
    addTearDown(revived.dispose);
    expect(revived.read(fontSizeSettingsProvider), saved);
  });

  test('输出处理规则保存后由新容器恢复', () async {
    final (:container, :preferences) = await _boot({});
    addTearDown(container.dispose);
    final saved = OutputProcessingSettings(
      rules: [OutputRegexRule(id: 'rule-1', title: '规则 A', pattern: '极其')],
    );

    await container.read(outputProcessingSettingsProvider.notifier).save(saved);

    final revived = _revive(preferences);
    addTearDown(revived.dispose);
    expect(revived.read(outputProcessingSettingsProvider), saved);
  });

  test('自动重试拒绝历史裸 JSON，并能恢复当前版本数据', () async {
    final (:container, :preferences) = await _boot({
      autoRetrySettingsStorageKey: '{"maxJitterSeconds":20,"maxRetryCount":2}',
    });
    addTearDown(container.dispose);
    expect(
      container.read(autoRetrySettingsProvider),
      const AutoRetrySettings(),
    );

    const saved = AutoRetrySettings(
      maxJitterSeconds: 10,
      maxRetryCount: 3,
      retryMode: RetryMode.fixedInterval,
      retryOnAbnormalFinishReason: true,
      retryOnTimeout: true,
      timeoutSeconds: 45,
    );
    await container.read(autoRetrySettingsProvider.notifier).save(saved);

    final revived = _revive(preferences);
    addTearDown(revived.dispose);
    expect(revived.read(autoRetrySettingsProvider), saved);
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
