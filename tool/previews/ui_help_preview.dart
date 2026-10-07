import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_form_dialog.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

void main() => runApp(uiHelpPreview());

@Preview(name: '按需帮助与预设编辑', size: Size(1280, 900))
Widget uiHelpPreview() => MaterialApp(
  theme: AppTheme.lightTheme(),
  darkTheme: AppTheme.darkTheme(),
  home: Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: Builder(
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: '预设 Prompt',
            description: '配置用于对话的预设消息。普通文本直接注入；有限宏按列表顺序求值后注入。',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PresetPromptFormDialog(
                    initialValue: PresetPrompt(
                      id: 'preview',
                      name: '写作预设',
                      updatedAt: DateTime(2026),
                      syntax: PresetPromptSyntax.sillyTavernSubsetV1,
                      messages: List.generate(
                        16,
                        (index) => PromptMessage(
                          id: '$index',
                          title: '写作条目 ${index + 1}',
                          role: PromptMessageRole.system,
                          content: '保持角色设定与上下文一致。\n\n{{setvar::风格::简洁}}',
                        ),
                      ),
                    ),
                    onSubmit: (_) async {},
                  ),
                ),
                child: const Text('编辑预设'),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
