import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../application/ports/agent_store.dart';
import '../domain/agent_models.dart';
import 'agent_record_codec.dart';

class SqliteAgentStore implements AgentStore {
  SqliteAgentStore(this.database);
  final AppDatabase database;
  @override
  List<AgentWorkspace> listWorkspaces() => [
    for (final row in database.connection.select(
      'SELECT id FROM agent_workspaces ORDER BY updated_at DESC, id DESC;',
    ))
      loadWorkspace(row['id'] as String)!,
  ];
  @override
  AgentWorkspace? loadWorkspace(String id, {String? sessionId}) {
    final projects = database.connection.select(
      'SELECT record_json FROM agent_workspaces WHERE id = ?;',
      [id],
    );
    if (projects.isEmpty) return null;
    final metadata =
        jsonDecode(projects.single['record_json'] as String) as Map;
    if (metadata['version'] != 2) throw const FormatException('不支持的作品记录版本');
    final rows = database.connection.select(
      'SELECT record_json FROM agent_sessions WHERE workspace_id = ? AND id = ?;',
      [id, sessionId ?? metadata['activeSessionId']],
    );
    return rows.isEmpty
        ? null
        : decodeAgentWorkspace(jsonDecode(rows.single['record_json'] as String))
              .copyWith(title: metadata['title'] as String);
  }

  @override
  void saveWorkspace(AgentWorkspace workspace) =>
      _transaction(() => _saveWorkspace(workspace));

  void _saveWorkspace(AgentWorkspace workspace, {bool activate = true}) {
    final existing = database.connection.select(
      'SELECT 1 FROM agent_sessions WHERE workspace_id = ? AND id = ?;',
      [workspace.id, workspace.sessionId],
    );
    if (existing.isEmpty && listSessions(workspace.id).length >= 100) {
      throw const AgentWorkspaceException('每部作品最多保存 100 个会话。');
    }
    final now = DateTime.now().toIso8601String();
    if (activate) {
      database.connection.execute(
        '''
        INSERT INTO agent_workspaces (id, updated_at, record_json) VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, record_json = excluded.record_json;
      ''',
        [
          workspace.id,
          now,
          jsonEncode({
            'version': 2,
            'title': workspace.title,
            'activeSessionId': workspace.sessionId,
          }),
        ],
      );
    }
    database.connection.execute(
      '''
      INSERT INTO agent_sessions (workspace_id, id, title, created_at, record_json) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(workspace_id, id) DO UPDATE SET title = excluded.title, record_json = excluded.record_json;
    ''',
      [
        workspace.id,
        workspace.sessionId,
        workspace.sessionTitle,
        now,
        jsonEncode(encodeAgentWorkspace(workspace)),
      ],
    );
  }

  @override
  List<({String id, String title})> listSessions(String workspaceId) => [
    for (final row in database.connection.select(
      'SELECT id, title FROM agent_sessions WHERE workspace_id = ? ORDER BY created_at, id;',
      [workspaceId],
    ))
      (id: row['id'] as String, title: row['title'] as String),
  ];

  @override
  List<AgentConfiguration> listConfigurations(String workspaceId) => [
    for (final row in database.connection.select(
      'SELECT record_json FROM agent_configurations WHERE workspace_id = ? ORDER BY revision DESC;',
      [workspaceId],
    ))
      decodeAgentConfiguration(jsonDecode(row['record_json'] as String)),
  ];

  @override
  AgentConfiguration saveConfiguration(
    String workspaceId,
    AgentConfiguration configuration,
  ) {
    if (configuration.name.trim().isEmpty ||
        configuration.name.length > 120 ||
        RegExp(r'[\x00-\x1f]').hasMatch(configuration.name)) {
      throw const AgentWorkspaceException('方案名称需为 1–120 个字符，不能包含控制字符。');
    }
    if (utf8.encode(configuration.preset).length > 64 * 1024 ||
        configuration.roles.values.any(
          (role) => utf8.encode(role.instructions).length > 64 * 1024,
        )) {
      throw const AgentWorkspaceException('每份提示词或预设不能超过 64 KiB。');
    }
    late AgentConfiguration saved;
    _transaction(() {
      final current = listConfigurations(workspaceId);
      if (current.length >= 200) {
        throw const AgentWorkspaceException('每部作品最多保存 200 个配置版本。');
      }
      saved = configuration.copyWith(
        revision: (current.firstOrNull?.revision ?? 0) + 1,
      );
      database.connection.execute(
        'INSERT INTO agent_configurations VALUES (?, ?, ?);',
        [
          workspaceId,
          saved.revision,
          jsonEncode(encodeAgentConfiguration(saved)),
        ],
      );
    });
    return saved;
  }

  @override
  List<AgentRunRecord> listRuns(
    String workspaceId, {
    int limit = 50,
    String? sessionId,
  }) => database.connection
      .select(
        'SELECT record_json FROM agent_runs WHERE workspace_id = ? ${sessionId == null ? '' : 'AND session_id = ?'} ORDER BY started_at DESC, id DESC LIMIT ?;',
        [workspaceId, ?sessionId, limit],
      )
      .map((row) => decodeAgentRun(jsonDecode(row['record_json'] as String)))
      .toList();
  @override
  AgentRunRecord? loadRun(String workspaceId, String runId) {
    final rows = database.connection.select(
      'SELECT record_json FROM agent_runs WHERE workspace_id = ? AND id = ?;',
      [workspaceId, runId],
    );
    return rows.isEmpty
        ? null
        : decodeAgentRun(jsonDecode(rows.single['record_json'] as String));
  }

  @override
  void checkpoint(AgentRunRecord run, {AgentWorkspace? workspace}) {
    _transaction(() {
      database.connection.execute(
        '''
        INSERT INTO agent_runs (id, workspace_id, started_at, status, record_json, session_id) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET status = excluded.status, record_json = excluded.record_json;
      ''',
        [
          run.id,
          run.workspaceId,
          run.startedAt.toIso8601String(),
          run.status.name,
          jsonEncode(encodeAgentRun(run)),
          run.sessionId,
        ],
      );
      if (workspace != null) _saveWorkspace(workspace, activate: false);
    });
  }

  @override
  void recoverInterruptedRuns() {
    final runs = database.connection
        .select("SELECT record_json FROM agent_runs WHERE status = 'running';")
        .map((row) => decodeAgentRun(jsonDecode(row['record_json'] as String)))
        .toList();
    for (final run in runs) {
      final workspace = run.parentId == null
          ? loadWorkspace(run.workspaceId, sessionId: run.sessionId)
          : null;
      checkpoint(
        run.copyWith(
          steps: [
            for (final step in run.steps)
              step.isRunning
                  ? step.copyWith(isRunning: false, isError: true)
                  : step,
          ],
          status: AgentRunStatus.interrupted,
          error: '应用关闭时任务尚未完成，未自动重试。',
        ),
        workspace: workspace?.copyWith(
          history: [
            ...closePendingAgentTools(workspace.history),
            const LlmTextMessage(
              role: LlmRole.user,
              text: '上次运行因应用关闭而中断。已保存的文档版本仍保留；请读取核实，不要假定所有工具成功。',
            ),
          ],
        ),
      );
    }
  }

  @override
  List<AgentDocument> listDocuments(String workspaceId) => database.connection
      .select(
        '''
    SELECT * FROM agent_document_revisions AS d
    WHERE workspace_id = ? AND revision = (SELECT MAX(revision) FROM agent_document_revisions
      WHERE workspace_id = d.workspace_id AND name = d.name) ORDER BY name;
  ''',
        [workspaceId],
      )
      .map(_document)
      .toList();
  @override
  AgentDocument? readDocument(
    String workspaceId,
    String name, {
    int? revision,
  }) {
    _validateName(name);
    final rows = database.connection.select(
      '''
      SELECT * FROM agent_document_revisions
      WHERE workspace_id = ? AND name = ? ${revision == null ? '' : 'AND revision = ?'}
      ORDER BY revision DESC LIMIT 1;
    ''',
      [workspaceId, name, ?revision],
    );
    return rows.isEmpty ? null : _document(rows.single);
  }

  @override
  AgentDocument writeDocument(
    String workspaceId,
    String name,
    String content, {
    required int expectedRevision,
    AgentDocumentKind? kind,
  }) {
    _validateName(name);
    if (utf8.encode(content).length > 256 * 1024) {
      throw const AgentWorkspaceException('文档不能超过 256 KiB。');
    }
    if (expectedRevision < 0) throw const AgentWorkspaceException('版本号不能为负数。');
    late AgentDocument document;
    _transaction(() {
      final current = readDocument(workspaceId, name);
      if ((current?.revision ?? 0) != expectedRevision) {
        throw const AgentWorkspaceException('文档版本冲突，请重新读取后再保存。');
      }
      if (current == null && listDocuments(workspaceId).length >= 100) {
        throw const AgentWorkspaceException('每个工作区最多保存 100 份文档。');
      }
      document = AgentDocument(
        id: current?.id ?? generateEntityId(),
        kind: kind ?? current?.kind ?? AgentDocumentKind.document,
        name: name,
        content: content,
        revision: expectedRevision + 1,
      );
      database.connection.execute(
        '''
        INSERT INTO agent_document_revisions (workspace_id, name, revision, content, document_id, kind) VALUES (?, ?, ?, ?, ?, ?);
      ''',
        [
          workspaceId,
          name,
          document.revision,
          content,
          document.id,
          document.kind.name,
        ],
      );
    });
    return document;
  }

  void _validateName(String name) {
    if (name.trim().isEmpty ||
        name != name.trim() ||
        name.length > 120 ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(name) ||
        name == '.' ||
        name == '..') {
      throw const AgentWorkspaceException('文档名需为 1–120 个字符，不能包含路径分隔符或控制字符。');
    }
  }

  AgentDocument _document(Map<String, Object?> row) => AgentDocument(
    id: row['document_id'] as String,
    kind: AgentDocumentKind.values.byName(row['kind'] as String),
    name: row['name'] as String,
    content: row['content'] as String,
    revision: row['revision'] as int,
  );
  void _transaction(void Function() action) {
    database.connection.execute('BEGIN IMMEDIATE;');
    try {
      action();
      database.connection.execute('COMMIT;');
    } catch (_) {
      database.connection.execute('ROLLBACK;');
      rethrow;
    }
  }
}
