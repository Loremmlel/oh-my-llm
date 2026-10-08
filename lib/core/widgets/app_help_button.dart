import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'dialogs/detail_display_dialog.dart';

/// 解释按需浮层展示，避免挤占所属列表或编辑器的空间。
class AppHelpButton extends StatelessWidget {
  const AppHelpButton({required this.title, required this.message, super.key});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '$title说明',
    icon: const Icon(Icons.help_outline, size: 20),
    constraints: const BoxConstraints.tightFor(
      width: AppInteractionSizes.minimumHitTarget,
      height: AppInteractionSizes.minimumHitTarget,
    ),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => DetailDisplayDialog(
        title: Text('$title说明'),
        child: SelectableText(message),
      ),
    ),
  );
}

/// 标题与帮助入口保持相邻，窄布局先让标题换行。
class AppHelpTitle extends StatelessWidget {
  const AppHelpTitle({
    required this.title,
    required this.message,
    this.style,
    super.key,
  });

  final String title;
  final String message;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(title, style: style)),
      AppHelpButton(title: title, message: message),
    ],
  );
}
