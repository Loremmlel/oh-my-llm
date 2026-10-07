-- 已发布的单 System 模式迁移，作为后续迁移的数据保留基线。
ALTER TABLE preset_prompts ADD COLUMN single_system_prompt INTEGER NOT NULL DEFAULT 0;
PRAGMA user_version = 24;
