import 'package:flutter/material.dart';

import '../../../application/chat_sessions_controller.dart';
import '../../../domain/models/chat_message.dart';

/// 删除消息前的确认弹窗；有兄弟分支时允许选择当前分支或全部版本。
class DeleteMessageDialog extends StatelessWidget {
  const DeleteMessageDialog({
    required this.role,
    required this.siblingCount,
    super.key,
  });

  final ChatMessageRole role;
  final int siblingCount;

  bool get _hasSiblingVersions => siblingCount > 1;

  String get _messageLabel => switch (role) {
    ChatMessageRole.user => '这条用户消息',
    ChatMessageRole.assistant => '这条回复',
    ChatMessageRole.system => '这条消息',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_hasSiblingVersions ? '删除哪个范围？' : '确认删除？'),
      content: Text(
        _hasSiblingVersions
            ? '$_messageLabel存在 $siblingCount 个版本。你可以只删除当前这一支，或删除同一父节点下的全部版本；两种操作都会删除各自后续的子分支。'
            : '将删除$_messageLabel及其后续子分支，此操作不可撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_hasSiblingVersions)
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop(ChatMessageDeletionScope.currentBranch);
            },
            child: const Text('删除当前分支'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _hasSiblingVersions
                  ? ChatMessageDeletionScope.allBranches
                  : ChatMessageDeletionScope.currentBranch,
            );
          },
          child: Text(_hasSiblingVersions ? '删除全部版本' : '删除'),
        ),
      ],
    );
  }
}
