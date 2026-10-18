import 'package:equatable/equatable.dart';

/// 一次模型生成的 Token 用量；协议未提供的字段保持 null。
class LlmUsage extends Equatable {
  const LlmUsage({
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
    this.cacheWriteInputTokens,
    this.outputDuration,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;
  final int? cacheWriteInputTokens;

  /// 从首段正文或思考到生成终态的本地耗时，不包含首段输出前的等待。
  final Duration? outputDuration;

  double? get tokensPerSecond =>
      outputTokens == null ||
          outputDuration == null ||
          outputDuration!.inMicroseconds <= 0
      ? null
      : outputTokens! *
            Duration.microsecondsPerSecond /
            outputDuration!.inMicroseconds;

  /// 缓存写入属于本次未命中缓存的输入，不再额外加入总量。
  int? get uncachedInputTokens => inputTokens == null
      ? null
      : (inputTokens! - (cachedInputTokens ?? 0)).clamp(0, inputTokens!);

  int? get totalTokens => inputTokens == null && outputTokens == null
      ? null
      : (inputTokens ?? 0) + (outputTokens ?? 0);

  bool get hasAnyValue =>
      inputTokens != null ||
      outputTokens != null ||
      reasoningTokens != null ||
      cachedInputTokens != null ||
      cacheWriteInputTokens != null;

  /// 合并分散在多个协议事件中的用量；新事件的已知字段优先。
  LlmUsage merge(LlmUsage newer) {
    return LlmUsage(
      inputTokens: newer.inputTokens ?? inputTokens,
      outputTokens: newer.outputTokens ?? outputTokens,
      reasoningTokens: newer.reasoningTokens ?? reasoningTokens,
      cachedInputTokens: newer.cachedInputTokens ?? cachedInputTokens,
      cacheWriteInputTokens:
          newer.cacheWriteInputTokens ?? cacheWriteInputTokens,
      outputDuration: newer.outputDuration ?? outputDuration,
    );
  }

  /// 不同调用按字段相加，未报告的字段保持未知；单次耗时不参与累计。
  LlmUsage add(LlmUsage other) {
    int? sum(int? a, int? b) =>
        a == null && b == null ? null : (a ?? 0) + (b ?? 0);
    return LlmUsage(
      inputTokens: sum(inputTokens, other.inputTokens),
      outputTokens: sum(outputTokens, other.outputTokens),
      reasoningTokens: sum(reasoningTokens, other.reasoningTokens),
      cachedInputTokens: sum(cachedInputTokens, other.cachedInputTokens),
      cacheWriteInputTokens: sum(
        cacheWriteInputTokens,
        other.cacheWriteInputTokens,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'reasoningTokens': reasoningTokens,
    'cachedInputTokens': cachedInputTokens,
    'cacheWriteInputTokens': cacheWriteInputTokens,
    if (outputDuration != null)
      'outputDurationMicros': outputDuration!.inMicroseconds,
  };

  /// 从协议或持久化 JSON 恢复；无任何有效值时返回 null。
  static LlmUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final usage = LlmUsage(
      inputTokens: _nonNegativeInt(json['inputTokens']),
      outputTokens: _nonNegativeInt(json['outputTokens']),
      reasoningTokens: _nonNegativeInt(json['reasoningTokens']),
      cachedInputTokens: _nonNegativeInt(json['cachedInputTokens']),
      cacheWriteInputTokens: _nonNegativeInt(json['cacheWriteInputTokens']),
      outputDuration: switch (_nonNegativeInt(json['outputDurationMicros'])) {
        final micros? => Duration(microseconds: micros),
        null => null,
      },
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
    outputDuration,
  ];
}
