import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';

void main() {
  test('完整 v16 工作区升级为作品与会话，保留原生历史草稿和文档版本', () {
    final directory = Directory.systemTemp.createTempSync('novel-v16-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/old.sqlite';
    final old = sqlite.sqlite3.open(path);
    old.execute(
      File('test/helpers/fixtures/schema_v16.sql').readAsStringSync(),
    );
    // 固定旧版 wire 数据，不能使用当前 codec 伪造历史兼容样本。
    final history = [
      {'type': 'text', 'role': 'system', 'text': '原系统提示词'},
      {'type': 'text', 'role': 'user', 'text': '原任务'},
      {
        'type': 'assistant',
        'text': '原回复',
        'reasoning': '原摘要',
        'protocol': 'responses',
        'endpoint': 'https://example.com/v1/responses',
        'model': 'old-model',
        'items': [
          {
            'type': 'reasoning',
            'encrypted_content': 'opaque-native-value',
            'summary': [],
          },
        ],
        'calls': [],
      },
    ];
    old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
      'novel',
      '2026-09-12',
      jsonEncode({
        'version': 1,
        'id': 'novel',
        'title': '旧作品',
        'modelId': 'old-model',
        'instructions': '旧预设',
        'draft': '未发送草稿',
        'history': history,
      }),
    ]);
    for (var revision = 1; revision <= 2; revision++) {
      old.execute('INSERT INTO agent_document_revisions VALUES (?, ?, ?, ?)', [
        'novel',
        '正文',
        revision,
        '原文 $revision',
      ]);
    }
    old.execute('INSERT INTO agent_runs VALUES (?, ?, ?, ?, ?)', [
      'run',
      'novel',
      '2026-09-12',
      'completed',
      jsonEncode({
        'version': 1,
        'id': 'run',
        'workspaceId': 'novel',
        'parentId': null,
        'role': 'coordinator',
        'status': 'completed',
        'prompt': '原任务',
        'startedAt': '2026-09-12T00:00:00',
        'content': '原回复',
        'error': '',
        'modelCalls': 1,
        'usage': null,
        'steps': [],
      }),
    ]);
    old.close();
    final database = AppDatabase.forPath(path);
    addTearDown(database.close);
    expect(
      database.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(17),
    );
    final session = jsonDecode(
      database.connection.select(
            'SELECT record_json FROM agent_sessions WHERE workspace_id = ?',
            ['novel'],
          ).single['record_json']
          as String,
    ) as Map;
    expect(session['history'], history);
    expect(session['draft'], '未发送草稿');
    expect(session['modelId'], 'old-model');
    final documents = database.connection.select(
      'SELECT * FROM agent_document_revisions ORDER BY revision',
    );
    expect(documents.map((r) => r['content']), ['原文 1', '原文 2']);
    expect(documents.map((r) => r['document_id']).toSet(), hasLength(1));
    expect(documents.every((r) => r['kind'] == 'document'), isTrue);
    expect(
      database.connection
          .select('SELECT session_id FROM agent_runs')
          .single['session_id'],
      'initial',
    );
  });
  test('旧工作区包络损坏时整体回滚迁移，不遗留新表或提高版本', () {
    final directory = Directory.systemTemp.createTempSync('novel-malformed-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/old.sqlite';
    final old = sqlite.sqlite3.open(path);
    old.execute(
      File('test/helpers/fixtures/schema_v16.sql').readAsStringSync(),
    );
    // 明确验证损坏的旧版记录，缺少 title/history 等必要字段。
    old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
      'n',
      '2026-09-12',
      '{"version":1,"id":"n"}',
    ]);
    old.close();
    expect(() => AppDatabase.forPath(path), throwsFormatException);
    final check = sqlite.sqlite3.open(path);
    addTearDown(check.close);
    expect(
      check.select('PRAGMA user_version').single['user_version'],
      allOf(greaterThanOrEqualTo(16), lessThan(17)),
    );
    expect(
      check.select(
        "SELECT name FROM sqlite_master WHERE name = 'agent_sessions'",
      ),
      isEmpty,
    );
    expect(
      check
          .select('SELECT record_json FROM agent_workspaces')
          .single['record_json'],
      '{"version":1,"id":"n"}',
    );
  });
}
