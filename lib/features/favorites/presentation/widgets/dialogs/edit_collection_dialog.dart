import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';

/// 收藏夹编辑对话框的用途。
enum EditCollectionDialogMode {
  /// 新建收藏夹；确认按钮为"创建"。
  create,

  /// 重命名既有收藏夹；确认按钮为"保存"，输入框预填原名称。
  rename,
}

/// 新建与重命名共用的收藏夹名称编辑对话框。
///
/// 校验在对话框内联完成：空白名称、系统保留名"未分类"都以 inline 错误
/// 提示且不关闭对话框；只有合法名称才会 pop 返回给调用方执行 mutation。
class EditCollectionDialog extends StatefulWidget {
  const EditCollectionDialog({required this.mode, this.initialName, super.key});

  final EditCollectionDialogMode mode;

  /// 重命名时的原名称。
  final String? initialName;

  @override
  State<EditCollectionDialog> createState() => _EditCollectionDialogState();
}

class _EditCollectionDialogState extends State<EditCollectionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isCreate => widget.mode == EditCollectionDialogMode.create;

  String get _title => _isCreate ? '新建收藏夹' : '重命名收藏夹';

  String get _confirmLabel => _isCreate ? '创建' : '保存';

  void _validateAndSubmit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMessage = '请输入收藏夹名称');
      return;
    }
    if (trimmed == AppReservedEntities.uncategorizedFavoriteCollectionName) {
      setState(() => _errorMessage = '该名称被系统收藏夹保留');
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '收藏夹名称',
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: _errorMessage,
        ),
        onSubmitted: (_) => _validateAndSubmit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _validateAndSubmit, child: Text(_confirmLabel)),
      ],
    );
  }
}
