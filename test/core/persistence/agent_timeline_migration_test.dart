import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

void main() {
  for (final fail in [false, true]) {
    test(
      fail
          ? '单时间线迁移中断时完整回滚 Agent 清空和 schema'
          : 'v21 升级只清空 Agent 测试数据，普通聊天和提示词保留且新作品重开不丢失',
      () {
        final directory = Directory.systemTemp.createTempSync(
          'agent-timeline-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}/old.sqlite';
        final old = sqlite.sqlite3.open(path);
        old.execute(
          File('test/helpers/fixtures/schema_v21.sql').readAsStringSync(),
        );
        // 固定旧版 wire 记录；新 codec 不再生成带会话的格式。
        old.execute('''
        INSERT INTO agent_workspaces VALUES ('work', '2026-09-18', '{"version":2,"title":"测试作品","activeSessionId":"initial"}');
        INSERT INTO agent_sessions VALUES ('work', 'initial', '会话 1', '2026-09-18', '{"version":2,"id":"work","title":"测试作品","sessionId":"initial","sessionTitle":"会话 1","modelId":null,"instructions":"","references":[],"history":""}', '草稿');
        INSERT INTO agent_documents VALUES ('work', '正文', '测试正文', 'doc', 'document', NULL);
        INSERT INTO agent_configurations VALUES ('work', '方案', '{"name":"方案","modelId":null,"preset":"","presetRoles":[],"roles":{}}');
        INSERT INTO agent_story_states VALUES ('work', '{"version":1,"revision":0,"rows":[]}');
        INSERT INTO agent_document_undo VALUES ('work', 'run', '正文', NULL, NULL);
        INSERT INTO agent_history_items VALUES ('work', 'item', '{"type":"text","role":"user","text":"旧任务"}');
        INSERT INTO agent_history_entries VALUES ('work', 'head', '', 'item');
        INSERT INTO conversations (id,title,created_at,updated_at,reasoning_effort) VALUES ('chat','普通聊天','2026','2026','medium');
        INSERT INTO messages (id,conversation_id,node_index,role,content,created_at) VALUES ('msg','chat',0,'user','必须保留的聊天正文','2026');
        INSERT INTO template_prompts (id,title,content,updated_at) VALUES ('template','提示词','必须保留的模板','2026');
      ''');
        if (fail) {
          old.execute(
            "CREATE TRIGGER stop_reset BEFORE DELETE ON agent_documents BEGIN SELECT RAISE(ABORT, '模拟迁移失败'); END;",
          );
        }
        old.close();
        if (fail) {
          expect(() => AppDatabase.forPath(path), throwsA(anything));
          final raw = sqlite.sqlite3.open(path);
          addTearDown(raw.close);
          expect(raw.select('PRAGMA user_version').single['user_version'], 21);
          expect(raw.select('SELECT * FROM agent_sessions'), hasLength(1));
          expect(
            raw.select('SELECT content FROM agent_documents').single['content'],
            '测试正文',
          );
          expect(raw.select('SELECT * FROM agent_history_items'), hasLength(1));
          return;
        }
        var db = AppDatabase.forPath(path);
        try {
          expect(
            db.connection.select('PRAGMA user_version').single['user_version'],
            greaterThanOrEqualTo(22),
          );
          expect(
            db.connection.select(
              "SELECT name FROM sqlite_master WHERE name='agent_sessions'",
            ),
            isEmpty,
          );
          expect(
            db.connection
                .select('PRAGMA table_info(agent_runs)')
                .map((r) => r['name']),
            isNot(contains('session_id')),
          );
          for (final table in db.connection.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'agent_%'",
          )) {
            expect(
              db.connection.select('SELECT * FROM ${table['name']}'),
              isEmpty,
              reason: table['name'] as String,
            );
          }
          expect(
            db.connection
                .select('SELECT content FROM messages')
                .single['content'],
            '必须保留的聊天正文',
          );
          expect(
            db.connection
                .select('SELECT content FROM template_prompts')
                .single['content'],
            '必须保留的模板',
          );
          expect(db.connection.select('PRAGMA foreign_key_check'), isEmpty);
          final workspace = AgentWorkspace(
            id: 'new',
            title: '正式作品',
            draft: '新草稿',
          );
          SqliteAgentStore(db).saveWorkspace(workspace);
          db.close();
          db = AppDatabase.forPath(path);
          expect(SqliteAgentStore(db).loadWorkspace('new'), workspace);
        } finally {
          db.close();
        }
      },
    );
  }
}
