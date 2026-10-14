import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/settings_tab.dart';

void main() {
  group('SettingsTab', () {
    test('默认顺序包含全部已知页签且不重复', () {
      expect(SettingsTab.defaultOrder.length, SettingsTab.values.length);
      expect(
        SettingsTab.defaultOrder.toSet().length,
        SettingsTab.values.length,
      );
    });

    test('fromKey 正确解析合法 key，对未知 key 返回 null', () {
      expect(SettingsTab.fromKey('providers'), SettingsTab.providers);
      expect(SettingsTab.fromKey('presets'), SettingsTab.presets);
      expect(SettingsTab.fromKey('prompts'), SettingsTab.prompts);
      expect(SettingsTab.fromKey('network'), SettingsTab.network);
      expect(
        SettingsTab.fromKey('output_processing'),
        SettingsTab.outputProcessing,
      );
      expect(SettingsTab.fromKey('other'), SettingsTab.other);
      expect(SettingsTab.fromKey('world_books'), SettingsTab.worldBooks);
      expect(SettingsTab.fromKey('unknown_key'), isNull);
    });

    test('sanitizeOrder 在输入为 null 或空时回退到默认顺序', () {
      expect(SettingsTab.sanitizeOrder(null), SettingsTab.defaultOrder);
      expect(SettingsTab.sanitizeOrder([]), SettingsTab.defaultOrder);
    });

    test('sanitizeOrder 过滤未知 key 并按相对默认顺序追加缺失项', () {
      final sanitized = SettingsTab.sanitizeOrder([
        'network',
        'invalid_foo',
        'providers',
        'network', // 重复项
      ]);

      expect(sanitized, [
        SettingsTab.network,
        SettingsTab.providers,
        SettingsTab.presets,
        SettingsTab.prompts,
        SettingsTab.outputProcessing,
        SettingsTab.other,
        SettingsTab.worldBooks,
      ]);
    });

    test('toKeys 正确序列化为字符串列表', () {
      final keys = SettingsTab.toKeys([
        SettingsTab.worldBooks,
        SettingsTab.network,
      ]);
      expect(keys, ['world_books', 'network']);
    });
  });
}
