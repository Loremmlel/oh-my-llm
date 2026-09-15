import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';

void main() {
  test('完整 v17 数据库升级后保留会话配置正文和原生记录，状态库初始为空', () {
    final directory = Directory.systemTemp.createTempSync('story-v17-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/old.sqlite';
    final old = sqlite.sqlite3.open(path);
    old.execute(
      File('test/helpers/fixtures/schema_v17.sql').readAsStringSync(),
    );
    // 固定已发布版本的 wire 数据，避免用新版构造器提前升级被测数据。
    final config = {
      'name': '旧方案',
      'revision': 1,
      'modelId': 'model',
      'preset': '旧预设',
      'presetRoles': ['coordinator', 'writer'],
      'roles': {
        'writer': {'modelId': 'writer-model', 'instructions': '旧写作规则'},
      },
    };
    final session = {
      'version': 2,
      'id': 'novel',
      'title': '旧小说',
      'sessionId': 'initial',
      'sessionTitle': '旧会话',
      'configuration': config,
      'references': [],
      'referencesFrozen': true,
      'modelId': 'model',
      'instructions': '旧预设',
      'draft': '未发送的原输入',
      'history': [
        {'type': 'text', 'role': 'user', 'text': '原开场'},
      ],
    };
    old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
      'novel',
      '2026-09-15',
      jsonEncode({'version': 2, 'title': '旧小说', 'activeSessionId': 'initial'}),
    ]);
    old.execute('INSERT INTO agent_sessions VALUES (?, ?, ?, ?, ?)', [
      'novel',
      'initial',
      '旧会话',
      '2026-09-15',
      jsonEncode(session),
    ]);
    old.execute('INSERT INTO agent_configurations VALUES (?, ?, ?)', [
      'novel',
      1,
      jsonEncode(config),
    ]);
    old.execute(
      'INSERT INTO agent_document_revisions VALUES (?, ?, ?, ?, ?, ?)',
      ['novel', '正文', 1, '旧正文', 'document-id', 'document'],
    );
    final record = jsonEncode({
      'version': 1,
      'id': 'run',
      'workspaceId': 'novel',
      'sessionId': 'initial',
      'parentId': null,
      'role': 'coordinator',
      'status': 'completed',
      'prompt': '原开场',
      'startedAt': '2026-09-15T00:00:00',
      'content': '旧正文',
      'error': '',
      'modelCalls': 1,
      'usage': null,
      'steps': [],
    });
    old.execute('INSERT INTO agent_runs VALUES (?, ?, ?, ?, ?, ?)', [
      'run',
      'novel',
      '2026-09-15',
      'completed',
      record,
      'initial',
    ]);
    old.close();
    final database = AppDatabase.forPath(path);
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    expect(
      database.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(18),
    );
    expect(
      database.connection
          .select('SELECT record_json FROM agent_sessions')
          .single['record_json'],
      jsonEncode(session),
    );
    expect(
      database.connection
          .select('SELECT record_json FROM agent_runs')
          .single['record_json'],
      record,
    );
    expect(store.loadWorkspace('novel')!.draft, '未发送的原输入');
    expect(store.listConfigurations('novel').single.preset, '旧预设');
    expect(store.readDocument('novel', '正文')!.content, '旧正文');
    expect(store.readStoryState('novel').rows, isEmpty);
    expect(store.latestStoryRound('novel'), isNull);
    expect(database.connection.select('PRAGMA foreign_key_check'), isEmpty);
  });
}
