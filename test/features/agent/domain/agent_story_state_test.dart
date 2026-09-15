import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';
import 'package:oh_my_llm/features/agent/domain/agent_story_state.dart';

void main() {
  final old = AgentStoryState(
    revision: 4,
    rows: [
      AgentStateRow(
        id: 'b',
        table: AgentStateTable.characters,
        cells: {'name': '乙', 'knowledge': '不知道秘密', 'place': '图书馆'},
      ),
      AgentStateRow(
        id: 'a',
        table: AgentStateTable.characters,
        cells: {'name': '甲', 'place': '操场'},
      ),
    ],
  );
  test('按稳定行标识局部修改，清空和删除均显式表达且保留旧快照', () {
    final next = old.apply([
      AgentStateOperation(
        kind: AgentStateOperationKind.update,
        table: AgentStateTable.characters,
        rowId: 'b',
        cells: {'place': ''},
      ),
      AgentStateOperation(
        kind: AgentStateOperationKind.delete,
        table: AgentStateTable.characters,
        rowId: 'a',
      ),
      AgentStateOperation(
        kind: AgentStateOperationKind.insert,
        table: AgentStateTable.events,
        cells: {'event': '甲决定保密'},
      ),
    ], () => 'new-event');
    expect(next.revision, 5);
    expect(next.rows.first.cells, {
      'name': '乙',
      'knowledge': '不知道秘密',
      'place': '',
    });
    expect(next.rows.last.id, 'new-event');
    expect(old.rows.first.cells['place'], '图书馆');
    expect(old.rows, hasLength(2));
  });
  for (final invalid in [
    AgentStateOperation(
      kind: AgentStateOperationKind.update,
      table: AgentStateTable.characters,
      rowId: 'missing',
      cells: {'name': '未知人物'},
    ),
    AgentStateOperation(
      kind: AgentStateOperationKind.update,
      table: AgentStateTable.characters,
      rowId: 'b',
      cells: {'unknown': '不存在的列'},
    ),
    AgentStateOperation(
      kind: AgentStateOperationKind.delete,
      table: AgentStateTable.events,
      rowId: 'b',
    ),
    AgentStateOperation(
      kind: AgentStateOperationKind.insert,
      table: AgentStateTable.characters,
      rowId: 'model-id',
      cells: {'name': '越权标识'},
    ),
  ]) {
    test(
      '非法操作 ${invalid.kind.name}/${invalid.table.name}/${invalid.rowId}/${invalid.cells.keys.join()} 拒绝整批修改',
      () {
        expect(
          () => old.apply([
            AgentStateOperation(
              kind: AgentStateOperationKind.update,
              table: AgentStateTable.characters,
              rowId: 'b',
              cells: {'place': '新地点'},
            ),
            invalid,
          ], () => 'unused'),
          throwsA(isA<AgentWorkspaceException>()),
        );
        expect(old.rows.first.cells['place'], '图书馆');
      },
    );
  }
  test('模型提供重复列或额外字段时拒绝参数', () {
    // 验证不可信工具参数，刻意构造错误 wire 数据。
    for (final value in [
      {
        'operation': 'update',
        'table': 'characters',
        'row_id': 'b',
        'cells': [
          {'column': 'name', 'value': '乙'},
          {'column': 'name', 'value': '甲'},
        ],
      },
      {
        'operation': 'delete',
        'table': 'characters',
        'row_id': 'b',
        'cells': [],
        'sql': 'ignored',
      },
    ]) {
      expect(
        () => AgentStateOperation.fromJson(value),
        throwsA(isA<AgentWorkspaceException>()),
      );
    }
  });
}
