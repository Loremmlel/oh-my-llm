import 'package:equatable/equatable.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

enum AgentRole { coordinator, writer, reviewer, character }

enum AgentRunStatus {
  running,
  completed,
  cancelled,
  failed,
  limitReached,
  interrupted,
}

class AgentWorkspace extends Equatable {
  AgentWorkspace({
    required this.id,
    required this.title,
    this.modelId,
    this.instructions = '',
    this.draft = '',
    List<LlmInputItem> history = const [],
  }) : history = List.unmodifiable(history);
  final String id;
  final String title;
  final String? modelId;
  final String instructions;
  final String draft;
  final List<LlmInputItem> history;
  AgentWorkspace copyWith({
    String? title,
    String? modelId,
    String? instructions,
    String? draft,
    List<LlmInputItem>? history,
  }) => AgentWorkspace(
    id: id,
    title: title ?? this.title,
    modelId: modelId ?? this.modelId,
    instructions: instructions ?? this.instructions,
    draft: draft ?? this.draft,
    history: history ?? this.history,
  );
  @override
  List<Object?> get props => [id, title, modelId, instructions, draft, history];
}

class AgentDocument extends Equatable {
  const AgentDocument({
    required this.name,
    required this.content,
    required this.revision,
  });
  final String name;
  final String content;
  final int revision;
  @override
  List<Object?> get props => [name, content, revision];
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
  });
  final String label;
  final String content;
  final String reasoning;
  final bool isError;
  final AgentStepKind kind;
  final bool isRunning;
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
  ];
}

class AgentRunRecord extends Equatable {
  AgentRunRecord({
    required this.id,
    required this.workspaceId,
    required this.prompt,
    required this.startedAt,
    this.parentId,
    this.role = AgentRole.coordinator,
    this.status = AgentRunStatus.running,
    this.content = '',
    this.error = '',
    this.modelCalls = 0,
    this.usage,
    List<AgentStep> steps = const [],
  }) : steps = List.unmodifiable(steps);
  final String id;
  final String workspaceId;
  final String? parentId;
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
  }) => AgentRunRecord(
    id: id,
    workspaceId: workspaceId,
    parentId: parentId,
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
