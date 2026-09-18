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

  /// 列表可省略撤回用的输入历史，撤回和重试必须使用完整轮次读取。
  List<AgentStoryRound> listStoryRounds(
    String workspaceId,
    String sessionId, {
    bool includeHistory = true,
  });
  AgentStoryRound prepareStoryRound(AgentStoryRound round);
  AgentStoryRound commitStoryRound(
    String workspaceId,
    String roundId,
    String stateAgentId,
    List<AgentStateOperation> operations,
  );
  void withdrawStoryRound(String workspaceId, String sessionId, String roundId);

  /// 原子撤回最新主任务的副作用并清空原回复，保留任务身份和当前草稿。
  AgentRunRecord resetLatestReply(
    String workspaceId,
    String sessionId,
    String runId,
  );
  List<({String id, String title})> listWorkspaces();
  AgentWorkspace? loadWorkspace(String id, {String? sessionId});
  void saveWorkspace(AgentWorkspace workspace);
  void saveDraft(String workspaceId, String sessionId, String draft);
  void renameSession(String workspaceId, String sessionId, String title);
  List<({String id, String title})> listSessions(String workspaceId);
  List<AgentConfiguration> listConfigurations(String workspaceId);
  AgentConfiguration saveConfiguration(
    String workspaceId,
    AgentConfiguration configuration,
  );

  /// 列表可省略模型输入历史；查看实际输入时通过 [loadRun] 按需读取。
  List<AgentRunRecord> listRuns(
    String workspaceId, {
    int limit = 50,
    String? sessionId,
    bool includeHistory = true,
  });
  AgentRunRecord? loadRun(String workspaceId, String runId);
  List<AgentRunRecord> listChildRuns(String workspaceId, String parentId);
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
