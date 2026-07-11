import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../settings/domain/models/template_prompt.dart';

class ComposerMessageField extends StatelessWidget {
  const ComposerMessageField({
    required this.messageController,
    required this.messageFocusNode,
    required this.selectedTemplatePrompt,
    required this.onSendPressed,
    super.key,
  });

  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final TemplatePrompt? selectedTemplatePrompt;
  final Future<void> Function()? onSendPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: messageFocusNode,
      builder: (context, child) {
        final isFocused = messageFocusNode.hasFocus;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                onSendPressed?.call(),
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                onSendPressed?.call(),
          },
          child: TextField(
            key: const ValueKey('chat-message-composer'), // test-key
            controller: messageController,
            focusNode: messageFocusNode,
            minLines: 2,
            maxLines: isFocused ? 5 : 2,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: '正文',
              hintText: selectedTemplatePrompt == null
                  ? '输入你的问题、指令或待处理内容。'
                  : '输入要注入模板的正文内容。',
              alignLabelWithHint: true,
            ),
          ),
        );
      },
    );
  }
}
