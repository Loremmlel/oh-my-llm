import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';

import 'agent_configuration.dart';
import 'agent_context_batch.dart';
import 'agent_run_request_snapshot.dart';
import 'agent_run_usage.dart';
import 'agent_script.dart';

export 'agent_configuration.dart';
export 'agent_run_request_snapshot.dart';
export 'agent_run_usage.dart';

enum AgentRunStatus {
  running,
  completed,
  cancelled,
  failed,
  limitReached,
  interrupted,
}

/// 一部作品拥有一条主时间线，历史、正文、状态和配置归属同一工作区。
class AgentWorkspace extends Equatable {
  AgentWorkspace({
    required this.id,
    required this.title,
    String? modelId,
    String instructions = agentDefaultPreset,
    AgentConfiguration? configuration,
    this.draft = '',
    List<LlmInputItem> history = const [],
    List<AgentDocument> references = const [],
    Map<String, String> knownScripts = const {},
    Map<String, AgentScriptProgress> scriptProgress = const {},
  }) : configuration =
           configuration ??
           AgentConfiguration(modelId: modelId, preset: instructions),
       history = List.unmodifiable(history),
       references = List.unmodifiable(references),
       knownScripts = Map.unmodifiable(knownScripts),
       scriptProgress = Map.unmodifiable(scriptProgress);
  final String id, title, draft;
  final AgentConfiguration configuration;
  String? get modelId => configuration.modelId;
  String get instructions => configuration.preset;
  final List<LlmInputItem> history;
  final List<AgentDocument> references;
  final Map<String, String> knownScripts;
  final Map<String, AgentScriptProgress> scriptProgress;
  AgentWorkspace copyWith({
    String? title,
    String? modelId,
    String? instructions,
    String? draft,
    AgentConfiguration? configuration,
    List<LlmInputItem>? history,
    List<AgentDocument>? references,
    Map<String, String>? knownScripts,
    Map<String, AgentScriptProgress>? scriptProgress,
  }) => AgentWorkspace(
    id: id,
    title: title ?? this.title,
    configuration:
        configuration ??
        this.configuration.copyWith(modelId: modelId, preset: instructions),
    draft: draft ?? this.draft,
    history: history ?? this.history,
    references: references ?? this.references,
    knownScripts: knownScripts ?? this.knownScripts,
    scriptProgress: scriptProgress ?? this.scriptProgress,
  );
  @override
  List<Object?> get props => [
    id,
    title,
    configuration,
    draft,
    history,
    references,
    knownScripts,
    scriptProgress,
  ];
}

class AgentDocument extends Equatable {
  const AgentDocument({
    required this.name,
    required this.content,
    this.id = '',
    this.kind = AgentDocumentKind.document,
    this.description = '',
  });
  final String id, name, content;
  final AgentDocumentKind kind;
  final String description;
  @override
  List<Object?> get props => [id, name, content, kind, description];
}

enum AgentStepKind { model, tool }

class AgentStep extends Equatable {
  const AgentStep({
    required this.label,
    this.content = '',
    this.reasoning = '',
    this.isError = false,
    this.kind = AgentStepKind.model,
    this.isRunning = false,
    this.inputItemCount,
  });
  final String label;
  final String content;
  final String reasoning;
  final bool isError;
  final AgentStepKind kind;
  final bool isRunning;
  final int? inputItemCount;
  AgentStep copyWith({
    String? content,
    String? reasoning,
    bool? isRunning,
    bool? isError,
  }) => AgentStep(
    label: label,
    content: content ?? this.content,
    reasoning: reasoning ?? this.reasoning,
    kind: kind,
    isRunning: isRunning ?? this.isRunning,
    inputItemCount: inputItemCount,
    isError: isError ?? this.isError,
  );
  @override
  List<Object?> get props => [
    label,
    content,
    reasoning,
    isError,
    kind,
    isRunning,
    inputItemCount,
  ];
}

/// 覆盖式重试和压缩边界所需的恢复信息，旧记录可能没有快照。
class AgentRunRecovery extends Equatable {
  const AgentRunRecovery({this.beforeWorkspace, this.historyEnd});

  final AgentWorkspace? beforeWorkspace;

  /// 作品原始历史中本任务的排他结束位置；压缩必须覆盖完整工具往返。
  final int? historyEnd;

  AgentRunRecovery copyWith({int? historyEnd}) => AgentRunRecovery(
    beforeWorkspace: beforeWorkspace,
    historyEnd: historyEnd ?? this.historyEnd,
  );

  @override
  List<Object?> get props => [beforeWorkspace, historyEnd];
}

class AgentRunRecord extends Equatable {
  AgentRunRecord({
    required this.id,
    required this.workspaceId,
    required this.prompt,
    required this.startedAt,
    this.parentId,
    this.rootRunId,
    this.summaryBatch,
    this.recovery = const AgentRunRecovery(),
    AgentRunRequestSnapshot? request,
    List<LlmInputItem> childHistory = const [],
    this.role = AgentRole.coordinator,
    this.status = AgentRunStatus.running,
    this.content = '',
    this.error = '',
    this.usage = const AgentRunUsage(),
    List<AgentStep> steps = const [],
  }) : steps = List.unmodifiable(steps),
       childHistory = List.unmodifiable(childHistory),
       request = request ?? AgentRunRequestSnapshot();
  final String id;
  final String workspaceId;
  final String? parentId;
  final String? rootRunId;
  final AgentContextBatch? summaryBatch;
  final AgentRunRecovery recovery;
  final AgentRunRequestSnapshot request;
  String get roundRunId => rootRunId ?? parentId ?? id;
  final List<LlmInputItem> childHistory;
  final AgentRole role;
  final AgentRunStatus status;
  final String prompt;
  final DateTime startedAt;
  final String content;
  final String error;
  final AgentRunUsage usage;
  final List<AgentStep> steps;
  AgentRunRecord copyWith({
    AgentRunStatus? status,
    String? content,
    String? error,
    AgentRunUsage? usage,
    List<AgentStep>? steps,
    List<LlmInputItem>? childHistory,
    AgentRunRequestSnapshot? request,
    AgentRunRecovery? recovery,
  }) => AgentRunRecord(
    id: id,
    workspaceId: workspaceId,
    parentId: parentId,
    rootRunId: rootRunId,
    summaryBatch: summaryBatch,
    recovery: recovery ?? this.recovery,
    request: request ?? this.request,
    childHistory: childHistory ?? this.childHistory,
    role: role,
    prompt: prompt,
    startedAt: startedAt,
    status: status ?? this.status,
    content: content ?? this.content,
    error: error ?? this.error,
    usage: usage ?? this.usage,
    steps: steps ?? this.steps,
  );
  @override
  List<Object?> get props => [
    id,
    workspaceId,
    parentId,
    rootRunId,
    summaryBatch,
    recovery,
    request,
    childHistory,
    role,
    status,
    prompt,
    startedAt,
    content,
    error,
    usage,
    steps,
  ];
}

/// 中断后补齐未确认的工具结果，禁止重放可能已经产生副作用的调用。
List<LlmInputItem> closePendingAgentTools(List<LlmInputItem> history) {
  final pending = <String, LlmToolCall>{};
  for (final item in history) {
    if (item is LlmAssistantTurn) {
      for (final call in item.toolCalls) {
        pending[call.callId] = call;
      }
    } else if (item is LlmToolResult) {
      pending.remove(item.callId);
    }
  }
  return [
    ...history,
    for (final call in pending.values)
      LlmToolResult(
        callId: call.callId,
        name: call.name,
        isError: true,
        output: '运行被中断，此调用的结果未确认。文档可能已保存；先读取当前内容核实，不要直接重复写入。',
      ),
  ];
}

class AgentWorkspaceException implements Exception {
  const AgentWorkspaceException(this.message);
  final String message;
  @override
  String toString() => message;
}
