import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_adaptive_actions.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';
import '../domain/agent_story_state.dart';
import 'agent_story_panel.dart';
import 'agent_summary_dialog.dart';
import 'agent_documents_panel.dart';
import 'agent_transcript.dart';
import 'agent_configuration_dialog.dart';
import 'agent_context_dialog.dart';

enum _WorkspaceView { transcript, documents, story }

class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  _WorkspaceView _view = _WorkspaceView.transcript;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final workspace = state.workspace;
    final model = ref
        .watch(agentModelsProvider)
        .where((m) => m.id == workspace?.modelId)
        .firstOrNull;
    final removedRounds = state.storyRounds
        .where(
          (r) =>
              r.status == AgentStoryRoundStatus.withdrawn ||
              r.status == AgentStoryRoundStatus.discarded,
        )
        .map((r) => r.id)
        .toSet();
    final roots =
        state.runs
            .where(
              (r) =>
                  r.parentId == null &&
                  r.role != AgentRole.summarizer &&
                  !removedRounds.contains(r.id),
            )
            .toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final latest = roots.lastOrNull;
    final activeChildren = state.runs
        .where((r) => r.parentId != null && r.status == AgentRunStatus.running)
        .toList();
    final pageActions = [
      IconButton(
        onPressed: workspace == null
            ? null
            : () => showAgentConfiguration(context),
        tooltip: '模型与规则',
        icon: const Icon(Icons.tune),
      ),
      IconButton(
        onPressed: workspace == null || state.busy
            ? null
            : () => showAgentContext(context),
        tooltip: '查看上下文',
        icon: const Icon(Icons.manage_search),
      ),
    ];
    return AppShellScaffold(
      currentDestination: AppDestination.agent,
      title: 'Agent 小说工作区',
      adaptiveActions: AppAdaptiveActions(
        wideActions: pageActions,
        compactActions: [
          PopupMenuButton<String>(
            tooltip: '工作区操作',
            onSelected: (value) {
              if (value == 'configuration') showAgentConfiguration(context);
              if (value == 'context') showAgentContext(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'configuration',
                enabled: workspace != null,
                child: const Text('模型与规则'),
              ),
              PopupMenuItem(
                value: 'context',
                enabled: workspace != null && !state.busy,
                child: const Text('查看上下文'),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, viewport) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 键盘与大字号压缩可用高度时，让上下文区滚动，保留输入和停止空间。
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: viewport.maxHeight * .5),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: math.min(288, constraints.maxWidth),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: '作品',
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: workspace?.id,
                                            isExpanded: true,
                                            isDense: true,
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.sm,
                                            ),
                                            hint: const Text('选择作品'),
                                            items: [
                                              for (final w in state.workspaces)
                                                DropdownMenuItem(
                                                  value: w.id,
                                                  child: Tooltip(
                                                    message: w.title,
                                                    child: Text(
                                                      w.title,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                            onChanged: state.busy
                                                ? null
                                                : (id) {
                                                    if (id != null) {
                                                      controller
                                                          .selectWorkspace(id);
                                                    }
                                                  },
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: state.busy
                                          ? null
                                          : controller.createWorkspace,
                                      tooltip: '新建作品',
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                              ),
                              if (workspace != null)
                                SizedBox(
                                  width: math.min(336, constraints.maxWidth),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: '会话',
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: workspace.sessionId,
                                              isExpanded: true,
                                              isDense: true,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadii.sm,
                                                  ),
                                              items: [
                                                for (final session
                                                    in controller.sessions)
                                                  DropdownMenuItem(
                                                    value: session.id,
                                                    child: Tooltip(
                                                      message: session.title,
                                                      child: Text(
                                                        session.title,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                              onChanged: state.busy
                                                  ? null
                                                  : (id) {
                                                      if (id != null) {
                                                        controller
                                                            .selectSession(id);
                                                      }
                                                    },
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: state.busy
                                            ? null
                                            : controller.createSession,
                                        tooltip: '新建会话',
                                        icon: const Icon(
                                          Icons.add_comment_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            showAgentSummaries(context),
                                        tooltip: '总结管理',
                                        icon: const Icon(
                                          Icons.summarize_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (workspace != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            for (final item in [
                              (
                                _WorkspaceView.transcript,
                                '正文',
                                Icons.article_outlined,
                                '返回执行流',
                              ),
                              (
                                _WorkspaceView.documents,
                                '工作文档',
                                Icons.folder_open_outlined,
                                '工作文档',
                              ),
                              (
                                _WorkspaceView.story,
                                '剧情状态',
                                Icons.table_chart_outlined,
                                '剧情状态与正文',
                              ),
                            ])
                              Tooltip(
                                message: item.$4,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _view = item.$1),
                                  style: TextButton.styleFrom(
                                    backgroundColor: _view == item.$1
                                        ? Theme.of(context)
                                              .colorScheme
                                              .secondaryContainer
                                        : null,
                                    foregroundColor: _view == item.$1
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                  ),
                                  icon: Icon(item.$3, size: 18),
                                  label: Semantics(
                                    selected: _view == item.$1,
                                    child: Text(item.$2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (workspace != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.xs,
                        ),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            Text(
                              model?.label ?? '请在“模型与规则”中选择模型',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                state.busy ? '● 运行中' : '● 就绪',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                              ),
                            ),
                            Text(
                              '${state.documents.length} 份文档',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (latest != null)
                              Text(
                                '本轮全部 Agent 已报告用量 · ${agentTreeUsageLabel(latest, state.runs)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (state.busy &&
                                (_view != _WorkspaceView.transcript))
                              TextButton.icon(
                                onPressed: controller.stop,
                                icon: const Icon(Icons.stop),
                                label: const Text('停止'),
                              ),
                          ],
                        ),
                      ),
                    if (activeChildren.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            for (final child in activeChildren)
                              AgentChildLink(record: child),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    if (state.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            state.error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (workspace != null) const AgentStoryActions(),
                  ],
                ),
              ),
            ),
            if (workspace == null)
              const Expanded(
                child: Center(
                  child: Text(
                    '新建作品，添加世界书和人物卡，再开始写作。\n文档和运行记录保存在本机。',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              Expanded(
                child: _view == _WorkspaceView.story
                    ? const AgentStoryPanel()
                    : _view == _WorkspaceView.documents
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: AgentDocumentsPanel(),
                      )
                    : AgentTranscript(
                        key: ValueKey('${workspace.id}/${workspace.sessionId}'),
                        records: roots,
                        allRuns: state.runs,
                        storyRounds: state.storyRounds,
                      ),
              ),
              if (_view == _WorkspaceView.transcript)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .45,
                  ),
                  child: _Composer(
                    key: ValueKey(
                      'composer/${workspace.id}/${workspace.sessionId}',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({super.key});
  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late final _input = TextEditingController(
    text: ref.read(agentWorkspaceProvider).workspace!.draft,
  );
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final configured = ref
        .watch(agentModelsProvider)
        .any((m) => m.id == state.workspace?.modelId);
    final canSend =
        !state.busy &&
        state.latestRound?.status != AgentStoryRoundStatus.pending &&
        configured &&
        state.workspace!.draft.trim().isNotEmpty;
    ref.listen(agentWorkspaceProvider.select((s) => s.workspace?.draft), (
      _,
      text,
    ) {
      if (text != null && text != _input.text) _input.text = text;
    });
    void send() {
      // Enter 保留换行；组合输入尚未提交时快捷键也不发送。
      if (canSend && _input.value.composing.isCollapsed) {
        unawaited(controller.send());
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppContentWidths.form),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): send,
                    },
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !state.busy,
                      decoration: const InputDecoration(
                        labelText: '任务',
                        hintText: '描述下一步要完成的任务…',
                      ),
                      onChanged: controller.setDraft,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.busy
                            ? '主 Agent 与子 Agent 共享停止控制'
                            : FocusManager.instance.highlightMode ==
                                  FocusHighlightMode.traditional
                            ? 'Ctrl + Enter 发送 · Enter 换行'
                            : '输入任务后开始写作',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (state.busy)
                      OutlinedButton.icon(
                        onPressed: controller.stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('停止全部'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: canSend ? send : null,
                        icon: const Icon(Icons.arrow_upward),
                        label: const Text('开始任务'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
