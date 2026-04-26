import 'package:equatable/equatable.dart';

class ChatDefaults extends Equatable {
  const ChatDefaults({this.defaultModelId, this.defaultPromptTemplateId});

  final String? defaultModelId;
  final String? defaultPromptTemplateId;

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

  Map<String, dynamic> toJson() {
    return {
      'defaultModelId': defaultModelId,
      'defaultPromptTemplateId': defaultPromptTemplateId,
    };
  }

  factory ChatDefaults.fromJson(Map<String, dynamic> json) {
    return ChatDefaults(
      defaultModelId: json['defaultModelId'] as String?,
      defaultPromptTemplateId: json['defaultPromptTemplateId'] as String?,
    );
  }

  @override
  List<Object?> get props => [defaultModelId, defaultPromptTemplateId];
}
