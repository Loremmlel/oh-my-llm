import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';

void main() {
  test('完整 v18 升级去除改稿版本，保留当前正文和连续整轮撤回', () {
    final directory = Directory.systemTemp.createTempSync(
      'agent-documents-v18-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/old.sqlite';
    final old = sqlite.sqlite3.open(path);
    old.execute(
      File('test/helpers/fixtures/schema_v18.sql').readAsStringSync(),
    );
    // 已发布 v18 的实际 wire 格式，包括随后被移除的版本字段。
    final config = {
      'name': '默认',
      'revision': 1,
      'modelId': 'm',
      'preset': '旧文风',
      'presetRoles': ['coordinator'],
      'roles': <String, Object?>{},
    };
    final session = {
      'version': 2,
      'id': 'w',
      'title': '小说',
      'sessionId': 'initial',
      'sessionTitle': '会话',
      'configuration': config,
      'references': [],
      'referencesFrozen': true,
      'modelId': 'm',
      'instructions': '',
      'draft': '原指令',
      'history': [],
    };
    old.execute('INSERT INTO agent_workspaces VALUES (?, ?, ?)', [
      'w',
      '2026',
      jsonEncode({'version': 2, 'title': '小说', 'activeSessionId': 'initial'}),
    ]);
    old.execute('INSERT INTO agent_sessions VALUES (?, ?, ?, ?, ?)', [
      'w',
      'initial',
      '会话',
      '2026',
      jsonEncode(session),
    ]);
    for (var version = 1; version <= 2; version++) {
      old.execute('INSERT INTO agent_configurations VALUES (?, ?, ?)', [
        'w',
        version,
        jsonEncode({...config, 'revision': version, 'preset': '文风 $version'}),
      ]);
    }
    for (var version = 1; version <= 4; version++) {
      final run = version <= 2 ? 'first' : 'second';
      old.execute(
        'INSERT INTO agent_document_revisions VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['w', '正文', version, '稿 $version', 'doc', 'document', run],
      );
    }
    for (final entry in [('first', 2, 0), ('second', 4, 1)]) {
      final (id, revision, stateRevision) = entry;
      final state = {'version': 1, 'revision': stateRevision, 'rows': []};
      final after = {...state, 'revision': stateRevision + 1};
      final round = {
        'version': 1,
        'id': id,
        'stateAgentId': '$id-state',
        'beforeWorkspace': session,
        'document': {
          'id': 'doc',
          'name': '正文',
          'content': '稿 $revision',
          'revision': revision,
          'kind': 'document',
        },
        'beforeState': state,
        'afterState': after,
        'status': 'committed',
        'operations': [],
      };
      old.execute(
        'INSERT INTO agent_story_rounds (id, workspace_id, session_id, status, record_json) VALUES (?, ?, ?, ?, ?)',
        [id, 'w', 'initial', 'committed', jsonEncode(round)],
      );
    }
    old.execute('INSERT INTO agent_story_states VALUES (?, ?)', [
      'w',
      jsonEncode({'version': 1, 'revision': 2, 'rows': []}),
    ]);
    old.close();
    final database = AppDatabase.forPath(path);
    addTearDown(database.close);
    final store = SqliteAgentStore(database);
    expect(
      database.connection.select('PRAGMA user_version').single['user_version'],
      greaterThanOrEqualTo(19),
    );
    expect(
      database.connection.select(
        "SELECT name FROM sqlite_master WHERE name = 'agent_document_revisions'",
      ),
      isEmpty,
    );
    expect(store.listDocuments('w'), hasLength(1));
    expect(store.readDocument('w', '正文')!.content, '稿 4');
    expect(store.listConfigurations('w').single.preset, '文风 2');
    expect(store.listStoryRounds('w', 'initial').first.document.content, '稿 4');
    store.withdrawStoryRound('w', 'initial', 'second');
    expect(store.readDocument('w', '正文')!.content, '稿 2');
    store.withdrawStoryRound('w', 'initial', 'first');
    expect(store.readDocument('w', '正文'), isNull);
    expect(store.readStoryState('w').rows, isEmpty);
    expect(store.loadWorkspace('w')!.draft, '原指令');
    expect(database.connection.select('PRAGMA foreign_key_check'), isEmpty);
  });
}
