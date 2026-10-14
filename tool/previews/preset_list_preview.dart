import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:oh_my_llm/app/theme/app_theme.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/lists/preset_prompts_view.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_section_card.dart';

@Preview(name: '预设列表 · 手机', group: '设置', size: Size(390, 844))
@Preview(name: '预设列表 · 紧凑宽屏', group: '设置', size: Size(760, 640))
Widget presetListPreview() => const _PresetListPreview();

/// 独立示例数据只用于布局与开关预览，不读取个人配置。
class _PresetListPreview extends StatefulWidget {
  const _PresetListPreview();

  @override
  State<_PresetListPreview> createState() => _PresetListPreviewState();
}

class _PresetListPreviewState extends State<_PresetListPreview> {
  List<PresetPrompt> presets = [
    for (final (index, name, count, macro) in [
      (0, '糖糖公司 · 写作预设', 180, true),
      (1, '日常对话', 6, false),
      (2, '长篇故事 · 角色与世界设定', 42, true),
      (3, '代码审阅', 8, false),
    ])
      PresetPrompt(
        id: '$index',
        name: name,
        updatedAt: DateTime(2026),
        syntax: macro
            ? PresetPromptSyntax.sillyTavernSubsetV1
            : PresetPromptSyntax.plain,
        singleSystemPrompt: index.isEven,
        messages: List.generate(
          count,
          (i) => PromptMessage(
            id: '$i',
            role: PromptMessageRole.system,
            content: '示例提示词',
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsSectionCard(
            title: '预设 Prompt',
            description: '管理用于对话的预设消息。',
            action: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('新增预设'),
            ),
            child: PresetPromptsView(
              templates: presets,
              onCopy: (_) async {},
              onEdit: (_) {},
              onDelete: (_) async {},
              onSingleSystemChanged: (preset, value) async => setState(() {
                presets = [
                  for (final item in presets)
                    if (item.id == preset.id)
                      item.copyWith(singleSystemPrompt: value)
                    else
                      item,
                ];
              }),
            ),
          ),
        ],
      ),
    ),
  );
}
