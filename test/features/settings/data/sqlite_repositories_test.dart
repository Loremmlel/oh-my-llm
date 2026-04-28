import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_template.dart';

// ── 辅助构造函数 ─────────────────────────────────────────────────────────────

PromptTemplate _template(String id, {DateTime? updatedAt}) => PromptTemplate(
  id: id,
  name: '模板 $id',
  systemPrompt: '系统 $id',
  messages: const [
    PromptMessage(id: 'msg-1', role: PromptMessageRole.user, content: '用户消息'),
  ],
  updatedAt: updatedAt ?? DateTime(2026, 1, 1),
);

FixedPromptSequence _sequence(String id, {DateTime? updatedAt}) =>
    FixedPromptSequence(
      id: id,
      name: '序列 $id',
      steps: const [FixedPromptSequenceStep(id: 'step-1', content: '步骤内容')],
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );

// ── SqlitePromptTemplateRepository ────────────────────────────────────────────

void main() {
  group('SqlitePromptTemplateRepository', () {
    late AppDatabase database;
    late SqlitePromptTemplateRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqlitePromptTemplateRepository(database);
    });

    tearDown(() => database.close());

    test('loadAll 空表返回空列表', () {
      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll 后 loadAll 可还原数据', () async {
      await repo.saveAll([_template('tpl-1'), _template('tpl-2')]);

      final result = repo.loadAll();
      expect(result, hasLength(2));
      // 两条时间相同时，顺序由 SQLite 插入顺序决定（DESC 同时间可能有不确定性，
      // 因此仅验证 id 集合而非固定顺序）。
      expect(result.map((t) => t.id).toSet(), {'tpl-1', 'tpl-2'});
    });

    test('loadAll 按 updated_at 降序返回', () async {
      await repo.saveAll([
        _template('old', updatedAt: DateTime(2026, 1, 1)),
        _template('new', updatedAt: DateTime(2026, 6, 1)),
      ]);

      final result = repo.loadAll();
      expect(result.first.id, 'new');
      expect(result.last.id, 'old');
    });

    test('saveAll 空列表后 loadAll 返回空列表（全部删除）', () async {
      await repo.saveAll([_template('tpl-1')]);
      await repo.saveAll([]);

      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll 覆盖写入：旧数据被清除，新数据生效', () async {
      await repo.saveAll([_template('tpl-old')]);
      await repo.saveAll([_template('tpl-new')]);

      final result = repo.loadAll();
      expect(result, hasLength(1));
      expect(result.single.id, 'tpl-new');
    });

    test('往返序列化：systemPrompt 和 messages 字段正确还原', () async {
      final original = PromptTemplate(
        id: 'full',
        name: '全字段',
        systemPrompt: '系统指令',
        messages: const [
          PromptMessage(id: 'msg-1', role: PromptMessageRole.user, content: '用户提问'),
          PromptMessage(id: 'msg-2', role: PromptMessageRole.assistant, content: '助手回答'),
        ],
        updatedAt: DateTime(2026, 3, 15),
      );
      await repo.saveAll([original]);

      final loaded = repo.loadAll().single;
      expect(loaded.id, original.id);
      expect(loaded.systemPrompt, original.systemPrompt);
      expect(loaded.messages, hasLength(2));
      expect(loaded.messages[0].content, '用户提问');
      expect(loaded.messages[1].role, PromptMessageRole.assistant);
    });
  });

  // ── SqliteFixedPromptSequenceRepository ──────────────────────────────────────

  group('SqliteFixedPromptSequenceRepository', () {
    late AppDatabase database;
    late SqliteFixedPromptSequenceRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqliteFixedPromptSequenceRepository(database);
    });

    tearDown(() => database.close());

    test('loadAll 空表返回空列表', () {
      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll 后 loadAll 可还原数据', () async {
      await repo.saveAll([_sequence('seq-1'), _sequence('seq-2')]);

      final result = repo.loadAll();
      expect(result, hasLength(2));
      expect(result.map((s) => s.id).toSet(), {'seq-1', 'seq-2'});
    });

    test('loadAll 按 updated_at 降序返回', () async {
      await repo.saveAll([
        _sequence('old', updatedAt: DateTime(2026, 1, 1)),
        _sequence('new', updatedAt: DateTime(2026, 6, 1)),
      ]);

      final result = repo.loadAll();
      expect(result.first.id, 'new');
      expect(result.last.id, 'old');
    });

    test('saveAll 空列表后 loadAll 返回空列表（全部删除）', () async {
      await repo.saveAll([_sequence('seq-1')]);
      await repo.saveAll([]);

      expect(repo.loadAll(), isEmpty);
    });

    test('saveAll 覆盖写入：旧数据被清除，新数据生效', () async {
      await repo.saveAll([_sequence('seq-old')]);
      await repo.saveAll([_sequence('seq-new')]);

      final result = repo.loadAll();
      expect(result, hasLength(1));
      expect(result.single.id, 'seq-new');
    });

    test('往返序列化：steps 字段正确还原', () async {
      final original = FixedPromptSequence(
        id: 'full-seq',
        name: '全字段序列',
        steps: const [
          FixedPromptSequenceStep(id: 's1', content: '第一步内容'),
          FixedPromptSequenceStep(id: 's2', content: '第二步内容'),
        ],
        updatedAt: DateTime(2026, 5, 20),
      );
      await repo.saveAll([original]);

      final loaded = repo.loadAll().single;
      expect(loaded.id, original.id);
      expect(loaded.steps, hasLength(2));
      expect(loaded.steps[0].id, 's1');
      expect(loaded.steps[1].content, '第二步内容');
    });
  });
}
