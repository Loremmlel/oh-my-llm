import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_endpoint_resolver.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import '../domain/agent_models.dart';
import 'agent_runtime.dart';
import 'ports/agent_store.dart';

class AgentModel {
  const AgentModel({
    required this.id,
    required this.label,
    required this.target,
    required this.options,
  });
  final String id, label;
  final LlmRequestTarget target;
  final LlmGenerationOptions options;
}

final agentClientProvider = Provider<LlmClient>(
  (ref) => throw StateError('Agent LLM 未绑定'),
);
final agentStoreProvider = Provider<AgentStore>(
  (ref) => throw StateError('Agent 存储未绑定'),
);
final agentModelsProvider = Provider<List<AgentModel>>(
  (ref) => throw StateError('Agent 模型未绑定'),
);
final agentWorkspaceProvider =
    NotifierProvider<AgentWorkspaceController, AgentWorkspaceState>(
      AgentWorkspaceController.new,
    );

final agentWorkspaceDetailsProvider = Provider.family<AgentWorkspace?, String>((
  ref,
  id,
) {
  final current = ref.watch(
    agentWorkspaceProvider.select((state) => state.workspace),
  );
  return current?.id == id
      ? current
      : ref.read(agentStoreProvider).loadWorkspace(id);
});

/// 优先显示运行中的内存快照；直接打开历史链接时按工作区边界读取持久记录。
final agentRunProvider =
    Provider.family<AgentRunRecord?, ({String workspaceId, String runId})>((
      ref,
      key,
    ) {
      final live = ref.watch(
        agentWorkspaceProvider.select(
          (state) => state.runs
              .where(
                (run) =>
                    run.workspaceId == key.workspaceId && run.id == key.runId,
              )
              .firstOrNull,
        ),
      );
      return live ??
          ref.read(agentStoreProvider).loadRun(key.workspaceId, key.runId);
    });

class AgentWorkspaceState {
  AgentWorkspaceState({
    List<AgentWorkspace> workspaces = const [],
    this.workspace,
    List<AgentRunRecord> runs = const [],
    List<AgentDocument> documents = const [],
    this.busy = false,
    this.error = '',
  }) : workspaces = List.unmodifiable(workspaces),
       runs = List.unmodifiable(runs),
       documents = List.unmodifiable(documents);
  final List<AgentWorkspace> workspaces;
  final AgentWorkspace? workspace;
  final List<AgentRunRecord> runs;
  final List<AgentDocument> documents;
  final bool busy;
  final String error;
}

class AgentWorkspaceController extends Notifier<AgentWorkspaceState> {
  late AgentStore _store;
  AgentRuntime? _runtime;
  bool _disposed = false;
  Timer? _draftTimer;
  AgentWorkspace? _pendingDraft;
  final _unsavedRuns = <AgentRunRecord>[];
  AgentWorkspace? _unsavedWorkspace;
  @override
  AgentWorkspaceState build() {
    _store = ref.read(agentStoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _runtime?.cancel();
      _draftTimer?.cancel();
      // 页面切换不销毁控制器；容器销毁时尽力保存尚未到期的输入。
      try {
        flushDraft();
      } catch (_) {
        /* 存储故障已在页面显示，销毁时不能再异步报错。 */
      }
    });
    try {
      _store.recoverInterruptedRuns();
      final workspaces = _store.listWorkspaces();
      final selected = workspaces.firstOrNull;
      return AgentWorkspaceState(
        workspaces: workspaces,
        workspace: selected,
        runs: selected == null ? const [] : _store.listRuns(selected.id),
        documents: selected == null
            ? const []
            : _store.listDocuments(selected.id),
      );
    } catch (_) {
      return AgentWorkspaceState(error: '无法读取 Agent 工作区，请检查本地存储后重新打开。');
    }
  }

  void createWorkspace() => _edit(() {
    if (state.busy) return;
    flushDraft();
    if (state.workspaces.length >= 100) {
      throw const AgentWorkspaceException('当前版本最多支持 100 个工作区。');
    }
    final workspace = AgentWorkspace(
      id: generateEntityId(),
      title: '工作区 ${state.workspaces.length + 1}',
    );
    _store.saveWorkspace(workspace);
    _load(workspace.id);
  });
  void selectWorkspace(String id) => _edit(() {
    if (state.busy) return;
    flushDraft();
    _load(id);
  });
  void configure({String? title, String? modelId, String? instructions}) =>
      _edit(() {
        final workspace = state.workspace;
        if (workspace == null || state.busy) return;
        if (workspace.history.isNotEmpty &&
            (modelId != null || instructions != null)) {
          throw const AgentWorkspaceException('已有上下文的模型和规则已固定；请新建工作区试验其他配置。');
        }
        flushDraft();
        _store.saveWorkspace(
          workspace.copyWith(
            title: title,
            modelId: modelId,
            instructions: instructions,
          ),
        );
        _load(workspace.id);
      });
  void setDraft(String text) {
    final workspace = state.workspace;
    if (workspace == null || state.busy) return;
    final next = workspace.copyWith(draft: text);
    _pendingDraft = next;
    state = AgentWorkspaceState(
      workspaces: state.workspaces,
      workspace: next,
      runs: state.runs,
      documents: state.documents,
      error: state.error,
    );
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 300),
      () => _edit(flushDraft),
    );
  }

  void flushDraft() {
    _draftTimer?.cancel();
    while (_unsavedRuns.isNotEmpty) {
      final record = _unsavedRuns.first;
      _store.checkpoint(
        record,
        workspace: record.parentId == null ? _unsavedWorkspace : null,
      );
      _unsavedRuns.removeAt(0);
    }
    _unsavedWorkspace = null;
    if (_pendingDraft case final draft?) {
      _store.saveWorkspace(draft);
      _pendingDraft = null;
    }
  }

  void saveDocument(String name, String content, int expectedRevision) =>
      _edit(() {
        final workspace = state.workspace;
        if (workspace == null || state.busy) return;
        flushDraft();
        _store.writeDocument(
          workspace.id,
          name,
          content,
          expectedRevision: expectedRevision,
        );
        // 手动修改通过新的消息告知模型，不改写旧工具结果。
        final updated = workspace.history.isEmpty
            ? workspace
            : workspace.copyWith(
                history: [
                  ...workspace.history,
                  LlmTextMessage(
                    role: LlmRole.user,
                    text: '用户在工作区保存了文档「$name」的新版本。下次使用前请重新读取。',
                  ),
                ],
              );
        _store.saveWorkspace(updated);
        _load(updated.id);
      });
  AgentDocument? readRevision(String name, int revision) =>
      state.workspace == null
      ? null
      : _store.readDocument(state.workspace!.id, name, revision: revision);

  Future<void> send() async {
    if (state.busy || state.workspace == null) return;
    AgentRuntime? runtime;
    try {
      flushDraft();
      var workspace = state.workspace!;
      final model = ref
          .read(agentModelsProvider)
          .where((m) => m.id == workspace.modelId)
          .firstOrNull;
      if (model == null) {
        throw const AgentWorkspaceException('请选择可用模型；若已删除，请恢复配置或新建工作区。');
      }
      if (workspace.draft.trim().isEmpty) return;
      final endpoint = const LlmEndpointResolver().resolveGenerationEndpoint(
        rawUrl: model.target.endpoint,
        protocol: model.target.protocol,
      );
      for (final turn in workspace.history.whereType<LlmAssistantTurn>()) {
        if (turn.replay.protocol != model.target.protocol ||
            turn.replay.endpoint != endpoint ||
            turn.replay.model != model.target.model) {
          throw const AgentWorkspaceException(
            '服务商的协议、端点或模型已改变；原生上下文不能迁移，请恢复配置或新建工作区。',
          );
        }
      }
      workspace = workspace.copyWith(modelId: model.id);
      runtime = AgentRuntime(
        client: ref.read(agentClientProvider),
        store: _store,
        workspace: workspace,
        target: model.target,
        options: model.options,
        onUpdate: (record) {
          if (_disposed) return;
          state = AgentWorkspaceState(
            workspaces: state.workspaces,
            workspace: _runtime!.workspace,
            runs: [record, ...state.runs.where((run) => run.id != record.id)]
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
            documents: state.documents,
            busy: true,
          );
        },
      );
      _runtime = runtime;
      state = AgentWorkspaceState(
        workspaces: state.workspaces,
        workspace: workspace,
        runs: state.runs,
        documents: state.documents,
        busy: true,
      );
      await runtime.run(workspace.draft.trim());
      if (!_disposed) {
        if (runtime.unsavedRecords.isEmpty) {
          _load(workspace.id);
        } else {
          _unsavedRuns.addAll(runtime.unsavedRecords);
          _unsavedWorkspace = runtime.workspace;
          state = AgentWorkspaceState(
            workspaces: state.workspaces,
            workspace: runtime.workspace,
            runs: state.runs,
            documents: state.documents,
            error: '执行记录未保存。修复存储后再次操作会重试保存，不会重跑旧工具。',
          );
        }
      }
    } catch (error) {
      runtime?.cancel();
      if (!_disposed) _showError(error);
    } finally {
      _runtime = null;
    }
  }

  void stop() => _runtime?.cancel();
  void _load(String id) {
    final workspace = _store.loadWorkspace(id);
    state = AgentWorkspaceState(
      workspaces: _store.listWorkspaces(),
      workspace: workspace,
      runs: _store.listRuns(id),
      documents: _store.listDocuments(id),
    );
  }

  void _edit(void Function() action) {
    try {
      action();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    state = AgentWorkspaceState(
      workspaces: state.workspaces,
      workspace: state.workspace,
      runs: state.runs,
      documents: state.documents,
      busy: _runtime != null && !(_runtime!.isCancelled),
      error: error is AgentWorkspaceException
          ? error.message
          : '工作区操作失败，请检查本地存储或服务商配置。',
    );
  }
}
