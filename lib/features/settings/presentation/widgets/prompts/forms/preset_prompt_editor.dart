import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';

import '../../../../domain/models/prompts/preset_prompt.dart';
import '../../shared/settings_form_dialog_scaffold.dart';
import '../../shared/settings_form_dialog_state_mixin.dart';
import 'editable_preset_prompt_item.dart';
import 'preset_prompt_editor_role.dart';
import 'preset_prompt_list_tile.dart';

/// 预设 Prompt 表单提交数据。
class PresetPromptFormData {
  const PresetPromptFormData({
    required this.name,
    required this.messages,
    this.syntax = PresetPromptSyntax.plain,
  });

  final String name;
  final List<PromptMessage> messages;
  final PresetPromptSyntax syntax;
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

/// 预设 Prompt 表单的输入与选中状态。
class _PresetPromptEditorState extends State<PresetPromptEditor>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final List<EditablePresetPromptItem> _items;
  String? _selectedItemId;
  late PresetPromptSyntax _syntax;
  late String _initialSnapshot;
  bool _leaveAllowed = false;
  bool _confirmingLeave = false;
  String? _saveError;
  String get _snapshot => jsonEncode([
    _nameController.text,
    _syntax.name,
    (_clearInsertionOrder.map((placement) => placement.name).toList()..sort()),
    for (final item in _items)
      [
        item.id,
        item.role.name,
        item.placement?.name,
        item.titleController.text,
        item.contentController.text,
      ],
  ]);

  Future<void> _requestLeave() async {
    if (isSaving || _confirmingLeave) return;
    _confirmingLeave = true;
    final leave =
        _snapshot == _initialSnapshot ||
        await showDialog<bool>(
              context: context,
              builder: (_) => const AppConfirmDialog(
                title: '放弃未保存的修改？',
                message: '返回后，本次对预设的修改将丢失。',
                confirmLabel: '放弃修改',
                isDestructive: true,
              ),
            ) ==
            true;
    _confirmingLeave = false;
    if (!mounted || !leave) return;
    setState(() => _leaveAllowed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  final _clearInsertionOrder = <PromptMessagePlacement>{};
  bool get _usesMacros => _syntax == PresetPromptSyntax.sillyTavernSubsetV1;

  @override
  void initState() {
    super.initState();
    _nameController = initController(widget.initialValue?.name ?? '');
    _syntax = widget.initialValue?.syntax ?? PresetPromptSyntax.plain;
    _items = _buildInitialItems(widget.initialValue);
    _selectedItemId = _items.isEmpty ? null : _items.first.id;
    _initialSnapshot = _snapshot;
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.titleController.dispose();
      item.contentController.dispose();
    }
    disposeAllControllers();
    super.dispose();
  }

  @override
  /// 构建预设 Prompt 的主从式编辑器。
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return PopScope<void>(
      canPop: _leaveAllowed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestLeave();
      },
      child: SettingsFormDialogScaffold(
        fullPage: true,
        title: isEditing ? '编辑预设' : '新增预设',
        helpText:
            '条目标题仅用于识别。System / User / Assistant 条目均可增删。\n\n'
            '前置消息位于历史之前；最新输入前消息位于历史之后、新输入之前；后置消息位于最后。System 条目以 system 角色发送。\n\n'
            'SillyTavern 有限宏按列表顺序求值启用条目，再按位置注入。支持 setvar / getvar / 文本 addvar、user、lastUserMessage、注释和 trim。导入注入顺序可在上下文中查看；移动条目会恢复该位置的列表顺序。普通文本模式不执行宏。',
        formKey: formKey,
        isSaving: isSaving,
        onSubmit: _handleSubmit,
        width: 1120,
        shouldScrollContent: (constraints) =>
            constraints.maxWidth < AppBreakpoints.formMasterDetail,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final header = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saveError != null)
                  Text(
                    _saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildNameField()),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildSyntaxField()),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
              ],
            );
            if (constraints.maxWidth < AppBreakpoints.formMasterDetail) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, _buildCompactLayout(context)],
              );
            }
            return SizedBox(
              height: constraints.maxHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 280,
                    child: _buildWideMasterPane(context: context),
                  ),
                  const VerticalDivider(width: 33),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        Expanded(
                          child: _buildDetailContent(context, isWide: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildCompactItemSelector(context)),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _addMessageItem,
              tooltip: '新增条目',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: _canMoveSelectedUp() ? () => _moveSelected(-1) : null,
              tooltip: '上移',
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              onPressed: _canMoveSelectedDown() ? () => _moveSelected(1) : null,
              tooltip: '下移',
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ],
        ),
        const Divider(height: 24),
        _buildDetailContent(context, isWide: false),
      ],
    );
  }

  Widget _buildWideMasterPane({required BuildContext context}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMasterHeader(context),
        const SizedBox(height: 16),
        Expanded(child: _buildMasterListView()),
      ],
    );
  }

  Widget _buildMasterHeader(BuildContext context) {
    final canMoveUp = _canMoveSelectedUp();
    final canMoveDown = _canMoveSelectedDown();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '条目 ${_items.length}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _addMessageItem,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新增条目'),
            ),
            IconButton.outlined(
              onPressed: canMoveUp ? () => _moveSelected(-1) : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: '上移',
            ),
            IconButton.outlined(
              onPressed: canMoveDown ? () => _moveSelected(1) : null,
              icon: const Icon(Icons.arrow_downward_rounded),
              tooltip: '下移',
            ),
          ],
        ),
      ],
    );
  }

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
      if (value != null) {
        setState(() {
          _syntax = value;
          if (!_usesMacros) {
            final grouped = [
              for (final placement in PromptMessagePlacement.values)
                ..._items.where((item) => item.placement == placement),
            ];
            _items
              ..clear()
              ..addAll(grouped);
          }
        });
      }
    },
  );

  Widget _buildMasterListView() {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _buildMasterListTile(index, _selectedIndex);
      },
    );
  }

  /// 紧凑模式下用下拉菜单替代条目列表，节省垂直空间，
  /// 避免用户编辑正文前需要滚动经过所有条目标题。
  Widget _buildCompactItemSelector(BuildContext context) {
    return AppDropdownField<int>(
      key: ValueKey('compact-item-selector-$_selectedItemId'),
      initialValue: _selectedIndex,
      isExpanded: true,
      items: [
        for (var index = 0; index < _items.length; index++)
          DropdownMenuItem(
            value: index,
            child: Text(
              '${index + 1}. ${_buildCompactItemTitle(_items[index])}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedItemId = _items[value].id;
          });
        }
      },
      decoration: const InputDecoration(labelText: '选择条目'),
    );
  }

  /// 构建条目标题，空标题时使用 fallback。
  String _buildCompactItemTitle(EditablePresetPromptItem item) {
    final title = item.titleController.text.trim();
    return title.isNotEmpty ? title : '未命名条目';
  }

  Widget _buildMasterListTile(int index, int selectedIndex) {
    return PresetPromptListTile(
      item: _items[index],
      isSelected: index == selectedIndex,
      onTap: () {
        setState(() {
          _selectedItemId = _items[index].id;
        });
      },
    );
  }

  Widget _buildDetailContent(BuildContext context, {required bool isWide}) {
    final selected = _selectedItem;
    if (selected == null) {
      return const Text('请先选择左侧条目。');
    }

    final contentField = TextField(
      key: const ValueKey('preset-prompt-content-field'), // test-key
      controller: selected.contentController,
      minLines: isWide ? null : 8,
      maxLines: isWide ? null : 16,
      expands: isWide,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        labelText: 'Prompt 内容',
        hintText: '输入这一条预设 Prompt 的具体内容。',
      ),
    );

    final fields = <Widget>[
      TextFormField(
        key: const ValueKey('preset-prompt-title-field'), // test-key
        controller: selected.titleController,
        decoration: const InputDecoration(
          labelText: '标题',
          hintText: '例如：前置约束、最新输入前提醒、后置收尾说明',
        ),
      ),
      AppDropdownField<PresetPromptEditorRole>(
        key: const ValueKey('preset-prompt-role-field'), // test-key
        initialValue: selected.role,
        items: const [
          DropdownMenuItem(
            value: PresetPromptEditorRole.system,
            child: Text('System'),
          ),
          DropdownMenuItem(
            value: PresetPromptEditorRole.user,
            child: Text('User'),
          ),
          DropdownMenuItem(
            value: PresetPromptEditorRole.assistant,
            child: Text('Assistant'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _replaceSelected(selected.copyWith(role: value));
            });
          }
        },
        decoration: const InputDecoration(labelText: '角色'),
      ),
      AppDropdownField<PromptMessagePlacement>(
        key: const ValueKey('preset-prompt-placement-field'), // test-key
        initialValue: selected.placement,
        items: PromptMessagePlacement.values
            .map((placement) {
              return DropdownMenuItem(
                value: placement,
                child: Text(switch (placement) {
                  PromptMessagePlacement.before => '前置',
                  PromptMessagePlacement.beforeLatestInput => '最新输入前',
                  PromptMessagePlacement.after => '后置',
                }),
              );
            })
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) {
            _changeSelectedPlacement(value);
          }
        },
        decoration: const InputDecoration(labelText: '位置'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: fields[0]),
              const SizedBox(width: 12),
              Expanded(child: fields[1]),
              const SizedBox(width: 12),
              Expanded(child: fields[2]),
            ],
          )
        else ...[
          fields[0],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[1]),
              const SizedBox(width: 12),
              Expanded(child: fields[2]),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (isWide) Expanded(child: contentField) else contentField,
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _removeSelectedItem(),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除当前条目'),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      key: const ValueKey('preset-prompt-name-field'), // test-key
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '预设 Prompt 名称',
        hintText: '例如：代码审阅助手',
      ),
    );
  }

  List<EditablePresetPromptItem> _buildInitialItems(PresetPrompt? template) {
    final original = template?.messages ?? const <PromptMessage>[];
    final ordered = _usesMacros
        ? original
        : original
              .where(
                (message) => message.placement == PromptMessagePlacement.before,
              )
              .followedBy(
                (template?.messages ?? const <PromptMessage>[]).where(
                  (message) =>
                      message.placement ==
                      PromptMessagePlacement.beforeLatestInput,
                ),
              )
              .followedBy(
                (template?.messages ?? const <PromptMessage>[]).where(
                  (message) =>
                      message.placement == PromptMessagePlacement.after,
                ),
              );
    return ordered
        .map((message) {
          return EditablePresetPromptItem(
            id: message.id,
            role: switch (message.role) {
              PromptMessageRole.system => PresetPromptEditorRole.system,
              PromptMessageRole.user => PresetPromptEditorRole.user,
              PromptMessageRole.assistant => PresetPromptEditorRole.assistant,
            },
            placement: message.placement,
            titleController: TextEditingController(text: message.title),
            contentController: LongTextEditingController(text: message.content),
          );
        })
        .toList(growable: true);
  }

  EditablePresetPromptItem? get _selectedItem {
    final selectedItemId = _selectedItemId;
    if (selectedItemId == null) {
      return null;
    }
    for (final item in _items) {
      if (item.id == selectedItemId) {
        return item;
      }
    }
    return null;
  }

  int get _selectedIndex {
    final selectedItemId = _selectedItemId;
    if (selectedItemId == null) {
      return -1;
    }
    return _items.indexWhere((item) => item.id == selectedItemId);
  }

  PromptMessagePlacement _resolveNewItemPlacement(
    EditablePresetPromptItem? selected,
  ) {
    if (selected == null) {
      return PromptMessagePlacement.before;
    }
    return selected.placement ?? PromptMessagePlacement.before;
  }

  int _resolveNewItemInsertIndex({
    required EditablePresetPromptItem? selected,
    required PromptMessagePlacement placement,
  }) {
    final selectedIndex = _selectedIndex;
    if (selected == null || selectedIndex < 0) {
      return switch (placement) {
        PromptMessagePlacement.before => _firstBeforeLatestInputIndex,
        PromptMessagePlacement.beforeLatestInput => _firstAfterIndex,
        PromptMessagePlacement.after => _items.length,
      };
    }
    return selectedIndex + 1;
  }

  void _addMessageItem() {
    final selected = _selectedItem;
    final placement = _resolveNewItemPlacement(selected);
    final newItem = EditablePresetPromptItem(
      id: generateEntityId(),
      role: PresetPromptEditorRole.user,
      placement: placement,
      titleController: TextEditingController(
        text: _buildNextGeneratedTitle(
          role: PromptMessageRole.user,
          placement: placement,
        ),
      ),
      contentController: LongTextEditingController(),
    );

    setState(() {
      final insertIndex = _resolveNewItemInsertIndex(
        selected: selected,
        placement: placement,
      );
      _items.insert(insertIndex, newItem);
      _clearInsertionOrder.add(placement);
      _selectedItemId = newItem.id;
    });
  }

  void _removeSelectedItem() {
    final index = _selectedIndex;
    if (index < 0) {
      return;
    }

    setState(() {
      final removed = _items.removeAt(index);
      removed.titleController.dispose();
      removed.contentController.dispose();
      if (_items.isEmpty) {
        _selectedItemId = null;
        return;
      }
      _selectedItemId = _items[index > 0 ? index - 1 : 0].id;
    });
  }

  bool _canMoveSelectedUp() {
    final index = _selectedIndex;
    if (index < 0) {
      return false;
    }
    if (_usesMacros) return index > 0;
    final selected = _items[index];
    return switch (selected.placement!) {
      PromptMessagePlacement.before => index > 0,
      PromptMessagePlacement.beforeLatestInput =>
        index > _firstBeforeLatestInputIndex,
      PromptMessagePlacement.after => index > _firstAfterIndex,
    };
  }

  bool _canMoveSelectedDown() {
    final index = _selectedIndex;
    if (index < 0) {
      return false;
    }
    if (_usesMacros) return index < _items.length - 1;
    final selected = _items[index];
    return switch (selected.placement!) {
      PromptMessagePlacement.before => index < _lastBeforeIndex,
      PromptMessagePlacement.beforeLatestInput =>
        index < _lastBeforeLatestInputIndex,
      PromptMessagePlacement.after => index < _items.length - 1,
    };
  }

  void _moveSelected(int delta) {
    final index = _selectedIndex;
    if (index < 0) {
      return;
    }

    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _items.length) {
      return;
    }

    final current = _items[index];
    final target = _items[nextIndex];
    if (!_usesMacros && current.placement != target.placement) {
      return;
    }

    setState(() {
      _clearInsertionOrder.add(current.placement!);
      _items[index] = target;
      _items[nextIndex] = current;
      _selectedItemId = current.id;
    });
  }

  void _changeSelectedPlacement(PromptMessagePlacement placement) {
    final index = _selectedIndex;
    if (index < 0) {
      return;
    }

    setState(() {
      _clearInsertionOrder.addAll([_items[index].placement!, placement]);
      if (_usesMacros) {
        _items[index] = _items[index].copyWith(placement: placement);
        return;
      }
      final current = _items.removeAt(index).copyWith(placement: placement);
      final insertIndex = switch (placement) {
        PromptMessagePlacement.before =>
          _firstBeforeLatestInputIndexAfterRemoval,
        PromptMessagePlacement.beforeLatestInput =>
          _firstAfterIndexAfterRemoval,
        PromptMessagePlacement.after => _items.length,
      };
      _items.insert(insertIndex, current);
      _selectedItemId = current.id;
    });
  }

  void _replaceSelected(EditablePresetPromptItem item) {
    final index = _selectedIndex;
    if (index < 0) {
      return;
    }
    _items[index] = item;
  }

  int get _firstBeforeLatestInputIndex {
    final index = _items.indexWhere(
      (item) => item.placement == PromptMessagePlacement.beforeLatestInput,
    );
    return index == -1 ? _firstAfterIndex : index;
  }

  int get _firstAfterIndex {
    final index = _items.indexWhere(
      (item) => item.placement == PromptMessagePlacement.after,
    );
    return index == -1 ? _items.length : index;
  }

  int get _firstBeforeLatestInputIndexAfterRemoval {
    final index = _items.indexWhere(
      (item) => item.placement == PromptMessagePlacement.beforeLatestInput,
    );
    return index == -1 ? _firstAfterIndexAfterRemoval : index;
  }

  int get _firstAfterIndexAfterRemoval {
    final index = _items.indexWhere(
      (item) => item.placement == PromptMessagePlacement.after,
    );
    return index == -1 ? _items.length : index;
  }

  int get _lastBeforeIndex {
    final index = _items.lastIndexWhere(
      (item) => item.placement == PromptMessagePlacement.before,
    );
    return index < 0 ? 0 : index;
  }

  int get _lastBeforeLatestInputIndex {
    final index = _items.lastIndexWhere(
      (item) => item.placement == PromptMessagePlacement.beforeLatestInput,
    );
    return index < 0 ? 0 : index;
  }

  String _buildNextGeneratedTitle({
    required PromptMessageRole role,
    required PromptMessagePlacement placement,
  }) {
    final nextIndex =
        _items
            .where(
              (item) =>
                  item.placement == placement &&
                  item.role == _toEditorRole(role),
            )
            .length +
        1;
    return buildPresetPromptMessageFallbackTitle(
      role: role,
      placement: placement,
      sequence: nextIndex,
    );
  }

  PresetPromptEditorRole _toEditorRole(PromptMessageRole role) {
    return switch (role) {
      PromptMessageRole.system => PresetPromptEditorRole.system,
      PromptMessageRole.user => PresetPromptEditorRole.user,
      PromptMessageRole.assistant => PresetPromptEditorRole.assistant,
    };
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showFormSnackBar('请填写预设 Prompt 名称');
      return;
    }

    for (final item in _items) {
      if (!_usesMacros && item.titleController.text.trim().isEmpty) {
        _selectedItemId = item.id;
        setState(() {});
        showFormSnackBar('请填写每条预设 Prompt 的标题');
        return;
      }
    }
    // 保留原始消息的 enabled 状态，防止设置页编辑后丢失聊天页的开关设置
    final originalEnabledById = <String, bool>{};
    if (widget.initialValue != null) {
      for (final m in widget.initialValue!.messages) {
        originalEnabledById[m.id] = m.enabled;
      }
    }

    final messages = _items
        .map((item) {
          final original = widget.initialValue?.messages
              .where((m) => m.id == item.id)
              .firstOrNull;
          return PromptMessage(
            id: item.id,
            role: switch (item.role) {
              PresetPromptEditorRole.system => PromptMessageRole.system,
              PresetPromptEditorRole.user => PromptMessageRole.user,
              PresetPromptEditorRole.assistant => PromptMessageRole.assistant,
            },
            title: _usesMacros
                ? item.titleController.text
                : item.titleController.text.trim(),
            content: item.contentController.textForSave(trim: !_usesMacros),
            placement: item.placement ?? PromptMessagePlacement.before,
            enabled: originalEnabledById[item.id] ?? true,
            sourceIdentifier: original?.sourceIdentifier,
            importInsertionOrder: _clearInsertionOrder.contains(item.placement)
                ? null
                : original?.importInsertionOrder,
          );
        })
        .toList(growable: false);

    try {
      await submitAndClose(() async {
        await widget.onSubmit(
          PresetPromptFormData(name: name, messages: messages, syntax: _syntax),
        );
        if (mounted) {
          setState(() => _leaveAllowed = true);
          await WidgetsBinding.instance.endOfFrame;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _saveError = '保存失败：$error');
    }
  }
}
