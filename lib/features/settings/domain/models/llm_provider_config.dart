import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'llm_model_config.dart';

/// 服务商下单个模型的配置。
class LlmProviderModelConfig extends Equatable {
  const LlmProviderModelConfig({
    required this.id,
    required this.displayName,
    required this.modelName,
    required this.supportsReasoning,
  });

  final String id;
  final String displayName;
  final String modelName;
  final bool supportsReasoning;

  LlmProviderModelConfig copyWith({
    String? id,
    String? displayName,
    String? modelName,
    bool? supportsReasoning,
  }) {
    return LlmProviderModelConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      modelName: modelName ?? this.modelName,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'modelName': modelName,
      'supportsReasoning': supportsReasoning,
    };
  }

  factory LlmProviderModelConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderModelConfig(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      modelName: json['modelName'] as String,
      supportsReasoning: json['supportsReasoning'] as bool? ?? false,
    );
  }

  /// 把模型与服务商凭据拼成请求层需要的完整配置。
  LlmModelConfig resolveForProvider(LlmProviderConfig provider) {
    return LlmModelConfig(
      id: id,
      displayName: displayName,
      apiUrl: provider.apiUrl,
      apiKey: provider.apiKey,
      modelName: modelName,
      supportsReasoning: supportsReasoning,
      providerId: provider.id,
      providerName: provider.name,
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, displayName, modelName, supportsReasoning];
}

/// LLM 服务商配置，持有共享的 URL / Key 与其下模型列表。
class LlmProviderConfig extends Equatable {
  const LlmProviderConfig({
    required this.id,
    required this.name,
    required this.apiUrl,
    required this.apiKey,
    this.models = const [],
  });

  final String id;
  final String name;
  final String apiUrl;
  final String apiKey;
  final List<LlmProviderModelConfig> models;

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? apiUrl,
    String? apiKey,
    List<LlmProviderModelConfig>? models,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'models': models.map((model) => model.toJson()).toList(growable: false),
    };
  }

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'] as List<dynamic>? ?? const [];
    return LlmProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      apiUrl: json['apiUrl'] as String,
      apiKey: json['apiKey'] as String,
      models: rawModels
          .map((item) {
            return LlmProviderModelConfig.fromJson(
              Map<String, dynamic>.from(item as Map),
            );
          })
          .toList(growable: false),
    );
  }

  /// 把当前服务商下所有模型展开为请求层可用的模型配置。
  List<LlmModelConfig> get resolvedModels {
    return models
        .map((model) => model.resolveForProvider(this))
        .toList(growable: false);
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, name, apiUrl, apiKey, models];
}

/// 将旧版平铺模型配置聚合为当前的“服务商 + 模型”结构。
///
/// 旧数据按 `apiUrl + apiKey` 归并到同一个服务商下，服务商名称沿用
/// 自动生成的占位文案，交由后续编辑流程让用户按需重命名。
List<LlmProviderConfig> migrateLegacyModelsToProviders(
  Iterable<LlmModelConfig> models,
) {
  final providers = <LlmProviderConfig>[];
  final providerIndexBySignature = <String, int>{};

  for (final model in models) {
    final signature = _buildLegacyProviderSignature(model.apiUrl, model.apiKey);
    final existingIndex = providerIndexBySignature[signature];
    final providerModel = LlmProviderModelConfig(
      id: model.id,
      displayName: model.displayName,
      modelName: model.modelName,
      supportsReasoning: model.supportsReasoning,
    );

    if (existingIndex == null) {
      providerIndexBySignature[signature] = providers.length;
      providers.add(
        LlmProviderConfig(
          id: 'provider-${providers.length + 1}',
          name: '服务商${providers.length + 1}',
          apiUrl: model.apiUrl,
          apiKey: model.apiKey,
          models: [providerModel],
        ),
      );
      continue;
    }

    final existingProvider = providers[existingIndex];
    providers[existingIndex] = existingProvider.copyWith(
      models: [...existingProvider.models, providerModel],
    );
  }

  return providers;
}

String _buildLegacyProviderSignature(String apiUrl, String apiKey) {
  return '${apiUrl.trim()}::${apiKey.trim()}';
}
