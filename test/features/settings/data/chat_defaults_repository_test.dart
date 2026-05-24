import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/chat_defaults_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/chat_defaults.dart';

void main() {
  group('ChatDefaultsRepository', () {
    test('load 在空存储时返回默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      expect(repo.load(), const ChatDefaults());
    });

    test('save 后 load 往返结果一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      const original = ChatDefaults(
        defaultModelId: 'model-1',
        defaultPresetPromptId: 'tpl-1',
      );
      await repo.save(original);

      expect(repo.load(), original);
    });

    test('load 非 Map JSON 时抛出 FormatException', () async {
      SharedPreferences.setMockInitialValues({
        chatDefaultsStorageKey: jsonEncode([1, 2, 3]),
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = ChatDefaultsRepository(prefs);

      expect(() => repo.load(), throwsA(isA<FormatException>()));
    });
  });
}
