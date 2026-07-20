import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_memory_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_preset_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/data/sqlite_template_prompt_repository.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

PresetPrompt template(String id, {DateTime? updatedAt}) => PresetPrompt(
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
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() => database.close());

  test('PresetPrompt round-trip', () async {
    final original = PresetPrompt(
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
        PromptMessage(
          id: 'msg-3',
          role: PromptMessageRole.user,
          title: '最新输入前user1',
          content: '输入前提醒',
          placement: PromptMessagePlacement.beforeLatestInput,
        ),
      ],
      updatedAt: DateTime(2026, 3, 15),
    );

    await presetPromptRepository.saveAll(database, [original]);
    expect(presetPromptRepository.loadAll(database).single, original);
  });

  test('FixedPromptSequence round-trip', () async {
    final original = FixedPromptSequence(
      id: 'full-seq',
      name: '全字段序列',
      steps: const [
        FixedPromptSequenceStep(id: 's1', title: '标题1', content: '第一步内容'),
        FixedPromptSequenceStep(id: 's2', title: '标题2', content: '第二步内容'),
      ],
      updatedAt: DateTime(2026, 5, 20),
    );

    await fixedPromptSequenceRepository.saveAll(database, [original]);
    expect(fixedPromptSequenceRepository.loadAll(database).single, original);
  });

  test('TemplatePrompt round-trip', () async {
    final original = templatePrompt('full', updatedAt: DateTime(2026, 3, 15));
    await templatePromptRepository.saveAll(database, [original]);
    expect(templatePromptRepository.loadAll(database).single, original);
  });

  test('MemoryPrompt round-trip', () async {
    final original = memoryPrompt('memory-full', updatedAt: DateTime(2026, 3, 15));
    await memoryPromptRepository.saveAll(database, [original]);
    expect(memoryPromptRepository.loadAll(database).single, original);
  });
}
