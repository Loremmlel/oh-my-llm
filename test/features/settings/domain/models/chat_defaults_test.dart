import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/chat_defaults.dart';

void main() {
  group('ChatDefaults', () {
    test('copyWith 清空 defaultModelId', () {
      const defaults = ChatDefaults(defaultModelId: 'model-1');
      final cleared = defaults.copyWith(clearDefaultModelId: true);
      expect(cleared.defaultModelId, isNull);
      expect(cleared.defaultPresetPromptId, isNull);
    });

    test('copyWith 清空 defaultPresetPromptId', () {
      const defaults = ChatDefaults(defaultPresetPromptId: 'preset-1');
      final cleared = defaults.copyWith(clearDefaultPresetPromptId: true);
      expect(cleared.defaultPresetPromptId, isNull);
    });

    test('copyWith 同时覆盖和清空不同字段', () {
      const defaults = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: 'preset-1',
      );
      final result = defaults.copyWith(
        defaultModelId: 'model-2',
        clearDefaultPresetPromptId: true,
      );
      expect(result.defaultModelId, 'model-2');
      expect(result.defaultPresetPromptId, isNull);
    });

    test('fromJson 正常解析', () {
      final defaults = ChatDefaults.fromJson({
        'defaultModelId': 'model-1',
        'defaultPresetPromptId': 'preset-1',
      });
      expect(defaults.defaultModelId, 'model-1');
      expect(defaults.defaultPresetPromptId, 'preset-1');
    });

    test('fromJson 缺失字段默认为 null', () {
      final defaults = ChatDefaults.fromJson({});
      expect(defaults.defaultModelId, isNull);
      expect(defaults.defaultPresetPromptId, isNull);
    });

    test('toJson → fromJson round-trip', () {
      const defaults = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: null,
      );
      final restored = ChatDefaults.fromJson(defaults.toJson());
      expect(restored, defaults);
    });
  });
}
