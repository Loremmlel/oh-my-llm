import 'dart:async';

import 'package:flutter/material.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_syntax_help.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_form_dialog_scaffold.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_form_dialog_state_mixin.dart';

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

  static const variableReconcileDebounce = Duration(milliseconds: 220);
  static const variableReconcileDebounceForLargeContent = Duration(
    milliseconds: 320,
  );

  @override
  State<TemplatePromptFormDialog> createState() =>
      _TemplatePromptFormDialogState();
}

/// 模板提示词表单的输入与变量状态。
class _TemplatePromptFormDialogState extends State<TemplatePromptFormDialog>
    with SettingsFormDialogStateMixin {
  static const _largeContentThreshold = 6000;

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final Map<String, TextEditingController> _variableControllers = {};
  late TemplatePromptCompilation _compilation;
  late List<TemplatePromptVariable> _variables;
  Timer? _variableReconcileDebounceTimer;
  String _pendingContent = '';
  String _lastReconciledContent = '';

  @override
  void initState() {
    super.initState();
    _titleController = initController(widget.initialValue?.title ?? '');
    _contentController = initController(widget.initialValue?.content ?? '');
    // 先用编译器校验正文：语法有效才与已保存变量协调，再校验临时完整
    // 定义，让合法旧 text/number 模板保留默认值，同时暴露不一致的存储元数据。
    _compilation = compileTemplatePromptContent(_contentController.text);
    if (_compilation.isValid) {
      _variables = reconcileCompiledTemplatePromptVariables(
        program: _compilation.program!,
        existingVariables: widget.initialValue?.variables ?? const [],
      );
      _compilation = compileTemplatePromptDefinition(
        _buildTemporaryTemplate(_contentController.text, _variables),
      );
    } else {
      _variables = const [];
    }
    _pendingContent = _contentController.text;
    _lastReconciledContent = _contentController.text;
    _syncVariableControllers();
    _contentController.addListener(_handleContentChanged);
  }

  @override
  void dispose() {
    _variableReconcileDebounceTimer?.cancel();
    _contentController.removeListener(_handleContentChanged);
    for (final controller in _variableControllers.values) {
      controller.dispose();
    }
    disposeAllControllers();
    super.dispose();
  }

  @override
  /// 构建模板提示词编辑表单和变量默认值输入区。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑模板提示词' : '新增模板提示词',
      formKey: formKey,
      isSaving: isSaving,
      submitEnabled: _compilation.isValid,
      onSubmit: _handleSubmit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const ValueKey('template-prompt-title-field'),
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '例如：翻译润色模板',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('template-prompt-content-field'),
            controller: _contentController,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '模板提示词',
              hintText: '请将以下{{正文}}翻译成{{目标语言}}，并保持{{语气}}。',
              alignLabelWithHint: true,
            ),
            validator: validateRequired,
          ),
          if (_compilation.diagnostics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _formatDiagnostic(_compilation.diagnostics.first),
              key: const ValueKey('template-prompt-compile-diagnostic'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          const TemplatePromptSyntaxHelp(),
          const SizedBox(height: 20),
          Text('变量默认值', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_variables.isEmpty)
            const Text('当前模板还没有检测到任何变量。')
          else
            for (final variable in _variables) ...[
              if (variable.isBody)
                _buildBodyVariableHint(context, variable)
              else if (variable.isNumber)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: ValueKey(
                      'template-prompt-variable-field-${variable.name}',
                    ),
                    controller: _variableControllers[variable.name],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${variable.name}（数字）',
                      hintText: '默认为 1',
                    ),
                    validator: _validateNumberDefault,
                  ),
                )
              else if (variable.isSelect)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'template-prompt-variable-field-${variable.name}',
                    ),
                    initialValue: variable.defaultValue,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '${variable.name}（单选）',
                    ),
                    items: [
                      for (final option in variable.options)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _variables = [
                          for (final item in _variables)
                            if (item.name == variable.name)
                              item.copyWith(defaultValue: value)
                            else
                              item,
                        ];
                      });
                    },
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: ValueKey(
                      'template-prompt-variable-field-${variable.name}',
                    ),
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
    _pendingContent = _contentController.text;
    _scheduleVariableReconcile();
  }

  /// 防抖调度：每次按键重置 timer，停止输入后才触发变量重算。
  void _scheduleVariableReconcile() {
    final debounceWindow = _resolveDebounceWindow(_pendingContent.length);
    _variableReconcileDebounceTimer?.cancel();
    _variableReconcileDebounceTimer = Timer(
      debounceWindow,
      _runVariableReconcile,
    );
  }

  void _flushVariableReconcile() {
    _variableReconcileDebounceTimer?.cancel();
    _runVariableReconcile();
  }

  void _runVariableReconcile() {
    final nextContent = _pendingContent;
    if (nextContent == _lastReconciledContent) {
      return;
    }
    _lastReconciledContent = nextContent;

    final nextCompilation = compileTemplatePromptContent(nextContent);
    if (!nextCompilation.isValid) {
      // 源语法无效：仅更新编译状态并展示首个诊断，保留变量列表与全部
      // 现有控制器，避免一次临时输入错误清空表单。
      setState(() {
        _compilation = nextCompilation;
      });
      return;
    }

    final nextVariables = reconcileCompiledTemplatePromptVariables(
      program: nextCompilation.program!,
      existingVariables: _buildVariablesFromControllers(),
    );
    final shapeChanged = !_sameVariableShape(_variables, nextVariables);
    if (!shapeChanged && _compilation == nextCompilation) {
      return;
    }
    setState(() {
      _compilation = nextCompilation;
      if (shapeChanged) {
        _variables = nextVariables;
        _syncVariableControllers();
      }
    });
  }

  /// 变量默认值变化只影响保存门禁：存储元数据不一致在打开表单时由定义
  /// 校验暴露，修复默认值后需要重新放行；内容语法已有效时默认值问题交给
  /// 字段校验与提交路径处理，避免每次按键都关闭保存按钮。
  void _handleVariableValueChanged() {
    if (_compilation.isValid) {
      return;
    }
    final contentCompilation = compileTemplatePromptContent(_pendingContent);
    if (!contentCompilation.isValid) {
      return;
    }
    final nextCompilation = compileTemplatePromptDefinition(
      _buildTemporaryTemplate(
        _pendingContent,
        _buildVariablesFromControllers(),
      ),
    );
    setState(() {
      _compilation = nextCompilation;
    });
  }

  bool _sameVariableShape(
    List<TemplatePromptVariable> current,
    List<TemplatePromptVariable> next,
  ) {
    if (current.length != next.length) {
      return false;
    }
    for (var index = 0; index < current.length; index += 1) {
      if (current[index].name != next[index].name ||
          current[index].isBody != next[index].isBody ||
          current[index].type != next[index].type ||
          !_sameStringList(current[index].options, next[index].options)) {
        return false;
      }
    }
    return true;
  }

  bool _sameStringList(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var i = 0; i < first.length; i += 1) {
      if (first[i] != second[i]) {
        return false;
      }
    }
    return true;
  }

  Duration _resolveDebounceWindow(int contentLength) {
    return contentLength > _largeContentThreshold
        ? TemplatePromptFormDialog.variableReconcileDebounceForLargeContent
        : TemplatePromptFormDialog.variableReconcileDebounce;
  }

  /// 从当前变量与控制器构建待提交的变量列表。
  ///
  /// 单选默认值由下拉框直接写入 [_variables]，不经过文本控制器；
  /// 数字默认值不再把空值兜底为 1（新建数字变量的默认 1 由协调阶段写入）。
  List<TemplatePromptVariable> _buildVariablesFromControllers() {
    return _variables
        .map((variable) {
          if (variable.isBody) {
            return const TemplatePromptVariable(
              name: templatePromptBodyVariableName,
            );
          }
          if (variable.isSelect) {
            return TemplatePromptVariable(
              name: variable.name,
              defaultValue: variable.defaultValue,
              type: variable.type,
              options: variable.options,
            );
          }
          final rawDefault =
              _variableControllers[variable.name]?.text.trim() ?? '';
          return TemplatePromptVariable(
            name: variable.name,
            defaultValue: rawDefault,
            type: variable.type,
          );
        })
        .toList(growable: false);
  }

  void _syncVariableControllers() {
    final activeNames = _variables
        .where((variable) => !variable.isBody && !variable.isSelect)
        .map((variable) => variable.name)
        .toSet();
    final removedNames = _variableControllers.keys
        .where((name) => !activeNames.contains(name))
        .toList(growable: false);
    for (final name in removedNames) {
      _variableControllers.remove(name)?.dispose();
    }

    for (final variable in _variables) {
      if (variable.isBody || variable.isSelect) {
        continue;
      }
      _variableControllers.putIfAbsent(variable.name, () {
        final controller = TextEditingController(text: variable.defaultValue);
        controller.addListener(_handleVariableValueChanged);
        return controller;
      });
    }
  }

  String _formatDiagnostic(TemplatePromptDiagnostic diagnostic) {
    return '第 ${diagnostic.location.line} 行第 ${diagnostic.location.column} 列：'
        '${diagnostic.message}';
  }

  /// 数字变量默认值校验：要求去空白后为整数，不允许空值（新建变量时的
  /// 默认 1 由协调阶段写入控制器）。
  String? _validateNumberDefault(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || int.tryParse(trimmed) == null) {
      return '默认值需为整数';
    }
    return null;
  }

  TemplatePrompt _buildTemporaryTemplate(
    String content,
    List<TemplatePromptVariable> variables,
  ) {
    return TemplatePrompt(
      id: '',
      title: '',
      content: content,
      variables: variables,
      updatedAt: DateTime(0),
    );
  }

  Future<void> _handleSubmit() async {
    _flushVariableReconcile();
    if (!_compilation.isValid) {
      return;
    }
    if (!validateForm()) {
      return;
    }

    final variables = _buildVariablesFromControllers();
    // 用表单正文与默认值构造临时完整定义再校验，防止字段校验与定义校验
    // 口径不一致时把非法定义保存下去；不一致按 inline 表单失败处理。
    final definitionCompilation = compileTemplatePromptDefinition(
      _buildTemporaryTemplate(_contentController.text.trim(), variables),
    );
    if (!definitionCompilation.isValid) {
      setState(() {
        _compilation = definitionCompilation;
      });
      return;
    }

    await submitAndClose(() {
      return widget.onSubmit(
        TemplatePromptFormData(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          variables: variables,
        ),
      );
    });
  }
}
