import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

import '../../../helpers/fixtures.dart';

/// 构造一个仅含指定模型 id 的最小服务商。
LlmProviderConfig _provider(String id, List<String> modelIds) {
  return LlmProviderConfig(
    id: id,
    name: id,
    apiUrl: 'https://$id.example.com/v1/chat/completions',
    apiKey: 'sk-test',
    models: [
      for (final modelId in modelIds)
        LlmProviderModelConfig(
          id: modelId,
          displayName: modelId,
          modelName: modelId,
          supportsReasoning: false,
        ),
    ],
  );
}

void main() {
  group('resolveSelectedModel', () {
    test('conversation selected 优先', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: 'model-claude',
        rememberedModelId: 'model-gpt',
      );
      expect(selected!.id, 'model-claude');
    });

    test('无 conversation 选中时回退 remembered default', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: 'model-claude',
      );
      expect(selected!.id, 'model-claude');
    });

    test('无 remembered 时回退首模型', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: null,
      );
      expect(selected!.id, 'model-gpt');
    });

    test('空列表返回 null', () {
      expect(
        resolveSelectedModel(
          modelConfigs: const [],
          selectedModelId: null,
          rememberedModelId: null,
        ),
        isNull,
      );
    });
  });

  group('resolveSelectedProviderId', () {
    test('无可用服务商返回 null', () {
      expect(
        resolveSelectedProviderId(
          providers: const [],
          selectedModel: TestFixtures.gpt41(),
        ),
        isNull,
      );
    });

    test('选中模型所属服务商优先', () {
      final providers = [
        _provider('provider-a', ['model-gpt']),
      ];
      expect(
        resolveSelectedProviderId(
          providers: providers,
          selectedModel: TestFixtures.model(
            id: 'model-gpt',
            providerId: 'provider-a',
          ),
        ),
        'provider-a',
      );
    });

    test('选中模型不在服务商列表时回退首服务商', () {
      final providers = [
        _provider('provider-a', ['other']),
      ];
      expect(
        resolveSelectedProviderId(
          providers: providers,
          selectedModel: TestFixtures.gpt41(),
        ),
        'provider-a',
      );
    });
  });

  group('resolveSelectedTemplatePrompt', () {
    test('null 选择返回 null', () {
      expect(
        resolveSelectedTemplatePrompt([
          TestFixtures.templatePrompt(id: 'tp-1'),
        ], null),
        isNull,
      );
    });

    test('命中返回对应模板', () {
      final result = resolveSelectedTemplatePrompt([
        TestFixtures.templatePrompt(id: 'tp-1'),
      ], 'tp-1');
      expect(result!.id, 'tp-1');
    });

    test('选择不存在时返回 null', () {
      expect(
        resolveSelectedTemplatePrompt([
          TestFixtures.templatePrompt(id: 'tp-1'),
        ], 'tp-missing'),
        isNull,
      );
    });
  });
}
