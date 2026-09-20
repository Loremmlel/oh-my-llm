import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/llm/llm_client.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_history_conversion.dart';

import '../domain/agent_models.dart';
import '../domain/agent_context_batch.dart';
import '../domain/agent_story_state.dart';
import 'agent_runtime.dart';
import 'agent_context.dart';
import 'agent_script_context.dart';
import '../domain/agent_script.dart';
import 'agent_model.dart';
export 'agent_model.dart';
import 'ports/agent_store.dart';

final agentClientProvider = Provider<LlmClient>(
  (ref) => throw StateError('Agent LLM 未绑定'),
);
final agentStoreProvider = Provider<AgentStore>(
  (ref) => throw StateError('Agent 存储未绑定'),
);
final agentPresetsProvider = Provider<List<({String name, String content})>>(
  (ref) => const [],
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
    List<({String id, String title})> workspaces = const [],
    this.workspace,
    List<AgentRunRecord> runs = const [],
    List<AgentDocument> documents = const [],
    AgentStoryState? storyState,
    List<AgentStoryRound> storyRounds = const [],
    this.latestRound,
    this.busy = false,
    this.error = '',
  }) : workspaces = List.unmodifiable(workspaces),
       runs = List.unmodifiable(runs),
       documents = List.unmodifiable(documents),
       storyState = storyState ?? AgentStoryState(),
       storyRounds = List.unmodifiable(storyRounds);
  final List<({String id, String title})> workspaces;
  final AgentWorkspace? workspace;
  final List<AgentRunRecord> runs;
  final List<AgentDocument> documents;
  final AgentStoryState storyState;
  final List<AgentStoryRound> storyRounds;
  final AgentStoryRound? latestRound;
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
      final selected = workspaces.isEmpty
          ? null
          : _store.loadWorkspace(workspaces.first.id);
      return AgentWorkspaceState(
        workspaces: workspaces,
        workspace: selected,
        storyState: selected == null
            ? null
            : _store.readStoryState(selected.id),
        storyRounds: selected == null
            ? []
            : _store.listStoryRounds(selected.id, includeHistory: false),
        latestRound: selected == null
            ? null
            : _store.latestStoryRound(selected.id),
        runs: selected == null
            ? const []
            : _store.listRuns(selected.id, includeHistory: false),
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
      title: '作品 ${state.workspaces.length + 1}',
    );
    _store.saveWorkspace(workspace);
    _load(workspace.id);
  });
  void selectWorkspace(String id) => _edit(() {
    if (state.busy) return;
    flushDraft();
    _load(id);
  });
  void renameWorkspace(String id, String title) => _edit(() {
    if (state.busy || state.workspace == null) return;
    final name = _validatedTitle(title);
    flushDraft();
    final workspace = _store.loadWorkspace(id);
    if (workspace == null) throw const AgentWorkspaceException('找不到此作品。');
    _store.saveWorkspace(workspace.copyWith(title: name));
    _load(state.workspace!.id);
  });

  String _validatedTitle(String title) {
    final name = title.trim();
    if (name.isEmpty) throw const AgentWorkspaceException('名称不能为空。');
    return name;
  }

  List<AgentConfiguration> get configurations => state.workspace == null
      ? []
      : _store.listConfigurations(state.workspace!.id);

  AgentConfiguration? saveConfiguration(AgentConfiguration configuration) {
    AgentConfiguration? saved;
    _edit(() {
      if (state.busy || state.workspace == null) return;
      flushDraft();
      saved = _store.saveConfiguration(
        state.workspace!.id,
        resolveAgentConfiguration(configuration),
      );
      _load(state.workspace!.id);
    });
    return saved;
  }

  void applyConfiguration(AgentConfiguration configuration) => _edit(() {
    if (state.busy || state.workspace == null) return;
    flushDraft();
    final workspace = state.workspace!;
    final saved = _store
        .listConfigurations(workspace.id)
        .where((c) => c == configuration)
        .firstOrNull;
    if (saved == null) throw const AgentWorkspaceException('请先保存此配置方案，再应用到作品。');
    _store.saveWorkspace(workspace.copyWith(configuration: saved));
    _load(workspace.id);
  });

  List<LlmInputItem> previewInput() {
    final current = state.workspace;
    if (current == null) return [];
    final model = ref
        .read(agentModelsProvider)
        .where((m) => m.id == current.modelId)
        .firstOrNull;
    final documents = _store.listDocuments(current.id);
    final batch = contextBatch;
    // 与运行器同样先转换完整历史再压缩，保持重建后的工具 ID 一致。
    final workspace = refreshAgentWorkspace(
      model == null
          ? current
          : current.copyWith(
              history: convertLlmHistory(current.history, model.target),
            ),
      documents,
    );
    return [
      ...buildAgentMainContext(workspace, batch: batch),
      ...agentScriptUpdates(workspace, documents, full: batch?.active ?? false),
      agentStateMessage(_store.readStoryState(workspace.id)),
      if (workspace.draft.trim().isNotEmpty)
        LlmTextMessage(role: LlmRole.user, text: workspace.draft.trim()),
    ];
  }

  List<LlmInputItem>? runInput(AgentRunRecord record, AgentStep step) {
    final count = step.inputItemCount;
    if (count == null) return null;
    // 列表不展开历史链；仅检查具体调用的输入时读取持久化快照。
    if (record.inputHistory == null && record.childHistory.isEmpty) {
      record = _store.loadRun(record.workspaceId, record.id) ?? record;
    }
    final history =
        record.inputHistory ??
        (record.parentId != null || record.role == AgentRole.summarizer
            ? record.childHistory
            : (state.workspace?.id == record.workspaceId
                  ? state.workspace!.history
                  : _store.loadWorkspace(record.workspaceId)?.history));
    if (history == null || count > history.length) return null;
    return history.take(count).toList();
  }

  AgentStoryRound? storyRoundFor(AgentRunRecord record) =>
      (record.role == AgentRole.coordinator || record.role == AgentRole.writer)
      ? _store.readStoryRound(record.workspaceId, record.roundRunId)
      : null;

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
      storyState: state.storyState,
      storyRounds: state.storyRounds,
      latestRound: state.latestRound,
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
        workspace: record.role == AgentRole.coordinator
            ? _unsavedWorkspace
            : null,
      );
      _unsavedRuns.removeAt(0);
    }
    _unsavedWorkspace = null;
    if (_pendingDraft case final draft?) {
      _store.saveDraft(draft.id, draft.draft);
      _pendingDraft = null;
    }
  }

  AgentScriptProgress? scriptProgressFor(AgentDocument document) {
    final progress = state.workspace?.scriptProgress[document.id];
    return progress?.fingerprint == agentScriptFingerprint(document)
        ? progress
        : null;
  }

  void saveDocument(
    String name,
    String content, {
    AgentDocumentKind? kind,
    String? documentId,
  }) => _edit(() {
    final workspace = state.workspace;
    if (workspace == null || state.busy) return;
    flushDraft();
    final savedDocument = _store.writeDocument(
      workspace.id,
      name,
      content,
      kind: kind,
      documentId: documentId,
    );
    // 手动修改通过新的消息告知模型，不改写旧工具结果。
    final updated =
        workspace.history.isEmpty ||
            savedDocument.kind != AgentDocumentKind.document
        ? workspace
        : workspace.copyWith(
            history: [
              ...workspace.history,
              LlmTextMessage(
                role: LlmRole.user,
                text: '用户在工作区保存了文档「$name」。下次使用前请重新读取当前内容。',
              ),
            ],
          );
    _store.saveWorkspace(updated);
    _load(updated.id);
  });
  Future<void> send({
    bool retryStory = false,
    AgentContextBatch? summaryBatch,
    String? retryReplyId,
  }) async {
    if (state.busy || state.workspace == null) return;
    AgentRuntime? runtime;
    try {
      flushDraft();
      var workspace = state.workspace!;
      final pending = _store.latestStoryRound(workspace.id);
      if (pending?.status == AgentStoryRoundStatus.pending &&
          !retryStory &&
          retryReplyId != pending?.id) {
        throw const AgentWorkspaceException('请先重试状态更新或放弃未完成轮次。');
      }
      if (retryStory && (pending?.status != AgentStoryRoundStatus.pending)) {
        throw const AgentWorkspaceException('请先完成或放弃未完成的正文轮次。');
      }
      final model = ref
          .read(agentModelsProvider)
          .where((m) => m.id == workspace.modelId)
          .firstOrNull;
      if (model == null) {
        throw const AgentWorkspaceException('请选择可用模型；若已删除，请重新选择模型。');
      }
      if (!retryStory &&
          retryReplyId == null &&
          summaryBatch == null &&
          workspace.draft.trim().isEmpty) {
        return;
      }
      workspace = workspace.copyWith(modelId: model.id);
      AgentRunRecord? retryRun;
      if (retryReplyId != null) {
        retryRun = _store.resetLatestReply(workspace.id, retryReplyId);
        _lastSummaryBatch = null;
        _load(workspace.id);
        workspace = state.workspace!;
      }
      runtime = AgentRuntime(
        client: ref.read(agentClientProvider),
        store: _store,
        workspace: workspace,
        roleModels: {
          for (final role in AgentRole.values)
            role: ?ref
                .read(agentModelsProvider)
                .where((m) => m.id == workspace.configuration.modelFor(role))
                .firstOrNull,
        },
        onUpdate: (record) {
          if (_disposed) return;
          state = AgentWorkspaceState(
            workspaces: state.workspaces,
            workspace: _runtime!.workspace,
            runs: [record, ...state.runs.where((run) => run.id != record.id)]
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
            documents: state.documents,
            storyState: state.storyState,
            storyRounds: state.storyRounds,
            latestRound: state.latestRound,
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
        storyState: state.storyState,
        storyRounds: state.storyRounds,
        latestRound: state.latestRound,
        busy: true,
      );
      if (summaryBatch != null) {
        _lastSummaryBatch = summaryBatch;
        _lastSummaryWorkspace = workspace.id;
        final result = await runtime.summarize(summaryBatch);
        if (result.status != AgentRunStatus.completed) {
          throw AgentWorkspaceException(result.error);
        }
        _lastSummaryBatch = null;
      } else if (retryStory) {
        await runtime.retryStory(pending!);
      } else {
        await runtime.run(
          retryRun?.prompt ?? workspace.draft.trim(),
          retryRun: retryRun,
        );
      }
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
            storyState: _store.readStoryState(workspace.id),
            storyRounds: _store.listStoryRounds(
              workspace.id,
              includeHistory: false,
            ),
            latestRound: _store.latestStoryRound(workspace.id),
            error: '执行记录未保存。修复存储后再次操作会重试保存，不会重跑旧工具。',
          );
        }
      }
    } catch (error) {
      runtime?.cancel();
      if (runtime != null && runtime.unsavedRecords.isNotEmpty) {
        _unsavedRuns.addAll(runtime.unsavedRecords);
        _unsavedWorkspace = runtime.workspace;
      }
      if (!_disposed) _showError(error);
    } finally {
      _runtime = null;
    }
  }

  AgentContextBatch? _lastSummaryBatch;
  String? _lastSummaryWorkspace;
  AgentContextBatch? get retrySummaryBatch {
    if (_lastSummaryWorkspace == state.workspace?.id &&
        _lastSummaryBatch != null) {
      return _lastSummaryBatch;
    }
    final latest = state.runs
        .where((r) => r.role == AgentRole.summarizer)
        .firstOrNull;
    if (latest == null ||
        latest.status == AgentRunStatus.running ||
        contextBatch?.summaryRunId == latest.id) {
      return null;
    }
    return latest.summaryBatch;
  }

  AgentContextBatch? get contextBatch => state.workspace == null
      ? null
      : _store.readContextBatch(state.workspace!.id);
  List<AgentRunRecord> runsFor(AgentRunRecord record) =>
      _store.listChildRuns(record.workspaceId, record.id);

  AgentContextBatch contextBatchFor(int count) {
    final committed = state.storyRounds.reversed
        .where((r) => r.status == AgentStoryRoundStatus.committed)
        .toList();
    final previous = contextBatch;
    final covered = previous?.active == true ? previous!.roundIds.length : 0;
    if (count <= 0 || covered + count > committed.length) {
      throw const AgentWorkspaceException('请选择有效的新增正文楼数。');
    }
    final selected = committed.take(covered + count).map((r) => r.id).toList();
    final end = _store.loadRun(state.workspace!.id, selected.last)?.historyEnd;
    if (end == null) throw const AgentWorkspaceException('正文缺少完整任务边界，无法压缩。');
    return AgentContextBatch(
      id: generateEntityId(),
      roundIds: selected,
      historyEnd: end,
    );
  }

  void saveContextBatch(AgentContextBatch batch) => _edit(() {
    if (state.busy || state.workspace == null) return;
    flushDraft();
    _store.saveContextBatch(state.workspace!.id, batch);
    _load(state.workspace!.id);
  });

  void stop() => _runtime?.cancel();
  void withdrawLatestRound() => _edit(() {
    final workspace = state.workspace;
    if (workspace == null || state.busy) return;
    flushDraft();
    final round = _store.latestStoryRound(workspace.id);
    if (round == null) throw const AgentWorkspaceException('没有可撤回的正文轮次。');
    _store.withdrawStoryRound(workspace.id, round.id);
    _load(workspace.id);
  });
  void _load(String id) {
    final workspace = _store.loadWorkspace(id);
    state = AgentWorkspaceState(
      workspaces: _store.listWorkspaces(),
      workspace: workspace,
      runs: workspace == null ? [] : _store.listRuns(id, includeHistory: false),
      documents: _store.listDocuments(id),
      storyState: _store.readStoryState(id),
      storyRounds: workspace == null
          ? []
          : _store.listStoryRounds(id, includeHistory: false),
      latestRound: _store.latestStoryRound(id),
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
      storyState: state.storyState,
      storyRounds: state.storyRounds,
      latestRound: state.latestRound,
      busy: _runtime != null && !(_runtime!.isCancelled),
      error: error is AgentWorkspaceException
          ? error.message
          : '工作区操作失败，请检查本地存储或服务商配置。',
    );
  }
}
