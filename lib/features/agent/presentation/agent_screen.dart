import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import '../application/agent_workspace_controller.dart';
import '../domain/agent_models.dart';
import 'agent_documents_panel.dart';
import 'agent_transcript.dart';

class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});
  @override
  Widget build(BuildContext context) => const AppShellScaffold(
    currentDestination: AppDestination.agent,
    title: 'Agent 工作区',
    body: _WorkspaceBody(),
  );
}

class _WorkspaceBody extends ConsumerStatefulWidget {
  const _WorkspaceBody();
  @override
  ConsumerState<_WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<_WorkspaceBody> {
  bool _documents = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final workspace = state.workspace;
    final model = ref
        .watch(agentModelsProvider)
        .where((m) => m.id == workspace?.modelId)
        .firstOrNull;
    final roots = state.runs.where((r) => r.parentId == null).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final latest = roots.lastOrNull;
    final activeChildren = state.runs
        .where((r) => r.parentId != null && r.status == AgentRunStatus.running)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: workspace?.id,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: const Text('选择工作区'),
                  items: [
                    for (final w in state.workspaces)
                      DropdownMenuItem(
                        value: w.id,
                        child: Text(w.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: state.busy
                      ? null
                      : (id) {
                          if (id != null) controller.selectWorkspace(id);
                        },
                ),
              ),
              IconButton(
                onPressed: state.busy ? null : controller.createWorkspace,
                tooltip: '新建工作区',
                icon: const Icon(Icons.add),
              ),
              IconButton(
                onPressed: workspace == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => const _ConfigurationDialog(),
                      ),
                tooltip: '模型与规则',
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                onPressed: workspace == null
                    ? null
                    : () => setState(() => _documents = !_documents),
                tooltip: _documents ? '返回执行流' : '工作文档',
                isSelected: _documents,
                icon: const Icon(Icons.folder_open_outlined),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${state.documents.length} 份文档',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (latest != null)
                  Text(
                    '本轮主 Agent · ${agentUsageLabel(latest)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        if (activeChildren.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (workspace == null)
          const Expanded(
            child: Center(
              child: Text(
                '新建工作区，开始写作、审稿或改写。\n文档和运行记录保存在本机。',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          Expanded(
            child: _documents
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: AgentDocumentsPanel(),
                  )
                : AgentTranscript(
                    key: ValueKey(workspace.id),
                    records: roots,
                    allRuns: state.runs,
                  ),
          ),
          if (!_documents) _Composer(key: ValueKey('composer/${workspace.id}')),
        ],
      ],
    );
  }
}

class _ConfigurationDialog extends ConsumerStatefulWidget {
  const _ConfigurationDialog();
  @override
  ConsumerState<_ConfigurationDialog> createState() =>
      _ConfigurationDialogState();
}

class _ConfigurationDialogState extends ConsumerState<_ConfigurationDialog> {
  late final _rules = TextEditingController(
    text: ref.read(agentWorkspaceProvider).workspace!.instructions,
  );
  @override
  void dispose() {
    _rules.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentWorkspaceProvider);
    final models = ref.watch(agentModelsProvider);
    final current = state.workspace!;
    final locked = state.busy || current.history.isNotEmpty;
    return AlertDialog(
      title: const Text('模型与规则'),
      content: SizedBox(
        width: AppContentWidths.readable,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: models.any((m) => m.id == current.modelId)
                    ? current.modelId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '运行模型（需支持工具调用）'),
                items: [
                  for (final m in models)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(m.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: locked
                    ? null
                    : (id) => ref
                          .read(agentWorkspaceProvider.notifier)
                          .configure(modelId: id),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _rules,
                readOnly: locked,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: '规则与文风（可选）'),
                onChanged: (text) => ref
                    .read(agentWorkspaceProvider.notifier)
                    .configure(instructions: text),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(locked ? '模型与规则已固定；更换配置请新建工作区。' : '模型与规则在首次运行后固定。'),
              const Text('每次任务最多 24 次模型调用、2 个并发子任务、10 分钟。'),
              if (models.isEmpty) const Text('先到设置添加支持工具调用的模型。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
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
        !state.busy && configured && state.workspace!.draft.trim().isNotEmpty;
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppContentWidths.form),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallbackShortcuts(
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
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.busy
                            ? '主 Agent 与子 Agent 共享停止控制'
                            : 'Ctrl + Enter 发送 · Enter 换行',
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
