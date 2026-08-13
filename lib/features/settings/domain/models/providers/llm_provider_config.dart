import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

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
  ///
  /// 协议属于服务商，不落到单个模型配置上。
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
      apiProtocol: provider.apiProtocol,
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props => [id, displayName, modelName, supportsReasoning];
}

/// LLM 服务商配置，持有共享的 URL / Key / API 协议与其下模型列表。
class LlmProviderConfig extends Equatable {
  const LlmProviderConfig({
    required this.id,
    required this.name,
    required this.apiUrl,
    required this.apiKey,
    required this.apiProtocol,
    this.models = const [],
  });

  final String id;
  final String name;
  final String apiUrl;
  final String apiKey;
  final LlmApiProtocol apiProtocol;
  final List<LlmProviderModelConfig> models;

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? apiUrl,
    String? apiKey,
    LlmApiProtocol? apiProtocol,
    List<LlmProviderModelConfig>? models,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      apiProtocol: apiProtocol ?? this.apiProtocol,
      models: models ?? this.models,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'apiProtocol': apiProtocol.storageValue,
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
      // 旧 JSON 缺失 apiProtocol 时固定回退为 chatCompletions；显式 null、
      // 未知值或非字符串值均由解析失败，不做静默降级。
      apiProtocol: !json.containsKey('apiProtocol')
          ? LlmApiProtocol.chatCompletions
          : LlmApiProtocol.fromJsonValue(json['apiProtocol']),
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
  List<Object> get props => [id, name, apiUrl, apiKey, apiProtocol, models];
}
