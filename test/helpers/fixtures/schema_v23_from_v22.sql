-- 固化的 v23 增量 fixture；先载入 schema_v21.sql 和 schema_v22_from_v21.sql。
-- 不调用生产迁移，保证 v23 → 后续版本从真实旧 schema 开始验证。
ALTER TABLE messages ADD COLUMN images_json TEXT NOT NULL DEFAULT '[]';
PRAGMA user_version = 23;
