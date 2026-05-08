import 'package:flutter/material.dart';

import '../../../../core/utils/id_generator.dart';
import '../../../../core/widgets/adaptive_master_detail_layout.dart';
import '../../domain/models/prompt_template.dart';
import 'settings_form_dialog_scaffold.dart';
import 'settings_form_dialog_state_mixin.dart';

/// 预设 Prompt 表单提交数据。
class PromptTemplateFormData {
  const PromptTemplateFormData({
    required this.name,
    required this.systemPromptTitle,
    required this.systemPrompt,
    required this.messages,
  });

  final String name;
  final String systemPromptTitle;
  final String systemPrompt;
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

enum _PresetPromptEditorRole { system, user, assistant }

/// 预设 Prompt 表单的输入与选中状态。
class _PromptTemplateFormDialogState extends State<PromptTemplateFormDialog>
    with SettingsFormDialogStateMixin {
  static const _systemItemId = '__system_preset_prompt__';

  late final TextEditingController _nameController;
  late final List<_EditablePresetPromptItem> _items;
  late String _selectedItemId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue?.name ?? '',
    );
    _items = _buildInitialItems(widget.initialValue);
    _selectedItemId = _items.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final item in _items) {
      item.titleController.dispose();
      item.contentController.dispose();
    }
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
          'system 固定唯一；前置与后置分组显示，后置永远排在前置之后。',
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
    return _PresetPromptListTile(
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

    final isSystem = selected.role == _PresetPromptEditorRole.system;
    final titleLabel = switch (selected.role) {
      _PresetPromptEditorRole.system => 'system 条目',
      _PresetPromptEditorRole.user => 'User 条目',
      _PresetPromptEditorRole.assistant => 'Assistant 条目',
    };
    final contentField = TextFormField(
      key: const ValueKey('preset-prompt-content-field'),
      controller: selected.contentController,
      minLines: isWide ? null : 8,
      maxLines: isWide ? null : 16,
      expands: isWide,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        labelText: isSystem ? 'system Prompt' : 'Prompt 内容',
        hintText: isSystem ? '你是我的人工智能助手，协助我完成各种任务。' : '输入这一条预设 Prompt 的具体内容。',
      ),
      onChanged: (_) => setState(() {}),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleLabel, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          isSystem
              ? 'system 只保留一个，用于放置系统级指令。'
              : '这里可以编辑标题、角色、位置和 Prompt 内容，左侧列表会即时同步。',
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
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<_PresetPromptEditorRole>(
          key: const ValueKey('preset-prompt-role-field'),
          initialValue: selected.role,
          items: isSystem
              ? const [
                  DropdownMenuItem(
                    value: _PresetPromptEditorRole.system,
                    child: Text('system'),
                  ),
                ]
              : const [
                  DropdownMenuItem(
                    value: _PresetPromptEditorRole.user,
                    child: Text('User'),
                  ),
                  DropdownMenuItem(
                    value: _PresetPromptEditorRole.assistant,
                    child: Text('Assistant'),
                  ),
                ],
          onChanged: isSystem
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      _replaceSelected(selected.copyWith(role: value));
                    });
                  }
                },
          decoration: const InputDecoration(labelText: '角色'),
        ),
        if (!isSystem) ...[
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
        ],
        const SizedBox(height: 12),
        if (isWide) Expanded(child: contentField) else contentField,
        if (!isSystem) ...[
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
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '预设 Prompt 名称',
        hintText: '例如：代码审阅助手',
      ),
    );
  }

  List<_EditablePresetPromptItem> _buildInitialItems(PromptTemplate? template) {
    final systemItem = _EditablePresetPromptItem(
      id: _systemItemId,
      role: _PresetPromptEditorRole.system,
      titleController: TextEditingController(
        text: template?.systemPromptTitle ?? defaultSystemPromptTitle,
      ),
      contentController: TextEditingController(
        text: template?.systemPrompt ?? '',
      ),
    );
    final messages = (template?.messages ?? const <PromptMessage>[])
        .where((message) => message.placement == PromptMessagePlacement.before)
        .followedBy(
          (template?.messages ?? const <PromptMessage>[]).where(
            (message) => message.placement == PromptMessagePlacement.after,
          ),
        )
        .map((message) {
          return _EditablePresetPromptItem(
            id: message.id,
            role: switch (message.role) {
              PromptMessageRole.user => _PresetPromptEditorRole.user,
              PromptMessageRole.assistant => _PresetPromptEditorRole.assistant,
            },
            placement: message.placement,
            titleController: TextEditingController(text: message.title),
            contentController: TextEditingController(text: message.content),
          );
        })
        .toList(growable: true);

    return [systemItem, ...messages];
  }

  _EditablePresetPromptItem? get _selectedItem {
    for (final item in _items) {
      if (item.id == _selectedItemId) {
        return item;
      }
    }
    return null;
  }

  int get _selectedIndex {
    return _items.indexWhere((item) => item.id == _selectedItemId);
  }

  void _addMessageItem() {
    final newItem = _EditablePresetPromptItem(
      id: generateEntityId(),
      role: _PresetPromptEditorRole.user,
      placement: PromptMessagePlacement.before,
      titleController: TextEditingController(
        text: _buildNextGeneratedTitle(
          role: PromptMessageRole.user,
          placement: PromptMessagePlacement.before,
        ),
      ),
      contentController: TextEditingController(),
    );

    setState(() {
      final firstAfterIndex = _items.indexWhere(
        (item) => item.placement == PromptMessagePlacement.after,
      );
      final insertIndex = firstAfterIndex == -1
          ? _items.length
          : firstAfterIndex;
      _items.insert(insertIndex, newItem);
      _selectedItemId = newItem.id;
    });
  }

  void _removeSelectedItem() {
    final index = _selectedIndex;
    if (index <= 0) {
      return;
    }

    setState(() {
      final removed = _items.removeAt(index);
      removed.titleController.dispose();
      removed.contentController.dispose();
      _selectedItemId = _items[index - 1].id;
    });
  }

  bool _canMoveSelectedUp() {
    final index = _selectedIndex;
    if (index <= 0) {
      return false;
    }
    final selected = _items[index];
    if (selected.role == _PresetPromptEditorRole.system) {
      return false;
    }
    if (selected.placement == PromptMessagePlacement.before) {
      return index > 1;
    }
    return index > _firstAfterIndex;
  }

  bool _canMoveSelectedDown() {
    final index = _selectedIndex;
    if (index <= 0) {
      return false;
    }
    final selected = _items[index];
    if (selected.role == _PresetPromptEditorRole.system) {
      return false;
    }
    if (selected.placement == PromptMessagePlacement.before) {
      return index < _lastBeforeIndex;
    }
    return index < _items.length - 1;
  }

  void _moveSelected(int delta) {
    final index = _selectedIndex;
    if (index <= 0) {
      return;
    }

    final nextIndex = index + delta;
    if (nextIndex <= 0 || nextIndex >= _items.length) {
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
    if (index <= 0) {
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

  void _replaceSelected(_EditablePresetPromptItem item) {
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

  _PresetPromptEditorRole _toEditorRole(PromptMessageRole role) {
    return switch (role) {
      PromptMessageRole.user => _PresetPromptEditorRole.user,
      PromptMessageRole.assistant => _PresetPromptEditorRole.assistant,
    };
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showFormSnackBar('请填写预设 Prompt 名称');
      return;
    }

    final systemItem = _items.firstWhere(
      (item) => item.role == _PresetPromptEditorRole.system,
    );
    if (systemItem.titleController.text.trim().isEmpty) {
      _selectedItemId = systemItem.id;
      setState(() {});
      showFormSnackBar('请填写 system 条目的标题');
      return;
    }

    for (final item in _items.where(
      (item) => item.role != _PresetPromptEditorRole.system,
    )) {
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
        .where((item) => item.role != _PresetPromptEditorRole.system)
        .map((item) {
          return PromptMessage(
            id: item.id,
            role: switch (item.role) {
              _PresetPromptEditorRole.user => PromptMessageRole.user,
              _PresetPromptEditorRole.assistant => PromptMessageRole.assistant,
              _PresetPromptEditorRole.system => PromptMessageRole.user,
            },
            title: item.titleController.text.trim(),
            content: item.contentController.text.trim(),
            placement: item.placement ?? PromptMessagePlacement.before,
          );
        })
        .toList(growable: false);

    await submitAndClose(() {
      return widget.onSubmit(
        PromptTemplateFormData(
          name: name,
          systemPromptTitle: systemItem.titleController.text.trim(),
          systemPrompt: systemItem.contentController.text.trim(),
          messages: messages,
        ),
      );
    });
  }
}

/// 左侧的预设 Prompt 标题项。
class _PresetPromptListTile extends StatelessWidget {
  const _PresetPromptListTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _EditablePresetPromptItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.secondaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.groupLabel} ',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: item.titleController.text.trim()),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                item.contentPreview,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表单内使用的可编辑预设 Prompt 条目。
class _EditablePresetPromptItem {
  const _EditablePresetPromptItem({
    required this.id,
    required this.role,
    required this.titleController,
    required this.contentController,
    this.placement,
  });

  final String id;
  final _PresetPromptEditorRole role;
  final PromptMessagePlacement? placement;
  final TextEditingController titleController;
  final TextEditingController contentController;

  String get groupLabel => switch (role) {
    _PresetPromptEditorRole.system => 'system',
    _PresetPromptEditorRole.user ||
    _PresetPromptEditorRole.assistant => switch (placement) {
      PromptMessagePlacement.before => '前置',
      PromptMessagePlacement.after => '后置',
      null => '前置',
    },
  };

  String get contentPreview {
    final text = contentController.text.trim().replaceAll('\n', ' ');
    if (text.isEmpty) {
      return '点击右侧填写内容';
    }
    if (text.length <= 36) {
      return text;
    }
    return '${text.substring(0, 36)}...';
  }

  _EditablePresetPromptItem copyWith({
    String? id,
    _PresetPromptEditorRole? role,
    PromptMessagePlacement? placement,
    TextEditingController? titleController,
    TextEditingController? contentController,
  }) {
    return _EditablePresetPromptItem(
      id: id ?? this.id,
      role: role ?? this.role,
      placement: placement ?? this.placement,
      titleController: titleController ?? this.titleController,
      contentController: contentController ?? this.contentController,
    );
  }
}
