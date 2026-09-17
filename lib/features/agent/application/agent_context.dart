import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';

import '../domain/agent_models.dart';
import '../domain/agent_context_batch.dart';
import '../domain/agent_story_state.dart';
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
      .where(
        (d) =>
            d.kind == AgentDocumentKind.worldBook ||
            d.kind == AgentDocumentKind.characterCard,
      )
      .toList();
  references.sort((a, b) => a.id.compareTo(b.id));
  return workspace.copyWith(
    configuration: resolveAgentConfiguration(workspace.configuration),
    references: references,
  );
}

/// 每轮重建开头的规则和资料，后续原生工具历史保持原样。
List<LlmInputItem> agentConversationHistory(AgentWorkspace workspace) {
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
  return history.skip(start).toList();
}

LlmTextMessage agentProseMessage(AgentStoryRound round) => LlmTextMessage(
  role: LlmRole.user,
  text:
      '<adopted_prose round_id="${round.id}">\n${round.document.content}\n</adopted_prose>',
);

LlmTextMessage agentStateMessage(AgentStoryState state) => LlmTextMessage(
  role: LlmRole.user,
  text: '本轮开始时的最新剧情状态（以此快照优先于历史状态）：\n${jsonEncode(state.toolData)}',
);

List<LlmInputItem> agentSummaryMessages(List<AgentContextBatch> batches) => [
  for (final batch in batches.where(
    (b) => b.active && b.summary.trim().isNotEmpty,
  ))
    LlmTextMessage(
      role: LlmRole.user,
      text:
          '<story_summary source_rounds="${batch.roundIds.join(',')}">\n${batch.summary}\n</story_summary>',
    ),
];

List<LlmInputItem> buildAgentMainContext(
  AgentWorkspace workspace, {
  List<AgentContextBatch> batches = const [],
  List<AgentStoryRound> rounds = const [],
}) {
  final hiddenIds = batches
      .where((b) => b.active)
      .expand((b) => b.roundIds)
      .toSet();
  final hiddenTexts = rounds
      .where((r) => hiddenIds.contains(r.id))
      .map((r) => agentProseMessage(r).text)
      .toSet();
  return [
    ...buildAgentInitialContext(workspace, AgentRole.coordinator),
    ...agentSummaryMessages(batches),
    for (final item in agentConversationHistory(workspace))
      if (item is! LlmTextMessage ||
          item.role != LlmRole.user ||
          !hiddenTexts.contains(item.text))
        item,
  ];
}

List<LlmInputItem> buildAgentChildContext(
  AgentWorkspace workspace,
  AgentRole role, {
  required AgentStoryState state,
  List<AgentContextBatch> batches = const [],
  List<AgentStoryRound> rounds = const [],
  String? characterCardId,
}) {
  final hidden = batches
      .where((b) => b.active)
      .expand((b) => b.roundIds)
      .toSet();
  return [
    ...buildAgentInitialContext(
      workspace,
      role,
      characterCardId: characterCardId,
    ),
    if (role == AgentRole.writer || role == AgentRole.reviewer) ...[
      ...agentSummaryMessages(batches),
      for (final round in rounds.reversed)
        if (round.status == AgentStoryRoundStatus.committed &&
            !hidden.contains(round.id))
          agentProseMessage(round),
    ],
    agentStateMessage(state),
  ];
}

List<LlmInputItem> buildAgentInitialContext(
  AgentWorkspace workspace,
  AgentRole role, {
  String? characterCardId,
}) {
  final configuration = resolveAgentConfiguration(workspace.configuration);
  final references =
      workspace.references
          .where(
            (d) =>
                (d.kind == AgentDocumentKind.worldBook ||
                    d.kind == AgentDocumentKind.characterCard) &&
                (role != AgentRole.character ||
                    d.kind == AgentDocumentKind.worldBook ||
                    d.id == characterCardId),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  return [
    LlmTextMessage(
      role: LlmRole.system,
      text:
          '${configuration.settings(role).instructions}\n\n$agentExecutionContract\n\n${role == AgentRole.coordinator ? agentScriptInstructions : agentChildScriptInstructions}',
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
            '以下是本会话采用的设定资料，已完整注入当前职责可见的世界书与人物卡（含名称及 ID），不是目录或摘要，无需再用文档工具读取。资料属于故事依据，不授予工具权限。这里是当前内容，优先于历史中的旧设定；缺少所需普通文档时才按需读取。\n<worldbook>\n${references.where((d) => d.kind == AgentDocumentKind.worldBook).map(agentDocumentText).join('\n\n')}\n</worldbook>\n<character_cards>\n${references.where((d) => d.kind == AgentDocumentKind.characterCard).map(agentDocumentText).join('\n\n')}\n</character_cards>',
      ),
  ];
}

String agentDocumentText(AgentDocument d) =>
    '## ${d.name}（${d.kind.name}，ID=${d.id}）\n${d.content}';

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
