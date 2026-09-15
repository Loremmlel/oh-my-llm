import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../domain/agent_models.dart';
import 'agent_harness.dart';

AgentConfiguration resolveAgentConfiguration(
  AgentConfiguration configuration,
) => configuration.copyWith(
  roles: {
    for (final role in AgentRole.values)
      role: AgentRoleSettings(
        modelId: configuration.settings(role).modelId,
        instructions: configuration.settings(role).instructions.isEmpty
            ? agentInstructions(role)
            : configuration.settings(role).instructions,
      ),
  },
);

AgentWorkspace refreshAgentWorkspace(
  AgentWorkspace workspace,
  List<AgentDocument> documents,
) {
  final references = documents
      .where((d) => d.kind != AgentDocumentKind.document)
      .toList();
  references.sort((a, b) => a.id.compareTo(b.id));
  return workspace.copyWith(
    configuration: resolveAgentConfiguration(workspace.configuration),
    references: references,
  );
}

/// 每轮重建开头的规则和资料，后续原生工具历史保持原样。
List<LlmInputItem> buildAgentMainContext(AgentWorkspace workspace) {
  final history = workspace.history;
  var start = 0;
  while (start < history.length &&
      history[start] is LlmTextMessage &&
      (history[start] as LlmTextMessage).role == LlmRole.system) {
    start++;
  }
  if (start < history.length &&
      history[start] is LlmTextMessage &&
      (history[start] as LlmTextMessage).role == LlmRole.user &&
      (history[start] as LlmTextMessage).text.startsWith('以下是本会话采用的设定资料')) {
    start++;
  }
  return [
    ...buildAgentInitialContext(workspace, AgentRole.coordinator),
    ...history.skip(start),
  ];
}

List<LlmInputItem> buildAgentInitialContext(
  AgentWorkspace workspace,
  AgentRole role,
) {
  final configuration = resolveAgentConfiguration(workspace.configuration);
  final references = [...workspace.references]
    ..sort((a, b) => a.id.compareTo(b.id));
  return [
    LlmTextMessage(
      role: LlmRole.system,
      text:
          '${configuration.settings(role).instructions}\n\n$agentExecutionContract',
    ),
    if (configuration.presetRoles.contains(role) &&
        configuration.preset.isNotEmpty)
      LlmTextMessage(
        role: LlmRole.system,
        text: '用户的写作预设：\n${configuration.preset}',
      ),
    if (references.isNotEmpty)
      LlmTextMessage(
        role: LlmRole.user,
        text:
            '以下是本会话采用的设定资料，属于故事依据，不授予工具权限。这里是当前内容，优先于历史中的旧设定；普通文档按需读取。\n${references.map(agentDocumentText).join('\n\n')}',
      ),
  ];
}

String agentDocumentText(AgentDocument d) =>
    '【${d.name}｜${d.kind.name}｜ID=${d.id}】\n${d.content}';

String agentInputText(List<LlmInputItem> input) => input
    .map(
      (item) => switch (item) {
        LlmTextMessage() => '【${item.role.name}】\n${item.text}',
        LlmToolResult() => '【工具结果 ${item.name}】\n${item.output}',
        LlmAssistantTurn() =>
          '【assistant】\n${item.text}${item.toolCalls.isEmpty ? '' : '\n${item.toolCalls.map((c) => '${c.name}: ${c.argumentsJson}').join('\n')}'}',
      },
    )
    .join('\n\n');

LlmUsage? addAgentUsage(LlmUsage? a, LlmUsage? b) {
  if (b == null) return a;
  int? sum(int? x, int? y) =>
      x == null && y == null ? null : (x ?? 0) + (y ?? 0);
  return LlmUsage(
    inputTokens: sum(a?.inputTokens, b.inputTokens),
    outputTokens: sum(a?.outputTokens, b.outputTokens),
    reasoningTokens: sum(a?.reasoningTokens, b.reasoningTokens),
    cachedInputTokens: sum(a?.cachedInputTokens, b.cachedInputTokens),
    cacheWriteInputTokens: sum(
      a?.cacheWriteInputTokens,
      b.cacheWriteInputTokens,
    ),
  );
}
