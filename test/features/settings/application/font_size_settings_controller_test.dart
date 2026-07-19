import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/settings/application/font_size_settings_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/font_size_settings.dart';

void main() {
  group('FontSizeSettingsController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late FontSizeSettingsController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      controller = container.read(fontSizeSettingsProvider.notifier);
    }

    test('无持久化数据时返回默认值', () async {
      await boot({});
      expect(container.read(fontSizeSettingsProvider).bodyFontSize, 14);
    });

    test('从持久化恢复已有设置', () async {
      await boot({});
      await controller.save(const FontSizeSettings(bodyFontSize: 18));

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      expect(revived.read(fontSizeSettingsProvider).bodyFontSize, 18);
    });

    test('持久化数据损坏时降级为默认值', () async {
      await boot({fontSizeSettingsStorageKey: '{bad json'});
      expect(container.read(fontSizeSettingsProvider).bodyFontSize, 14);
    });

    test('updateLocal 只更新内存不写磁盘', () async {
      await boot({});
      controller.updateLocal(const FontSizeSettings(bodyFontSize: 20));

      expect(container.read(fontSizeSettingsProvider).bodyFontSize, 20);
      expect(sp.getString(fontSizeSettingsStorageKey), isNull);
    });

    test('save 写入磁盘并更新状态', () async {
      await boot({});
      await controller.save(const FontSizeSettings(bodyFontSize: 22));

      expect(container.read(fontSizeSettingsProvider).bodyFontSize, 22);
      expect(sp.getString(fontSizeSettingsStorageKey), isNotNull);
    });

    test('save 后重建容器能恢复', () async {
      await boot({});
      await controller.save(const FontSizeSettings(bodyFontSize: 19));

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      expect(revived.read(fontSizeSettingsProvider).bodyFontSize, 19);
    });
  });
}
