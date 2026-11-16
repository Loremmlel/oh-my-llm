import 'package:equatable/equatable.dart';

import 'llm_usage.dart';

/// 对话内已有调用的累计用量，缓存命中率按累计缓存输入 / (累计缓存输入 + 累计未命中输入) 计算。
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
    var hasCachedUsage = false;
    var cachedInput = 0;
    var uncachedInput = 0;
    for (final usage in usages) {
      incomplete |= usage?.inputTokens == null || usage?.outputTokens == null;
      if (usage == null) continue;
      tokens = tokens.add(usage);
      final input = usage.inputTokens;
      final cached = usage.cachedInputTokens;
      if (input == null || input <= 0) continue;
      if (cached != null && cached > input) continue;
      if (cached != null) hasCachedUsage = true;
      cachedInput += cached ?? 0;
      uncachedInput += input - (cached ?? 0);
    }
    final denominator = cachedInput + uncachedInput;
    return LlmUsageSummary(
      tokens: tokens,
      cacheHitRate: !hasCachedUsage || denominator == 0
          ? null
          : cachedInput / denominator,
      incomplete: incomplete,
    );
  }

  final LlmUsage tokens;
  final double? cacheHitRate;
  final bool incomplete;

  @override
  List<Object?> get props => [tokens, cacheHitRate, incomplete];
}
