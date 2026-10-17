import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';

import '../../../application/worldbooks/world_books_controller.dart';
import '../../../domain/models/worldbooks/world_book.dart';
import '../shared/settings_entity_row.dart';
import '../shared/settings_section_card.dart';

class WorldBooksTab extends ConsumerWidget {
  const WorldBooksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(worldBooksProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsSectionCard(
          title: '世界书',
          description: '在对话侧栏选择一本世界书。启用条目按顺序全量注入，位置固定在预设前置消息之后、对话内容之前。新对话默认不选。',
          action: FilledButton.icon(
            onPressed: () => context.push('/settings/worldbooks/new'),
            icon: const Icon(Icons.add),
            label: const Text('新增世界书'),
          ),
          child: books.isEmpty
              ? const Text('还没有世界书，点击“新增世界书”开始编辑。')
              : Column(
                  children: [
                    for (final book in books)
                      _WorldBookRow(key: ValueKey(book.id), book: book),
                  ],
                ),
        ),
      ],
    );
  }
}

class _WorldBookRow extends ConsumerStatefulWidget {
  const _WorldBookRow({required this.book, super.key});
  final WorldBook book;
  @override
  ConsumerState<_WorldBookRow> createState() => _WorldBookRowState();
}

class _WorldBookRowState extends ConsumerState<_WorldBookRow> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AppConfirmDialog(
          title: '删除世界书？',
          message: '删除「${widget.book.name}」及其全部条目。引用它的对话将停止注入，已有聊天记录保留。',
          confirmLabel: '删除',
          isDestructive: true,
        ),
      );
      if (confirmed == true && mounted) {
        await ref.read(worldBooksProvider.notifier).deleteById(widget.book.id);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '删除失败：$error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsEntityRow(
    title: widget.book.name,
    body: [
      Text(
        '${widget.book.entries.length} 个条目 · ${widget.book.entries.where((entry) => entry.enabled).length} 个启用',
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
    actions: [
      IconButton(
        tooltip: '编辑 ${widget.book.name}',
        onPressed: _deleting
            ? null
            : () => context.push(
                '/settings/worldbooks/${Uri.encodeComponent(widget.book.id)}',
              ),
        icon: const Icon(Icons.edit_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: '世界书操作',
        enabled: !_deleting,
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (_) => _delete(),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'delete',
            child: Text(
              '删除 ${widget.book.name}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ],
  );
}
