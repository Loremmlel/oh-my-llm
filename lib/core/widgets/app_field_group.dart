import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

/// 短表单字段按内容需要限宽，窄容器内自动换行；长正文应放在组外。
class AppFieldGroup extends StatelessWidget {
  const AppFieldGroup({
    required this.children,
    this.fieldWidth = 320,
    super.key,
  });
  final List<Widget> children;
  final double fieldWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.md,
      children: [
        for (final child in children)
          SizedBox(
            width: math.min(fieldWidth, constraints.maxWidth),
            child: child,
          ),
      ],
    ),
  );
}
