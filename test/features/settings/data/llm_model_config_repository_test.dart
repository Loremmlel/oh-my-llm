import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

LlmModelConfig _model(String id) => LlmModelConfig(
  id: id,
  displayName: '模型 $id',
  apiUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  modelName: 'gpt-test',
  supportsReasoning: false,
);

void main() {
  group('LlmModelConfigRepository', () {
    test('loadAll 在 SP 为空时返回空列表', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      expect(repo.loadAll(), isEmpty);
    });

    test('loadAll 在 SP 键值为空字符串时返回空列表', () async {
      SharedPreferences.setMockInitialValues({
        llmModelConfigsStorageKey: '',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll 保存后 loadAll 可以正确还原数据', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      final models = [_model('m-1'), _model('m-2')];
      await repo.saveAll(models);

      final loaded = repo.loadAll();
      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'm-1');
      expect(loaded[1].id, 'm-2');
    });

    test('saveAll 保存空列表后 loadAll 返回空列表', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      await repo.saveAll([_model('m-1')]);
      await repo.saveAll([]);

      expect(repo.loadAll(), isEmpty);
    });

    test('往返序列化保持字段一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      final original = LlmModelConfig(
        id: 'full-model',
        displayName: '全字段模型',
        apiUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-secret',
        modelName: 'gpt-4o',
        supportsReasoning: true,
      );
      await repo.saveAll([original]);

      final loaded = repo.loadAll().single;
      expect(loaded.id, original.id);
      expect(loaded.displayName, original.displayName);
      expect(loaded.apiUrl, original.apiUrl);
      expect(loaded.apiKey, original.apiKey);
      expect(loaded.modelName, original.modelName);
      expect(loaded.supportsReasoning, original.supportsReasoning);
    });
  });
}
