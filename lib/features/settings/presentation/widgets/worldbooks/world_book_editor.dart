import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../../../domain/models/worldbooks/world_book.dart';
import '../shared/settings_editor_list.dart';
import '../shared/settings_form_dialog_state_mixin.dart';

class WorldBookEditor extends StatefulWidget {
  const WorldBookEditor({required this.onSubmit, this.initialValue, super.key});
  final WorldBook? initialValue;
  final Future<void> Function(WorldBook) onSubmit;

  @override
  State<WorldBookEditor> createState() => _WorldBookEditorState();
}

class _WorldBookEditorState extends State<WorldBookEditor>
    with
        SettingsFormDialogStateMixin,
        SettingsItemListEditorMixin<WorldBookEditor, WorldBookEntry> {
  late final String _id = widget.initialValue?.id ?? generateEntityId();

  @override
  String get initialName => widget.initialValue?.name ?? '';

  @override
  bool get trimItemTitle => false;

  @override
  bool get trimItemContent => false;

  @override
  String itemIdOf(WorldBookEntry item) => item.id;

  @override
  String itemTitleOf(WorldBookEntry item) => item.title;

  @override
  String itemContentOf(WorldBookEntry item) => item.content;

  @override
  String? itemStatusOf(WorldBookEntry item) => item.enabled ? null : '停用';

  @override
  WorldBookEntry copyItemWithText(
    WorldBookEntry item, {
    required String title,
    required String content,
  }) => item.copyWith(title: title, content: content);

  String _snapshot() {
    syncSelectedItem();
    return jsonEncode([
      nameController.text,
      items.map((entry) => entry.toJson()).toList(),
    ]);
  }

  @override
  void initState() {
    super.initState();
    initEditorItems(widget.initialValue?.entries ?? const []);
    captureInitialSnapshot(_snapshot());
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  Future<void> _remove() async {
    syncSelectedItem();
    final current = selectedItem;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: '删除条目？',
        message: '删除「${current.title}」后，保存世界书时生效。',
        confirmLabel: '删除',
        isDestructive: true,
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(removeSelected);
  }

  Future<void> _save() async {
    syncSelectedItem();
    if (!validateForm()) return;
    final invalid = items.indexWhere((entry) => entry.title.trim().isEmpty);
    if (invalid >= 0) {
      setState(() {
        selectItem(invalid);
        saveError = '请填写每个条目的标题';
      });
      return;
    }
    await submitPageAndClose(
      () => widget.onSubmit(
        WorldBook(
          id: _id,
          name: nameController.text.trim(),
          entries: List.unmodifiable(items),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  bool _compact(BoxConstraints constraints) =>
      constraints.maxWidth < AppBreakpoints.formMasterDetail ||
      MediaQuery.sizeOf(context).height < 640 ||
      MediaQuery.textScalerOf(context).scale(1) > 1.5;

  @override
  Widget build(BuildContext context) => buildEditorPage(
    title: widget.initialValue == null ? '新增世界书' : '编辑世界书',
    targetName: '世界书',
    helpText:
        '条目按列表顺序保存。对话选择世界书后，所有启用且正文非空的条目都会以 XML 标签分隔，固定放在预设前置消息之后、对话内容之前。\n\n'
        '不进行关键词匹配，也不执行 SillyTavern 宏。保存后的修改从下一次请求起生效，正在进行的请求使用发送时的内容。',
    snapshotBuilder: _snapshot,
    shouldScrollContent: (c) => _compact(c) && c.maxHeight < 420,
    onSubmit: _save,
    builder: (context, constraints, shouldScroll) => buildMasterDetailSection(
      constraints: constraints,
      compact: _compact(constraints),
      shouldScroll: shouldScroll,
      showWideDeleteButton: false,
      header: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppTextField.form(
          controller: nameController,
          readOnly: isSaving,
          validator: validateRequired,
          decoration: const InputDecoration(labelText: '世界书名称'),
        ),
      ),
      onAdd: () => setState(
        () => insertItem(
          WorldBookEntry(id: generateEntityId(), title: '新条目', content: ''),
        ),
      ),
      detailBuilder: (_, current, {required isWide, required expandContent}) =>
          Column(
            mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField.form(
                controller: itemTitleController,
                readOnly: isSaving,
                validator: validateRequired,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile.adaptive(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用条目'),
                      value: current.enabled,
                      onChanged: isSaving
                          ? null
                          : (value) => setState(() {
                              syncSelectedItem();
                              items[selectedIndex] = items[selectedIndex]
                                  .copyWith(enabled: value);
                            }),
                    ),
                  ),
                  IconButton(
                    tooltip: '删除当前条目',
                    onPressed: isSaving ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              SettingsExpandedTextField(
                controller: itemContentController,
                expand: expandContent,
                readOnly: isSaving,
                decoration: const InputDecoration(labelText: '正文'),
              ),
            ],
          ),
    ),
  );
}
