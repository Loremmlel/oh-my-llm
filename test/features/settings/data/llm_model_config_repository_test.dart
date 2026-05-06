import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

LlmModelConfig _model(String id) => LlmModelConfig(
  id: id,
  displayName: '模型 $id',
  apiUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  modelName: 'gpt-test-$id',
  supportsReasoning: false,
  providerId: 'provider-1',
  providerName: '服务商 1',
);

void main() {
  group('LlmModelConfigRepository', () {
    test('loadAll 在 SP 为空时返回空列表', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      expect(repo.loadAll(), isEmpty);
      expect(repo.loadProviders(), isEmpty);
    });

    test('loadAll 在 SP 键值为空字符串时返回空列表', () async {
      SharedPreferences.setMockInitialValues({
        llmModelConfigsStorageKey: '',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      expect(repo.loadAll(), isEmpty);
      expect(repo.loadProviders(), isEmpty);
    });

    test('saveProviders 保存后 loadProviders 可以正确还原数据', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      final providers = [
        LlmProviderConfig(
          id: 'provider-1',
          name: 'OpenAI 官方',
          apiUrl: 'https://api.openai.com/v1/chat/completions',
          apiKey: 'sk-secret',
          models: const [
            LlmProviderModelConfig(
              id: 'model-1',
              displayName: 'GPT-4.1',
              modelName: 'gpt-4.1',
              supportsReasoning: true,
            ),
            LlmProviderModelConfig(
              id: 'model-2',
              displayName: 'GPT-4o mini',
              modelName: 'gpt-4o-mini',
              supportsReasoning: false,
            ),
          ],
        ),
      ];
      await repo.saveProviders(providers);

      final loadedProviders = repo.loadProviders();
      expect(loadedProviders, hasLength(1));
      expect(loadedProviders.single.name, 'OpenAI 官方');
      expect(loadedProviders.single.models, hasLength(2));

      final loadedModels = repo.loadAll();
      expect(loadedModels.map((model) => model.id), ['model-1', 'model-2']);
      expect(loadedModels.every((model) => model.providerId == 'provider-1'), isTrue);
    });

    test('saveAll 仍可把平铺模型转换为服务商结构', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      final models = [_model('m-1'), _model('m-2')];
      await repo.saveAll(models);

      final loadedProviders = repo.loadProviders();
      expect(loadedProviders, hasLength(1));
      expect(loadedProviders.single.models, hasLength(2));

      final loaded = repo.loadAll();
      expect(loaded, hasLength(2));
      expect(loaded[0].providerId, 'provider-1');
      expect(loaded[0].providerName, '服务商 1');
    });

    test('loadProviders 会按相同 URL 和 Key 聚合旧版模型配置', () async {
      SharedPreferences.setMockInitialValues({
        llmModelConfigsStorageKey: jsonEncode([
          {
            'id': 'model-1',
            'displayName': 'DeepSeek V4 Flash',
            'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
            'apiKey': 'sk-deepseek',
            'modelName': 'deepseek-v4-flash',
            'supportsReasoning': true,
          },
          {
            'id': 'model-2',
            'displayName': 'DeepSeek V3',
            'apiUrl': 'https://api.deepseek.com/v1/chat/completions',
            'apiKey': 'sk-deepseek',
            'modelName': 'deepseek-v3',
            'supportsReasoning': false,
          },
          {
            'id': 'model-3',
            'displayName': 'Gemini 2.5 Flash',
            'apiUrl': 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            'apiKey': 'sk-google',
            'modelName': 'gemini-2.5-flash',
            'supportsReasoning': true,
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      final providers = repo.loadProviders();
      expect(providers, hasLength(2));
      expect(providers[0].models.map((model) => model.id), containsAll(['model-1', 'model-2']));
      expect(providers[1].models.single.id, 'model-3');

      final flattened = repo.loadAll();
      final deepSeekModels = flattened.where((model) => model.apiKey == 'sk-deepseek');
      expect(deepSeekModels.map((model) => model.providerName).toSet(), {'服务商1'});
    });

    test('往返序列化保持字段一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LlmModelConfigRepository(prefs);

      const originalProvider = LlmProviderConfig(
        id: 'provider-full',
        name: '全字段服务商',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        apiKey: 'sk-secret',
        models: [
          LlmProviderModelConfig(
            id: 'model-full',
            displayName: '全字段模型',
            modelName: 'gpt-4o',
            supportsReasoning: true,
          ),
        ],
      );
      await repo.saveProviders(const [originalProvider]);

      final loaded = repo.loadProviders().single;
      expect(loaded.id, originalProvider.id);
      expect(loaded.name, originalProvider.name);
      expect(loaded.apiUrl, originalProvider.apiUrl);
      expect(loaded.apiKey, originalProvider.apiKey);
      expect(loaded.models.single.id, originalProvider.models.single.id);
      expect(
        loaded.models.single.supportsReasoning,
        originalProvider.models.single.supportsReasoning,
      );
    });
  });
}
