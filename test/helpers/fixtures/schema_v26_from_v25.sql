BEGIN IMMEDIATE;
CREATE TABLE world_books (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  entries_json TEXT NOT NULL DEFAULT '[]',
  updated_at TEXT NOT NULL
);
ALTER TABLE conversations ADD COLUMN selected_world_book_id TEXT;
ALTER TABLE preset_prompts ADD COLUMN custom_reasoning_tag TEXT NOT NULL DEFAULT '';
PRAGMA user_version = 26;
COMMIT;
