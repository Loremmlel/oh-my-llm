import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_provider_config.dart';

void main() {
  test('图像能力默认关闭且服务商解析、复制和 JSON 往返保留独立能力', () {
    final legacy = LlmProviderModelConfig.fromJson({
      'id': 'm',
      'displayName': '模型',
      'modelName': 'vision',
    });
    expect(legacy.supportsImageInput, isFalse);
    final enabled = legacy.copyWith(supportsImageInput: true);
    final provider = LlmProviderConfig(
      id: 'p',
      name: '服务商',
      apiUrl: 'url',
      apiKey: '',
      apiProtocol: LlmApiProtocol.responses,
      models: [enabled],
    );
    final restored = LlmProviderConfig.fromJson(provider.toJson());
    expect(restored, provider);
    expect(restored.models.single.supportsReasoning, isFalse);
    final resolved = restored.resolvedModels.single;
    expect(resolved.supportsImageInput, isTrue);
    expect(LlmModelConfig.fromJson(resolved.toJson()), resolved);
    expect(resolved.copyWith(displayName: '重命名').supportsImageInput, isTrue);
    expect(resolved.copyWith(supportsImageInput: false), isNot(resolved));
  });
}
