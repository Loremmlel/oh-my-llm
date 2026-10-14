import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_dropdown_field.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/features/settings/application/worldbooks/world_books_controller.dart';

import '../../../application/composer/chat_composer_command.dart';
import '../../../application/sessions/chat_sessions_controller.dart';

class WorldBookSelector extends ConsumerWidget {
  const WorldBookSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(worldBooksProvider);
    final id = ref.watch(
      activeChatConversationProvider.select((chat) => chat.selectedWorldBookId),
    );
    final missing = id != null && resolveWorldBook(books, id) == null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: AppDropdownField<String>(
        key: ValueKey(id),
        initialValue: id ?? '',
        isExpanded: true,
        fillWidth: true,
        decoration: InputDecoration(
          labelText: '世界书',
          errorText: missing ? '世界书已删除，请重新选择或取消选择' : null,
          suffixIcon: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppHelpButton(
                title: '世界书',
                message: '在设置的“世界书”页签管理条目。当前选择仅用于本对话，启用条目按顺序全量注入，位于预设前置消息之后、对话内容之前。修改选择从下一次请求起生效。',
              ),
              Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('不使用世界书')),
          if (missing)
            DropdownMenuItem(value: id, child: const Text('已删除的世界书')),
          for (final book in books)
            DropdownMenuItem(
              value: book.id,
              child: Text(book.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => ref
            .read(chatComposerCommandProvider)
            .selectWorldBook(value == '' ? null : value),
      ),
    );
  }
}
