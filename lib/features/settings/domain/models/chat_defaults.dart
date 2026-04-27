import 'package:equatable/equatable.dart';

/// 聊天页使用的默认模型与默认 Prompt 配置。
class ChatDefaults extends Equatable {
  const ChatDefaults({this.defaultModelId, this.defaultPromptTemplateId});

  final String? defaultModelId;
  final String? defaultPromptTemplateId;

  /// 复制默认项，并允许单独覆盖或清空字段。
  ChatDefaults copyWith({
    String? defaultModelId,
    String? defaultPromptTemplateId,
    bool clearDefaultModelId = false,
    bool clearDefaultPromptTemplateId = false,
  }) {
    return ChatDefaults(
      defaultModelId: clearDefaultModelId
          ? null
          : defaultModelId ?? this.defaultModelId,
      defaultPromptTemplateId: clearDefaultPromptTemplateId
          ? null
          : defaultPromptTemplateId ?? this.defaultPromptTemplateId,
    );
  }

  /// 将默认项序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'defaultModelId': defaultModelId,
      'defaultPromptTemplateId': defaultPromptTemplateId,
    };
  }

  /// 从 JSON 反序列化默认项。
  factory ChatDefaults.fromJson(Map<String, dynamic> json) {
    return ChatDefaults(
      defaultModelId: json['defaultModelId'] as String?,
      defaultPromptTemplateId: json['defaultPromptTemplateId'] as String?,
    );
  }

  @override
  List<Object?> get props => [defaultModelId, defaultPromptTemplateId];
}
