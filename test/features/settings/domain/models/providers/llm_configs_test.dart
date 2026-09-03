import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

void main() {
  const protocols = LlmApiProtocol.values;

  group('LlmModelConfig', () {
    Map<String, dynamic> minimalJson({Object? apiProtocol}) {
      return {
        'id': 'm1',
        'displayName': 'D',
        'apiUrl': 'url',
        'apiKey': 'key',
        'modelName': 'n',
        'apiProtocol': ?apiProtocol,
      };
    }

    test('missing optional provider fields use compatibility defaults', () {
      final config = LlmModelConfig.fromJson(minimalJson());
      expect(config.providerId, '');
      expect(config.providerName, '');
      expect(config.supportsReasoning, isFalse);
      expect(config.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('toJson omits empty provider fields and writes non-empty fields', () {
      const withoutProvider = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
      );
      const withProvider = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
        providerId: 'p1',
        providerName: 'P',
      );

      expect(withoutProvider.toJson(), isNot(contains('providerId')));
      expect(withoutProvider.toJson(), isNot(contains('providerName')));
      expect(withProvider.toJson()['providerId'], 'p1');
      expect(withProvider.toJson()['providerName'], 'P');
    });

    test('every protocol round-trips and keeps its stable storage value', () {
      for (final protocol in protocols) {
        final config = LlmModelConfig(
          id: 'm1',
          displayName: 'D',
          apiUrl: 'url',
          apiKey: 'key',
          modelName: 'n',
          supportsReasoning: false,
          apiProtocol: protocol,
        );

        expect(LlmModelConfig.fromJson(config.toJson()), config);
        expect(config.toJson()['apiProtocol'], protocol.storageValue);
      }
    });

    test('unknown and non-string protocol values are rejected', () {
      for (final badValue in [
        'future-protocol',
        123,
        true,
        {'x': 1},
        ['responses'],
      ]) {
        expect(
          () => LlmModelConfig.fromJson(minimalJson(apiProtocol: badValue)),
          throwsFormatException,
          reason: '$badValue',
        );
      }
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

    Map<String, dynamic> minimalJson({Object? apiProtocol}) {
      return {
        'id': 'p1',
        'name': 'P',
        'apiUrl': 'url',
        'apiKey': 'key',
        'apiProtocol': ?apiProtocol,
      };
    }

    test('resolveForProvider combines model and provider data', () {
      const provider = LlmProviderConfig(
        id: 'provider-1',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-xxx',
        apiProtocol: LlmApiProtocol.responses,
      );

      final resolved = model2.resolveForProvider(provider);
      expect(resolved.id, 'm2');
      expect(resolved.displayName, 'M2');
      expect(resolved.modelName, 'model-2');
      expect(resolved.apiUrl, provider.apiUrl);
      expect(resolved.apiKey, provider.apiKey);
      expect(resolved.supportsReasoning, isTrue);
      expect(resolved.providerId, provider.id);
      expect(resolved.providerName, provider.name);
      expect(resolved.apiProtocol, LlmApiProtocol.responses);
    });

    test('missing models and protocol use compatibility defaults', () {
      final provider = LlmProviderConfig.fromJson(minimalJson());
      expect(provider.models, isEmpty);
      expect(provider.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('every protocol round-trips and keeps its stable storage value', () {
      for (final protocol in protocols) {
        final provider = LlmProviderConfig(
          id: 'p1',
          name: 'P',
          apiUrl: 'url',
          apiKey: 'key',
          apiProtocol: protocol,
          models: const [model1],
        );

        expect(LlmProviderConfig.fromJson(provider.toJson()), provider);
        expect(provider.toJson()['apiProtocol'], protocol.storageValue);
      }
    });

    test('null, unknown, and non-string protocol values are rejected', () {
      for (final badValue in [
        null,
        'future-protocol',
        123,
        true,
        {'x': 1},
        ['responses'],
      ]) {
        final json = minimalJson()..['apiProtocol'] = badValue;
        expect(
          () => LlmProviderConfig.fromJson(json),
          throwsFormatException,
          reason: '$badValue',
        );
      }
    });
  });
}
