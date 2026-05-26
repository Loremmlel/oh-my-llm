import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/settings/application/settings_import_deduplicator.dart';
import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/memory_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_placement.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompt_message_role.dart';
import 'package:oh_my_llm/features/settings/domain/models/settings_export_data.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';

void main() {
  final testDate = DateTime(2025, 1, 1);

  // ── 工厂辅助函数 ──────...──────────...──────────...──────────

  MemoryPrompt _mem({
    String id = 'mem-1',
    String name = '测试记忆',
    String content = 'hello world',
  }) {
    return MemoryPrompt(id: id, name: name, content: content, updatedAt: testDate);
  }

  PromptMessage _msg({
    String id = 'msg-1',
    PromptMessageRole role = PromptMessageRole.user,
    String title = '前置user1',
    String content = '你好',
    PromptMessagePlacement placement = PromptMessagePlacement.before,
  }) {
    return PromptMessage(id: id, role: role, title: title, content: content, placement: placement);
  }

  PresetPrompt _preset({
    String id = 'pst-1',
    String name = '测试模板',
    List<PromptMessage>? messages,
  }) {
    return PresetPrompt(id: id, name: name, messages: messages ?? [_msg()], updatedAt: testDate);
  }

  TemplatePromptVariable _var({
    String name = '变量1',
    String defaultValue = '默认值',
  }) {
    return TemplatePromptVariable(name: name, defaultValue: defaultValue);
  }

  TemplatePrompt _tpl({
    String id = 'tpl-1',
    String title = '测试模板',
    String content = '请处理{{正文}}',
    List<TemplatePromptVariable>? variables,
  }) {
    return TemplatePrompt(
      id: id,
      title: title,
      content: content,
      variables: variables ?? [_var()],
      updatedAt: testDate,
    );
  }

  FixedPromptSequenceStep _step({
    String id = 'step-1',
    String title = '步骤1',
    String content = '第一步内容',
  }) {
    return FixedPromptSequenceStep(id: id, title: title, content: content);
  }

  FixedPromptSequence _seq({
    String id = 'seq-1',
    String name = '测试序列',
    List<FixedPromptSequenceStep>? steps,
  }) {
    return FixedPromptSequence(id: id, name: name, steps: steps ?? [_step()], updatedAt: testDate);
  }

  LlmProviderModelConfig _model({
    String id = 'model-1',
    String displayName = 'GPT-4',
    String modelName = 'gpt-4',
    bool supportsReasoning = false,
  }) {
    return LlmProviderModelConfig(
      id: id,
      displayName: displayName,
      modelName: modelName,
      supportsReasoning: supportsReasoning,
    );
  }

  LlmProviderConfig _provider({
    String id = 'pvd-1',
    String name = 'OpenAI',
    String apiUrl = 'https://api.openai.com/v1',
    String apiKey = 'sk-abc123',
    List<LlmProviderModelConfig>? models,
  }) {
    return LlmProviderConfig(id: id, name: name, apiUrl: apiUrl, apiKey: apiKey, models: models ?? [_model()]);
  }

  SettingsExportData _export({
    List<LlmProviderConfig> modelProviders = const [],
    List<MemoryPrompt> memoryPrompts = const [],
    List<PresetPrompt> presetPrompts = const [],
    List<TemplatePrompt> templatePrompts = const [],
    List<FixedPromptSequence> fixedPromptSequences = const [],
  }) {
    return SettingsExportData(
      modelProviders: modelProviders,
      memoryPrompts: memoryPrompts,
      presetPrompts: presetPrompts,
      templatePrompts: templatePrompts,
      fixedPromptSequences: fixedPromptSequences,
    );
  }

  // ── MemoryPromptImportComparator ──────...──────────...──────────

  group('MemoryPromptImportComparator', () {
    const comparator = MemoryPromptImportComparator();

    test('内容相同时 isEquivalent 返回 true', () {
      final existing = _mem(content: 'hello');
      final incoming = _mem(content: 'hello');

      expect(comparator.isEquivalent(existing, incoming), isTrue);
    });

    test('内容不同时 isEquivalent 返回 false（同长度，测内容比较）', () {
      final existing = _mem(content: 'abc');
      final incoming = _mem(content: 'def');

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('内容长度不同时 isEquivalent 通过长度守卫返回 false', () {
      final existing = _mem(content: 'a');
      final incoming = _mem(content: 'abcdef');

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });
  });

  // ── PresetPromptImportComparator ──────...──────────...──────────

  group('PresetPromptImportComparator', () {
    const comparator = PresetPromptImportComparator();

    test('消息完全相同时 isEquivalent 返回 true', () {
      final messages = [_msg(content: 'hello', role: PromptMessageRole.user)];
      final existing = _preset(messages: messages);
      final incoming = _preset(messages: messages.map((m) => m).toList());

      expect(comparator.isEquivalent(existing, incoming), isTrue);
    });

    test('消息数量不同时 isEquivalent 返回 false', () {
      final existing = _preset(messages: [_msg()]);
      final incoming = _preset(messages: [_msg(), _msg(id: 'msg-2', content: '第二条')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('消息标题不同时 isEquivalent 返回 false', () {
      final existing = _preset(messages: [_msg(title: '标题A')]);
      final incoming = _preset(messages: [_msg(title: '标题B')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('消息正文不同时 isEquivalent 返回 false', () {
      final existing = _preset(messages: [_msg(content: '旧正文')]);
      final incoming = _preset(messages: [_msg(content: '新正文')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('消息角色不同时 isEquivalent 返回 false', () {
      final existing = _preset(messages: [_msg(role: PromptMessageRole.user)]);
      final incoming = _preset(messages: [_msg(role: PromptMessageRole.assistant)]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });
  });

  // ── TemplatePromptImportComparator ──────...──────────...──────────

  group('TemplatePromptImportComparator', () {
    const comparator = TemplatePromptImportComparator();

    test('内容与变量完全相同时 isEquivalent 返回 true', () {
      final variables = [_var(name: '语气', defaultValue: '正式')];
      final existing = _tpl(content: '请用{{语气}}回复', variables: variables);
      final incoming = _tpl(content: '请用{{语气}}回复', variables: [
        _var(name: '语气', defaultValue: '正式'),
      ]);

      expect(comparator.isEquivalent(existing, incoming), isTrue);
    });

    test('内容不同时 isEquivalent 返回 false', () {
      final existing = _tpl(content: '翻译{{正文}}');
      final incoming = _tpl(content: '改写{{正文}}');

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('变量数量不同时 isEquivalent 返回 false', () {
      final existing = _tpl(variables: [_var(name: '语气')]);
      final incoming = _tpl(variables: [_var(name: '语气'), _var(name: '长度')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });

    test('变量名称或默认值不同时 isEquivalent 返回 false', () {
      final existing = _tpl(variables: [_var(name: '语气', defaultValue: '正式')]);
      final incoming = _tpl(variables: [_var(name: '风格', defaultValue: '轻松')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });
  });

  // ── FixedPromptSequenceImportComparator ──────...──────────...──────────

  group('FixedPromptSequenceImportComparator', () {
    const comparator = FixedPromptSequenceImportComparator();

    test('步骤完全相同时 isEquivalent 返回 true', () {
      final steps = [_step(title: '步骤1', content: '你好')];
      final existing = _seq(steps: steps);
      final incoming = _seq(steps: [_step(title: '步骤1', content: '你好')]);

      expect(comparator.isEquivalent(existing, incoming), isTrue);
    });

    test('步骤不同时 isEquivalent 返回 false', () {
      final existing = _seq(steps: [_step(title: '步骤1', content: '你好')]);
      final incoming = _seq(steps: [_step(title: '步骤2', content: '再见')]);

      expect(comparator.isEquivalent(existing, incoming), isFalse);
    });
  });

  // ── SettingsImportDeduplicator.deduplicate() ──────...──────────

  group('SettingsImportDeduplicator.deduplicate()', () {
    const deduplicator = SettingsImportDeduplicator();

    test('按 apiUrl+apiKey+modelName 过滤已存在的模型服务商', () {
      // 已有服务商：url1/key1 下有 gpt-4
      final existingProviders = [
        _provider(apiUrl: 'https://url1.example.com', apiKey: 'key1', models: [
          _model(modelName: 'gpt-4'),
        ]),
      ];

      // 导入数据：
      // p1: 相同 url1/key1，包含 gpt-4（重复）和 gpt-3.5（新）
      // p2: 相同 url1/key1，仅含 gpt-4（全部重复，整个服务商应被移除）
      // p3: 不同 url2/key2，含 gpt-4（不同服务商，不重复）
      final data = _export(modelProviders: [
        _provider(id: 'pvd-import-1', apiUrl: 'https://url1.example.com', apiKey: 'key1', models: [
          _model(modelName: 'gpt-4'),
          _model(id: 'model-2', displayName: 'GPT-3.5', modelName: 'gpt-3.5'),
        ]),
        _provider(id: 'pvd-import-2', apiUrl: 'https://url1.example.com', apiKey: 'key1', models: [
          _model(modelName: 'gpt-4'),
        ]),
        _provider(id: 'pvd-import-3', apiUrl: 'https://url2.example.com', apiKey: 'key2', models: [
          _model(modelName: 'gpt-4'),
        ]),
      ]);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: existingProviders,
        existingMemoryPrompts: const [],
        existingTemplates: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      // p1 保留，仅含 gpt-3.5；p2 全重复被移除；p3 全保留
      expect(result.modelProviders.length, 2);
      expect(result.modelProviders[0].models.length, 1);
      expect(result.modelProviders[0].models[0].modelName, 'gpt-3.5');
      expect(result.modelProviders[1].apiUrl, 'https://url2.example.com');
      expect(result.modelProviders[1].models.length, 1);
      expect(result.modelProviders[1].models[0].modelName, 'gpt-4');
    });

    test('过滤已存在的记忆提示词', () {
      final existingMemoryPrompts = [_mem(id: 'e-1', content: '常见的记忆内容')];
      final data = _export(memoryPrompts: [
        _mem(id: 'i-1', content: '常见的记忆内容'), // 重复
        _mem(id: 'i-2', content: '全新的记忆内容'), // 新
      ]);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: existingMemoryPrompts,
        existingTemplates: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      expect(result.memoryPrompts.length, 1);
      expect(result.memoryPrompts[0].content, '全新的记忆内容');
    });

    test('过滤已存在的预设提示词模板', () {
      final existingTemplates = [
        _preset(messages: [_msg(content: '已有系统指令', role: PromptMessageRole.system)]),
      ];
      final data = _export(presetPrompts: [
        _preset(messages: [_msg(content: '已有系统指令', role: PromptMessageRole.system)]), // 重复
        _preset(id: 'pst-new', messages: [_msg(content: '全新系统指令', role: PromptMessageRole.system)]), // 新
      ]);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingTemplates: existingTemplates,
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      expect(result.presetPrompts.length, 1);
      expect(result.presetPrompts[0].id, 'pst-new');
    });

    test('过滤已存在的模板提示词', () {
      final existingTemplatePrompts = [
        _tpl(content: '翻译成{{语言}}', variables: [_var(name: '语言', defaultValue: '英文')]),
      ];
      final data = _export(templatePrompts: [
        _tpl(content: '翻译成{{语言}}', variables: [_var(name: '语言', defaultValue: '英文')]), // 重复
        _tpl(id: 'tpl-new', content: '改写成{{风格}}', variables: [_var(name: '风格', defaultValue: '轻松')]), // 新
      ]);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingTemplates: const [],
        existingTemplatePrompts: existingTemplatePrompts,
        existingSequences: const [],
      );

      expect(result.templatePrompts.length, 1);
      expect(result.templatePrompts[0].id, 'tpl-new');
    });

    test('过滤已存在的固定顺序提示词', () {
      final existingSequences = [
        _seq(steps: [_step(title: '步骤1', content: '启动')]),
      ];
      final data = _export(fixedPromptSequences: [
        _seq(steps: [_step(title: '步骤1', content: '启动')]), // 重复
        _seq(id: 'seq-new', steps: [_step(title: '步骤A', content: '初始化')]), // 新
      ]);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingTemplates: const [],
        existingTemplatePrompts: const [],
        existingSequences: existingSequences,
      );

      expect(result.fixedPromptSequences.length, 1);
      expect(result.fixedPromptSequences[0].id, 'seq-new');
    });

    test('输入数据为空时返回空结果', () {
      final result = deduplicator.deduplicate(
        data: _export(),
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingTemplates: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      expect(result.modelProviders, isEmpty);
      expect(result.memoryPrompts, isEmpty);
      expect(result.presetPrompts, isEmpty);
      expect(result.templatePrompts, isEmpty);
      expect(result.fixedPromptSequences, isEmpty);
    });

    test('所有已有数据均匹配时返回全空分类', () {
      final existingMemoryPrompts = [_mem(content: '内容A')];
      final existingTemplates = [_preset(messages: [_msg(content: '消息A')])];
      final existingTemplatePrompts = [_tpl(content: '模板A')];
      final existingSequences = [_seq(steps: [_step(title: '步A', content: '内容A')])];

      final data = _export(
        memoryPrompts: [_mem(content: '内容A')],
        presetPrompts: [_preset(messages: [_msg(content: '消息A')])],
        templatePrompts: [_tpl(content: '模板A')],
        fixedPromptSequences: [_seq(steps: [_step(title: '步A', content: '内容A')])],
      );

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: existingMemoryPrompts,
        existingTemplates: existingTemplates,
        existingTemplatePrompts: existingTemplatePrompts,
        existingSequences: existingSequences,
      );

      expect(result.modelProviders, isEmpty);
      expect(result.memoryPrompts, isEmpty);
      expect(result.presetPrompts, isEmpty);
      expect(result.templatePrompts, isEmpty);
      expect(result.fixedPromptSequences, isEmpty);
    });
  });
}
