import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_prompt_template_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_template.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

PromptTemplate template(String id, {DateTime? updatedAt}) => PromptTemplate(
  id: id,
  name: '模板 $id',
  messages: [
    PromptMessage(
      id: '_legacy-system-message',
      role: PromptMessageRole.system,
      title: defaultSystemPromptTitle,
      content: '系统 $id',
    ),
    const PromptMessage(
      id: 'msg-1',
      role: PromptMessageRole.user,
      title: '前置user1',
      content: '用户消息',
    ),
  ],
  updatedAt: updatedAt ?? DateTime(2026, 1, 1),
);

FixedPromptSequence sequence(String id, {DateTime? updatedAt}) =>
    FixedPromptSequence(
      id: id,
      name: '序列 $id',
      steps: const [FixedPromptSequenceStep(id: 'step-1', content: '步骤内容')],
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );

TemplatePrompt templatePrompt(String id, {DateTime? updatedAt}) =>
    TemplatePrompt(
      id: id,
      title: '模板提示词 $id',
      content: '请处理{{正文}}，并补充{{语气}}。',
      variables: const [
        TemplatePromptVariable(name: templatePromptBodyVariableName),
        TemplatePromptVariable(name: '语气', defaultValue: '专业'),
      ],
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );

MemoryPrompt memoryPrompt(String id, {DateTime? updatedAt}) => MemoryPrompt(
  id: id,
  name: '记忆提示词 $id',
  content: '请总结当前对话的重要事实与待办。',
  updatedAt: updatedAt ?? DateTime(2026, 1, 1),
);

void main() {
  group('SqlitePromptTemplateRepository', () {
    late AppDatabase database;
    late SqlitePromptTemplateRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqlitePromptTemplateRepository(database);
    });

    tearDown(() => database.close());

    test('round-trip preserves prompt template fields', () async {
      final original = PromptTemplate(
        id: 'full',
        name: '全字段',
        messages: const [
          PromptMessage(
            id: 'msg-sys',
            role: PromptMessageRole.system,
            title: defaultSystemPromptTitle,
            content: '系统指令',
          ),
          PromptMessage(
            id: 'msg-1',
            role: PromptMessageRole.user,
            title: '前置user1',
            content: '用户提问',
            placement: PromptMessagePlacement.before,
          ),
          PromptMessage(
            id: 'msg-2',
            role: PromptMessageRole.assistant,
            title: '后置assistant1',
            content: '助手回答',
            placement: PromptMessagePlacement.after,
          ),
        ],
        updatedAt: DateTime(2026, 3, 15),
      );

      await repo.saveAll([original]);

      expect(repo.loadAll().single, original);
    });

    test('legacy prompt message defaults placement to before', () {
      final decoded = PromptMessage.fromJson({
        'id': 'msg-old',
        'role': 'user',
        'content': '旧模板消息',
      });

      expect(decoded.placement, PromptMessagePlacement.before);
    });

    test(
      'legacy prompt template generates fallback titles for system and messages',
      () {
        final decoded = PromptTemplate.fromJson({
          'id': 'legacy',
          'name': '旧模板',
          'systemPrompt': '系统指令',
          'messages': [
            {'id': 'm1', 'role': 'user', 'content': '前置消息'},
            {
              'id': 'm2',
              'role': 'assistant',
              'placement': 'after',
              'content': '后置消息',
            },
          ],
          'updatedAt': '2026-01-01T00:00:00.000',
        });

        expect(decoded.messages[0].role, PromptMessageRole.system);
        expect(decoded.messages[0].title, 'system');
        expect(decoded.messages[0].content, '系统指令');
        expect(decoded.messages[1].title, '前置user1');
        expect(decoded.messages[2].title, '后置assistant1');
      },
    );
  });

  group('SqliteFixedPromptSequenceRepository', () {
    late AppDatabase database;
    late SqliteFixedPromptSequenceRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqliteFixedPromptSequenceRepository(database);
    });

    tearDown(() => database.close());

    test('round-trip preserves sequence steps', () async {
      final original = FixedPromptSequence(
        id: 'full-seq',
        name: '全字段序列',
        steps: const [
          FixedPromptSequenceStep(id: 's1', title: '标题1', content: '第一步内容'),
          FixedPromptSequenceStep(id: 's2', title: '标题2', content: '第二步内容'),
        ],
        updatedAt: DateTime(2026, 5, 20),
      );

      await repo.saveAll([original]);

      expect(repo.loadAll().single, original);
    });

    test('legacy fixed sequence generates fallback step titles', () {
      final decoded = FixedPromptSequence.fromJson({
        'id': 'legacy-seq',
        'name': '旧序列',
        'steps': [
          {'id': 's1', 'content': '第一步内容'},
          {'id': 's2', 'content': '第二步内容'},
        ],
        'updatedAt': '2026-01-01T00:00:00.000',
      });

      expect(decoded.steps[0].title, '标题1');
      expect(decoded.steps[1].title, '标题2');
    });
  });

  group('SqliteTemplatePromptRepository', () {
    late AppDatabase database;
    late SqliteTemplatePromptRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqliteTemplatePromptRepository(database);
    });

    tearDown(() => database.close());

    test('round-trip preserves content and variables', () async {
      final original = templatePrompt('full', updatedAt: DateTime(2026, 3, 15));

      await repo.saveAll([original]);

      expect(repo.loadAll().single, original);
    });
  });

  group('SqliteMemoryPromptRepository', () {
    late AppDatabase database;
    late SqliteMemoryPromptRepository repo;

    setUp(() {
      database = AppDatabase.inMemory();
      repo = SqliteMemoryPromptRepository(database);
    });

    tearDown(() => database.close());

    test('round-trip preserves memory prompt fields', () async {
      final original = memoryPrompt(
        'memory-full',
        updatedAt: DateTime(2026, 3, 15),
      );

      await repo.saveAll([original]);

      expect(repo.loadAll().single, original);
    });
  });
}
