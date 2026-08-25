import 'package:flutter/material.dart';

/// 模板语法说明：默认收起，展开后展示第一版语法示例与限制。
///
/// 新增与编辑模板表单共用，每次打开都恢复收起状态，不持久化展开偏好。
/// 说明区不提供语法插入、交互式编辑或渲染预览。
class TemplatePromptSyntaxHelp extends StatefulWidget {
  const TemplatePromptSyntaxHelp({super.key});

  @override
  State<TemplatePromptSyntaxHelp> createState() =>
      _TemplatePromptSyntaxHelpState();
}

class _TemplatePromptSyntaxHelpState extends State<TemplatePromptSyntaxHelp> {
  static const _exampleLines = <String>[
    '{{主角名}}',
    '{{章节数:number}}',
    '{{人称:select|一|二|三}}',
    '{{#if 人称 == "一"}}',
    '使用“我”的口吻，主角是{{主角名}}。',
    '{{else if 人称 == "二"}}',
    '使用“你”的口吻。',
    '{{else}}',
    '使用第三人称。',
    '{{/if}}',
  ];

  static const _limitations = <String>[
    '文本与单选变量支持 == 和 !=；数字变量还支持 >、>=、<、<=。',
    '字符串字面量需用双引号，整数不用引号。',
    '单选变量用 | 分隔选项，条件分支内可以使用普通变量。',
    '控制标签可与正文同行或独占一行；独占一行的控制标签会整行移除，不留空白行。',
    '{{正文}} 必须放在条件块之外；模板未写 {{正文}} 时，正文会插入在模板上方。',
    '{{正文}} 不能作为条件变量引用。',
    '比较运算符与变量名之间需要空白分隔（如 人称== "一" 会被拒绝）。',
    '第一版不支持嵌套条件、组合条件、模板引用与渲染预览，不支持在单选选项中使用 |，也不支持把 {{ 转义为字面文本。',
  ];

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('template-prompt-syntax-help'),
      title: const Text('模板语法说明'),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildExampleBlock(context),
              const SizedBox(height: 12),
              for (final limitation in _limitations)
                _buildLimitationItem(context, limitation),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExampleBlock(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _exampleLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(line, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _buildLimitationItem(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
