import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/app_help_button.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_dialog_actions.dart';
import 'package:oh_my_llm/features/settings/application/worldbooks/world_books_controller.dart';

import '../../../application/composer/chat_composer_command.dart';
import '../../../application/sessions/chat_sessions_controller.dart';

class WorldBookSelector extends ConsumerWidget {
  const WorldBookSelector({super.key});

  static const _help =
      '在设置的“世界书”页签管理条目。当前选择仅用于本对话，可启用多本并上下调整顺序。'
      '启用条目按世界书顺序、书内条目顺序全量注入，位于预设前置消息之后、对话内容之前。'
      '修改选择从下一次请求起生效。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(worldBooksProvider);
    final ids = ref.watch(
      activeChatConversationProvider.select(
        (chat) => chat.selectedWorldBookIds,
      ),
    );
    final missing = ids.any((id) => resolveWorldBook(books, id) == null);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHelpTitle(title: '世界书', message: _help),
          OutlinedButton(
            onPressed: () async {
              final selected = ids.toList();
              final result = await showDialog<List<String>>(
                context: context,
                builder: (context) => StatefulBuilder(
                  builder: (context, setDialogState) {
                    final orderedIds = [
                      ...selected,
                      for (final book in books)
                        if (!selected.contains(book.id)) book.id,
                    ];
                    void move(int index, int delta) => setDialogState(() {
                      final id = selected.removeAt(index);
                      selected.insert(index + delta, id);
                    });
                    return AppDialogActions(
                      onSubmit: () => Navigator.pop(context, selected),
                      child: AlertDialog(
                        title: const Text('选择世界书'),
                        contentPadding: const EdgeInsets.all(AppSpacing.md),
                        content: SizedBox(
                          width: 480,
                          child: orderedIds.isEmpty
                              ? const Text('还没有世界书，请先在设置中新增。')
                              : ListView(
                                  shrinkWrap: true,
                                  children: [
                                    for (final id in orderedIds)
                                      CheckboxListTile(
                                        key: ValueKey('world-book-$id'),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value: selected.contains(id),
                                        title: Text(
                                          resolveWorldBook(books, id)?.name ??
                                              '已删除的世界书',
                                        ),
                                        subtitle: selected.contains(id)
                                            ? Text(
                                                '注入顺序 ${selected.indexOf(id) + 1}',
                                              )
                                            : null,
                                        onChanged: (enabled) =>
                                            setDialogState(() {
                                              if (enabled == true) {
                                                selected.add(id);
                                              } else {
                                                selected.remove(id);
                                              }
                                            }),
                                        secondary: selected.contains(id)
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: '上移世界书',
                                                    onPressed:
                                                        selected.indexOf(id) > 0
                                                        ? () => move(
                                                            selected.indexOf(
                                                              id,
                                                            ),
                                                            -1,
                                                          )
                                                        : null,
                                                    icon: const Icon(
                                                      Icons
                                                          .arrow_upward_rounded,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: '下移世界书',
                                                    onPressed:
                                                        selected.indexOf(id) <
                                                            selected.length - 1
                                                        ? () => move(
                                                            selected.indexOf(
                                                              id,
                                                            ),
                                                            1,
                                                          )
                                                        : null,
                                                    icon: const Icon(
                                                      Icons
                                                          .arrow_downward_rounded,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : null,
                                      ),
                                  ],
                                ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, selected),
                            child: const Text('应用'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
              if (result != null && context.mounted) {
                ref.read(chatComposerCommandProvider).selectWorldBooks(result);
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ids.isEmpty ? '不使用世界书' : '已启用 ${ids.length} 本世界书',
                  ),
                ),
                const Icon(Icons.tune_rounded, size: 18),
              ],
            ),
          ),
          if (missing)
            Text(
              '部分世界书已删除，请取消勾选；其余世界书继续生效。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
