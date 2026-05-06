import 'dart:convert';

import 'package:equatable/equatable.dart';

/// OpenAI 兼容模型配置。
class LlmModelConfig extends Equatable {
  const LlmModelConfig({
    required this.id,
    required this.displayName,
    required this.apiUrl,
    required this.apiKey,
    required this.modelName,
    required this.supportsReasoning,
    this.providerId = '',
    this.providerName = '',
  });

  final String id;
  final String displayName;
  final String apiUrl;
  final String apiKey;
  final String modelName;
  final bool supportsReasoning;
  final String providerId;
  final String providerName;

  /// 复制模型配置，并允许覆盖任意字段。
  LlmModelConfig copyWith({
    String? id,
    String? displayName,
    String? apiUrl,
    String? apiKey,
    String? modelName,
    bool? supportsReasoning,
    String? providerId,
    String? providerName,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
    );
  }

  /// 将模型配置序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'modelName': modelName,
      'supportsReasoning': supportsReasoning,
      if (providerId.isNotEmpty) 'providerId': providerId,
      if (providerName.isNotEmpty) 'providerName': providerName,
    };
  }

  /// 从 JSON 反序列化模型配置。
  factory LlmModelConfig.fromJson(Map<String, dynamic> json) {
    return LlmModelConfig(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      apiUrl: json['apiUrl'] as String,
      apiKey: json['apiKey'] as String,
      modelName: json['modelName'] as String,
      supportsReasoning: json['supportsReasoning'] as bool? ?? false,
      providerId: json['providerId'] as String? ?? '',
      providerName: json['providerName'] as String? ?? '',
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  List<Object> get props {
    return [
      id,
      displayName,
      apiUrl,
      apiKey,
      modelName,
      supportsReasoning,
      providerId,
      providerName,
    ];
  }
}
