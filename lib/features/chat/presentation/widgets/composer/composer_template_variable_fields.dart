import 'package:flutter/material.dart';

import '../../../../settings/domain/models/template_prompt.dart';

class ComposerTemplateVariableFields extends StatelessWidget {
  const ComposerTemplateVariableFields({
    required this.selectedTemplatePrompt,
    required this.templateVariableControllers,
    super.key,
  });

  final TemplatePrompt selectedTemplatePrompt;
  final Map<String, TextEditingController> templateVariableControllers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minItemWidth = 220.0;
        const gap = 6.0;
        final crossAxisCount =
            ((constraints.maxWidth + gap) / (minItemWidth + gap)).floor().clamp(
              1,
              3,
            );
        final itemWidth = crossAxisCount == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (crossAxisCount - 1)) /
                  crossAxisCount;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final variable in selectedTemplatePrompt.inputVariables)
              SizedBox(
                width: itemWidth,
                child: TextField(
                  key: ValueKey('template-variable-${variable.name}'),
                  controller: templateVariableControllers[variable.name],
                  decoration: InputDecoration(
                    labelText: variable.name,
                    hintText: variable.defaultValue.isEmpty
                        ? '未设置默认值'
                        : variable.defaultValue,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
