import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/template_prompt.dart';
import '../../domain/template_prompt_parser.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

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
class _TemplatePromptFormDialogState extends State<TemplatePromptFormDialog>
    with SettingsFormDialogStateMixin {
  static const _largeContentThreshold = 6000;
  static const _variableReconcileDebounce = Duration(milliseconds: 220);
  static const _variableReconcileThrottle = Duration(milliseconds: 80);
  static const _variableReconcileDebounceForLargeContent = Duration(
    milliseconds: 320,
  );
  static const _variableReconcileThrottleForLargeContent = Duration(
    milliseconds: 140,
  );

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final Map<String, TextEditingController> _variableControllers = {};
  late List<TemplatePromptVariable> _variables;
  Timer? _variableReconcileDebounceTimer;
  Timer? _variableReconcileThrottleTimer;
  DateTime? _lastVariableReconcileAt;
  String _pendingContent = '';
  String _lastReconciledContent = '';

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
    _pendingContent = _contentController.text;
    _lastReconciledContent = _contentController.text;
    _syncVariableControllers();
    _contentController.addListener(_handleContentChanged);
  }

  @override
  void dispose() {
    _variableReconcileDebounceTimer?.cancel();
    _variableReconcileThrottleTimer?.cancel();
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
      formKey: formKey,
      isSaving: isSaving,
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

  /// 对模板变量重算做“节流 + 防抖”双调度，减少高频输入卡顿。
  void _scheduleVariableReconcile() {
    final debounceWindow = _resolveDebounceWindow(_pendingContent.length);
    final throttleWindow = _resolveThrottleWindow(_pendingContent.length);
    final now = DateTime.now();
    final last = _lastVariableReconcileAt;
    final canRunLeading =
        last == null || now.difference(last) >= throttleWindow;
    if (canRunLeading) {
      _variableReconcileThrottleTimer?.cancel();
      _runVariableReconcile();
    } else if (!(_variableReconcileThrottleTimer?.isActive ?? false)) {
      final remaining = throttleWindow - now.difference(last);
      _variableReconcileThrottleTimer = Timer(remaining, _runVariableReconcile);
    }

    _variableReconcileDebounceTimer?.cancel();
    _variableReconcileDebounceTimer = Timer(
      debounceWindow,
      _runVariableReconcile,
    );
  }

  void _flushVariableReconcile() {
    _variableReconcileDebounceTimer?.cancel();
    _variableReconcileThrottleTimer?.cancel();
    _runVariableReconcile(force: true);
  }

  void _runVariableReconcile({bool force = false}) {
    final nextContent = _pendingContent;
    if (!force && nextContent == _lastReconciledContent) {
      return;
    }
    _lastReconciledContent = nextContent;
    _lastVariableReconcileAt = DateTime.now();

    final nextVariables = reconcileTemplatePromptVariables(
      content: nextContent,
      existingVariables: _buildVariablesFromControllers(),
    );
    if (_sameVariableShape(_variables, nextVariables)) {
      return;
    }

    setState(() {
      _variables = nextVariables;
      _syncVariableControllers();
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
          current[index].isBody != next[index].isBody) {
        return false;
      }
    }
    return true;
  }

  Duration _resolveDebounceWindow(int contentLength) {
    return contentLength > _largeContentThreshold
        ? _variableReconcileDebounceForLargeContent
        : _variableReconcileDebounce;
  }

  Duration _resolveThrottleWindow(int contentLength) {
    return contentLength > _largeContentThreshold
        ? _variableReconcileThrottleForLargeContent
        : _variableReconcileThrottle;
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
    _flushVariableReconcile();
    if (!validateForm()) {
      return;
    }

    final variables = _buildVariablesFromControllers();
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
