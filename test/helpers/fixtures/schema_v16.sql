-- 2026-09-12 从 v15 业务 schema 固化的迁移 fixture，后续 schema 变更不得滚动重建。
CREATE TABLE collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      );

CREATE TABLE conversation_branch_selections (
        conversation_id TEXT NOT NULL,
        parent_id TEXT NOT NULL,
        child_id TEXT NOT NULL,
        PRIMARY KEY (conversation_id, parent_id),
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );

CREATE TABLE conversation_checkpoints (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        parent_checkpoint_id TEXT,
        covered_until_message_id TEXT,
        source_memory_prompt_name TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );

CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        selected_model_id TEXT,
        selected_preset_prompt_id TEXT,
        reasoning_enabled INTEGER NOT NULL DEFAULT 0,
        reasoning_effort TEXT NOT NULL,
        selected_checkpoint_id TEXT,
        excluded_message_ids_json TEXT NOT NULL DEFAULT '[]',
        auto_retry_enabled INTEGER NOT NULL DEFAULT 0
      );

CREATE TABLE favorites (
        id TEXT PRIMARY KEY,
        collection_id TEXT NOT NULL,
        user_message_content TEXT NOT NULL,
        assistant_content TEXT NOT NULL,
        assistant_reasoning_content TEXT NOT NULL DEFAULT '',
        source_conversation_id TEXT,
        source_conversation_title TEXT,
        source_assistant_message_id TEXT,
        created_at TEXT NOT NULL,
        assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
        title TEXT,
        collection_assigned_at TEXT NOT NULL,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE RESTRICT
      );

CREATE TABLE fixed_prompt_sequences (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        steps_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );

CREATE TABLE memory_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        node_index INTEGER NOT NULL,
        parent_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning_content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
        user_message_segments_json TEXT NOT NULL DEFAULT '[]',
        applied_checkpoint_title TEXT NOT NULL DEFAULT '',
        template_prompt_id TEXT DEFAULT NULL,
        template_variable_values_json TEXT NOT NULL DEFAULT '{}',
        finish_reason TEXT DEFAULT NULL,
        token_usage_json TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
      );

CREATE TABLE preset_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        messages_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );

CREATE TABLE template_prompts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        variables_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      );

CREATE INDEX idx_conversation_checkpoints_conversation_created_at
      ON conversation_checkpoints(conversation_id, created_at DESC);

CREATE INDEX idx_conversations_updated_at
      ON conversations(updated_at DESC);

CREATE INDEX idx_favorites_collection_assigned
      ON favorites(collection_id, collection_assigned_at DESC);

CREATE INDEX idx_favorites_collection_created
      ON favorites(collection_id, created_at DESC, id DESC);

CREATE INDEX idx_favorites_created_at
      ON favorites(created_at DESC);

CREATE INDEX idx_messages_conversation_node_index
      ON messages(conversation_id, node_index);

CREATE INDEX idx_messages_conversation_parent
      ON messages(conversation_id, parent_id);
INSERT INTO collections (id, name, created_at) VALUES ('__uncategorized_favorites__', '未分类', '2026-09-12T00:00:00.000');
PRAGMA user_version = 15;


      CREATE TABLE agent_workspaces (
        id TEXT PRIMARY KEY, updated_at TEXT NOT NULL, record_json TEXT NOT NULL
      );
      CREATE TABLE agent_runs (
        id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, started_at TEXT NOT NULL,
        status TEXT NOT NULL, record_json TEXT NOT NULL,
        FOREIGN KEY (workspace_id) REFERENCES agent_workspaces(id) ON DELETE CASCADE
      );
      CREATE INDEX idx_agent_runs_workspace ON agent_runs(workspace_id, started_at DESC, id DESC);
      CREATE TABLE agent_document_revisions (
        workspace_id TEXT NOT NULL, name TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0),
        content TEXT NOT NULL, PRIMARY KEY(workspace_id, name, revision),
        FOREIGN KEY (workspace_id) REFERENCES agent_workspaces(id) ON DELETE CASCADE
      );

PRAGMA user_version = 16;
