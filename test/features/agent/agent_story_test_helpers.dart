import 'package:oh_my_llm/features/agent/application/agent_context.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

AgentStoryRound seedProseFloor(SqliteAgentStore store, int number) {
  final workspace = store.loadWorkspace('novel')!;
  final root = AgentRunRecord(
    id: 'floor-$number',
    workspaceId: workspace.id,
    prompt: '写第 $number 楼',
    startedAt: DateTime(2026, 9, 16).add(Duration(seconds: number)),
  );
  store.checkpoint(root);
  final document = store.writeDocument(
    workspace.id,
    '正文',
    '正式正文 $number',
    sourceRunId: root.id,
  );
  final state = AgentRunRecord(
    id: 'state-$number',
    workspaceId: workspace.id,
    parentId: root.id,
    role: AgentRole.state,
    prompt: '更新',
    startedAt: root.startedAt,
  );
  store.checkpoint(state);
  store.prepareStoryRound(
    AgentStoryRound(
      id: root.id,
      beforeWorkspace: workspace.copyWith(draft: root.prompt),
      document: document,
      beforeState: store.readStoryState(workspace.id),
      stateAgentId: state.id,
    ),
  );
  final saved = store.commitStoryRound(workspace.id, root.id, state.id, []);
  store.checkpoint(state.copyWith(status: AgentRunStatus.completed));
  store.checkpoint(
    root.copyWith(status: AgentRunStatus.completed, content: document.content),
    workspace: workspace.copyWith(
      history: [...workspace.history, agentProseMessage(saved)],
    ),
  );
  return saved;
}
