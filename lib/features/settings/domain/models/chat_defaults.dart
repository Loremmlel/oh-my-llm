import 'package:equatable/equatable.dart';

/// 聊天页最近一次使用的模型与前置 Prompt 记忆。
class ChatDefaults extends Equatable {
  const ChatDefaults({this.defaultModelId, this.defaultPresetPromptId});

  final String? defaultModelId;
  final String? defaultPresetPromptId;

  /// 复制默认项，并允许单独覆盖或清空字段。
  ChatDefaults copyWith({
    String? defaultModelId,
    String? defaultPresetPromptId,
    bool clearDefaultModelId = false,
    bool clearDefaultPresetPromptId = false,
  }) {
    return ChatDefaults(
      defaultModelId: clearDefaultModelId
          ? null
          : defaultModelId ?? this.defaultModelId,
      defaultPresetPromptId: clearDefaultPresetPromptId
          ? null
          : defaultPresetPromptId ?? this.defaultPresetPromptId,
    );
  }

  /// 将默认项序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'defaultModelId': defaultModelId,
      'defaultPresetPromptId': defaultPresetPromptId,
    };
  }

  /// 从 JSON 反序列化默认项。
  factory ChatDefaults.fromJson(Map<String, dynamic> json) {
    return ChatDefaults(
      defaultModelId: json['defaultModelId'] as String?,
      defaultPresetPromptId:
          json['defaultPresetPromptId'] as String? ??
          json['defaultPromptTemplateId'] as String?,
    );
  }

  @override
  List<Object?> get props => [defaultModelId, defaultPresetPromptId];
}
