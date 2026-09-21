import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/preset_macros/silly_tavern_preset_import.dart';
import 'package:oh_my_llm/features/chat/application/requests/chat_request_message_builder.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';

// 外部格式 fixture，验证来源字段而非应用自身模型的序列化。
Map<String, Object?> prompt(
  String id, {
  String title = '',
  String role = 'system',
  String? content,
  int position = 0,
  int depth = 4,
  int order = 100,
  bool marker = false,
}) => {
  'identifier': id,
  'name': title,
  'role': role,
  'content': content ?? id,
  'injection_position': position,
  'injection_depth': depth,
  'injection_order': order,
  'marker': marker,
};
String file(
  List<Map<String, Object?>> prompts,
  List<Map<String, Object?>> entries,
) => jsonEncode({
  'prompts': prompts,
  'prompt_order': [
    {'character_id': 100001, 'order': entries},
  ],
});
Map<String, Object?> entry(String id, [bool enabled = true]) => {
  'identifier': id,
  'enabled': enabled,
};

void main() {
  test('相同标题不产生选择规则，顺序表控制开关，备用条目关闭且保留原文', () {
    final source = SillyTavernPresetFile.parse(
      file(
        [
          {...prompt('a', title: '选一', content: ' a\n'), 'enabled': false},
          prompt('chatHistory', marker: true, content: ''),
          prompt('b', title: '选一'),
          prompt('spare'),
        ],
        [entry('a'), entry('chatHistory'), entry('b', false)],
      ),
    );
    final plan = source.plan(0);
    expect(plan.canImport, isTrue);
    expect(plan.messages.map((m) => m.sourceIdentifier), ['a', 'b', 'spare']);
    expect(plan.messages.map((m) => m.enabled), [true, false, false]);
    expect(plan.messages.first.content, ' a\n');
    expect(plan.messages.map((m) => m.placement), [
      PromptMessagePlacement.before,
      PromptMessagePlacement.after,
      PromptMessagePlacement.before,
    ]);
    var nextId = 0;
    final imported = source.createPreset(
      plan,
      name: '导入',
      newId: () => 'local-${nextId++}',
    );
    expect(imported.messages.first.id, isNot('a'));
    expect(imported.syntax, PresetPromptSyntax.sillyTavernSubsetV1);
  });

  test('深度和同层角色排序不改变变量求值顺序', () {
    final source = SillyTavernPresetFile.parse(
      file(
        [
          prompt('init', content: '{{setvar::x::约束}}', position: 1, depth: 0),
          prompt('chatHistory', marker: true, content: ''),
          prompt('after', content: '{{getvar::x}}'),
          prompt('system', position: 1, depth: 0, order: 10),
          prompt('userLate', role: 'user', position: 1, depth: 0, order: 20),
          prompt('userEarly', role: 'user', position: 1, depth: 0, order: 5),
          prompt('latest', position: 1, depth: 1),
          prompt('model', role: 'model', position: 1, depth: 0),
          prompt('userSameOrder', role: 'user', position: 1, depth: 0),
        ],
        [
          for (final id in [
            'init',
            'chatHistory',
            'after',
            'system',
            'userLate',
            'userEarly',
            'latest',
            'model',
            'userSameOrder',
          ])
            entry(id),
        ],
      ),
    );
    var id = 0;
    final preset = source.createPreset(
      source.plan(0),
      name: '深度',
      newId: () => '${id++}',
    );
    final request = buildRequestMessages(
      presetPrompt: preset,
      conversationMessages: [
        ChatMessage(
          id: 'input',
          role: ChatMessageRole.user,
          content: '本次输入',
          createdAt: DateTime(2026),
        ),
      ],
      latestInputMessageId: 'input',
    );
    expect(request.map((m) => m.content), [
      'latest',
      '本次输入',
      'userEarly',
      'system',
      'userLate',
      'model',
      'userSameOrder',
      '约束',
    ]);
  });

  test('多个顺序表分开选择，未知位置与含正文槽位由用户指定', () {
    final object = jsonDecode(
      file(
        [prompt('odd', position: 1, depth: 5), prompt('slot', marker: true)],
        [entry('odd'), entry('slot')],
      ),
    ) as Map;
    (object['prompt_order'] as List).insert(0, {
      'character_id': 100000,
      'order': [entry('odd', false)],
    });
    final source = SillyTavernPresetFile.parse(jsonEncode(object));
    expect(source.preferredOrder, 1);
    expect(source.plan(1).canImport, isFalse);
    final resolved = source.plan(
      1,
      placements: {
        'odd': PromptMessagePlacement.beforeLatestInput,
        'slot': PromptMessagePlacement.after,
      },
    );
    expect(resolved.canImport, isTrue);
    expect(resolved.messages.map((m) => m.content), ['odd', 'slot']);
  });

  for (final input in [
    '{}',
    file([prompt('a'), prompt('a')], [entry('a')]),
    file([prompt('a')], [entry('missing')]),
    file([prompt('a')], [entry('a'), entry('a')]),
    file(
      [
        {...prompt('a'), 'injection_depth': '1'},
      ],
      [entry('a')],
    ),
  ]) {
    test('损坏的外部结构明确失败 ${input.length}', () {
      expect(() => SillyTavernPresetFile.parse(input), throwsFormatException);
    });
  }
}
