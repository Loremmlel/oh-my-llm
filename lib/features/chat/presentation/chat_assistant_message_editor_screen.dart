import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_text_field.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_dialog_actions.dart';
import 'package:oh_my_llm/core/widgets/long_text_editing_controller.dart';

import '../application/sessions/chat_sessions_controller.dart';

class ChatAssistantMessageEditorScreen extends ConsumerStatefulWidget {
  const ChatAssistantMessageEditorScreen({
    required this.conversationId,
    required this.messageId,
    super.key,
  });

  final String conversationId;
  final String messageId;

  @override
  ConsumerState<ChatAssistantMessageEditorScreen> createState() =>
      _ChatAssistantMessageEditorScreenState();
}

class _ChatAssistantMessageEditorScreenState
    extends ConsumerState<ChatAssistantMessageEditorScreen> {
  late final _original = ref
      .read(chatSessionsProvider.notifier)
      .findAssistantMessage(widget.conversationId, widget.messageId);
  late final _content = LongTextEditingController(
    text: _original?.content ?? '',
  );
  bool _saving = false;
  bool _confirmingLeave = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    if (_saving || _confirmingLeave) return;
    _confirmingLeave = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => const AppConfirmDialog(
        title: '放弃未保存的修改？',
        message: '返回后，本次对助手消息的修改将丢失。',
        confirmLabel: '放弃修改',
        isDestructive: true,
      ),
    );
    _confirmingLeave = false;
    if (mounted && discard == true) context.pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(chatSessionsProvider.notifier)
          .editAssistantMessage(
            conversationId: widget.conversationId,
            messageId: widget.messageId,
            content: _content.textForSave(),
          );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请重试。';
        });
      }
      return;
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    const title = Text('编辑助手消息');
    if (_original == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: Text('助手消息不存在')),
      );
    }

    final canSave = !_saving && !ref.watch(isChatBusyProvider);
    return ListenableBuilder(
      listenable: _content,
      builder: (context, child) => PopScope<void>(
        canPop: !_saving && !_content.hasTextChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: child!,
      ),
      child: AppDialogActions(
        onSubmit: canSave ? _save : null,
        child: Scaffold(
          appBar: AppBar(
            title: title,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppContentWidths.form,
                  ),
                  child: AppTextField(
                    controller: _content,
                    readOnly: _saving,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: '正文',
                      errorText: _error,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
