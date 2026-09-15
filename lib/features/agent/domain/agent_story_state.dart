import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'agent_models.dart';

enum AgentStateTable { scene, characters, events }

extension AgentStateTableDescription on AgentStateTable {
  String get label => switch (this) {
    AgentStateTable.scene => '场景状态',
    AgentStateTable.characters => '人物动态',
    AgentStateTable.events => '重要经历',
  };

  Map<String, String> get columns => switch (this) {
    AgentStateTable.scene => const {
      'time': '剧情时间／阶段',
      'place': '地点',
      'characters': '在场人物',
      'world': '其他世界状态',
    },
    AgentStateTable.characters => const {
      'name': '人物',
      'place': '位置',
      'goal': '当前目标',
      'condition': '身体与情绪',
      'relations': '关系',
      'knowledge': '所知与判断',
    },
    AgentStateTable.events => const {
      'characters': '参与人物',
      'event': '事件简述',
      'time_place': '时间／地点',
      'effect': '持续影响',
    },
  };
}

class AgentStateRow extends Equatable {
  AgentStateRow({
    required this.id,
    required this.table,
    required Map<String, String> cells,
  }) : cells = Map.unmodifiable(cells);
  final String id;
  final AgentStateTable table;
  final Map<String, String> cells;
  Map<String, Object?> toJson() => {
    'id': id,
    'table': table.name,
    'cells': cells,
  };
  factory AgentStateRow.fromJson(Map<String, dynamic> json) => AgentStateRow(
    id: json['id'] as String,
    table: AgentStateTable.values.byName(json['table'] as String),
    cells: Map<String, String>.from(json['cells'] as Map),
  );
  @override
  List<Object?> get props => [id, table, cells];
}

enum AgentStateOperationKind { insert, update, delete }

class AgentStateOperation extends Equatable {
  AgentStateOperation({
    required this.kind,
    required this.table,
    this.rowId = '',
    Map<String, String> cells = const {},
  }) : cells = Map.unmodifiable(cells);
  final AgentStateOperationKind kind;
  final AgentStateTable table;
  final String rowId;
  final Map<String, String> cells;

  Map<String, Object?> toJson() => {
    'operation': kind.name,
    'table': table.name,
    'row_id': rowId,
    'cells': [
      for (final entry in cells.entries)
        {'column': entry.key, 'value': entry.value},
    ],
  };

  factory AgentStateOperation.fromJson(Object? value) {
    const error = AgentWorkspaceException('状态操作参数不合法，请检查操作、表、行标识和单元格。');
    if (value is! Map ||
        value.length != 4 ||
        !value.keys.toSet().containsAll([
          'operation',
          'table',
          'row_id',
          'cells',
        ]) ||
        value['row_id'] is! String ||
        value['cells'] is! List) {
      throw error;
    }
    final kind = AgentStateOperationKind.values
        .where((v) => v.name == value['operation'])
        .firstOrNull;
    final table = AgentStateTable.values
        .where((v) => v.name == value['table'])
        .firstOrNull;
    if (kind == null || table == null) throw error;
    final cells = <String, String>{};
    for (final cell in value['cells'] as List) {
      if (cell is! Map ||
          cell.length != 2 ||
          cell['column'] is! String ||
          cell['value'] is! String ||
          cells.containsKey(cell['column'])) {
        throw error;
      }
      cells[cell['column'] as String] = cell['value'] as String;
    }
    return AgentStateOperation(
      kind: kind,
      table: table,
      rowId: value['row_id'] as String,
      cells: cells,
    );
  }

  @override
  List<Object?> get props => [kind, table, rowId, cells];
}

class AgentStoryState extends Equatable {
  AgentStoryState({this.revision = 0, List<AgentStateRow> rows = const []})
    : rows = List.unmodifiable(rows);
  final int revision;
  final List<AgentStateRow> rows;
  Map<String, Object?> toJson() => {
    'version': 1,
    'revision': revision,
    'rows': rows.map((r) => r.toJson()).toList(),
  };
  factory AgentStoryState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('不支持的剧情状态版本');
    return AgentStoryState(
      revision: json['revision'] as int,
      rows: [
        for (final row in json['rows'] as List)
          AgentStateRow.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
    );
  }

  /// 先在不可变快照上验证整批操作，任何错误均不改变原状态。
  AgentStoryState apply(
    List<AgentStateOperation> operations,
    String Function() newId,
  ) {
    final next = [...rows];
    for (final op in operations) {
      if (!op.cells.keys.every(op.table.columns.containsKey)) {
        throw const AgentWorkspaceException('状态列不存在，整批修改未保存。');
      }
      final index = next.indexWhere(
        (r) => r.id == op.rowId && r.table == op.table,
      );
      switch (op.kind) {
        case AgentStateOperationKind.insert:
          if (op.rowId.isNotEmpty || op.cells.isEmpty) {
            throw const AgentWorkspaceException('新增行需提供单元格，行标识由应用生成。');
          }
          next.add(
            AgentStateRow(
              id: newId(),
              table: op.table,
              cells: {
                for (final key in op.table.columns.keys)
                  key: op.cells[key] ?? '',
              },
            ),
          );
        case AgentStateOperationKind.update:
          if (index < 0 || op.cells.isEmpty) {
            throw const AgentWorkspaceException('更新目标行不存在或没有提供单元格。');
          }
          next[index] = AgentStateRow(
            id: op.rowId,
            table: op.table,
            cells: {...next[index].cells, ...op.cells},
          );
        case AgentStateOperationKind.delete:
          if (index < 0 || op.cells.isNotEmpty) {
            throw const AgentWorkspaceException('删除目标行不存在或包含了单元格参数。');
          }
          next.removeAt(index);
      }
    }
    if (next.where((r) => r.table == AgentStateTable.scene).length > 1) {
      throw const AgentWorkspaceException('场景状态只允许保留一行。');
    }
    final result = AgentStoryState(revision: revision + 1, rows: next);
    if (utf8.encode(jsonEncode(result.toJson())).length > 512 * 1024) {
      throw const AgentWorkspaceException('剧情状态超过 512 KiB，整批修改未保存。');
    }
    return result;
  }

  Map<String, Object?> get toolData => {
    'revision': revision,
    'tables': [
      for (final table in AgentStateTable.values)
        {
          'id': table.name,
          'name': table.label,
          'columns': table.columns,
          'rows': rows
              .where((r) => r.table == table)
              .map((r) => {'id': r.id, 'cells': r.cells})
              .toList(),
        },
    ],
  };
  @override
  List<Object?> get props => [revision, rows];
}

enum AgentStoryRoundStatus { pending, committed, withdrawn, discarded }

/// 正文和状态共用一个轮次；完整旧快照让撤回不依赖模型的逆向修改。
class AgentStoryRound extends Equatable {
  AgentStoryRound({
    required this.id,
    required this.beforeWorkspace,
    required this.document,
    required this.beforeState,
    required this.stateAgentId,
    this.status = AgentStoryRoundStatus.pending,
    this.afterState,
    List<AgentStateOperation> operations = const [],
  }) : operations = List.unmodifiable(operations);
  final String id, stateAgentId;
  final AgentWorkspace beforeWorkspace;
  final AgentDocument document;
  final AgentStoryState beforeState;
  final AgentStoryState? afterState;
  final AgentStoryRoundStatus status;
  final List<AgentStateOperation> operations;
  AgentStoryRound copyWith({
    String? stateAgentId,
    AgentStoryRoundStatus? status,
    AgentStoryState? afterState,
    List<AgentStateOperation>? operations,
  }) => AgentStoryRound(
    id: id,
    beforeWorkspace: beforeWorkspace,
    document: document,
    beforeState: beforeState,
    stateAgentId: stateAgentId ?? this.stateAgentId,
    status: status ?? this.status,
    afterState: afterState ?? this.afterState,
    operations: operations ?? this.operations,
  );
  @override
  List<Object?> get props => [
    id,
    beforeWorkspace,
    document,
    beforeState,
    stateAgentId,
    status,
    afterState,
    operations,
  ];
}
