import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_content.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../application/ports/agent_store.dart';
import '../domain/agent_models.dart';
import '../domain/agent_story_state.dart';
import 'agent_record_codec.dart';

class SqliteAgentStore implements AgentStore {
  SqliteAgentStore(this.database);
  final AppDatabase database;

  @override
  AgentStoryState readStoryState(String workspaceId) {
    final rows = database.connection.select(
      'SELECT record_json FROM agent_story_states WHERE workspace_id = ?;',
      [workspaceId],
    );
    return rows.isEmpty
        ? AgentStoryState()
        : AgentStoryState.fromJson(
            jsonDecode(rows.single['record_json'] as String)
                as Map<String, dynamic>,
          );
  }

  @override
  AgentStoryRound? readStoryRound(String workspaceId, String roundId) {
    final rows = database.connection.select(
      'SELECT record_json FROM agent_story_rounds WHERE workspace_id = ? AND id = ?;',
      [workspaceId, roundId],
    );
    return rows.isEmpty
        ? null
        : decodeAgentStoryRound(
            jsonDecode(rows.single['record_json'] as String)
                as Map<String, dynamic>,
          );
  }

  @override
  AgentStoryRound? latestStoryRound(String workspaceId) {
    final rows = database.connection.select(
      "SELECT record_json FROM agent_story_rounds WHERE workspace_id = ? AND status IN ('pending', 'committed') ORDER BY sequence DESC LIMIT 1;",
      [workspaceId],
    );
    return rows.isEmpty
        ? null
        : decodeAgentStoryRound(
            jsonDecode(rows.single['record_json'] as String)
                as Map<String, dynamic>,
          );
  }

  @override
  List<AgentStoryRound> listStoryRounds(String workspaceId, String sessionId) =>
      [
        for (final row in database.connection.select(
          'SELECT record_json FROM agent_story_rounds WHERE workspace_id = ? AND session_id = ? ORDER BY sequence DESC LIMIT 50;',
          [workspaceId, sessionId],
        ))
          decodeAgentStoryRound(
            jsonDecode(row['record_json'] as String) as Map<String, dynamic>,
          ),
      ];

  @override
  AgentStoryRound prepareStoryRound(AgentStoryRound round) {
    late AgentStoryRound result;
    _transaction(() {
      final workspaceId = round.beforeWorkspace.id;
      final owner = loadRun(workspaceId, round.id);
      if (owner == null ||
          owner.parentId != null ||
          owner.role != AgentRole.coordinator ||
          owner.status != AgentRunStatus.running ||
          owner.sessionId != round.beforeWorkspace.sessionId) {
        throw const AgentWorkspaceException('正文轮次不属于当前主任务。');
      }
      final current = readStoryRound(workspaceId, round.id);
      if (current != null &&
          (current.status != AgentStoryRoundStatus.pending ||
              current.document != round.document ||
              current.beforeState != round.beforeState)) {
        throw const AgentWorkspaceException('本轮已保存或绑定了另一版正文，请先撤回或放弃本轮。');
      }
      final latest = latestStoryRound(workspaceId);
      if (latest?.status == AgentStoryRoundStatus.pending &&
          latest?.id != round.id) {
        throw const AgentWorkspaceException('作品有未完成的状态更新，请先重试或放弃该轮。');
      }
      _checkStoryInputs(round);
      result = current?.copyWith(stateAgentId: round.stateAgentId) ?? round;
      _saveStoryRound(result);
    });
    return result;
  }

  @override
  AgentStoryRound commitStoryRound(
    String workspaceId,
    String roundId,
    String stateAgentId,
    List<AgentStateOperation> operations,
  ) {
    late AgentStoryRound result;
    _transaction(() {
      final round = readStoryRound(workspaceId, roundId);
      if (round == null || round.stateAgentId != stateAgentId) {
        throw const AgentWorkspaceException('状态更新任务不匹配。');
      }
      if (round.status == AgentStoryRoundStatus.committed) {
        if (operations.length != round.operations.length ||
            Iterable<int>.generate(operations.length)
                .any((i) => operations[i] != round.operations[i])) {
          throw const AgentWorkspaceException('本轮已经保存，不能提交另一批修改。');
        }
        result = round;
        return;
      }
      if (round.status != AgentStoryRoundStatus.pending ||
          latestStoryRound(workspaceId)?.id != roundId) {
        throw const AgentWorkspaceException('本轮已撤回或不再是最新轮次。');
      }
      final child = loadRun(workspaceId, stateAgentId);
      if (child == null ||
          child.parentId != roundId ||
          child.status != AgentRunStatus.running ||
          child.role != AgentRole.state) {
        throw const AgentWorkspaceException('只有本轮绑定的状态 Agent 可以更新剧情。');
      }
      _checkStoryInputs(round);
      final next = round.beforeState.apply(operations, generateEntityId);
      result = round.copyWith(
        status: AgentStoryRoundStatus.committed,
        afterState: next,
        operations: operations,
      );
      _saveStoryState(workspaceId, next);
      _saveStoryRound(result);
    });
    return result;
  }

  void _checkStoryInputs(AgentStoryRound round) {
    if (readStoryState(round.beforeWorkspace.id).revision !=
            round.beforeState.revision ||
        readDocument(round.beforeWorkspace.id, round.document.name) !=
            round.document ||
        round.document.kind != AgentDocumentKind.document) {
      throw const AgentWorkspaceException('正文或状态已变化，拒绝保存过期结果。请放弃本轮后重新开始。');
    }
  }

  void _saveStoryState(String workspaceId, AgentStoryState value) {
    database.connection.execute(
      'INSERT INTO agent_story_states (workspace_id, record_json) VALUES (?, ?) ON CONFLICT(workspace_id) DO UPDATE SET record_json = excluded.record_json;',
      [workspaceId, jsonEncode(value.toJson())],
    );
  }

  void _saveStoryRound(AgentStoryRound round) {
    database.connection.execute(
      'INSERT INTO agent_story_rounds (id, workspace_id, session_id, status, record_json) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET status = excluded.status, record_json = excluded.record_json;',
      [
        round.id,
        round.beforeWorkspace.id,
        round.beforeWorkspace.sessionId,
        round.status.name,
        jsonEncode(encodeAgentStoryRound(round)),
      ],
    );
  }

  @override
  void withdrawStoryRound(
    String workspaceId,
    String sessionId,
    String roundId,
  ) {
    _transaction(() {
      final round = latestStoryRound(workspaceId);
      if (round == null ||
          round.id != roundId ||
          round.beforeWorkspace.sessionId != sessionId) {
        throw const AgentWorkspaceException('只能在所属会话撤回作品最新一轮。');
      }
      if (database.connection.select(
        "SELECT 1 FROM agent_runs WHERE workspace_id = ? AND status = 'running' LIMIT 1;",
        [workspaceId],
      ).isNotEmpty) {
        throw const AgentWorkspaceException('请先停止作品的运行，再撤回。');
      }
      final state = readStoryState(workspaceId);
      if (state !=
          AgentStoryState(
            revision: state.revision,
            rows: (round.afterState ?? round.beforeState).rows,
          )) {
        throw const AgentWorkspaceException('状态已经变化，不能覆盖后续剧情。');
      }
      // 版本继续递增，防止撤回后旧异步结果误中相同版本。
      _saveStoryState(
        workspaceId,
        AgentStoryState(
          revision: state.revision + 1,
          rows: round.beforeState.rows,
        ),
      );
      _saveStoryRound(
        round.copyWith(
          status: round.status == AgentStoryRoundStatus.pending
              ? AgentStoryRoundStatus.discarded
              : AgentStoryRoundStatus.withdrawn,
        ),
      );
      final current = loadWorkspace(workspaceId, sessionId: sessionId)!;
      // 只恢复本轮仍拥有的写入；用户后来手动修改的文档不被撤回覆盖。
      for (final entry in database.connection.select(
        'SELECT * FROM agent_document_undo WHERE workspace_id = ? AND run_id = ?;',
        [workspaceId, roundId],
      )) {
        final owned = database.connection.select(
          'SELECT 1 FROM agent_documents WHERE workspace_id = ? AND name = ? AND source_run_id = ?;',
          [workspaceId, entry['name'], roundId],
        );
        if (owned.isEmpty) continue;
        database.connection.execute(
          'DELETE FROM agent_documents WHERE workspace_id = ? AND name = ?;',
          [workspaceId, entry['name']],
        );
        if (entry['before_json'] != null) {
          final previous = decodeAgentDocument(
            jsonDecode(entry['before_json'] as String),
          );
          _saveDocument(
            workspaceId,
            previous,
            entry['before_source_run_id'] as String?,
          );
        }
      }
      _saveWorkspace(
        current.copyWith(
          history: round.beforeWorkspace.history,
          draft: round.beforeWorkspace.draft,
        ),
      );
    });
  }

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
      'SELECT record_json FROM agent_configurations WHERE workspace_id = ? ORDER BY name;',
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
      if (current.length >= 200 &&
          !current.any((c) => c.name == configuration.name)) {
        throw const AgentWorkspaceException('每部作品最多保存 200 个配置方案。');
      }
      saved = configuration;
      database.connection.execute(
        'INSERT INTO agent_configurations (workspace_id, name, record_json) VALUES (?, ?, ?) ON CONFLICT(workspace_id, name) DO UPDATE SET record_json = excluded.record_json;',
        [workspaceId, saved.name, jsonEncode(encodeAgentConfiguration(saved))],
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
              text: '上次运行因应用关闭而中断。已保存的文档仍保留；请读取核实，不要假定所有工具成功。',
            ),
          ],
        ),
      );
    }
  }

  @override
  List<AgentDocument> listDocuments(String workspaceId) => database.connection
      .select(
        'SELECT * FROM agent_documents WHERE workspace_id = ? ORDER BY name;',
        [workspaceId],
      )
      .map(_document)
      .toList();

  @override
  AgentDocument? readDocument(String workspaceId, String name) {
    _validateName(name);
    final rows = database.connection.select(
      'SELECT * FROM agent_documents WHERE workspace_id = ? AND name = ?;',
      [workspaceId, name],
    );
    return rows.isEmpty ? null : _document(rows.single);
  }

  @override
  AgentDocument writeDocument(
    String workspaceId,
    String name,
    String content, {
    AgentDocumentKind? kind,
    String? sourceRunId,
  }) {
    _validateName(name);
    if (utf8.encode(content).length > 256 * 1024) {
      throw const AgentWorkspaceException('文档不能超过 256 KiB。');
    }
    late AgentDocument document;
    _transaction(() {
      final current = readDocument(workspaceId, name);
      if (current == null && listDocuments(workspaceId).length >= 100) {
        throw const AgentWorkspaceException('每个工作区最多保存 100 份文档。');
      }
      if (sourceRunId != null) {
        final owner = loadRun(workspaceId, sourceRunId);
        if (owner == null ||
            owner.parentId != null ||
            owner.status != AgentRunStatus.running) {
          throw const AgentWorkspaceException('文档写入不属于当前主任务。');
        }
        final rows = database.connection.select(
          'SELECT source_run_id FROM agent_documents WHERE workspace_id = ? AND name = ?;',
          [workspaceId, name],
        );
        // 同一轮无论改稿多少次，只留写入前的一份撤回快照。
        database.connection.execute(
          'INSERT OR IGNORE INTO agent_document_undo (workspace_id, run_id, name, before_json, before_source_run_id) VALUES (?, ?, ?, ?, ?);',
          [
            workspaceId,
            sourceRunId,
            name,
            current == null ? null : jsonEncode(encodeAgentDocument(current)),
            rows.firstOrNull?['source_run_id'],
          ],
        );
      }
      document = AgentDocument(
        id: current?.id ?? generateEntityId(),
        kind: kind ?? current?.kind ?? AgentDocumentKind.document,
        name: name,
        content: content,
      );
      _saveDocument(workspaceId, document, sourceRunId);
    });
    return document;
  }

  void _saveDocument(
    String workspaceId,
    AgentDocument document,
    String? sourceRunId,
  ) {
    database.connection.execute(
      'INSERT INTO agent_documents (workspace_id, name, content, document_id, kind, source_run_id) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(workspace_id, name) DO UPDATE SET content = excluded.content, kind = excluded.kind, source_run_id = excluded.source_run_id;',
      [
        workspaceId,
        document.name,
        document.content,
        document.id,
        document.kind.name,
        sourceRunId,
      ],
    );
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
