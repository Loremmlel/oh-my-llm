import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/preset_macros/preset_macro_renderer.dart';

void main() {
  PresetPrompt preset(List<String> bodies) => PresetPrompt(
    id: 'preset',
    name: '宏测试',
    updatedAt: DateTime(2026),
    syntax: PresetPromptSyntax.sillyTavernSubsetV1,
    messages: [
      for (var i = 0; i < bodies.length; i++)
        PromptMessage(
          id: '$i',
          role: PromptMessageRole.system,
          title: '选一 别关 $i',
          content: bodies[i],
        ),
    ],
  );

  test('变量按启用条目顺序组合且每次请求重建环境', () {
    final source = preset([
      '{{setvar::x::简洁}}',
      '{{addvar::x::，避免套话}}',
      '{{getvar::x}}',
    ]);
    expect(renderPresetPrompt(source).messages.last.content, '简洁，避免套话');
    final disabled = source.copyWith(
      messages: [
        source.messages[0],
        source.messages[1].copyWith(enabled: false),
        source.messages[2],
      ],
    );
    expect(renderPresetPrompt(disabled).messages.last.content, '简洁');
    expect(
      renderPresetPrompt(preset(['{{getvar::x}}'])).messages.single.content,
      '',
    );
    expect(
      renderPresetPrompt(
        source.copyWith(
          messages: source.messages
              .map((m) => m.copyWith(title: '新标题'))
              .toList(),
        ),
      ).messages.last.content,
      '简洁，避免套话',
    );
  });

  final cases = <(String, String)>[
    ('{{SETVAR::Name::第一行\n{{USER}}::第三行}}{{getvar::Name}}', '第一行\nuser::第三行'),
    ('{{setvar::x::旧}}{{setvar::x::新}}{{getvar::x}}', '新'),
    ('{{setvar::x::{{getvar::later}}}}{{setvar::later::之后}}{{getvar::x}}', ''),
    ('{{// 注释\n{{setvar::x::不执行}}}}{{getvar::x}}', ''),
    ('{{未知::{{setvar::x::不执行}}}}{{getvar::x}}', '{{未知::{{setvar::x::不执行}}}}'),
    (' a\n\n{{trim}}\r\nb ', ' ab '),
    ('{{setvar::Name::保留}}{{getvar::name}}', ''),
    ('{{setvar::n::1}}{{addvar::n::2}}{{getvar::n}}', '{{addvar::n::2}}1'),
    ('{{setvar::x::}}{{addvar::x::正文}}{{getvar::x}}', '正文'),
  ];
  for (var i = 0; i < cases.length; i++) {
    test('有限宏语义保留嵌套、原文和空白边界 ${i + 1}', () {
      final (source, expected) = cases[i];
      final result = renderPresetPrompt(preset([source]));
      expect(result.hasErrors, isFalse);
      expect(result.messages.single.content, expected);
    });
  }

  test('用户正文作为数据插入且不会再次执行其中的宏', () {
    final result = renderPresetPrompt(
      preset(['{{lastUserMessage}}{{getvar::x}}']),
      lastUserMessage: '{{setvar::x::危险}}',
    );
    expect(result.messages.single.content, '{{setvar::x::危险}}');
  });

  test('普通预设保持双花括号字面文本', () {
    final source = preset(['{{user}}'])
        .copyWith(syntax: PresetPromptSyntax.plain);
    expect(renderPresetPrompt(source).messages.single.content, '{{user}}');
  });

  for (final source in [
    '{{setvar::x}}',
    '{{getvar::}}',
    '{{user',
    '{{user::多余}}',
    '${'{{setvar::x::' * 33}值${'}}' * 33}',
    'x' * (8 * 1024 * 1024 + 1),
    '{{user}}' * 50001,
  ]) {
    test('无效宏或资源超限产生可定位错误 ${source.length}', () {
      final result = renderPresetPrompt(preset([source]));
      expect(result.hasErrors, isTrue);
      expect(result.diagnostics.last.entryId, '0');
    });
  }
}
