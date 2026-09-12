import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../domain/agent_models.dart';

Map<String, dynamic> encodeAgentWorkspace(AgentWorkspace value) => {
  'version': 1,
  'id': value.id,
  'title': value.title,
  'modelId': value.modelId,
  'instructions': value.instructions,
  'draft': value.draft,
  'history': value.history.map(_encodeInput).toList(),
};
AgentWorkspace decodeAgentWorkspace(Map<String, dynamic> json) {
  _version(json);
  return AgentWorkspace(
    id: json['id'] as String,
    title: json['title'] as String,
    modelId: json['modelId'] as String?,
    instructions: json['instructions'] as String,
    draft: json['draft'] as String,
    history: (json['history'] as List)
        .map((v) => _decodeInput(v as Map<String, dynamic>))
        .toList(),
  );
}

Map<String, dynamic> encodeAgentRun(AgentRunRecord value) => {
  'version': 1,
  'id': value.id,
  'workspaceId': value.workspaceId,
  'parentId': value.parentId,
  'role': value.role.name,
  'status': value.status.name,
  'prompt': value.prompt,
  'startedAt': value.startedAt.toIso8601String(),
  'content': value.content,
  'error': value.error,
  'modelCalls': value.modelCalls,
  'usage': value.usage?.toJson(),
  'steps': [
    for (final step in value.steps)
      {
        'label': step.label,
        'content': step.content,
        'reasoning': step.reasoning,
        'isError': step.isError,
        'kind': step.kind.name,
        'isRunning': step.isRunning,
      },
  ],
};
AgentRunRecord decodeAgentRun(Map<String, dynamic> json) {
  _version(json);
  return AgentRunRecord(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    parentId: json['parentId'] as String?,
    role: AgentRole.values.byName(json['role'] as String),
    status: AgentRunStatus.values.byName(json['status'] as String),
    prompt: json['prompt'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    content: json['content'] as String,
    error: json['error'] as String,
    modelCalls: json['modelCalls'] as int,
    usage: LlmUsage.fromJson(json['usage']),
    steps: [
      for (final step in json['steps'] as List)
        AgentStep(
          label: step['label'] as String,
          content: step['content'] as String,
          reasoning: step['reasoning'] as String,
          isError: step['isError'] as bool,
          kind: step['kind'] == null
              ? ((step['label'] as String).startsWith('模型回复 ')
                    ? AgentStepKind.model
                    : AgentStepKind.tool)
              : AgentStepKind.values.byName(step['kind'] as String),
          isRunning: step['isRunning'] as bool? ?? false,
        ),
    ],
  );
}

void _version(Map<String, dynamic> json) {
  if (json['version'] != 1) throw const FormatException('不支持的 Agent 记录版本');
}

Map<String, Object?> _encodeInput(LlmInputItem item) => switch (item) {
  LlmTextMessage() => {
    'type': 'text',
    'role': item.role.name,
    'text': item.text,
  },
  LlmToolResult() => {
    'type': 'result',
    'callId': item.callId,
    'name': item.name,
    'output': item.output,
    'isError': item.isError,
  },
  LlmAssistantTurn() => {
    'type': 'assistant',
    'text': item.text,
    'reasoning': item.reasoning,
    'protocol': item.replay.protocol.storageValue,
    'endpoint': item.replay.endpoint.toString(),
    'model': item.replay.model,
    'items': item.replay.items,
    'calls': [
      for (final call in item.toolCalls)
        {
          'callId': call.callId,
          'name': call.name,
          'arguments': call.argumentsJson,
        },
    ],
  },
};
LlmInputItem _decodeInput(Map<String, dynamic> json) => switch (json['type']) {
  'text' => LlmTextMessage(
    role: LlmRole.values.byName(json['role'] as String),
    text: json['text'] as String,
  ),
  'result' => LlmToolResult(
    callId: json['callId'] as String,
    name: json['name'] as String,
    output: json['output'] as String,
    isError: json['isError'] as bool,
  ),
  'assistant' => LlmAssistantTurn(
    text: json['text'] as String,
    reasoning: json['reasoning'] as String,
    replay: LlmReplayEnvelope(
      protocol: LlmApiProtocol.fromJsonValue(json['protocol']),
      endpoint: Uri.parse(json['endpoint'] as String),
      model: json['model'] as String,
      items: [
        for (final item in json['items'] as List)
          Map<String, Object?>.from(item as Map),
      ],
    ),
    toolCalls: [
      for (final call in json['calls'] as List)
        LlmToolCall(
          callId: call['callId'] as String,
          name: call['name'] as String,
          argumentsJson: call['arguments'] as String,
        ),
    ],
  ),
  _ => throw const FormatException('无效的 Agent 上下文项'),
};
