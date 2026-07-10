import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  group('LlmProviderModelConfig', () {
    test('resolveForProvider 拼接完整配置', () {
      const model = LlmProviderModelConfig(
        id: 'model-1',
        displayName: 'GPT-4',
        modelName: 'gpt-4',
        supportsReasoning: true,
      );
      const provider = LlmProviderConfig(
        id: 'provider-1',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-xxx',
      );
      final resolved = model.resolveForProvider(provider);
      expect(resolved.id, 'model-1');
      expect(resolved.displayName, 'GPT-4');
      expect(resolved.modelName, 'gpt-4');
      expect(resolved.apiUrl, 'https://api.openai.com/v1');
      expect(resolved.apiKey, 'sk-xxx');
      expect(resolved.supportsReasoning, isTrue);
      expect(resolved.providerId, 'provider-1');
      expect(resolved.providerName, 'OpenAI');
    });

    test('fromJson supportsReasoning 默认 false', () {
      final model = LlmProviderModelConfig.fromJson({
        'id': 'm1', 'displayName': 'D', 'modelName': 'n',
      });
      expect(model.supportsReasoning, isFalse);
    });
  });

  group('LlmProviderConfig', () {
    const model1 = LlmProviderModelConfig(
      id: 'm1', displayName: 'M1', modelName: 'model-1', supportsReasoning: false,
    );
    const model2 = LlmProviderModelConfig(
      id: 'm2', displayName: 'M2', modelName: 'model-2', supportsReasoning: true,
    );

    test('resolvedModels 展开所有模型', () {
      const provider = LlmProviderConfig(
        id: 'p1', name: 'P', apiUrl: 'url', apiKey: 'key',
        models: [model1, model2],
      );
      final resolved = provider.resolvedModels;
      expect(resolved, hasLength(2));
      expect(resolved[0].modelName, 'model-1');
      expect(resolved[1].modelName, 'model-2');
      expect(resolved[0].providerId, 'p1');
    });

    test('resolvedModels 空模型列表返回空', () {
      const provider = LlmProviderConfig(
        id: 'p1', name: 'P', apiUrl: 'url', apiKey: 'key',
      );
      expect(provider.resolvedModels, isEmpty);
    });

    test('fromJson models 为 null 时回退为空列表', () {
      final provider = LlmProviderConfig.fromJson({
        'id': 'p1', 'name': 'P', 'apiUrl': 'url', 'apiKey': 'key',
      });
      expect(provider.models, isEmpty);
    });

    test('toJson → fromJson round-trip', () {
      const provider = LlmProviderConfig(
        id: 'p1', name: 'P', apiUrl: 'url', apiKey: 'key',
        models: [model1],
      );
      final restored = LlmProviderConfig.fromJson(provider.toJson());
      expect(restored, provider);
    });
  });
}
