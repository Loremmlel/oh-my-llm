import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/preset_prompt_editor.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';
import 'package:oh_my_llm/features/settings/domain/models/worldbooks/world_book.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/worldbooks/world_book_editor.dart';

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
            title: '世界书',
            description: '按保存顺序全量注入启用条目。',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => WorldBookEditor(
                      initialValue: WorldBook(
                        id: 'world-preview',
                        name: '群岛与远航',
                        updatedAt: DateTime(2026),
                        entries: [
                          const WorldBookEntry(
                            id: 'world',
                            title: '世界设定',
                            content: '城市分布在群岛之上，以帆船维系贸易。\n\n每座岛屿都有自己的风俗、语言与历史。',
                          ),
                          const WorldBookEntry(
                            id: 'cast',
                            title: '群像人物与相互关系',
                            content: '记录人物的背景、动机与相互关系。',
                          ),
                          const WorldBookEntry(
                            id: 'style',
                            title: '叙事规则',
                            content: '从人物行动与对话推进剧情。',
                            enabled: false,
                          ),
                        ],
                      ),
                      onSubmit: (_) async {},
                    ),
                  ),
                ),
                child: const Text('编辑世界书'),
              ),
            ),
          ),
          SettingsSectionCard(
            title: '预设 Prompt',
            description: '配置用于对话的预设消息。普通文本直接注入；有限宏按列表顺序求值后注入。',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PresetPromptEditor(
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
