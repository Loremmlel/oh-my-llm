import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';

void main() {
  const allProtocols = [
    LlmApiProtocol.chatCompletions,
    LlmApiProtocol.responses,
    LlmApiProtocol.anthropic,
  ];

  group('LlmProviderModelConfig', () {
    test('resolveForProvider 拼接完整配置并继承 provider 协议', () {
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
        apiProtocol: LlmApiProtocol.responses,
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
      expect(resolved.apiProtocol, LlmApiProtocol.responses);
    });

    test('resolveForProvider 三种协议都能带入', () {
      for (final protocol in allProtocols) {
        const model = LlmProviderModelConfig(
          id: 'model-1',
          displayName: 'D',
          modelName: 'n',
          supportsReasoning: false,
        );
        final provider = LlmProviderConfig(
          id: 'provider-1',
          name: 'P',
          apiUrl: 'url',
          apiKey: 'key',
          apiProtocol: protocol,
        );
        expect(model.resolveForProvider(provider).apiProtocol, protocol);
      }
    });

    test('fromJson supportsReasoning 默认 false', () {
      final model = LlmProviderModelConfig.fromJson({
        'id': 'm1',
        'displayName': 'D',
        'modelName': 'n',
      });
      expect(model.supportsReasoning, isFalse);
    });
  });

  group('LlmProviderConfig', () {
    const model1 = LlmProviderModelConfig(
      id: 'm1',
      displayName: 'M1',
      modelName: 'model-1',
      supportsReasoning: false,
    );
    const model2 = LlmProviderModelConfig(
      id: 'm2',
      displayName: 'M2',
      modelName: 'model-2',
      supportsReasoning: true,
    );

    test('resolvedModels 展开所有模型并携带协议', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: 'P',
        apiUrl: 'url',
        apiKey: 'key',
        apiProtocol: LlmApiProtocol.anthropic,
        models: [model1, model2],
      );
      final resolved = provider.resolvedModels;
      expect(resolved, hasLength(2));
      expect(resolved[0].modelName, 'model-1');
      expect(resolved[1].modelName, 'model-2');
      expect(resolved[0].providerId, 'p1');
      expect(resolved[0].apiProtocol, LlmApiProtocol.anthropic);
    });

    test('resolvedModels 空模型列表返回空', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: 'P',
        apiUrl: 'url',
        apiKey: 'key',
        apiProtocol: LlmApiProtocol.chatCompletions,
      );
      expect(provider.resolvedModels, isEmpty);
    });

    test('fromJson models 为 null 时回退为空列表', () {
      final provider = LlmProviderConfig.fromJson({
        'id': 'p1',
        'name': 'P',
        'apiUrl': 'url',
        'apiKey': 'key',
      });
      expect(provider.models, isEmpty);
      expect(provider.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('fromJson 缺 apiProtocol 时默认 chatCompletions', () {
      final provider = LlmProviderConfig.fromJson({
        'id': 'p1',
        'name': 'P',
        'apiUrl': 'url',
        'apiKey': 'key',
        'models': [model1.toJson()],
      });
      expect(provider.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('fromJson 显式 null apiProtocol 抛 FormatException', () {
      expect(
        () => LlmProviderConfig.fromJson({
          'id': 'p1',
          'name': 'P',
          'apiUrl': 'url',
          'apiKey': 'key',
          'apiProtocol': null,
        }),
        throwsFormatException,
      );
    });

    test('三种协议 toJson → fromJson round-trip', () {
      for (final protocol in allProtocols) {
        final provider = LlmProviderConfig(
          id: 'p1',
          name: 'P',
          apiUrl: 'url',
          apiKey: 'key',
          apiProtocol: protocol,
          models: [model1],
        );
        final restored = LlmProviderConfig.fromJson(provider.toJson());
        expect(restored, provider);
        expect(restored.apiProtocol, protocol);
      }
    });

    test('toJson 写出 apiProtocol 存储值', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: 'P',
        apiUrl: 'url',
        apiKey: 'key',
        apiProtocol: LlmApiProtocol.anthropic,
      );
      expect(provider.toJson()['apiProtocol'], 'anthropic');
    });

    test('copyWith 支持覆盖 apiProtocol', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: 'P',
        apiUrl: 'url',
        apiKey: 'key',
        apiProtocol: LlmApiProtocol.chatCompletions,
      );
      final updated = provider.copyWith(apiProtocol: LlmApiProtocol.responses);
      expect(updated.apiProtocol, LlmApiProtocol.responses);
      expect(updated.id, 'p1');
      expect(provider.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('props 包含 apiProtocol', () {
      const provider = LlmProviderConfig(
        id: 'p1',
        name: 'P',
        apiUrl: 'url',
        apiKey: 'key',
        apiProtocol: LlmApiProtocol.responses,
      );
      expect(provider.props, contains(LlmApiProtocol.responses));
    });

    test('fromJson 显式未知 apiProtocol 抛 FormatException', () {
      expect(
        () => LlmProviderConfig.fromJson({
          'id': 'p1',
          'name': 'P',
          'apiUrl': 'url',
          'apiKey': 'key',
          'apiProtocol': 'future-protocol',
        }),
        throwsFormatException,
      );
    });

    test('fromJson apiProtocol 为非字符串值抛 FormatException', () {
      for (final badValue in [
        123,
        true,
        {'x': 1},
        ['responses'],
      ]) {
        expect(
          () => LlmProviderConfig.fromJson({
            'id': 'p1',
            'name': 'P',
            'apiUrl': 'url',
            'apiKey': 'key',
            'apiProtocol': badValue,
          }),
          throwsFormatException,
          reason: '$badValue',
        );
      }
    });
  });
}
