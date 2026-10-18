import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_usage_summary.dart';

import 'dialogs/detail_display_dialog.dart';

String _tokenCount(int? value) => value == null
    ? '—'
    : value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );

/// Chat 与 Agent 的助手回复共用同一行用量及速度信息。
class LlmReplyUsage extends StatelessWidget {
  const LlmReplyUsage({super.key, required this.usage});

  final LlmUsage usage;

  @override
  Widget build(BuildContext context) {
    final values = <(String, int?)>[
      ('输入', usage.inputTokens),
      ('缓存命中', usage.cachedInputTokens),
      ('缓存写入', usage.cacheWriteInputTokens),
      ('输出', usage.outputTokens),
    ].where((entry) => entry.$2 != null);
    final labels = [
      for (final (label, value) in values) '$label ${_tokenCount(value)}',
      'TPS ${usage.tokensPerSecond?.toStringAsFixed(1) ?? '—'}',
    ];
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final (index, label) in labels.indexed)
          Text(
            '${index == 0 ? '' : '· '}$label',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 对话累计只在入口显示总量，分项和缓存命中率在同一详情中查看。
class ConversationTokenUsage extends StatelessWidget {
  const ConversationTokenUsage({super.key, required this.summary});

  final LlmUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = summary.tokens;
    final partial = summary.incomplete ? '（部分用量未报告）' : '';
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => DetailDisplayDialog(
          title: const Text('对话总 Token'),
          child: SelectableText(
            [
              '总 Token：${_tokenCount(tokens.totalTokens)}$partial',
              '输入未缓存：${_tokenCount(tokens.uncachedInputTokens)}',
              if (tokens.cachedInputTokens != null)
                '输入缓存命中：${_tokenCount(tokens.cachedInputTokens)}',
              if (tokens.cacheWriteInputTokens != null)
                '其中缓存写入：${_tokenCount(tokens.cacheWriteInputTokens)}',
              '输出：${_tokenCount(tokens.outputTokens)}',
              '缓存命中率：${summary.cacheHitRate == null ? '—' : '${(summary.cacheHitRate! * 100).toStringAsFixed(1)}%'}',
            ].join('\n'),
          ),
        ),
      ),
      child: Text(
        '总 Token ${_tokenCount(tokens.totalTokens)}${summary.incomplete ? ' *' : ''}',
      ),
    );
  }
}
