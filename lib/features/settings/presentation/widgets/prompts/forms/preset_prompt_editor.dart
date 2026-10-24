import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';

import '../../../../domain/models/prompts/preset_prompt.dart';
import '../../shared/settings_editor_list.dart';
import '../../shared/settings_form_dialog_state_mixin.dart';

/// 预设 Prompt 表单提交数据。
class PresetPromptFormData {
  const PresetPromptFormData({
    required this.name,
    required this.messages,
    this.syntax = PresetPromptSyntax.plain,
    this.customReasoningTag = '',
  });

  final String name;
  final List<PromptMessage> messages;
  final PresetPromptSyntax syntax;
  final String customReasoningTag;
}

/// 新增或编辑预设 Prompt 的页面工作区。
class PresetPromptEditor extends StatefulWidget {
  const PresetPromptEditor({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(PresetPromptFormData formData) onSubmit;
  final PresetPrompt? initialValue;

  @override
  State<PresetPromptEditor> createState() => _PresetPromptEditorState();
}

class _PresetPromptEditorState extends State<PresetPromptEditor>
    with
        SettingsFormDialogStateMixin,
        SettingsItemListEditorMixin<PresetPromptEditor, PromptMessage> {
  late final TextEditingController _reasoningTagController = initController(
    widget.initialValue?.customReasoningTag ?? '',
  );
  late PresetPromptSyntax _syntax =
      widget.initialValue?.syntax ?? PresetPromptSyntax.plain;
  final _clearInsertionOrder = <PromptMessagePlacement>{};

  bool get _usesMacros => _syntax == PresetPromptSyntax.sillyTavernSubsetV1;

  @override
  String get initialName => widget.initialValue?.name ?? '';

  @override
  bool get trimItemTitle => !_usesMacros;

  @override
  bool get trimItemContent => !_usesMacros;

  @override
  String itemIdOf(PromptMessage item) => item.id;

  @override
  String itemTitleOf(PromptMessage item) => item.title;

  @override
  String itemContentOf(PromptMessage item) => item.content;

  @override
  PromptMessage copyItemWithText(
    PromptMessage item, {
    required String title,
    required String content,
  }) => item.copyWith(title: title, content: content);

  String _snapshot() {
    syncSelectedItem();
    return jsonEncode([
      nameController.text,
      _reasoningTagController.text,
      _syntax.name,
      (_clearInsertionOrder.map((p) => p.name).toList()..sort()),
      for (final item in items)
        [
          item.id,
          item.role.name,
          item.placement.name,
          item.title,
          item.content,
        ],
    ]);
  }

  @override
  void initState() {
    super.initState();
    final original = widget.initialValue?.messages ?? const <PromptMessage>[];
    initEditorItems(_usesMacros ? original : _groupByPlacement(original));
    captureInitialSnapshot(_snapshot());
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  List<PromptMessage> _groupByPlacement(Iterable<PromptMessage> source) => [
    for (final placement in PromptMessagePlacement.values)
      ...source.where((item) => item.placement == placement),
  ];

  @override
  void moveSelected(int delta) {
    final current = selectedItem;
    if (current == null) return;
    _clearInsertionOrder.add(current.placement);
    super.moveSelected(delta);
  }

  @override
  Widget build(BuildContext context) => buildEditorPage(
    title: widget.initialValue == null ? '新增预设' : '编辑预设',
    targetName: '预设',
    helpText:
        '条目标题仅用于识别。System / User / Assistant 条目均可增删。\n\n'
        '前置消息位于历史之前；最新输入前消息位于历史之后、新输入之前；后置消息位于最后。System 条目以 system 角色发送。\n\n'
        'SillyTavern 有限宏按列表顺序求值启用条目，再按位置注入。支持 setvar / getvar / 文本 addvar、user、lastUserMessage、注释和 trim。导入注入顺序可在上下文中查看；移动条目会恢复该位置的列表顺序。普通文本模式不执行宏。\n\n'
        '自定义 CoT 标签可选填。例如输出使用 <thinking_diy>...</thinking_diy>，只填写 thinking_diy。标签中的内容显示为推理，正文和协议原生推理继续保留。此选项不会自动修改预设内容。',
    width: 1120,
    minExpandedHeight: 500,
    snapshotBuilder: _snapshot,
    onSubmit: _handleSubmit,
    builder: (context, constraints, shouldScroll) => buildMasterDetailSection(
      constraints: constraints,
      shouldScroll: shouldScroll,
      emptyText: '请先选择左侧条目。',
      canMoveUp: _canMoveSelectedUp(),
      canMoveDown: _canMoveSelectedDown(),
      onAdd: _addMessageItem,
      onDeleteSelected: selectedItem != null
          ? () => setState(removeSelected)
          : null,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField.form(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '预设 Prompt 名称',
                    hintText: '例如：代码审阅助手',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _buildSyntaxField()),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField.form(
            controller: _reasoningTagController,
            decoration: const InputDecoration(
              labelText: '自定义 CoT 标签（可选）',
              hintText: 'thinking_diy',
            ),
            validator: (value) =>
                PresetPrompt.isValidReasoningTag(value?.trim() ?? '')
                ? null
                : '只填写标签名，不包含空格、尖括号、斜杠、引号或等号',
          ),
          const SizedBox(height: 8),
        ],
      ),
      detailBuilder: (_, selected, {required isWide, required expandContent}) =>
          _buildDetail(selected, isWide: isWide, expandContent: expandContent),
    ),
  );

  Widget _buildSyntaxField() => AppDropdownField<PresetPromptSyntax>(
    initialValue: _syntax,
    isExpanded: true,
    decoration: const InputDecoration(labelText: '模板语法'),
    items: const [
      DropdownMenuItem(value: PresetPromptSyntax.plain, child: Text('普通文本')),
      DropdownMenuItem(
        value: PresetPromptSyntax.sillyTavernSubsetV1,
        child: Text('SillyTavern 有限宏'),
      ),
    ],
    onChanged: (value) {
      if (value == null) return;
      setState(() {
        syncSelectedItem();
        final selectedId = selectedItem?.id;
        _syntax = value;
        if (!_usesMacros) {
          final grouped = _groupByPlacement(items);
          items
            ..clear()
            ..addAll(grouped);
          if (selectedId != null) {
            selectedIndex = items.indexWhere((item) => item.id == selectedId);
          }
        }
      });
    },
  );

  Widget _buildDetail(
    PromptMessage selected, {
    required bool isWide,
    required bool expandContent,
  }) {
    final titleField = AppTextField.form(
      controller: itemTitleController,
      decoration: const InputDecoration(
        labelText: '标题',
        hintText: '例如：前置约束、最新输入前提醒、后置收尾说明',
      ),
    );
    final roleField = AppDropdownField<PromptMessageRole>(
      fillWidth: true,
      initialValue: selected.role,
      decoration: const InputDecoration(labelText: '角色'),
      items: const [
        DropdownMenuItem(
          value: PromptMessageRole.system,
          child: Text('System'),
        ),
        DropdownMenuItem(value: PromptMessageRole.user, child: Text('User')),
        DropdownMenuItem(
          value: PromptMessageRole.assistant,
          child: Text('Assistant'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          syncSelectedItem();
          items[selectedIndex] = items[selectedIndex].copyWith(role: value);
        });
      },
    );
    final placementField = AppDropdownField<PromptMessagePlacement>(
      fillWidth: true,
      initialValue: selected.placement,
      decoration: const InputDecoration(labelText: '位置'),
      items: [
        for (final placement in PromptMessagePlacement.values)
          DropdownMenuItem(
            value: placement,
            child: Text(switch (placement) {
              PromptMessagePlacement.before => '前置',
              PromptMessagePlacement.beforeLatestInput => '最新输入前',
              PromptMessagePlacement.after => '后置',
            }),
          ),
      ],
      onChanged: (value) {
        if (value != null) _changeSelectedPlacement(value);
      },
    );
    return Column(
      mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: titleField),
              const SizedBox(width: 12),
              Expanded(child: roleField),
              const SizedBox(width: 12),
              Expanded(child: placementField),
            ],
          )
        else ...[
          titleField,
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: roleField),
              const SizedBox(width: 12),
              Expanded(child: placementField),
            ],
          ),
        ],
        const SizedBox(height: 8),
        SettingsExpandedTextField(
          controller: itemContentController,
          expand: expandContent,
          decoration: const InputDecoration(
            labelText: 'Prompt 内容',
            hintText: '输入这一条预设 Prompt 的具体内容。',
          ),
        ),
      ],
    );
  }

  void _addMessageItem() {
    syncSelectedItem();
    final selected = selectedItem;
    final placement = selected?.placement ?? PromptMessagePlacement.before;
    final sequence =
        items
            .where(
              (i) =>
                  i.placement == placement && i.role == PromptMessageRole.user,
            )
            .length +
        1;
    final insertAt = selected == null
        ? _insertIndexForPlacement(placement)
        : selectedIndex + 1;
    setState(() {
      _clearInsertionOrder.add(placement);
      insertItem(
        PromptMessage(
          id: generateEntityId(),
          role: PromptMessageRole.user,
          placement: placement,
          title: buildPresetPromptMessageFallbackTitle(
            role: PromptMessageRole.user,
            placement: placement,
            sequence: sequence,
          ),
          content: '',
        ),
        at: insertAt,
      );
    });
  }

  void _changeSelectedPlacement(PromptMessagePlacement placement) {
    if (selectedIndex < 0) return;
    setState(() {
      syncSelectedItem();
      _clearInsertionOrder.addAll([items[selectedIndex].placement, placement]);
      if (_usesMacros) {
        items[selectedIndex] = items[selectedIndex].copyWith(
          placement: placement,
        );
        return;
      }
      final current = items
          .removeAt(selectedIndex)
          .copyWith(placement: placement);
      final targetIndex = _insertIndexForPlacement(placement);
      items.insert(targetIndex, current);
      selectedIndex = targetIndex;
    });
  }

  int _insertIndexForPlacement(PromptMessagePlacement placement) =>
      switch (placement) {
        PromptMessagePlacement.before => _firstIndexOf(
          PromptMessagePlacement.beforeLatestInput,
        ),
        PromptMessagePlacement.beforeLatestInput => _firstIndexOf(
          PromptMessagePlacement.after,
        ),
        PromptMessagePlacement.after => items.length,
      };

  int _firstIndexOf(PromptMessagePlacement placement) {
    final index = items.indexWhere((item) => item.placement == placement);
    if (index != -1) return index;
    return placement == PromptMessagePlacement.beforeLatestInput
        ? _firstIndexOf(PromptMessagePlacement.after)
        : items.length;
  }

  int _lastIndexOf(PromptMessagePlacement placement) {
    final index = items.lastIndexWhere((item) => item.placement == placement);
    return index < 0 ? 0 : index;
  }

  bool _canMoveSelectedUp() {
    if (selectedIndex < 0) return false;
    if (_usesMacros) return selectedIndex > 0;
    return switch (items[selectedIndex].placement) {
      PromptMessagePlacement.before => selectedIndex > 0,
      PromptMessagePlacement.beforeLatestInput =>
        selectedIndex > _firstIndexOf(PromptMessagePlacement.beforeLatestInput),
      PromptMessagePlacement.after =>
        selectedIndex > _firstIndexOf(PromptMessagePlacement.after),
    };
  }

  bool _canMoveSelectedDown() {
    if (selectedIndex < 0) return false;
    if (_usesMacros) return selectedIndex < items.length - 1;
    return switch (items[selectedIndex].placement) {
      PromptMessagePlacement.before =>
        selectedIndex < _lastIndexOf(PromptMessagePlacement.before),
      PromptMessagePlacement.beforeLatestInput =>
        selectedIndex < _lastIndexOf(PromptMessagePlacement.beforeLatestInput),
      PromptMessagePlacement.after => selectedIndex < items.length - 1,
    };
  }

  Future<void> _handleSubmit() async {
    syncSelectedItem();
    if (!validateForm()) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showFormSnackBar('请填写预设 Prompt 名称');
      return;
    }
    for (var i = 0; i < items.length; i++) {
      if (!_usesMacros && items[i].title.trim().isEmpty) {
        setState(() => selectItem(i));
        showFormSnackBar('请填写每条预设 Prompt 的标题');
        return;
      }
    }
    final messages = [
      for (final item in items)
        item.copyWith(
          title: _usesMacros ? item.title : item.title.trim(),
          clearImportInsertionOrder: _clearInsertionOrder.contains(
            item.placement,
          ),
        ),
    ];
    await submitPageAndClose(
      () => widget.onSubmit(
        PresetPromptFormData(
          name: name,
          messages: messages,
          syntax: _syntax,
          customReasoningTag: _reasoningTagController.text.trim(),
        ),
      ),
    );
  }
}
