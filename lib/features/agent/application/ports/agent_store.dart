import '../../domain/agent_models.dart';

/// 工作区与执行记录的原子检查点；工具只能拿到绑定的工作区 ID。
abstract interface class AgentStore {
  List<AgentWorkspace> listWorkspaces();
  AgentWorkspace? loadWorkspace(String id, {String? sessionId});
  void saveWorkspace(AgentWorkspace workspace);
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
  AgentDocument? readDocument(String workspaceId, String name, {int? revision});
  AgentDocument writeDocument(
    String workspaceId,
    String name,
    String content, {
    required int expectedRevision,
    AgentDocumentKind? kind,
  });
}
