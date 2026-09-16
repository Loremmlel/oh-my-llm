import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_request.dart';

import '../domain/agent_models.dart';
import '../domain/agent_context_batch.dart';
import '../domain/agent_story_state.dart';

Map<String, dynamic> encodeAgentWorkspace(AgentWorkspace value) => {
  'version': 2,
  'id': value.id,
  'title': value.title,
  'sessionId': value.sessionId,
  'sessionTitle': value.sessionTitle,
  'configuration': encodeAgentConfiguration(value.configuration),
  'references': value.references.map(encodeAgentDocument).toList(),
  'modelId': value.modelId,
  'instructions': value.instructions,
  'draft': value.draft,
  'history': value.history.map(_encodeInput).toList(),
};
AgentWorkspace decodeAgentWorkspace(Map<String, dynamic> json) {
  if (json['version'] != 2) throw const FormatException('不支持的 Agent 会话版本');
  return AgentWorkspace(
    id: json['id'] as String,
    title: json['title'] as String,
    sessionId: json['sessionId'] as String,
    sessionTitle: json['sessionTitle'] as String,
    configuration: decodeAgentConfiguration(
      json['configuration'] as Map<String, dynamic>,
    ),
    references: (json['references'] as List)
        .map((v) => decodeAgentDocument(Map<String, dynamic>.from(v as Map)))
        .toList(),
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
  'rootRunId': value.rootRunId,
  'summaryBatch': value.summaryBatch?.toJson(),
  'sessionId': value.sessionId,
  'modelId': value.modelId,
  'modelLabel': value.modelLabel,
  'usageIncomplete': value.usageIncomplete,
  'childHistory': value.childHistory.map(_encodeInput).toList(),
  'inputHistory': value.inputHistory?.map(_encodeInput).toList(),
  'tools': [
    for (final t in value.tools)
      {
        'name': t.name,
        'description': t.description,
        'parameters': t.parameters,
      },
  ],
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
        'inputItemCount': step.inputItemCount,
      },
  ],
};
AgentRunRecord decodeAgentRun(Map<String, dynamic> json) {
  _version(json);
  return AgentRunRecord(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    parentId: json['parentId'] as String?,
    rootRunId: json['rootRunId'] as String?,
    summaryBatch: json['summaryBatch'] == null
        ? null
        : AgentContextBatch.fromJson(
            Map<String, dynamic>.from(json['summaryBatch'] as Map),
          ),
    sessionId: json['sessionId'] as String? ?? 'initial',
    modelId: json['modelId'] as String?,
    modelLabel: json['modelLabel'] as String? ?? '',
    usageIncomplete: json['usageIncomplete'] as bool? ?? false,
    childHistory: [
      for (final v in json['childHistory'] as List? ?? [])
        _decodeInput(Map<String, dynamic>.from(v as Map)),
    ],
    inputHistory: (json['inputHistory'] as List?)
        ?.map((v) => _decodeInput(Map<String, dynamic>.from(v as Map)))
        .toList(),
    tools: [
      for (final v in json['tools'] as List? ?? [])
        LlmToolDefinition(
          name: v['name'] as String,
          description: v['description'] as String,
          parameters: Map<String, Object?>.from(v['parameters'] as Map),
        ),
    ],
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
          inputItemCount: step['inputItemCount'] as int?,
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

Map<String, Object?> encodeAgentConfiguration(AgentConfiguration value) => {
  'name': value.name,
  'modelId': value.modelId,
  'preset': value.preset,
  'presetRoles': value.presetRoles.map((r) => r.name).toList(),
  'roles': {
    for (final entry in value.roles.entries)
      entry.key.name: {
        'modelId': entry.value.modelId,
        'instructions': entry.value.instructions,
      },
  },
};
AgentConfiguration decodeAgentConfiguration(Map<String, dynamic> json) =>
    AgentConfiguration(
      name: json['name'] as String,
      modelId: json['modelId'] as String?,
      preset: json['preset'] as String,
      presetRoles: (json['presetRoles'] as List).map(
        (v) => AgentRole.values.byName(v as String),
      ),
      roles: {
        for (final e in (json['roles'] as Map<String, dynamic>).entries)
          AgentRole.values.byName(e.key): AgentRoleSettings(
            modelId: e.value['modelId'] as String?,
            instructions: e.value['instructions'] as String,
          ),
      },
    );
Map<String, Object?> encodeAgentDocument(AgentDocument d) => {
  'id': d.id,
  'name': d.name,
  'content': d.content,
  'kind': d.kind.name,
};
AgentDocument decodeAgentDocument(Map<String, dynamic> j) => AgentDocument(
  id: j['id'] as String,
  name: j['name'] as String,
  content: j['content'] as String,
  kind: AgentDocumentKind.values.byName(j['kind'] as String),
);

Map<String, Object?> encodeAgentStoryRound(AgentStoryRound round) => {
  'version': 1,
  'id': round.id,
  'writerRunId': round.writerRunId,
  'stateAgentId': round.stateAgentId,
  'beforeWorkspace': encodeAgentWorkspace(round.beforeWorkspace),
  'document': encodeAgentDocument(round.document),
  'beforeState': round.beforeState.toJson(),
  'afterState': round.afterState?.toJson(),
  'status': round.status.name,
  'operations': round.operations.map((op) => op.toJson()).toList(),
};

AgentStoryRound decodeAgentStoryRound(Map<String, dynamic> json) {
  if (json['version'] != 1) throw const FormatException('不支持的剧情轮次版本');
  return AgentStoryRound(
    id: json['id'] as String,
    writerRunId: json['writerRunId'] as String?,
    stateAgentId: json['stateAgentId'] as String,
    beforeWorkspace: decodeAgentWorkspace(
      json['beforeWorkspace'] as Map<String, dynamic>,
    ),
    document: decodeAgentDocument(json['document'] as Map<String, dynamic>),
    beforeState: AgentStoryState.fromJson(
      json['beforeState'] as Map<String, dynamic>,
    ),
    afterState: json['afterState'] == null
        ? null
        : AgentStoryState.fromJson(json['afterState'] as Map<String, dynamic>),
    status: AgentStoryRoundStatus.values.byName(json['status'] as String),
    operations: (json['operations'] as List)
        .map(AgentStateOperation.fromJson)
        .toList(),
  );
}
