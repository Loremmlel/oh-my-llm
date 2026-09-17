import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/agent/data/sqlite_agent_store.dart';
import 'package:oh_my_llm/features/agent/domain/agent_models.dart';

void main() {
  test('剧本采用元信息名称，改名保留身份，冲突和非法保存均不破坏旧资料', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final store = SqliteAgentStore(db);
    store.saveWorkspace(AgentWorkspace(id: 'w', title: '小说'));
    const original =
        '\uFEFF---\r\nname: 秋季\r\ndescription: >-\r\n  开学之后\r\n  持续两月\r\n---\r\n正文';
    final first = store.writeDocument(
      'w',
      '',
      original,
      kind: AgentDocumentKind.script,
    );
    expect(first.name, '秋季');
    expect(first.description, '开学之后 持续两月');
    expect(first.content, original);
    final renamed = store.writeDocument(
      'w',
      first.name,
      original.replaceFirst('秋季', '新秋季'),
      documentId: first.id,
    );
    expect(renamed.id, first.id);
    expect(store.readDocument('w', '秋季'), isNull);
    expect(store.readDocument('w', '新秋季'), renamed);
    store.writeDocument('w', '另一份', '普通资料');
    for (final content in [
      original.replaceFirst('秋季', '另一份'),
      '无元信息',
      'x' * (256 * 1024 + 1),
    ]) {
      expect(
        () => store.writeDocument(
          'w',
          renamed.name,
          content,
          documentId: renamed.id,
        ),
        throwsA(isA<AgentWorkspaceException>()),
      );
      expect(store.readDocument('w', '新秋季'), renamed);
    }
    final run = AgentRunRecord(
      id: 'run',
      workspaceId: 'w',
      prompt: '写作',
      startedAt: DateTime(2026),
    );
    store.checkpoint(run);
    expect(
      () => store.writeDocument(
        'w',
        renamed.name,
        '恶意覆盖',
        kind: AgentDocumentKind.document,
        sourceRunId: run.id,
      ),
      throwsA(isA<AgentWorkspaceException>()),
    );
    expect(store.readDocument('w', '新秋季'), renamed);
  });
}
