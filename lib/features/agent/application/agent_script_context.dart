import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:oh_my_llm/core/llm/llm_content.dart';

import '../domain/agent_models.dart';
import '../domain/agent_script.dart';
import '../domain/agent_story_state.dart';

String agentScriptFingerprint(AgentDocument document) =>
    sha256.convert(utf8.encode(document.content)).toString();

Map<String, String> agentScriptCatalog(List<AgentDocument> documents) => {
  for (final doc in documents.where((d) => d.kind == AgentDocumentKind.script))
    doc.id: agentScriptFingerprint(doc),
};

/// 发现只追加一次，已见内容由作品检查点保存，不从可伪造的用户文本推断。
List<LlmInputItem> agentScriptUpdates(
  AgentWorkspace workspace,
  List<AgentDocument> documents, {
  bool full = false,
}) {
  final scripts =
      documents.where((d) => d.kind == AgentDocumentKind.script).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  final catalog = agentScriptCatalog(scripts);
  if (full) {
    return [
      LlmTextMessage(
        role: LlmRole.user,
        text:
            '当前完整剧本目录及有效进度（全文按需重新读取，未列出的旧剧本不再生效）：\n${jsonEncode([
              for (final doc in scripts) {'script_id': doc.id, 'name': doc.name, 'description': doc.description, 'fingerprint': catalog[doc.id], if (workspace.scriptProgress[doc.id]?.fingerprint == catalog[doc.id]) 'progress': workspace.scriptProgress[doc.id]!.toJson()},
            ])}',
      ),
    ];
  }
  final changes = <Map<String, Object?>>[
    for (final doc in scripts)
      if (workspace.knownScripts[doc.id] != catalog[doc.id])
        {
          'script_id': doc.id,
          'name': doc.name,
          'description': doc.description,
          'fingerprint': catalog[doc.id],
          'change': workspace.knownScripts.containsKey(doc.id)
              ? 'updated'
              : 'added',
        },
    for (final id in workspace.knownScripts.keys)
      if (!catalog.containsKey(id)) {'script_id': id, 'change': 'removed'},
  ];
  if (changes.isEmpty) return [];
  return [
    LlmTextMessage(
      role: LlmRole.user,
      text:
          '<script_catalog_updates>\n${jsonEncode(changes)}\n</script_catalog_updates>\n'
          '以上是剧本元信息，不是全文。需要细节时用 read_script 读取。'
          'updated 表示作者修改了当前剧本，旧全文与旧备忘需重新核对；'
          'removed 表示退出目录，不再作为有效剧本约束。以最新通知为准。',
    ),
  ];
}

AgentScriptProgress validateAgentScriptProgress({
  required AgentDocument document,
  required String status,
  required String notes,
  required Object? sourceRoundIds,
  required List<AgentStoryRound> rounds,
}) {
  final phase = AgentScriptStatus.values
      .where((s) => s.name == status)
      .firstOrNull;
  if (phase == null ||
      notes.trim().isEmpty ||
      utf8.encode(notes).length > 16 * 1024) {
    throw const AgentWorkspaceException('备忘需提供合法状态和 1–16 KiB 的说明。');
  }
  final committed = rounds
      .where((r) => r.status == AgentStoryRoundStatus.committed)
      .map((r) => r.id)
      .toSet();
  if (sourceRoundIds is! List ||
      sourceRoundIds.any((id) => id is! String || !committed.contains(id)) ||
      sourceRoundIds.toSet().length != sourceRoundIds.length ||
      (phase != AgentScriptStatus.planned && sourceRoundIds.isEmpty)) {
    throw const AgentWorkspaceException('推进或完成必须关联本作品已经提交的正式正文；来源 ID 不得重复。');
  }
  return AgentScriptProgress(
    fingerprint: agentScriptFingerprint(document),
    status: phase,
    notes: notes.trim(),
    sourceRoundIds: List<String>.from(sourceRoundIds),
  );
}
