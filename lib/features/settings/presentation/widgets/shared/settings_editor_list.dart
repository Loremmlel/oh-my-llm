import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/theme/app_ui_colors.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import 'settings_form_dialog_state_mixin.dart';

/// 世界书、预设与固定顺序编辑共用条目工具栏、列表间距和滚动区域。
class SettingsEditorList extends StatelessWidget {
  const SettingsEditorList({
    required this.itemCount,
    required this.itemBuilder,
    required this.onAdd,
    this.onMoveUp,
    this.onMoveDown,
    this.itemLabel = '条目',
    this.addLabel = '新增条目',
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onAdd;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final String itemLabel;
  final String addLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$itemLabel $itemCount',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(addLabel),
          ),
          IconButton(
            onPressed: onMoveUp,
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: '上移',
          ),
          IconButton(
            onPressed: onMoveDown,
            icon: const Icon(Icons.arrow_downward_rounded),
            tooltip: '下移',
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: itemBuilder,
        ),
      ),
    ],
  );
}

/// 以同一选中标记呈现可编辑条目，停用等状态紧邻标题。
class SettingsEditorListTile extends StatelessWidget {
  const SettingsEditorListTile({
    this.title = '',
    this.titleController,
    this.emptyTitle = '未命名条目',
    required this.selected,
    required this.onTap,
    this.status,
    super.key,
  });

  final String title;
  final TextEditingController? titleController;
  final String emptyTitle;
  final bool selected;
  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final controller = titleController;
    if (controller != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => _buildTile(context, value.text),
      );
    }
    return _buildTile(context, title);
  }

  Widget _buildTile(BuildContext context, String rawTitle) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolvedTitle = rawTitle.trim().isEmpty
        ? emptyTitle
        : rawTitle.trim();
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? Theme.of(context).uiColors.selection
            : Colors.transparent,
        shape: BorderDirectional(
          start: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    resolvedTitle,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(status!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 在有界视口下自动填满剩余高度的多行编辑器字段。
class SettingsExpandedTextField extends StatelessWidget {
  const SettingsExpandedTextField({
    required this.controller,
    required this.expand,
    required this.decoration,
    this.fieldKey,
    this.readOnly = false,
    this.validator,
    this.minLines = 6,
    this.maxLines = 12,
    super.key,
  });

  final TextEditingController controller;
  final bool expand;
  final InputDecoration decoration;
  final Key? fieldKey;
  final bool readOnly;
  final FormFieldValidator<String>? validator;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final field = validator != null
        ? AppTextField.form(
            key: fieldKey,
            controller: controller,
            readOnly: readOnly,
            minLines: expand ? null : minLines,
            maxLines: expand ? null : maxLines,
            expands: expand,
            textAlignVertical: TextAlignVertical.top,
            decoration: decoration,
            validator: validator,
          )
        : AppTextField(
            key: fieldKey,
            controller: controller,
            readOnly: readOnly,
            minLines: expand ? null : minLines,
            maxLines: expand ? null : maxLines,
            expands: expand,
            textAlignVertical: TextAlignVertical.top,
            decoration: decoration,
          );
    return expand ? Expanded(child: field) : field;
  }
}

/// 预设、世界书与固定顺序提示词共用的条目列表状态与主从布局封装。
mixin SettingsItemListEditorMixin<T extends StatefulWidget, E>
    on SettingsFormDialogStateMixin<T> {
  late final TextEditingController nameController = initController(initialName);
  late final TextEditingController itemTitleController = initController();
  late final LongTextEditingController itemContentController =
      initLongTextController();
  final List<E> items = [];
  int selectedIndex = -1;

  String get initialName => '';
  bool get trimItemTitle => true;
  bool get trimItemContent => true;
  String get emptyItemTitle => '未命名条目';

  String itemIdOf(E item);
  String itemTitleOf(E item);
  String itemContentOf(E item);
  String? itemStatusOf(E item) => null;
  E copyItemWithText(E item, {required String title, required String content});

  E? get selectedItem => selectedIndex >= 0 && selectedIndex < items.length
      ? items[selectedIndex]
      : null;

  void initEditorItems(Iterable<E> initialItems) {
    items
      ..clear()
      ..addAll(initialItems);
    if (items.isNotEmpty) {
      _loadSelected(0);
    }
  }

  void syncSelectedItem() {
    final current = selectedItem;
    if (current == null) return;
    items[selectedIndex] = copyItemWithText(
      current,
      title: trimItemTitle
          ? itemTitleController.text.trim()
          : itemTitleController.text,
      content: itemContentController.textForSave(trim: trimItemContent),
    );
  }

  void selectItem(int index) {
    syncSelectedItem();
    _loadSelected(index);
  }

  void _loadSelected(int index) {
    selectedIndex = index;
    itemTitleController.text = itemTitleOf(items[index]);
    itemContentController.loadText(itemContentOf(items[index]));
  }

  void insertItem(E item, {int? at}) {
    syncSelectedItem();
    final index = at ?? (selectedIndex >= 0 ? selectedIndex + 1 : items.length);
    items.insert(index, item);
    _loadSelected(index);
  }

  void removeSelected({int minCount = 0}) {
    if (selectedIndex < 0 || items.length <= minCount) return;
    items.removeAt(selectedIndex);
    if (items.isEmpty) {
      selectedIndex = -1;
      itemTitleController.clear();
      itemContentController.clear();
    } else {
      _loadSelected(selectedIndex.clamp(0, items.length - 1));
    }
  }

  void moveSelected(int delta) {
    final next = selectedIndex + delta;
    if (selectedIndex < 0 || next < 0 || next >= items.length) return;
    syncSelectedItem();
    final item = items.removeAt(selectedIndex);
    items.insert(next, item);
    selectedIndex = next;
  }

  String _resolvedTitleAt(int index) {
    final raw = index == selectedIndex
        ? itemTitleController.text
        : itemTitleOf(items[index]);
    final trimmed = raw.trim();
    return trimmed.isEmpty ? emptyItemTitle : trimmed;
  }

  Widget buildMasterDetailSection({
    required BoxConstraints constraints,
    required bool shouldScroll,
    required Widget header,
    required VoidCallback onAdd,
    required Widget Function(
      BuildContext context,
      E item, {
      required bool isWide,
      required bool expandContent,
    })
    detailBuilder,
    bool? compact,
    bool canMoveUp = true,
    bool canMoveDown = true,
    VoidCallback? onDeleteSelected,
    bool showWideDeleteButton = true,
    String itemLabel = '条目',
    String addLabel = '新增条目',
    String selectLabel = '选择条目',
    String deleteLabel = '删除当前条目',
    String emptyText = '还没有条目，点击“新增条目”开始编辑。',
  }) {
    final isCompact =
        compact ?? constraints.maxWidth < AppBreakpoints.formMasterDetail;
    final expandDetail = !shouldScroll;
    final onMoveUp = !isSaving && canMoveUp && selectedIndex > 0
        ? () => setState(() => moveSelected(-1))
        : null;
    final onMoveDown =
        !isSaving &&
            canMoveDown &&
            selectedIndex >= 0 &&
            selectedIndex < items.length - 1
        ? () => setState(() => moveSelected(1))
        : null;
    final onDelete = !isSaving ? onDeleteSelected : null;

    Widget buildDetail({required bool isWide, required bool expandContent}) {
      final current = selectedItem;
      if (current == null) return Center(child: Text(emptyText));
      final body = detailBuilder(
        context,
        current,
        isWide: isWide,
        expandContent: expandContent,
      );
      if (!isWide || !showWideDeleteButton) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(deleteLabel),
            ),
          ),
        ],
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: itemTitleController,
      builder: (context, _, _) {
        if (isCompact) {
          final detail = buildDetail(
            isWide: false,
            expandContent: expandDetail,
          );
          final selectedKey = selectedItem == null
              ? null
              : itemIdOf(selectedItem as E);
          return Column(
            mainAxisSize: expandDetail ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AppDropdownField<int>(
                      key: ValueKey('compact-item-selector-$selectedKey'),
                      fillWidth: true,
                      initialValue:
                          selectedIndex >= 0 && selectedIndex < items.length
                          ? selectedIndex
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: selectLabel),
                      items: [
                        for (var i = 0; i < items.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${i + 1}. ${_resolvedTitleAt(i)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => selectItem(value));
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: isSaving ? null : onAdd,
                    tooltip: addLabel,
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: onMoveUp,
                    tooltip: '上移',
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    onPressed: onMoveDown,
                    tooltip: '下移',
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      tooltip: deleteLabel,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (expandDetail) Expanded(child: detail) else detail,
            ],
          );
        }

        return SizedBox(
          height: constraints.maxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: SettingsEditorList(
                  itemLabel: itemLabel,
                  addLabel: addLabel,
                  itemCount: items.length,
                  itemBuilder: (_, index) => SettingsEditorListTile(
                    title: itemTitleOf(items[index]),
                    titleController: index == selectedIndex
                        ? itemTitleController
                        : null,
                    emptyTitle: emptyItemTitle,
                    status: itemStatusOf(items[index]),
                    selected: index == selectedIndex,
                    onTap: isSaving
                        ? null
                        : () => setState(() => selectItem(index)),
                  ),
                  onAdd: isSaving ? null : onAdd,
                  onMoveUp: onMoveUp,
                  onMoveDown: onMoveDown,
                ),
              ),
              const VerticalDivider(width: 33),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: buildDetail(isWide: true, expandContent: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
