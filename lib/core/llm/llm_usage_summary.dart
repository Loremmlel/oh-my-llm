import 'package:equatable/equatable.dart';

import 'llm_usage.dart';

/// 对话内已有调用的累计用量，缓存命中率只使用同时报告输入与缓存的记录。
class LlmUsageSummary extends Equatable {
  const LlmUsageSummary({
    this.tokens = const LlmUsage(),
    this.cacheHitRate,
    this.incomplete = false,
  });

  factory LlmUsageSummary.fromUsages(
    Iterable<LlmUsage?> usages, {
    bool incomplete = false,
  }) {
    var tokens = const LlmUsage();
    var cacheInput = 0;
    var cacheRead = 0;
    for (final usage in usages) {
      incomplete |= usage?.inputTokens == null || usage?.outputTokens == null;
      if (usage == null) continue;
      tokens = tokens.add(usage);
      final input = usage.inputTokens;
      final cached = usage.cachedInputTokens;
      if (input != null && input > 0 && cached != null && cached <= input) {
        cacheInput += input;
        cacheRead += cached;
      }
    }
    return LlmUsageSummary(
      tokens: tokens,
      cacheHitRate: cacheInput == 0 ? null : cacheRead / cacheInput,
      incomplete: incomplete,
    );
  }

  final LlmUsage tokens;
  final double? cacheHitRate;
  final bool incomplete;

  @override
  List<Object?> get props => [tokens, cacheHitRate, incomplete];
}
