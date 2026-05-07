import 'package:flutter/material.dart';

import '../../domain/models/template_prompt.dart';
import '../../domain/template_prompt_parser.dart';
import 'settings_form_dialog_scaffold.dart';

/// 模板提示词表单提交数据。
class TemplatePromptFormData {
  const TemplatePromptFormData({
    required this.title,
    required this.content,
    required this.variables,
  });

  final String title;
  final String content;
  final List<TemplatePromptVariable> variables;
}

/// 新增或编辑模板提示词的对话框。
class TemplatePromptFormDialog extends StatefulWidget {
  const TemplatePromptFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(TemplatePromptFormData formData) onSubmit;
  final TemplatePrompt? initialValue;

  @override
  State<TemplatePromptFormDialog> createState() =>
      _TemplatePromptFormDialogState();
}

/// 模板提示词表单的输入与变量状态。
class _TemplatePromptFormDialogState extends State<TemplatePromptFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final Map<String, TextEditingController> _variableControllers = {};
  late List<TemplatePromptVariable> _variables;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialValue?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialValue?.content ?? '',
    );
    _variables = reconcileTemplatePromptVariables(
      content: _contentController.text,
      existingVariables: widget.initialValue?.variables ?? const [],
    );
    _syncVariableControllers();
    _contentController.addListener(_handleContentChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController
      ..removeListener(_handleContentChanged)
      ..dispose();
    for (final controller in _variableControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  /// 构建模板提示词编辑表单和变量默认值输入区。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑模板提示词' : '新增模板提示词',
      formKey: _formKey,
      isSaving: _isSaving,
      onSubmit: _handleSubmit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '例如：翻译润色模板',
            ),
            validator: _validateRequired,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contentController,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '模板提示词',
              hintText: '请将以下{{正文}}翻译成{{目标语言}}，并保持{{语气}}。',
              alignLabelWithHint: true,
            ),
            validator: _validateRequired,
          ),
          const SizedBox(height: 8),
          Text(
            '使用 {{变量名}} 声明可注入变量；其中 {{正文}} 对应聊天页主输入框，不设置默认值。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Text('变量默认值', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_variables.isEmpty)
            const Text('当前模板还没有检测到任何变量。')
          else
            for (final variable in _variables) ...[
              if (variable.isBody)
                _buildBodyVariableHint(context, variable)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _variableControllers[variable.name],
                    decoration: InputDecoration(
                      labelText: variable.name,
                      hintText: '留空则聊天页默认使用空值',
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }

  Widget _buildBodyVariableHint(
    BuildContext context,
    TemplatePromptVariable variable,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.notes_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text('${variable.name} 使用聊天页主输入框提供内容，不单独设置默认值。')),
            ],
          ),
        ),
      ),
    );
  }

  void _handleContentChanged() {
    final nextVariables = reconcileTemplatePromptVariables(
      content: _contentController.text,
      existingVariables: _buildVariablesFromControllers(),
    );
    if (_variables.length == nextVariables.length &&
        _variables.every((variable) => nextVariables.contains(variable))) {
      return;
    }

    setState(() {
      _variables = nextVariables;
      _syncVariableControllers();
    });
  }

  List<TemplatePromptVariable> _buildVariablesFromControllers() {
    return _variables
        .map((variable) {
          if (variable.isBody) {
            return const TemplatePromptVariable(
              name: templatePromptBodyVariableName,
            );
          }
          return TemplatePromptVariable(
            name: variable.name,
            defaultValue:
                _variableControllers[variable.name]?.text.trim() ?? '',
          );
        })
        .toList(growable: false);
  }

  void _syncVariableControllers() {
    final activeNames = _variables
        .where((variable) => !variable.isBody)
        .map((variable) => variable.name)
        .toSet();
    final removedNames = _variableControllers.keys
        .where((name) => !activeNames.contains(name))
        .toList(growable: false);
    for (final name in removedNames) {
      _variableControllers.remove(name)?.dispose();
    }

    for (final variable in _variables) {
      if (variable.isBody) {
        continue;
      }
      _variableControllers.putIfAbsent(
        variable.name,
        () => TextEditingController(text: variable.defaultValue),
      );
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final variables = _buildVariablesFromControllers();
    setState(() {
      _isSaving = true;
    });

    await widget.onSubmit(
      TemplatePromptFormData(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        variables: variables,
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }
    return null;
  }
}
