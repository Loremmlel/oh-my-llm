import '../../domain/agent_models.dart';
import '../../domain/agent_story_state.dart';
import '../../domain/agent_context_batch.dart';

/// 工作区与执行记录的原子检查点；工具只能拿到绑定的工作区 ID。
abstract interface class AgentStore {
  List<AgentContextBatch> listContextBatches(
    String workspaceId,
    String sessionId,
  );
  void saveContextBatch(
    String workspaceId,
    String sessionId,
    AgentContextBatch batch,
  );
  AgentStoryState readStoryState(String workspaceId);
  AgentStoryRound? readStoryRound(String workspaceId, String roundId);
  AgentStoryRound? latestStoryRound(String workspaceId);
  List<AgentStoryRound> listStoryRounds(String workspaceId, String sessionId);
  AgentStoryRound prepareStoryRound(AgentStoryRound round);
  AgentStoryRound commitStoryRound(
    String workspaceId,
    String roundId,
    String stateAgentId,
    List<AgentStateOperation> operations,
  );
  void withdrawStoryRound(String workspaceId, String sessionId, String roundId);
  List<AgentWorkspace> listWorkspaces();
  AgentWorkspace? loadWorkspace(String id, {String? sessionId});
  void saveWorkspace(AgentWorkspace workspace);
  void renameSession(String workspaceId, String sessionId, String title);
  List<({String id, String title})> listSessions(String workspaceId);
  List<AgentConfiguration> listConfigurations(String workspaceId);
  AgentConfiguration saveConfiguration(
    String workspaceId,
    AgentConfiguration configuration,
  );
  List<AgentRunRecord> listRuns(
    String workspaceId, {
    int limit = 50,
    String? sessionId,
  });
  AgentRunRecord? loadRun(String workspaceId, String runId);
  void checkpoint(AgentRunRecord run, {AgentWorkspace? workspace});
  void recoverInterruptedRuns();
  List<AgentDocument> listDocuments(String workspaceId);
  AgentDocument? readDocument(String workspaceId, String name);
  AgentDocument writeDocument(
    String workspaceId,
    String name,
    String content, {
    AgentDocumentKind? kind,
    String? sourceRunId,
    String? documentId,
  });
}
