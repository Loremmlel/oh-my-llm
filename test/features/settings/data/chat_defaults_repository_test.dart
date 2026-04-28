import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/chat_defaults.dart';

void main() {
  group('ChatDefaultsRepository', () {
    test('load 在 SP 为空时返回默认值（两个字段均为 null）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      final result = repo.load();
      expect(result, const ChatDefaults());
      expect(result.defaultModelId, isNull);
      expect(result.defaultPromptTemplateId, isNull);
    });

    test('load 在 SP 键值为空字符串时返回默认值', () async {
      SharedPreferences.setMockInitialValues({chatDefaultsStorageKey: ''});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      expect(repo.load(), const ChatDefaults());
    });

    test('load 可以还原有效 JSON', () async {
      final json = jsonEncode({
        'defaultModelId': 'model-abc',
        'defaultPromptTemplateId': 'tpl-xyz',
      });
      SharedPreferences.setMockInitialValues({chatDefaultsStorageKey: json});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      final result = repo.load();
      expect(result.defaultModelId, 'model-abc');
      expect(result.defaultPromptTemplateId, 'tpl-xyz');
    });

    test('load 可以处理 JSON 中的 null 字段', () async {
      final json = jsonEncode({
        'defaultModelId': null,
        'defaultPromptTemplateId': 'tpl-only',
      });
      SharedPreferences.setMockInitialValues({chatDefaultsStorageKey: json});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      final result = repo.load();
      expect(result.defaultModelId, isNull);
      expect(result.defaultPromptTemplateId, 'tpl-only');
    });

    test('save 后 load 往返结果一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      const original = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPromptTemplateId: 'tpl-1',
      );
      await repo.save(original);

      expect(repo.load(), original);
    });

    test('save 后 load 仅有 defaultModelId 的场景', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      const original = ChatDefaults(defaultModelId: 'model-only');
      await repo.save(original);

      final loaded = repo.load();
      expect(loaded.defaultModelId, 'model-only');
      expect(loaded.defaultPromptTemplateId, isNull);
    });

    test('load 非 Map JSON 时抛出 FormatException', () async {
      SharedPreferences.setMockInitialValues({
        chatDefaultsStorageKey: '[1, 2, 3]',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      expect(() => repo.load(), throwsA(isA<FormatException>()));
    });
  });
}
