import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// 不可变的历史前缀；会话、执行输入与撤回快照只保存链尾标识。
///
/// 节点由前驱与原始 JSON 共同标识，分支及原生协议字段均完整保留。
class SqliteJsonHistory {
  SqliteJsonHistory(this.database);
  final Database database;

  String write(String workspaceId, Iterable<Object?> items) {
    var head = '';
    final insertItem = database.prepare('''
      INSERT OR IGNORE INTO agent_history_items
        (workspace_id, id, item_json) VALUES (?, ?, ?);
    ''');
    final insert = database.prepare('''
      INSERT OR IGNORE INTO agent_history_entries
        (workspace_id, id, parent_id, item_id) VALUES (?, ?, ?, ?);
    ''');
    try {
      for (final item in items) {
        final json = jsonEncode(item);
        final itemId = sha256.convert(utf8.encode(json)).toString();
        final id = sha256.convert(utf8.encode('$head:$itemId')).toString();
        insertItem.execute([workspaceId, itemId, json]);
        insert.execute([workspaceId, id, head, itemId]);
        head = id;
      }
    } finally {
      insert.close();
      insertItem.close();
    }
    return head;
  }

  List<dynamic> read(String workspaceId, String head) {
    if (head.isEmpty) return [];
    final rows = database.select(
      '''
      WITH RECURSIVE history(id, parent_id, item_id, depth) AS (
        SELECT id, parent_id, item_id, 0 FROM agent_history_entries
        WHERE workspace_id = ? AND id = ?
        UNION ALL
        SELECT e.id, e.parent_id, e.item_id, h.depth + 1
        FROM agent_history_entries e JOIN history h ON e.id = h.parent_id
        WHERE e.workspace_id = ?
      ) SELECT h.parent_id, i.item_json FROM history h
        LEFT JOIN agent_history_items i ON i.workspace_id = ? AND i.id = h.item_id
        ORDER BY h.depth DESC;
    ''',
      [workspaceId, head, workspaceId, workspaceId],
    );
    if (rows.isEmpty ||
        rows.first['parent_id'] != '' ||
        rows.any((r) => r['item_json'] == null)) {
      throw const FormatException('Agent 历史链不完整');
    }
    return [for (final row in rows) jsonDecode(row['item_json'] as String)];
  }

  /// 此变换也用于旧库迁移；正常读写只接受迁移后的链尾格式。
  Map<String, dynamic> compact(
    String workspaceId,
    Map<String, dynamic> record,
  ) => {
    for (final entry in record.entries)
      entry.key: switch (entry.key) {
        'history' || 'childHistory' || 'inputHistory' =>
          entry.value == null ? null : write(workspaceId, entry.value as List),
        'beforeWorkspace' => compact(
          workspaceId,
          entry.value as Map<String, dynamic>,
        ),
        _ => entry.value,
      },
  };

  Map<String, dynamic> expand(
    String workspaceId,
    Map<String, dynamic> record, {
    bool includeHistory = true,
  }) => {
    for (final entry in record.entries)
      entry.key: switch (entry.key) {
        'history' || 'childHistory' || 'inputHistory' =>
          entry.value == null
              ? null
              : includeHistory
              ? read(workspaceId, entry.value as String)
              : entry.key == 'inputHistory'
              ? null
              : <dynamic>[],
        'beforeWorkspace' => expand(
          workspaceId,
          entry.value as Map<String, dynamic>,
          includeHistory: includeHistory,
        ),
        _ => entry.value,
      },
  };
}
