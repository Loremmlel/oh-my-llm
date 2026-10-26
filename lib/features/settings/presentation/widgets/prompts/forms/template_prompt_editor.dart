import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_compiler.dart';
import 'package:oh_my_llm/features/settings/domain/template_prompt_language/template_prompt_program.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/prompts/forms/template_prompt_syntax_help.dart';
import 'package:oh_my_llm/features/settings/presentation/widgets/shared/settings_editor_list.dart';
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

/// 新增或编辑模板提示词的页面工作区。
class TemplatePromptEditor extends StatefulWidget {
  const TemplatePromptEditor({
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
  State<TemplatePromptEditor> createState() => _TemplatePromptEditorState();
}

class _TemplatePromptEditorState extends State<TemplatePromptEditor>
    with SettingsFormDialogStateMixin {
  static const _largeContentThreshold = 6000;

  late final TextEditingController _titleController = initController(
    widget.initialValue?.title ?? '',
  );
  late final LongTextEditingController _contentController =
      initLongTextController(widget.initialValue?.content ?? '');
  final Map<String, LongTextEditingController> _variableControllers = {};
  late TemplatePromptCompilation _compilation;
  late List<TemplatePromptVariable> _variables;
  Timer? _variableReconcileDebounceTimer;
  String _pendingContent = '';
  String _lastReconciledContent = '';

  String _snapshot() => jsonEncode([
    _titleController.text,
    _contentController.text,
    for (final v in _buildVariablesFromControllers())
      [v.name, v.type.name, v.defaultValue, v.options],
  ]);

  @override
  void initState() {
    super.initState();
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
    captureInitialSnapshot(_snapshot());
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
  Widget build(BuildContext context) => buildEditorPage(
    title: widget.initialValue == null ? '新增模板提示词' : '编辑模板提示词',
    targetName: '模板提示词',
    helpText: TemplatePromptSyntaxHelp.message,
    submitEnabled: _compilation.isValid,
    snapshotBuilder: _snapshot,
    additionalControllers: _variableControllers.values,
    shouldScrollContent: (constraints) => constraints.maxHeight < 260,
    onSubmit: _handleSubmit,
    builder: (context, constraints, _) {
      final expand = constraints.hasBoundedHeight;
      final isWide =
          expand && constraints.maxWidth >= AppBreakpoints.formMasterDetail;
      final mainPane = Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField.form(
            controller: _titleController,
            readOnly: isSaving,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '例如：翻译润色模板',
            ),
            validator: validateRequired,
          ),
          const SizedBox(height: 8),
          SettingsExpandedTextField(
            controller: _contentController,
            expand: expand,
            minLines: 5,
            readOnly: isSaving,
            validator: validateRequired,
            decoration: const InputDecoration(
              labelText: '模板提示词',
              hintText: '请将以下{{正文}}翻译成{{目标语言}}，并保持{{语气}}。',
              alignLabelWithHint: true,
            ),
          ),
          if (_compilation.diagnostics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _formatDiagnostic(_compilation.diagnostics.first),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      );
      final variablesSection = _buildVariablesSection(context);
      if (isWide) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: mainPane),
              const VerticalDivider(width: 33),
              SizedBox(
                width: 320,
                child: SingleChildScrollView(child: variablesSection),
              ),
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: expand ? FlexFit.tight : FlexFit.loose,
            child: mainPane,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: expand
                  ? constraints.maxHeight * 0.32
                  : double.infinity,
            ),
            child: SingleChildScrollView(child: variablesSection),
          ),
        ],
      );
    },
  );

  Widget _buildVariablesSection(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('变量默认值', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      if (_variables.isEmpty)
        Text('当前模板还没有检测到任何变量。', style: Theme.of(context).textTheme.bodySmall)
      else
        for (final variable in _variables)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildVariableField(context, variable),
          ),
    ],
  );

  Widget _buildVariableField(
    BuildContext context,
    TemplatePromptVariable variable,
  ) {
    if (variable.isBody) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.notes_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${variable.name} · 来自聊天输入框')),
            ],
          ),
        ),
      );
    }
    if (variable.isSelect) {
      return AppDropdownField<String>(
        fillWidth: true,
        initialValue: variable.defaultValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: '${variable.name}（单选）'),
        items: [
          for (final option in variable.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: isSaving
            ? null
            : (value) {
                if (value == null) return;
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
      );
    }
    return AppTextField.form(
      controller: _variableControllers[variable.name],
      readOnly: isSaving,
      keyboardType: variable.isNumber ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: variable.isNumber ? '${variable.name}（数字）' : variable.name,
        hintText: variable.isNumber ? '默认为 1' : '留空则聊天页默认使用空值',
      ),
      validator: variable.isNumber ? _validateNumberDefault : null,
    );
  }

  void _handleContentChanged() {
    _pendingContent = _contentController.text;
    _variableReconcileDebounceTimer?.cancel();
    _variableReconcileDebounceTimer = Timer(
      _pendingContent.length > _largeContentThreshold
          ? TemplatePromptEditor.variableReconcileDebounceForLargeContent
          : TemplatePromptEditor.variableReconcileDebounce,
      _runVariableReconcile,
    );
  }

  void _runVariableReconcile() {
    final nextContent = _pendingContent;
    if (nextContent == _lastReconciledContent) return;
    _lastReconciledContent = nextContent;

    final nextCompilation = compileTemplatePromptContent(nextContent);
    if (!nextCompilation.isValid) {
      setState(() => _compilation = nextCompilation);
      return;
    }

    final nextVariables = reconcileCompiledTemplatePromptVariables(
      program: nextCompilation.program!,
      existingVariables: _buildVariablesFromControllers(),
    );
    final shapeChanged = !_sameVariableShape(_variables, nextVariables);
    if (!shapeChanged && _compilation == nextCompilation) return;
    setState(() {
      _compilation = nextCompilation;
      if (shapeChanged) {
        _variables = nextVariables;
        _syncVariableControllers();
      }
    });
  }

  void _handleVariableValueChanged() {
    if (_compilation.isValid) return;
    final contentCompilation = compileTemplatePromptContent(_pendingContent);
    if (!contentCompilation.isValid) return;
    setState(() {
      _compilation = compileTemplatePromptDefinition(
        _buildTemporaryTemplate(
          _pendingContent,
          _buildVariablesFromControllers(),
        ),
      );
    });
  }

  bool _sameVariableShape(
    List<TemplatePromptVariable> current,
    List<TemplatePromptVariable> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].name != next[i].name ||
          current[i].isBody != next[i].isBody ||
          current[i].type != next[i].type ||
          !listEquals(current[i].options, next[i].options)) {
        return false;
      }
    }
    return true;
  }

  List<TemplatePromptVariable> _buildVariablesFromControllers() => [
    for (final variable in _variables)
      if (variable.isBody)
        const TemplatePromptVariable(name: templatePromptBodyVariableName)
      else if (variable.isSelect)
        variable
      else
        TemplatePromptVariable(
          name: variable.name,
          defaultValue:
              _variableControllers[variable.name]?.textForSave(trim: true) ??
              '',
          type: variable.type,
        ),
  ];

  void _syncVariableControllers() {
    final activeNames = {
      for (final v in _variables)
        if (!v.isBody && !v.isSelect) v.name,
    };
    for (final name in _variableControllers.keys.toList()) {
      if (!activeNames.contains(name)) {
        _variableControllers.remove(name)?.dispose();
      }
    }
    for (final variable in _variables) {
      if (variable.isBody || variable.isSelect) continue;
      _variableControllers.putIfAbsent(variable.name, () {
        return LongTextEditingController(text: variable.defaultValue)
          ..addListener(_handleVariableValueChanged);
      });
    }
  }

  String _formatDiagnostic(TemplatePromptDiagnostic d) =>
      '第 ${d.location.line} 行第 ${d.location.column} 列：${d.message}';

  String? _validateNumberDefault(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty || int.tryParse(trimmed) == null ? '默认值需为整数' : null;
  }

  TemplatePrompt _buildTemporaryTemplate(
    String content,
    List<TemplatePromptVariable> variables,
  ) => TemplatePrompt(
    id: '',
    title: '',
    content: content,
    variables: variables,
    updatedAt: DateTime(0),
  );

  Future<void> _handleSubmit() async {
    _variableReconcileDebounceTimer?.cancel();
    _runVariableReconcile();
    if (!_compilation.isValid || !validateForm()) return;

    final variables = _buildVariablesFromControllers();
    final definitionCompilation = compileTemplatePromptDefinition(
      _buildTemporaryTemplate(_contentController.text.trim(), variables),
    );
    if (!definitionCompilation.isValid) {
      setState(() => _compilation = definitionCompilation);
      return;
    }

    await submitPageAndClose(
      () => widget.onSubmit(
        TemplatePromptFormData(
          title: _titleController.text.trim(),
          content: _contentController.textForSave(trim: true),
          variables: variables,
        ),
      ),
    );
  }
}
