import 'package:flutter/material.dart';

import '../../../../../core/utils/id_generator.dart';
import '../../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../../domain/models/prompt_template.dart';
import '../settings_form_dialog_scaffold.dart';
import '../settings_form_dialog_state_mixin.dart';
import 'editable_preset_prompt_item.dart';
import 'preset_prompt_editor_role.dart';
import 'preset_prompt_list_tile.dart';

/// 预设 Prompt 表单提交数据。
class PromptTemplateFormData {
  const PromptTemplateFormData({required this.name, required this.messages});

  final String name;
  final List<PromptMessage> messages;
}

/// 新增或编辑预设 Prompt 的对话框。
class PromptTemplateFormDialog extends StatefulWidget {
  const PromptTemplateFormDialog({
    required this.onSubmit,
    this.initialValue,
    super.key,
  });

  final Future<void> Function(PromptTemplateFormData formData) onSubmit;
  final PromptTemplate? initialValue;

  @override
  State<PromptTemplateFormDialog> createState() =>
      _PromptTemplateFormDialogState();
}

/// 预设 Prompt 表单的输入与选中状态。
class _PromptTemplateFormDialogState extends State<PromptTemplateFormDialog>
    with SettingsFormDialogStateMixin {
  late final TextEditingController _nameController;
  late final List<EditablePresetPromptItem> _items;
  String? _selectedItemId;

  @override
  void initState() {
    super.initState();
    _nameController = initController(widget.initialValue?.name ?? '');
    _items = _buildInitialItems(widget.initialValue);
    _selectedItemId = _items.isEmpty ? null : _items.first.id;
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
    const masterDetailBreakpoint = 900.0;

    return SettingsFormDialogScaffold(
      title: isEditing ? '编辑预设 Prompt' : '新增预设 Prompt',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _handleSubmit,
      width: 1120,
      shouldScrollContent: (constraints) =>
          constraints.maxWidth < masterDetailBreakpoint,
      child: AdaptiveMasterDetailLayout(
        key: const ValueKey('preset-prompt-form-layout'),
        breakpoint: masterDetailBreakpoint,
        masterWidth: 340,
        minHeight: 620,
        compactChild: _buildCompactLayout(context),
        master: _buildWideMasterPane(
          context: context,
          key: const ValueKey('preset-prompt-master-pane'),
        ),
        detail: _buildWidePane(
          context: context,
          key: const ValueKey('preset-prompt-detail-pane'),
          child: _buildDetailContent(context, isWide: true),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMasterContent(context),
        const SizedBox(height: 16),
        _buildCompactPane(
          context: context,
          key: const ValueKey('preset-prompt-detail-pane'),
          child: _buildDetailContent(context, isWide: false),
        ),
      ],
    );
  }

  Widget _buildWidePane({
    required BuildContext context,
    required Widget child,
    required Key key,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildWideMasterPane({
    required BuildContext context,
    required Key key,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMasterHeader(context),
            const SizedBox(height: 16),
            Expanded(child: _buildMasterListView()),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPane({
    required BuildContext context,
    required Widget child,
    required Key key,
  }) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildMasterContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMasterHeader(context),
        const SizedBox(height: 16),
        _buildMasterListContent(),
      ],
    );
  }

  Widget _buildMasterHeader(BuildContext context) {
    final canMoveUp = _canMoveSelectedUp();
    final canMoveDown = _canMoveSelectedDown();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('预设 Prompt 条目', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildNameField(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _addMessageItem,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('新增条目'),
            ),
            OutlinedButton.icon(
              onPressed: canMoveUp ? () => _moveSelected(-1) : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              label: const Text('上移'),
            ),
            OutlinedButton.icon(
              onPressed: canMoveDown ? () => _moveSelected(1) : null,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const Text('下移'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '左侧仅显示条目标题；system / user / assistant 都可自由增删，后置消息始终排在前置消息之后。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

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

  Widget _buildMasterListContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < _items.length; index++) ...[
          _buildMasterListTile(index, _selectedIndex),
          if (index != _items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
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

    final titleLabel = switch (selected.role) {
      PresetPromptEditorRole.system => 'System 条目',
      PresetPromptEditorRole.user => 'User 条目',
      PresetPromptEditorRole.assistant => 'Assistant 条目',
    };
    final contentField = TextField(
      key: const ValueKey('preset-prompt-content-field'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleLabel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '这里可以编辑标题、角色、位置和 Prompt 内容。system 条目会以 system 消息发送给模型。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const ValueKey('preset-prompt-title-field'),
          controller: selected.titleController,
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '例如：前置约束、后置收尾说明',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PresetPromptEditorRole>(
          key: const ValueKey('preset-prompt-role-field'),
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
        const SizedBox(height: 12),
        DropdownButtonFormField<PromptMessagePlacement>(
          key: const ValueKey('preset-prompt-placement-field'),
          initialValue: selected.placement,
          items: PromptMessagePlacement.values
              .map((placement) {
                return DropdownMenuItem(
                  value: placement,
                  child: Text(switch (placement) {
                    PromptMessagePlacement.before => '前置',
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
        const SizedBox(height: 12),
        if (isWide) Expanded(child: contentField) else contentField,
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
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
      key: const ValueKey('preset-prompt-name-field'),
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '预设 Prompt 名称',
        hintText: '例如：代码审阅助手',
      ),
    );
  }

  List<EditablePresetPromptItem> _buildInitialItems(PromptTemplate? template) {
    return (template?.messages ?? const <PromptMessage>[])
        .where((message) => message.placement == PromptMessagePlacement.before)
        .followedBy(
          (template?.messages ?? const <PromptMessage>[]).where(
            (message) => message.placement == PromptMessagePlacement.after,
          ),
        )
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
            contentController: TextEditingController(text: message.content),
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
      return placement == PromptMessagePlacement.before
          ? _firstAfterIndex
          : _items.length;
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
      contentController: TextEditingController(),
    );

    setState(() {
      final insertIndex = _resolveNewItemInsertIndex(
        selected: selected,
        placement: placement,
      );
      _items.insert(insertIndex, newItem);
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
    final selected = _items[index];
    if (selected.placement == PromptMessagePlacement.before) {
      return index > 0;
    }
    return index > _firstAfterIndex;
  }

  bool _canMoveSelectedDown() {
    final index = _selectedIndex;
    if (index < 0) {
      return false;
    }
    final selected = _items[index];
    if (selected.placement == PromptMessagePlacement.before) {
      return index < _lastBeforeIndex;
    }
    return index < _items.length - 1;
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
    if (current.placement != target.placement) {
      return;
    }

    setState(() {
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
      final current = _items.removeAt(index).copyWith(placement: placement);
      if (placement == PromptMessagePlacement.before) {
        final insertIndex = _firstAfterIndexAfterRemoval;
        _items.insert(insertIndex, current);
      } else {
        _items.add(current);
      }
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

  int get _firstAfterIndex {
    final index = _items.indexWhere(
      (item) => item.placement == PromptMessagePlacement.after,
    );
    return index == -1 ? _items.length : index;
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
    return index <= 0 ? 0 : index;
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
      if (item.titleController.text.trim().isEmpty) {
        _selectedItemId = item.id;
        setState(() {});
        showFormSnackBar('请填写每条预设 Prompt 的标题');
        return;
      }
      if (item.contentController.text.trim().isEmpty) {
        _selectedItemId = item.id;
        setState(() {});
        showFormSnackBar('请填写每条预设 Prompt 的内容');
        return;
      }
    }
    final messages = _items
        .map((item) {
          return PromptMessage(
            id: item.id,
            role: switch (item.role) {
              PresetPromptEditorRole.system => PromptMessageRole.system,
              PresetPromptEditorRole.user => PromptMessageRole.user,
              PresetPromptEditorRole.assistant => PromptMessageRole.assistant,
            },
            title: item.titleController.text.trim(),
            content: item.contentController.text.trim(),
            placement: item.placement ?? PromptMessagePlacement.before,
          );
        })
        .toList(growable: false);

    await submitAndClose(() {
      return widget.onSubmit(
        PromptTemplateFormData(name: name, messages: messages),
      );
    });
  }
}
