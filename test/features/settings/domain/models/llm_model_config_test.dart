import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
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
        'id': 'm1', 'displayName': 'D', 'apiUrl': 'url',
        'apiKey': 'key', 'modelName': 'n',
      });
      expect(config.supportsReasoning, isFalse);
    });

    test('toJson 不序列化空的 providerId/providerName', () {
      const config = LlmModelConfig(
        id: 'm1', displayName: 'D', apiUrl: 'url',
        apiKey: 'key', modelName: 'n', supportsReasoning: false,
      );
      final json = config.toJson();
      expect(json.containsKey('providerId'), isFalse);
      expect(json.containsKey('providerName'), isFalse);
    });

    test('toJson 序列化非空的 providerId/providerName', () {
      const config = LlmModelConfig(
        id: 'm1', displayName: 'D', apiUrl: 'url',
        apiKey: 'key', modelName: 'n', supportsReasoning: false,
        providerId: 'p1', providerName: 'P',
      );
      final json = config.toJson();
      expect(json['providerId'], 'p1');
      expect(json['providerName'], 'P');
    });
  });
}
