import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

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
              hintText: selectedTemplatePrompt == null
                  ? '写下你的问题或想法…'
                  : '输入模板正文…',
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        );
      },
    );
  }
}
