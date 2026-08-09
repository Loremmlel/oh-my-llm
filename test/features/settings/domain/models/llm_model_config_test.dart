import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  const allProtocols = [
    LlmApiProtocol.chatCompletions,
    LlmApiProtocol.responses,
    LlmApiProtocol.anthropic,
  ];

  group('LlmModelConfig', () {
    test('fromJson 缺失 providerId/providerName 默认为空字符串', () {
      final config = LlmModelConfig.fromJson({
        'id': 'm1',
        'displayName': 'D',
        'apiUrl': 'url',
        'apiKey': 'key',
        'modelName': 'n',
      });
      expect(config.providerId, '');
      expect(config.providerName, '');
    });

    test('fromJson supportsReasoning 默认 false', () {
      final config = LlmModelConfig.fromJson({
        'id': 'm1',
        'displayName': 'D',
        'apiUrl': 'url',
        'apiKey': 'key',
        'modelName': 'n',
      });
      expect(config.supportsReasoning, isFalse);
    });

    test('toJson 不序列化空的 providerId/providerName', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
      );
      final json = config.toJson();
      expect(json.containsKey('providerId'), isFalse);
      expect(json.containsKey('providerName'), isFalse);
    });

    test('toJson 序列化非空的 providerId/providerName', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
        providerId: 'p1',
        providerName: 'P',
      );
      final json = config.toJson();
      expect(json['providerId'], 'p1');
      expect(json['providerName'], 'P');
    });

    test('构造缺省 apiProtocol 默认 chatCompletions', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
      );
      expect(config.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('fromJson 缺 apiProtocol 时默认 chatCompletions', () {
      final config = LlmModelConfig.fromJson({
        'id': 'm1',
        'displayName': 'D',
        'apiUrl': 'url',
        'apiKey': 'key',
        'modelName': 'n',
      });
      expect(config.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('三种协议 toJson → fromJson round-trip', () {
      for (final protocol in allProtocols) {
        final config = LlmModelConfig(
          id: 'm1',
          displayName: 'D',
          apiUrl: 'url',
          apiKey: 'key',
          modelName: 'n',
          supportsReasoning: false,
          apiProtocol: protocol,
        );
        final restored = LlmModelConfig.fromJson(config.toJson());
        expect(restored, config);
        expect(restored.apiProtocol, protocol);
      }
    });

    test('toJson 写出 apiProtocol 存储值', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
        apiProtocol: LlmApiProtocol.anthropic,
      );
      expect(config.toJson()['apiProtocol'], 'anthropic');
    });

    test('copyWith 支持覆盖 apiProtocol', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
      );
      final updated = config.copyWith(apiProtocol: LlmApiProtocol.responses);
      expect(updated.apiProtocol, LlmApiProtocol.responses);
      expect(updated.id, 'm1');
      expect(config.apiProtocol, LlmApiProtocol.chatCompletions);
    });

    test('props 包含 apiProtocol', () {
      const config = LlmModelConfig(
        id: 'm1',
        displayName: 'D',
        apiUrl: 'url',
        apiKey: 'key',
        modelName: 'n',
        supportsReasoning: false,
        apiProtocol: LlmApiProtocol.responses,
      );
      expect(config.props, contains(LlmApiProtocol.responses));
    });

    test('fromJson 显式未知 apiProtocol 抛 FormatException', () {
      expect(
        () => LlmModelConfig.fromJson({
          'id': 'm1',
          'displayName': 'D',
          'apiUrl': 'url',
          'apiKey': 'key',
          'modelName': 'n',
          'apiProtocol': 'future-protocol',
        }),
        throwsFormatException,
      );
    });
  });
}
