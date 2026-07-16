import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/output_processing_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/output_processing_settings.dart';

OutputRegexRule _rule({
  String id = 'rule-1',
  String title = '过滤增殖',
  String pattern = '极其',
  String replacement = '',
  int order = 0,
  bool enabled = true,
}) {
  return OutputRegexRule(
    id: id,
    title: title,
    pattern: pattern,
    replacement: replacement,
    order: order,
    enabled: enabled,
  );
}

void main() {
  group('OutputProcessingSettingsController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late OutputProcessingSettingsController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      controller = container.read(outputProcessingSettingsProvider.notifier);
    }

    test('无持久化数据时返回空规则', () async {
      await boot({});
      expect(container.read(outputProcessingSettingsProvider).rules, isEmpty);
    });

    test('save 后写入 SharedPreferences 并更新状态', () async {
      await boot({});
      final settings = OutputProcessingSettings(rules: [_rule()]);

      await controller.save(settings);

      expect(container.read(outputProcessingSettingsProvider), settings);
      expect(sp.getString(outputProcessingSettingsStorageKey), isNotNull);
    });

    test('build 从已有持久化数据恢复规则', () async {
      final persisted = OutputProcessingSettings(
        rules: [
          _rule(id: 'a', title: '规则 A', order: 0),
          _rule(id: 'b', title: '规则 B', pattern: r'\d+', replacement: 'N', order: 1),
        ],
      );
      await boot({});
      await controller.save(persisted);

      // 用同一份 SharedPreferences 重建容器，验证 build() 恢复。
      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      expect(revived.read(outputProcessingSettingsProvider), persisted);
    });

    test('持久化数据损坏时降级为空规则', () async {
      await boot({outputProcessingSettingsStorageKey: '{不是合法 JSON'});
      expect(container.read(outputProcessingSettingsProvider).rules, isEmpty);
    });
  });
}
