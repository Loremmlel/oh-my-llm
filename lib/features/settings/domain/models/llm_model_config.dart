import 'dart:convert';

import 'package:equatable/equatable.dart';

class LlmModelConfig extends Equatable {
  const LlmModelConfig({
    required this.id,
    required this.displayName,
    required this.apiUrl,
    required this.apiKey,
    required this.modelName,
    required this.supportsReasoning,
  });

  final String id;
  final String displayName;
  final String apiUrl;
  final String apiKey;
  final String modelName;
  final bool supportsReasoning;

  LlmModelConfig copyWith({
    String? id,
    String? displayName,
    String? apiUrl,
    String? apiKey,
    String? modelName,
    bool? supportsReasoning,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'modelName': modelName,
      'supportsReasoning': supportsReasoning,
    };
  }

  factory LlmModelConfig.fromJson(Map<String, dynamic> json) {
    return LlmModelConfig(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      apiUrl: json['apiUrl'] as String,
      apiKey: json['apiKey'] as String,
      modelName: json['modelName'] as String,
      supportsReasoning: json['supportsReasoning'] as bool? ?? false,
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
    ];
  }
}
