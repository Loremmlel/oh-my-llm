import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';

void main() {
  for (final malformed in [false, true]) {
    test(malformed ? '损坏历史使迁移整体回滚，原草稿和正文仍在旧库' : '已发布 v20 历史经过顺序迁移并清空旧 Agent 测试数据，重开不重复迁移', () {
      final directory = Directory.systemTemp.createTempSync(
        'agent-history-v20-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/old.sqlite';
      final old = sqlite.sqlite3.open(path);
      old.execute(
        File('test/helpers/fixtures/schema_v20.sql').readAsStringSync(),
      );
      // 固定已发布格式，迁移不依赖当前 codec 生成历史样本。
      final history = [
        {'type': 'text', 'role': 'user', 'text': '原开场'},
        {
          'type': 'assistant',
          'text': '正文',
          'reasoning': '推理摘要',
          'protocol': 'responses',
          'endpoint': 'https://example.com/v1/responses',
          'model': 'old-model',
          'items': [
            {
              'type': 'reasoning',
              'encrypted_content': 'original-native-value',
              'summary': [],
            },
          ],
          'calls': [],
        },
      ];
      final workspace = <String, dynamic>{
        'version': 2,
        'id': 'novel',
        'title': '旧小说',
        'sessionId': 'initial',
        'sessionTitle': '原会话',
        'modelId': 'old-model',
        'instructions': '旧规则',
        'configuration': {
          'name': '旧方案',
          'modelId': 'old-model',
          'preset': '旧规则',
          'presetRoles': ['writer'],
          'roles': {},
        },
        'references': [],
        'draft': '未发送',
        'history': history,
      };
      final run = <String, dynamic>{
        'version': 1,
        'id': 'root',
        'workspaceId': 'novel',
        'sessionId': 'initial',
        'parentId': null,
        'role': 'coordinator',
        'status': 'completed',
        'prompt': '原开场',
        'startedAt': '2026-09-15T00:00:00',
        'content': '正文',
        'error': '',
        'modelCalls': 1,
        'usage': null,
        'steps': [],
        'childHistory': [],
        'inputHistory': history,
      };
      final round = <String, dynamic>{
        'version': 1,
        'id': 'root',
        'stateAgentId': 'state',
        'beforeWorkspace': workspace,
        'document': {
          'id': 'prose',
          'name': '正文',
          'kind': 'document',
          'content': '原文永久保留',
        },
        'beforeState': {'version': 1, 'revision': 0, 'rows': []},
        'afterState': {'version': 1, 'revision': 1, 'rows': []},
        'status': 'committed',
        'operations': [],
      };
      old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
        'novel',
        '2026-09-15',
        jsonEncode({
          'version': 2,
          'title': '旧小说',
          'activeSessionId': 'initial',
        }),
      ]);
      old.execute('INSERT INTO agent_sessions VALUES (?, ?, ?, ?, ?)', [
        'novel',
        'initial',
        '原会话',
        '2026-09-15',
        jsonEncode(workspace),
      ]);
      old.execute('INSERT INTO agent_runs VALUES (?, ?, ?, ?, ?, ?)', [
        'root',
        'novel',
        '2026-09-15',
        'completed',
        jsonEncode(run),
        'initial',
      ]);
      old.execute(
        'INSERT INTO agent_story_rounds (id, workspace_id, session_id, status, record_json) VALUES (?, ?, ?, ?, ?)',
        [
          'root',
          'novel',
          'initial',
          'committed',
          jsonEncode(
            malformed
                ? {
                    ...round,
                    'beforeWorkspace': {...workspace, 'history': '损坏的旧数组'},
                  }
                : round,
          ),
        ],
      );
      old.execute(
        'INSERT INTO agent_context_batches (workspace_id, session_id, id, record_json) VALUES (?, ?, ?, ?)',
        [
          'novel',
          'initial',
          'summary',
          jsonEncode({
            'version': 1,
            'id': 'summary',
            'roundIds': ['root'],
            'summary': '旧总结',
            'summaryRunId': null,
            'status': 'active',
          }),
        ],
      );
      old.close();
      if (malformed) {
        expect(() => AppDatabase.forPath(path), throwsA(anything));
        final raw = sqlite.sqlite3.open(path);
        addTearDown(raw.close);
        expect(raw.select('PRAGMA user_version').single['user_version'], 20);
        expect(
          raw
              .select('SELECT record_json FROM agent_sessions')
              .single['record_json'],
          jsonEncode(workspace),
        );
        expect(
          raw.select(
            "SELECT name FROM sqlite_master WHERE name LIKE 'agent_history_%'",
          ),
          isEmpty,
        );
      } else {
        var database = AppDatabase.forPath(path);
        try {
          for (var open = 0; open < 2; open++) {
            final store = SqliteAgentStore(database);
            expect(
              database.connection
                  .select('PRAGMA user_version')
                  .single['user_version'],
              greaterThanOrEqualTo(21),
            );
            expect(store.loadWorkspace('novel'), isNull);
            expect(store.loadRun('novel', 'root'), isNull);
            expect(store.readStoryRound('novel', 'root'), isNull);
            expect(store.readContextBatch('novel'), isNull);
            expect(
              database.connection.select('SELECT * FROM agent_history_items'),
              isEmpty,
            );
            expect(
              database.connection.select('PRAGMA foreign_key_check'),
              isEmpty,
            );
            if (open == 0) {
              database.close();
              database = AppDatabase.forPath(path);
            }
          }
        } finally {
          database.close();
        }
      }
    });
  }
}
