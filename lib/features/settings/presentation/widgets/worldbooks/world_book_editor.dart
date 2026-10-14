import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/utils/id_generator.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import '../../../domain/models/worldbooks/world_book.dart';
import '../shared/settings_editor_list.dart';
import '../shared/settings_form_dialog_scaffold.dart';
import '../shared/settings_form_dialog_state_mixin.dart';

class WorldBookEditor extends StatefulWidget {
  const WorldBookEditor({required this.onSubmit, this.initialValue, super.key});
  final WorldBook? initialValue;
  final Future<void> Function(WorldBook) onSubmit;

  @override
  State<WorldBookEditor> createState() => _WorldBookEditorState();
}

class _WorldBookEditorState extends State<WorldBookEditor>
    with SettingsFormDialogStateMixin {
  late final String _id;
  late final TextEditingController _name;
  late final TextEditingController _title;
  late final LongTextEditingController _content;
  late final List<WorldBookEntry> _entries;
  late final String _initialSnapshot;
  int? _selected;
  bool _leaveAllowed = false;
  bool _confirmingLeave = false;
  String? _error;

  String get _snapshot => jsonEncode([
    _name.text,
    _entries.map((entry) => entry.toJson()).toList(),
  ]);

  @override
  void initState() {
    super.initState();
    final book = widget.initialValue;
    _id = book?.id ?? generateEntityId();
    _name = initController(book?.name ?? '');
    _title = initController();
    _content = initLongTextController();
    _entries = [...?book?.entries];
    if (_entries.isNotEmpty) _select(0);
    _initialSnapshot = _snapshot;
  }

  @override
  void dispose() {
    disposeAllControllers();
    super.dispose();
  }

  void _select(int index) {
    _selected = index;
    _title.text = _entries[index].title;
    _content.loadText(_entries[index].content);
  }

  void _add() => setState(() {
    final index = _selected == null ? _entries.length : _selected! + 1;
    _entries.insert(
      index,
      WorldBookEntry(id: generateEntityId(), title: '新条目', content: ''),
    );
    _select(index);
  });

  void _move(int delta) => setState(() {
    final index = _selected!;
    _entries.insert(index + delta, _entries.removeAt(index));
    _selected = index + delta;
  });

  Future<void> _remove() async {
    final index = _selected!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: '删除条目？',
        message: '删除「${_entries[index].title}」后，保存世界书时生效。',
        confirmLabel: '删除',
        isDestructive: true,
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _entries.removeAt(index);
      if (_entries.isEmpty) {
        _selected = null;
        _title.clear();
        _content.clear();
      } else {
        _select(index.clamp(0, _entries.length - 1));
      }
    });
  }

  Future<void> _requestLeave() async {
    if (isSaving || _confirmingLeave) return;
    _confirmingLeave = true;
    final leave =
        _snapshot == _initialSnapshot ||
        await showDialog<bool>(
              context: context,
              builder: (_) => const AppConfirmDialog(
                title: '放弃未保存的修改？',
                message: '返回后，本次对世界书的修改将丢失。',
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

  Future<void> _save() async {
    if (!validateForm()) return;
    final invalid = _entries.indexWhere((entry) => entry.title.trim().isEmpty);
    if (invalid >= 0) {
      setState(() {
        _select(invalid);
        _error = '请填写每个条目的标题';
      });
      return;
    }
    final book = WorldBook(
      id: _id,
      name: _name.text.trim(),
      entries: _entries,
      updatedAt: DateTime.now(),
    );
    try {
      await submitAndClose(() async {
        await widget.onSubmit(book);
        if (mounted) {
          setState(() => _leaveAllowed = true);
          await WidgetsBinding.instance.endOfFrame;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    }
  }

  bool _compact(BoxConstraints constraints) =>
      constraints.maxWidth < AppBreakpoints.formMasterDetail ||
      MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom <
          640 ||
      MediaQuery.textScalerOf(context).scale(1) > 1.5;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _leaveAllowed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestLeave();
    },
    child: SettingsFormDialogScaffold(
      fullPage: true,
      title: widget.initialValue == null ? '新增世界书' : '编辑世界书',
      helpText:
          '条目按列表顺序保存。对话选择世界书后，所有启用且正文非空的条目都会以 XML 标签分隔，固定放在预设前置消息之后、对话内容之前。\n\n'
          '不进行关键词匹配，也不执行 SillyTavern 宏。保存后的修改从下一次请求起生效，正在进行的请求使用发送时的内容。',
      formKey: formKey,
      isSaving: isSaving,
      onSubmit: _save,
      shouldScrollContent: _compact,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = _compact(constraints);
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextFormField(
                controller: _name,
                readOnly: isSaving,
                validator: validateRequired,
                decoration: const InputDecoration(labelText: '世界书名称'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Row(
                  children: [
                    Expanded(
                      child: AppDropdownField<int>(
                        key: ValueKey(_selected),
                        initialValue: _selected,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '选择条目'),
                        items: [
                          for (var i = 0; i < _entries.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                '${i + 1}. ${_entries[i].title}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (index) {
                                if (index != null) {
                                  setState(() => _select(index));
                                }
                              },
                      ),
                    ),
                    ..._actions(),
                  ],
                ),
                const Divider(height: AppSpacing.xl),
                _detail(wide: false),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: SettingsEditorList(
                  itemCount: _entries.length,
                  onAdd: isSaving ? null : _add,
                  onMoveUp: !isSaving && (_selected ?? 0) > 0
                      ? () => _move(-1)
                      : null,
                  onMoveDown:
                      !isSaving &&
                          _selected != null &&
                          _selected! < _entries.length - 1
                      ? () => _move(1)
                      : null,
                  itemBuilder: (_, index) {
                    final entry = _entries[index];
                    return SettingsEditorListTile(
                      title: entry.title,
                      selected: _selected == index,
                      status: entry.enabled ? null : '停用',
                      onTap: isSaving
                          ? null
                          : () => setState(() => _select(index)),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 33),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(child: _detail(wide: true)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  List<Widget> _actions() => [
    IconButton(
      tooltip: '新增条目',
      onPressed: isSaving ? null : _add,
      icon: const Icon(Icons.add),
    ),
    IconButton(
      tooltip: '上移',
      onPressed: !isSaving && (_selected ?? 0) > 0 ? () => _move(-1) : null,
      icon: const Icon(Icons.arrow_upward_rounded),
    ),
    IconButton(
      tooltip: '下移',
      onPressed:
          !isSaving && _selected != null && _selected! < _entries.length - 1
          ? () => _move(1)
          : null,
      icon: const Icon(Icons.arrow_downward_rounded),
    ),
  ];

  Widget _detail({required bool wide}) {
    final index = _selected;
    if (index == null) return const Center(child: Text('还没有条目，点击“新增条目”开始编辑。'));
    final content = TextField(
      controller: _content,
      readOnly: isSaving,
      minLines: wide ? null : 10,
      maxLines: wide ? null : 20,
      expands: wide,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(labelText: '正文'),
      onChanged: (_) => _entries[index] = _entries[index].copyWith(
        content: _content.textForSave(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _title,
          readOnly: isSaving,
          validator: validateRequired,
          decoration: const InputDecoration(labelText: '标题'),
          onChanged: (value) => setState(
            () => _entries[index] = _entries[index].copyWith(title: value),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用条目'),
                value: _entries[index].enabled,
                onChanged: isSaving
                    ? null
                    : (value) => setState(
                        () => _entries[index] = _entries[index].copyWith(
                          enabled: value,
                        ),
                      ),
              ),
            ),
            IconButton(
              tooltip: '删除当前条目',
              onPressed: isSaving ? null : _remove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (wide) Expanded(child: content) else content,
      ],
    );
  }
}
