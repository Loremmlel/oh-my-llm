import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';
import '../domain/agent_story_state.dart';
import 'agent_transcript.dart';

class AgentRunScreen extends ConsumerWidget {
  const AgentRunScreen({
    super.key,
    required this.workspaceId,
    required this.runId,
  });
  final String workspaceId, runId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentWorkspaceProvider);
    AgentRunRecord? record;
    AgentWorkspace? workspace;
    AgentStoryRound? round;
    String? error;
    try {
      record = ref.watch(
        agentRunProvider((workspaceId: workspaceId, runId: runId)),
      );
      workspace = ref.watch(agentWorkspaceDetailsProvider(workspaceId));
      if (record != null) {
        round = ref.read(agentWorkspaceProvider.notifier).storyRoundFor(record);
      }
    } catch (_) {
      error = '无法读取执行记录，请检查本地存储后重试。';
    }
    void back() {
      if (context.canPop()) {
        context.pop();
      } else if (record?.parentId case final parent?) {
        context.goNamed(
          'agentRun',
          pathParameters: {'workspaceId': workspaceId, 'runId': parent},
        );
      } else {
        if (workspace != null) {
          ref
              .read(agentWorkspaceProvider.notifier)
              .selectWorkspace(workspaceId);
        }
        context.go('/agent');
      }
    }

    final current = record;
    return AppShellScaffold(
      currentDestination: AppDestination.agent,
      title: current == null ? '子 Agent' : agentRoleLabel(current.role),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: back,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回上级任务'),
                ),
                if (current != null)
                  Expanded(
                    child: Text(
                      current.id,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                '${current.modelLabel.isEmpty ? '旧记录未保存模型名称' : current.modelLabel} · ${agentStatusLabel(current.status)}\n${agentUsageLabel(current)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: current == null
                ? Center(child: Text(error ?? '找不到此工作区的执行记录。'))
                : AgentTranscript(
                    records: [current],
                    allRuns: {
                      for (final r
                          in ref
                              .read(agentWorkspaceProvider.notifier)
                              .runsFor(current))
                        r.id: r,
                      for (final r in state.runs.where(
                        (r) =>
                            r.workspaceId == current.workspaceId &&
                            r.sessionId == current.sessionId,
                      ))
                        r.id: r,
                    }.values.toList(),
                    storyRounds: [?round],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Expanded(child: Text('子任务由父任务调度，执行过程保留供查看。')),
                  if (state.busy && current?.status == AgentRunStatus.running)
                    OutlinedButton.icon(
                      onPressed: ref.read(agentWorkspaceProvider.notifier).stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('停止全部'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
