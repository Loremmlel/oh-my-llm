import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';

void main() {
  test('完整已发布 v19 顺序升级后清空旧 Agent 测试设定', () {
    final directory = Directory.systemTemp.createTempSync('agent-context-v19-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/old.sqlite';
    final old = sqlite.sqlite3.open(path);
    old.execute(
      File('test/helpers/fixtures/schema_v19.sql').readAsStringSync(),
    );
    // 迁移边界使用已发布 wire 格式，不由新模型生成旧记录。
    final workspace = jsonEncode({
      'version': 2,
      'id': 'novel',
      'title': '旧小说',
      'sessionId': 'initial',
      'sessionTitle': '会话 1',
      'configuration': {
        'name': '默认',
        'modelId': 'model',
        'preset': '既有文风',
        'presetRoles': ['writer'],
        'roles': {
          'writer': {'modelId': null, 'instructions': '用户自己的写作规则'},
        },
      },
      'modelId': 'model',
      'instructions': '',
      'references': [],
      'draft': '原草稿',
      'history': [],
    });
    old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
      'novel',
      '2026-09-15',
      jsonEncode({'version': 2, 'title': '旧小说', 'activeSessionId': 'initial'}),
    ]);
    old.execute('INSERT INTO agent_sessions VALUES (?, ?, ?, ?, ?)', [
      'novel',
      'initial',
      '会话 1',
      '2026-09-15',
      workspace,
    ]);
    old.execute('INSERT INTO agent_documents VALUES (?, ?, ?, ?, ?, ?)', [
      'novel',
      '世界',
      '旧设定',
      'world',
      'worldBook',
      null,
    ]);
    old.close();
    final database = AppDatabase.forPath(path);
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    expect(
      database.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(20),
    );
    expect(store.loadWorkspace('novel'), isNull);
    expect(store.listDocuments('novel'), isEmpty);
    expect(store.readContextBatch('novel'), isNull);
    database.close();
    final reopened = AppDatabase.forPath(path);
    addTearDown(reopened.close);
    expect(SqliteAgentStore(reopened).loadWorkspace('novel'), isNull);
  });
}
