-- 固化的 v22 增量 fixture；测试先载入 schema_v21.sql，再执行本文件。
-- 不调用生产迁移，确保 v22 → 后续版本的测试从真实旧 schema 开始。
DELETE FROM agent_workspaces;
DROP TABLE agent_context_batches;
DROP TABLE agent_story_rounds;
DROP TABLE agent_sessions;
DROP INDEX idx_agent_runs_session;
ALTER TABLE agent_runs DROP COLUMN session_id;
ALTER TABLE agent_workspaces ADD COLUMN draft TEXT NOT NULL DEFAULT '';
CREATE TABLE agent_story_rounds (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE, workspace_id TEXT NOT NULL,
  status TEXT NOT NULL, record_json TEXT NOT NULL,
  FOREIGN KEY(workspace_id) REFERENCES agent_workspaces(id) ON DELETE CASCADE
);
CREATE INDEX idx_agent_story_rounds_workspace ON agent_story_rounds(workspace_id, sequence DESC);
CREATE TABLE agent_context_batches (
  workspace_id TEXT PRIMARY KEY, id TEXT NOT NULL, record_json TEXT NOT NULL,
  FOREIGN KEY(workspace_id) REFERENCES agent_workspaces(id) ON DELETE CASCADE
);
PRAGMA user_version = 22;
