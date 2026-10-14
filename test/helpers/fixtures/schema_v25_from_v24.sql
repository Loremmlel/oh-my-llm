ALTER TABLE preset_prompts ADD COLUMN syntax TEXT NOT NULL DEFAULT 'plain';
PRAGMA user_version = 25;
