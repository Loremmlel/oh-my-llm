import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart'
    as smooth_md;
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_story_state.dart';

class AgentStoryActions extends ConsumerWidget {
  const AgentStoryActions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentWorkspaceProvider);
    final round = state.latestRound;
    if (round == null) return const SizedBox.shrink();
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final ownSession =
        round.beforeWorkspace.sessionId == state.workspace?.sessionId;
    final pending = round.status == AgentStoryRoundStatus.pending;
    Future<void> withdraw() async {
      final draft = state.workspace!.draft;
      if (draft.isNotEmpty && draft != round.beforeWorkspace.draft) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => const AppConfirmDialog(
            title: '替换当前输入并撤回？',
            message: '当前未发送的输入会替换为本轮原指令，正文与状态回到本轮之前。历史记录仍可查看。',
            confirmLabel: '撤回并替换输入',
          ),
        );
        if (confirmed != true) return;
      }
      controller.withdrawLatestRound();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            pending ? '正文已保留 · 状态待更新' : '本轮正文与状态已保存',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!ownSession)
            TextButton(
              onPressed: state.busy
                  ? null
                  : () => controller.selectSession(
                      round.beforeWorkspace.sessionId,
                    ),
              child: const Text('前往所属会话'),
            )
          else ...[
            if (pending)
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => unawaited(controller.send(retryStory: true)),
                child: const Text('重试状态更新'),
              ),
            TextButton(
              onPressed: state.busy ? null : withdraw,
              child: Text(pending ? '放弃本轮' : '撤回最新一轮'),
            ),
          ],
        ],
      ),
    );
  }
}

class AgentStoryPanel extends ConsumerWidget {
  const AgentStoryPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentWorkspaceProvider);
    final rounds = state.storyRounds;
    final prose = rounds
        .where(
          (r) =>
              r.status == AgentStoryRoundStatus.committed ||
              r.status == AgentStoryRoundStatus.pending,
        )
        .toList()
        .reversed
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 1 + prose.length + (rounds.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('剧情状态', style: Theme.of(context).textTheme.titleMedium),
              if (state.storyState.rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text('尚无剧情记录。首轮正文审查通过后会自动建立状态。'),
                ),
              for (final table in AgentStateTable.values)
                _StateTable(
                  key: ValueKey('${state.workspace?.id}/${table.name}'),
                  table: table,
                  rows: state.storyState.rows
                      .where((r) => r.table == table)
                      .toList(),
                ),
              const Divider(),
              Text('本会话正文', style: Theme.of(context).textTheme.titleMedium),
              if (rounds.isEmpty) const Text('本会话尚未选定正文。'),
            ],
          );
        }
        if (index > prose.length) {
          return _RoundHistory(
            key: ValueKey(
              '${state.workspace?.id}/${state.workspace?.sessionId}/history',
            ),
            rounds: rounds,
          );
        }
        final round = prose[index - 1];
        return ExpansionTile(
          key: PageStorageKey('story/${round.id}'),
          title: Text(round.document.name),
          subtitle: Text(
            round.status == AgentStoryRoundStatus.pending ? '状态待更新' : '已采用',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: smooth_md.SmoothMarkdown(
                data: round.document.content,
                selectable: true,
                styleSheet: smooth_md.MarkdownStyleSheet.fromTheme(
                  Theme.of(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoundHistory extends StatefulWidget {
  const _RoundHistory({super.key, required this.rounds});
  final List<AgentStoryRound> rounds;
  @override
  State<_RoundHistory> createState() => _RoundHistoryState();
}

class _RoundHistoryState extends State<_RoundHistory> {
  static const _pageSize = 20;
  int _visible = _pageSize;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('轮次历史'),
    subtitle: const Text('查看已采用、撤回或放弃的正文与执行记录'),
    children: [
      for (final round in widget.rounds.take(_visible))
        ListTile(
          title: Text(round.document.name),
          subtitle: Text(switch (round.status) {
            AgentStoryRoundStatus.pending => '状态待更新',
            AgentStoryRoundStatus.committed => '已采用',
            AgentStoryRoundStatus.withdrawn => '已撤回',
            AgentStoryRoundStatus.discarded => '已放弃',
          }),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(
            'agentRun',
            pathParameters: {
              'workspaceId': round.beforeWorkspace.id,
              'runId': round.id,
            },
          ),
        ),
      if (_visible < widget.rounds.length)
        TextButton(
          onPressed: () => setState(() => _visible += _pageSize),
          child: const Text('加载更多轮次'),
        ),
    ],
  );
}

class _StateTable extends StatefulWidget {
  const _StateTable({super.key, required this.table, required this.rows});
  final AgentStateTable table;
  final List<AgentStateRow> rows;
  @override
  State<_StateTable> createState() => _StateTableState();
}

class _StateTableState extends State<_StateTable> {
  static const _pageSize = 20;
  int _visible = _pageSize;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text('${widget.table.label} · ${widget.rows.length} 条'),
    initiallyExpanded: widget.table == AgentStateTable.scene,
    children: [
      if (widget.rows.isEmpty) const ListTile(title: Text('暂无记录')),
      for (final row in widget.rows.take(_visible))
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final column in widget.table.columns.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      '${column.value}：${row.cells[column.key]?.isNotEmpty == true ? row.cells[column.key] : '—'}',
                    ),
                  ),
                const Divider(),
              ],
            ),
          ),
        ),
      if (widget.rows.length > _visible)
        TextButton(
          onPressed: () => setState(() => _visible += _pageSize),
          child: const Text('加载更多记录'),
        ),
    ],
  );
}
