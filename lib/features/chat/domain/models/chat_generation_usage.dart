import 'package:equatable/equatable.dart';

/// 一次模型生成的 Token 用量；协议未提供的字段保持 null。
class ChatGenerationUsage extends Equatable {
  const ChatGenerationUsage({
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
    this.cacheWriteInputTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;
  final int? cacheWriteInputTokens;

  bool get hasAnyValue =>
      inputTokens != null ||
      outputTokens != null ||
      reasoningTokens != null ||
      cachedInputTokens != null ||
      cacheWriteInputTokens != null;

  /// 合并分散在多个协议事件中的用量；新事件的已知字段优先。
  ChatGenerationUsage merge(ChatGenerationUsage newer) {
    return ChatGenerationUsage(
      inputTokens: newer.inputTokens ?? inputTokens,
      outputTokens: newer.outputTokens ?? outputTokens,
      reasoningTokens: newer.reasoningTokens ?? reasoningTokens,
      cachedInputTokens: newer.cachedInputTokens ?? cachedInputTokens,
      cacheWriteInputTokens:
          newer.cacheWriteInputTokens ?? cacheWriteInputTokens,
    );
  }

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'cachedInputTokens': cachedInputTokens,
    'cacheWriteInputTokens': cacheWriteInputTokens,
  };

  /// 从协议或持久化 JSON 恢复；无任何有效值时返回 null。
  static ChatGenerationUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final usage = ChatGenerationUsage(
      inputTokens: _nonNegativeInt(json['inputTokens']),
      outputTokens: _nonNegativeInt(json['outputTokens']),
      reasoningTokens: _nonNegativeInt(json['reasoningTokens']),
      cachedInputTokens: _nonNegativeInt(json['cachedInputTokens']),
      cacheWriteInputTokens: _nonNegativeInt(json['cacheWriteInputTokens']),
    );
    return usage.hasAnyValue ? usage : null;
  }

  static int? _nonNegativeInt(Object? value) {
    return value is int && value >= 0 ? value : null;
  }

  @override
  List<Object?> get props => [
    inputTokens,
    outputTokens,
    reasoningTokens,
    cachedInputTokens,
    cacheWriteInputTokens,
  ];
}
