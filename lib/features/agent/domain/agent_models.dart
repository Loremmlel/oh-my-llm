import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import 'agent_configuration.dart';
export 'agent_configuration.dart';

enum AgentRunStatus {
  running,
  completed,
  cancelled,
  failed,
  limitReached,
  interrupted,
}

/// 作品与选中会话的只读视图；历史只由对应会话持久化。
class AgentWorkspace extends Equatable {
  AgentWorkspace({
    required this.id,
    required this.title,
    String? modelId,
    String instructions = '',
    AgentConfiguration? configuration,
    this.sessionId = 'initial',
    this.sessionTitle = '会话 1',
    this.draft = '',
    List<LlmInputItem> history = const [],
    List<AgentDocument> references = const [],
    this.referencesFrozen = false,
  }) : configuration =
           configuration ??
           AgentConfiguration(modelId: modelId, preset: instructions),
       history = List.unmodifiable(history),
       references = List.unmodifiable(references);
  final String id, title, sessionId, sessionTitle, draft;
  final AgentConfiguration configuration;
  String? get modelId => configuration.modelId;
  String get instructions => configuration.preset;
  final List<LlmInputItem> history;
  final List<AgentDocument> references;
  final bool referencesFrozen;
  AgentWorkspace copyWith({
    String? title,
    String? modelId,
    String? instructions,
    String? draft,
    String? sessionId,
    String? sessionTitle,
    AgentConfiguration? configuration,
    List<LlmInputItem>? history,
    List<AgentDocument>? references,
    bool? referencesFrozen,
  }) => AgentWorkspace(
    id: id,
    title: title ?? this.title,
    sessionId: sessionId ?? this.sessionId,
    sessionTitle: sessionTitle ?? this.sessionTitle,
    configuration:
        configuration ??
        this.configuration.copyWith(modelId: modelId, preset: instructions),
    draft: draft ?? this.draft,
    history: history ?? this.history,
    references: references ?? this.references,
    referencesFrozen: referencesFrozen ?? this.referencesFrozen,
  );
  @override
  List<Object?> get props => [
    id,
    title,
    sessionId,
    sessionTitle,
    configuration,
    draft,
    history,
    references,
    referencesFrozen,
  ];
}

class AgentDocument extends Equatable {
  const AgentDocument({
    required this.name,
    required this.content,
    required this.revision,
    this.id = '',
    this.kind = AgentDocumentKind.document,
  });
  final String id, name, content;
  final int revision;
  final AgentDocumentKind kind;
  @override
  List<Object?> get props => [id, name, content, revision, kind];
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

class AgentRunRecord extends Equatable {
  AgentRunRecord({
    required this.id,
    required this.workspaceId,
    required this.prompt,
    required this.startedAt,
    this.parentId,
    this.sessionId = 'initial',
    this.modelId,
    this.modelLabel = '',
    this.usageIncomplete = false,
    List<LlmInputItem> childHistory = const [],
    List<LlmToolDefinition> tools = const [],
    this.role = AgentRole.coordinator,
    this.status = AgentRunStatus.running,
    this.content = '',
    this.error = '',
    this.modelCalls = 0,
    this.usage,
    List<AgentStep> steps = const [],
  }) : steps = List.unmodifiable(steps),
       childHistory = List.unmodifiable(childHistory),
       tools = List.unmodifiable(tools);
  final String id;
  final String workspaceId;
  final String? parentId;
  final String sessionId, modelLabel;
  final String? modelId;
  final bool usageIncomplete;
  final List<LlmInputItem> childHistory;
  final List<LlmToolDefinition> tools;
  final AgentRole role;
  final AgentRunStatus status;
  final String prompt;
  final DateTime startedAt;
  final String content;
  final String error;
  final int modelCalls;
  final LlmUsage? usage;
  final List<AgentStep> steps;
  AgentRunRecord copyWith({
    AgentRunStatus? status,
    String? content,
    String? error,
    int? modelCalls,
    LlmUsage? usage,
    List<AgentStep>? steps,
    List<LlmInputItem>? childHistory,
    bool? usageIncomplete,
  }) => AgentRunRecord(
    id: id,
    workspaceId: workspaceId,
    parentId: parentId,
    sessionId: sessionId,
    modelId: modelId,
    modelLabel: modelLabel,
    tools: tools,
    childHistory: childHistory ?? this.childHistory,
    usageIncomplete: usageIncomplete ?? this.usageIncomplete,
    role: role,
    prompt: prompt,
    startedAt: startedAt,
    status: status ?? this.status,
    content: content ?? this.content,
    error: error ?? this.error,
    modelCalls: modelCalls ?? this.modelCalls,
    usage: usage ?? this.usage,
    steps: steps ?? this.steps,
  );
  @override
  List<Object?> get props => [
    id,
    workspaceId,
    parentId,
    sessionId,
    modelId,
    modelLabel,
    tools,
    childHistory,
    usageIncomplete,
    role,
    status,
    prompt,
    startedAt,
    content,
    error,
    modelCalls,
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
        output: '运行被中断，此调用的结果未确认。文档可能已保存；先读取当前版本核实，不要直接重复写入。',
      ),
  ];
}

class AgentWorkspaceException implements Exception {
  const AgentWorkspaceException(this.message);
  final String message;
  @override
  String toString() => message;
}
