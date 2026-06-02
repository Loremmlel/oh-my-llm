import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/settings/data/llm_model_config_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

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
      SharedPreferences.setMockInitialValues({llmModelConfigsStorageKey: ''});
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
      expect(
        loadedModels.every((model) => model.providerId == 'provider-1'),
        isTrue,
      );
    });

  });
}
