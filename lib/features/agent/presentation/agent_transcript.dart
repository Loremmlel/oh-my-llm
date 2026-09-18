import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart'
    as smooth_md;
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../domain/agent_models.dart';
import '../domain/agent_story_state.dart';
import '../application/agent_context.dart';
import 'agent_context_dialog.dart';

String agentRoleLabel(AgentRole role) => switch (role) {
  AgentRole.coordinator => '主 Agent',
  AgentRole.writer => '写作 Agent',
  AgentRole.reviewer => '审稿 Agent',
  AgentRole.character => '角色 Agent',
  AgentRole.state => '状态 Agent',
  AgentRole.summarizer => '总结 Agent',
};

String agentStatusLabel(AgentRunStatus status) => switch (status) {
  AgentRunStatus.running => '运行中',
  AgentRunStatus.completed => '已完成',
  AgentRunStatus.cancelled => '已停止',
  AgentRunStatus.failed => '失败',
  AgentRunStatus.limitReached => '达到上限',
  AgentRunStatus.interrupted => '意外中断',
};

String agentUsageLabel(AgentRunRecord record) {
  final usage = record.usage;
  final input = usage?.inputTokens, cached = usage?.cachedInputTokens;
  return '${record.modelCalls} 次调用 · 输入 ${input ?? '—'} · 输出 ${usage?.outputTokens ?? '—'} · 缓存读取 ${cached ?? '—'} · 缓存写入 ${usage?.cacheWriteInputTokens ?? '—'}${record.usageIncomplete || record.status != AgentRunStatus.completed ? '（部分用量未报告）' : ''}';
}

String agentTreeUsageLabel(AgentRunRecord root, List<AgentRunRecord> records) {
  var total = root;
  final descendants = <String>{root.id};
  var previous = -1;
  while (previous != descendants.length) {
    previous = descendants.length;
    descendants.addAll(
      records.where((r) => descendants.contains(r.parentId)).map((r) => r.id),
    );
  }
  for (final child in records.where(
    (r) => r.id != root.id && descendants.contains(r.id),
  )) {
    total = total.copyWith(
      modelCalls: total.modelCalls + child.modelCalls,
      usage: addAgentUsage(total.usage, child.usage),
      usageIncomplete:
          total.usageIncomplete ||
          child.usageIncomplete ||
          child.status != AgentRunStatus.completed,
    );
  }
  return agentUsageLabel(total);
}

class AgentChildLink extends StatelessWidget {
  const AgentChildLink({super.key, required this.record});
  final AgentRunRecord record;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => context.pushNamed(
      'agentRun',
      pathParameters: {'workspaceId': record.workspaceId, 'runId': record.id},
    ),
    icon: Icon(
      record.status == AgentRunStatus.running
          ? Icons.pending_outlined
          : Icons.subdirectory_arrow_right,
      size: 18,
    ),
    label: Text(
      '${agentRoleLabel(record.role)} · ${record.id.split('-').last} · ${agentStatusLabel(record.status)}',
    ),
  );
}

/// 主会话和子会话共用同一执行流，只有读者操作时才主动改变滚动位置。
class AgentTranscript extends StatefulWidget {
  const AgentTranscript({
    super.key,
    required this.records,
    required this.allRuns,
    this.storyRounds = const [],
    this.retryReplyId,
    this.onRetry,
  });
  final List<AgentRunRecord> records, allRuns;
  final List<AgentStoryRound> storyRounds;
  final String? retryReplyId;
  final VoidCallback? onRetry;
  @override
  State<AgentTranscript> createState() => _AgentTranscriptState();
}

class _AgentTranscriptState extends State<AgentTranscript> {
  final _scroll = ScrollController();
  bool _showLatestButton = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            '从一个任务开始\n\n添加工作文档，再描述要写作、审查或改写的内容。\n思考、工具调用和子 Agent 将在这里依次出现。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<Notification>(
          onNotification: (notification) {
            // 内容增长也会改变末尾距离；通知只控制按钮，不触发自动滚动。
            final metrics = switch (notification) {
              ScrollNotification(depth: 0, :final metrics) ||
              ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
              _ => null,
            };
            if (metrics != null) {
              final showLatest = metrics.extentAfter > 80;
              if (showLatest != _showLatestButton) {
                setState(() => _showLatestButton = showLatest);
              }
            }
            return false;
          },
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: widget.records.length,
              itemBuilder: (context, index) {
                final record = widget.records[index];
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppContentWidths.form,
                    ),
                    child: _RunTranscript(
                      key: ValueKey(record.id),
                      record: record,
                      showRetry: record.id == widget.retryReplyId,
                      onRetry: widget.onRetry,
                      round: widget.storyRounds
                          .where(
                            (r) =>
                                (record.role == AgentRole.writer ||
                                    record.role == AgentRole.coordinator) &&
                                r.id == record.roundRunId,
                          )
                          .firstOrNull,
                      children:
                          widget.allRuns
                              .where((r) => r.parentId == record.id)
                              .toList()
                            ..sort(
                              (a, b) => a.startedAt.compareTo(b.startedAt),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_showLatestButton)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.xs,
            child: FilledButton.tonalIcon(
              onPressed: () {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              },
              icon: const Icon(Icons.arrow_downward),
              label: const Text('回到最新'),
            ),
          ),
      ],
    );
  }
}

class _RunTranscript extends StatefulWidget {
  const _RunTranscript({
    super.key,
    required this.record,
    required this.children,
    this.round,
    this.showRetry = false,
    this.onRetry,
  });
  final AgentRunRecord record;
  final List<AgentRunRecord> children;
  final AgentStoryRound? round;
  final bool showRetry;
  final VoidCallback? onRetry;
  @override
  State<_RunTranscript> createState() => _RunTranscriptState();
}

class _RunTranscriptState extends State<_RunTranscript> {
  late bool _expanded = !_hasResult;
  AgentRunRecord get record => widget.record;
  List<AgentRunRecord> get children => widget.children;
  bool get _hasResult =>
      widget.round != null || record.status != AgentRunStatus.running;
  @override
  void didUpdateWidget(_RunTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.round == null && widget.round != null) ||
        (oldWidget.record.status == AgentRunStatus.running &&
            record.status != AgentRunStatus.running)) {
      _expanded = false;
    }
    if (oldWidget.record.status != AgentRunStatus.running &&
        record.status == AgentRunStatus.running) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.parentId == null ? '你' : '委派任务',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(record.prompt),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  '${_expanded ? '收起' : '展开'}执行过程 · ${record.steps.length} 步',
                ),
              ),
              if (widget.showRetry)
                TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
            ],
          ),
          if (_expanded) ...[
            if (children.isNotEmpty)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final child in children)
                    AgentChildLink(key: ValueKey(child.id), record: child),
                ],
              ),
            for (var i = 0; i < record.steps.length; i++)
              _StepView(
                key: ValueKey('${record.id}/$i'),
                step: record.steps[i],
                record: record,
              ),
            Text(
              agentTreeUsageLabel(record, [record, ...children]),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (widget.round != null ||
              (record.status != AgentRunStatus.running &&
                  record.content.isNotEmpty &&
                  (!_expanded || record.steps.isEmpty)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: _AgentMarkdown(
                content: widget.round?.document.content ?? record.content,
              ),
            ),
          if (widget.round?.status == AgentStoryRoundStatus.pending)
            const Text('正文已选定，剧情状态待更新。'),
          if (record.status == AgentRunStatus.running &&
              !record.steps.any((s) => s.isRunning))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text('等待子 Agent 完成…'),
            ),
          if (record.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SelectableText(
                record.error,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              widget.round?.status == AgentStoryRoundStatus.committed
                  ? '正文已采用'
                  : agentStatusLabel(record.status),
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({super.key, required this.step, required this.record});
  final AgentStep step;
  final AgentRunRecord record;
  @override
  Widget build(BuildContext context) {
    if (step.kind == AgentStepKind.tool) {
      Map<String, dynamic>? payload;
      try {
        payload = jsonDecode(step.content) as Map<String, dynamic>;
      } catch (_) {
        /* 旧记录保持可读。 */
      }
      final arguments = payload?['arguments'];
      final name = arguments is Map
          ? arguments['name'] ?? arguments['role'] ?? arguments['task_id']
          : null;
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        minTileHeight: 48,
        dense: true,
        visualDensity: VisualDensity.compact,
        childrenPadding: const EdgeInsets.only(
          left: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        leading: Icon(
          step.isRunning
              ? Icons.pending_outlined
              : step.isError
              ? Icons.error_outline
              : Icons.check,
          size: 18,
        ),
        title: Text(
          [
            step.label,
            if (name != null) '$name',
            if (step.isRunning) '执行中',
            if (step.isError) '未成功',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(_formatTool(payload, step.content)),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (step.inputItemCount != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    showAgentContext(context, record: record, step: step),
                icon: const Icon(Icons.manage_search),
                label: Text('查看${step.label}的输入'),
              ),
            ),
          if (step.reasoning.isNotEmpty)
            _ReasoningView(text: step.reasoning, running: step.isRunning),
          if (step.isRunning && step.reasoning.isEmpty && step.content.isEmpty)
            const Text('等待模型响应…'),
          if (step.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: _AgentMarkdown(content: step.content),
            ),
        ],
      ),
    );
  }
}

class _AgentMarkdown extends StatelessWidget {
  const _AgentMarkdown({required this.content});
  final String content;
  @override
  Widget build(BuildContext context) => smooth_md.SmoothMarkdown(
    data: content,
    selectable: true,
    styleSheet: smooth_md.MarkdownStyleSheet.fromTheme(Theme.of(context)),
  );
}

String _formatTool(Map<String, dynamic>? payload, String fallback) {
  if (payload == null) return fallback;
  Object? result = payload['result'];
  if (result is String) {
    try {
      result = jsonDecode(result);
    } catch (_) {
      /* 文本结果无需再解码。 */
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  return '参数\n${encoder.convert(payload['arguments'])}'
      '${payload.containsKey('result') ? '\n\n结果\n${result is String ? result : encoder.convert(result)}' : ''}';
}

class _ReasoningView extends StatefulWidget {
  const _ReasoningView({required this.text, required this.running});
  final String text;
  final bool running;
  @override
  State<_ReasoningView> createState() => _ReasoningViewState();
}

class _ReasoningViewState extends State<_ReasoningView> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              '${widget.running ? '思考中' : '思考过程'} · ${text.length} 字符${_expanded ? ' · 收起' : ' · 展开'}',
            ),
          ),
        ),
        if (_expanded || widget.running)
          Container(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            ),
            child: SelectableText(
              _expanded || text.length <= 480
                  ? text
                  : '…${text.substring(text.length - 480)}',
              maxLines: _expanded ? null : 4,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
