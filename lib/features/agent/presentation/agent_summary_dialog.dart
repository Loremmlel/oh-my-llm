import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_context_batch.dart';
import '../domain/agent_models.dart';
import '../domain/agent_story_state.dart';
import 'agent_transcript.dart';

Future<void> showAgentSummaries(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SummaryManager());

class _SummaryManager extends ConsumerStatefulWidget {
  const _SummaryManager();
  @override
  ConsumerState<_SummaryManager> createState() => _SummaryManagerState();
}

class _SummaryManagerState extends ConsumerState<_SummaryManager> {
  final _count = TextEditingController(text: '1');
  String? _error;
  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final batches = controller.contextBatches;
    final rounds = state.storyRounds.reversed
        .where((r) => r.status == AgentStoryRoundStatus.committed)
        .toList();
    final hidden = batches
        .where((b) => b.active)
        .expand((b) => b.roundIds)
        .toSet();
    final available = rounds.where((r) => !hidden.contains(r.id)).toList();
    final summaryRun = state.runs
        .where((r) => r.role == AgentRole.summarizer)
        .firstOrNull;
    final enabled =
        !state.busy &&
        state.latestRound?.status != AgentStoryRoundStatus.pending;
    String range(AgentContextBatch batch) {
      final first = rounds.indexWhere((r) => r.id == batch.roundIds.first);
      final last = rounds.indexWhere((r) => r.id == batch.roundIds.last);
      return first < 0 || last < 0
          ? '${batch.roundIds.length} 楼（来源已变化）'
          : '第 ${first + 1}—${last + 1} 楼';
    }

    void apply(bool summarize) {
      try {
        final batch = controller.contextBatchFor(
          int.tryParse(_count.text) ?? 0,
        );
        setState(() => _error = null);
        if (summarize) {
          unawaited(controller.send(summaryBatch: batch));
        } else {
          controller.saveContextBatch(batch);
        }
      } on AgentWorkspaceException catch (error) {
        setState(() => _error = error.message);
      }
    }

    return AlertDialog(
      title: const Text('总结管理'),
      content: SizedBox(
        width: AppContentWidths.readable,
        height: 560,
        child: ListView(
          children: [
            Text(
              '正式正文 ${rounds.length} 楼 · 原文参与 ${available.length} 楼 · 已整理 ${hidden.length} 楼',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '总结放在正文之前。隐藏仅排除可定位的正式正文块；工具结果、Reasoning 和旧会话中已有的正文副本仍保留。原文和剧情状态不会删除。',
            ),
            const SizedBox(height: AppSpacing.md),
            if (available.isEmpty)
              const Text('暂无可整理的正文。完成写作后可在这里批量隐藏或总结。')
            else ...[
              Text('从较早未整理的正文开始（第 ${rounds.indexOf(available.first) + 1} 楼）'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _count,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '处理楼数',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton(
                    onPressed: enabled ? () => apply(false) : null,
                    child: const Text('直接隐藏'),
                  ),
                  FilledButton(
                    onPressed: enabled ? () => apply(true) : null,
                    child: const Text('总结并替代'),
                  ),
                ],
              ),
            ],
            if (state.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  state.error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (summaryRun != null) ...[
              const Divider(),
              Text('最近总结任务 · ${agentStatusLabel(summaryRun.status)}'),
              Text(
                agentUsageLabel(summaryRun),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (summaryRun.error.isNotEmpty) Text(summaryRun.error),
              if (summaryRun.status == AgentRunStatus.running)
                const Text('正在总结，关闭窗口后任务仍会继续。'),
              if (summaryRun.content.isNotEmpty &&
                  summaryRun.status == AgentRunStatus.running)
                SelectableText(summaryRun.content),
              if (controller.retrySummaryBatch case final batch?)
                TextButton(
                  onPressed: enabled
                      ? () => controller.send(summaryBatch: batch)
                      : null,
                  child: const Text('重试总结'),
                ),
            ],
            for (final batch in batches) ...[
              const Divider(),
              Text(
                '${range(batch)} · ${switch (batch.status) {
                  AgentContextBatchStatus.active => batch.summary.isEmpty ? '已隐藏' : '摘要生效',
                  AgentContextBatchStatus.restored => '原文已恢复',
                  AgentContextBatchStatus.invalidated => '来源失效',
                }}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (batch.summary.isNotEmpty) SelectableText(batch.summary),
              ExpansionTile(
                title: const Text('查看来源正文'),
                children: [
                  for (final round in state.storyRounds.reversed.where(
                    (r) => batch.roundIds.contains(r.id),
                  ))
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: SelectableText(
                        '${round.document.name}\n${round.document.content}',
                      ),
                    ),
                ],
              ),
              if (batch.status != AgentContextBatchStatus.invalidated)
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    TextButton(
                      onPressed: enabled
                          ? () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _SummaryEditor(
                                batch: batch,
                                label: range(batch),
                              ),
                            )
                          : null,
                      child: const Text('编辑摘要'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => controller.send(summaryBatch: batch)
                          : null,
                      child: const Text('重新总结'),
                    ),
                    if (batch.active)
                      TextButton(
                        onPressed: enabled
                            ? () => controller.saveContextBatch(
                                batch.copyWith(
                                  status: AgentContextBatchStatus.restored,
                                ),
                              )
                            : null,
                        child: const Text('恢复原文'),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (state.busy)
          OutlinedButton.icon(
            onPressed: controller.stop,
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _SummaryEditor extends ConsumerStatefulWidget {
  const _SummaryEditor({required this.batch, required this.label});
  final AgentContextBatch batch;
  final String label;
  @override
  ConsumerState<_SummaryEditor> createState() => _SummaryEditorState();
}

class _SummaryEditorState extends ConsumerState<_SummaryEditor> {
  late final _text = TextEditingController(text: widget.batch.summary);
  bool _allowClose = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_text.text != widget.batch.summary) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (_) => const AppConfirmDialog(
          title: '放弃未保存的修改？',
          message: '已保存的摘要不受影响。',
          confirmLabel: '放弃修改',
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) {
      setState(() => _allowClose = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    return PopScope<void>(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text('编辑摘要 · ${widget.label}'),
        content: SizedBox(
          width: AppContentWidths.readable,
          height: 400,
          child: Column(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: '摘要',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (state.error.isNotEmpty)
                Text(
                  state.error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('取消')),
          FilledButton(
            onPressed: state.busy
                ? null
                : () {
                    ref
                        .read(agentWorkspaceProvider.notifier)
                        .saveContextBatch(
                          widget.batch.copyWith(summary: _text.text),
                        );
                    if (ref.read(agentWorkspaceProvider).error.isEmpty) {
                      setState(() => _allowClose = true);
                      Navigator.of(context).pop();
                    }
                  },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
