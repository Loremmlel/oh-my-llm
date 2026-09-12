import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';

import '../application/ports/agent_store.dart';
import '../domain/agent_models.dart';
import 'agent_record_codec.dart';

class SqliteAgentStore implements AgentStore {
  SqliteAgentStore(this.database);
  final AppDatabase database;
  @override
  List<AgentWorkspace> listWorkspaces() => database.connection
      .select(
        'SELECT record_json FROM agent_workspaces ORDER BY updated_at DESC, id DESC;',
      )
      .map(
        (row) => decodeAgentWorkspace(jsonDecode(row['record_json'] as String)),
      )
      .toList();
  @override
  AgentWorkspace? loadWorkspace(String id) {
    final rows = database.connection.select(
      'SELECT record_json FROM agent_workspaces WHERE id = ?;',
      [id],
    );
    return rows.isEmpty
        ? null
        : decodeAgentWorkspace(
            jsonDecode(rows.single['record_json'] as String),
          );
  }

  @override
  void saveWorkspace(AgentWorkspace workspace) {
    database.connection.execute(
      '''
      INSERT INTO agent_workspaces (id, updated_at, record_json) VALUES (?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, record_json = excluded.record_json;
    ''',
      [
        workspace.id,
        DateTime.now().toIso8601String(),
        jsonEncode(encodeAgentWorkspace(workspace)),
      ],
    );
  }

  @override
  List<AgentRunRecord> listRuns(String workspaceId, {int limit = 50}) =>
      database.connection
          .select(
            'SELECT record_json FROM agent_runs WHERE workspace_id = ? ORDER BY started_at DESC, id DESC LIMIT ?;',
            [workspaceId, limit],
          )
          .map(
            (row) => decodeAgentRun(jsonDecode(row['record_json'] as String)),
          )
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
        INSERT INTO agent_runs (id, workspace_id, started_at, status, record_json) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET status = excluded.status, record_json = excluded.record_json;
      ''',
        [
          run.id,
          run.workspaceId,
          run.startedAt.toIso8601String(),
          run.status.name,
          jsonEncode(encodeAgentRun(run)),
        ],
      );
      if (workspace != null) saveWorkspace(workspace);
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
          ? loadWorkspace(run.workspaceId)
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
    SELECT name, content, revision FROM agent_document_revisions AS d
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
      SELECT name, content, revision FROM agent_document_revisions
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
        name: name,
        content: content,
        revision: expectedRevision + 1,
      );
      database.connection.execute(
        '''
        INSERT INTO agent_document_revisions (workspace_id, name, revision, content) VALUES (?, ?, ?, ?);
      ''',
        [workspaceId, name, document.revision, content],
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
