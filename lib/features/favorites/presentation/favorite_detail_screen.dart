import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/widgets/app_empty_state.dart';
import '../application/collections_controller.dart';
import '../application/favorite_source_conversation_command.dart';
import '../application/favorites_controller.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite.dart';
import 'package:oh_my_llm/core/widgets/app_confirm_dialog.dart';
import 'widgets/favorite_card.dart';

/// 单条收藏的详情页，展示完整对话内容。
///
/// 只接收 [favoriteId]（可能为 null/空），实体经 [favoriteByIdProvider]
/// 按 ID 读取；链接无效或收藏已删除时展示可返回的恢复状态。
/// 不保存任何 route 传入的 [Favorite] 镜像，避免陈旧数据。
class FavoriteDetailScreen extends ConsumerStatefulWidget {
  const FavoriteDetailScreen({required this.favoriteId, super.key});

  final String? favoriteId;

  @override
  ConsumerState<FavoriteDetailScreen> createState() =>
      _FavoriteDetailScreenState();
}

class _FavoriteDetailScreenState extends ConsumerState<FavoriteDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final rawId = widget.favoriteId?.trim() ?? '';
    final favorite = rawId.isEmpty
        ? null
        : ref.watch(favoriteByIdProvider(rawId));

    if (favorite == null) {
      final invalid = rawId.isEmpty;
      return _FavoriteDetailRecoveryPage(
        title: invalid ? '收藏链接无效' : '收藏不存在',
        description: invalid ? '链接中缺少有效的收藏 ID。' : '这条收藏可能已被删除。',
      );
    }

    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = favorite.collectionId != null
        ? collectionById[favorite.collectionId]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(favorite.title ?? '收藏详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: '重命名',
            onPressed: () => _showRenameDialog(context, favorite),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除收藏',
            onPressed: () => _confirmDelete(context, favorite),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: FavoriteCard(
          favorite: favorite,
          collectionName: collection?.name,
          onDeletePressed: () => _confirmDelete(context, favorite),
          onMoveToCollection: () =>
              _showMoveDialog(context, favorite, collections),
          onGoToConversation: favorite.sourceConversationId != null
              ? () => _goToConversation(context, favorite)
              : null,
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    Favorite favorite,
  ) async {
    final controller = TextEditingController(text: favorite.title ?? '');
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名收藏'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '自定义标题',
              hintText: '留空则使用消息摘要',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确认'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (result == null) return;
    final trimmed = result.trim();
    // 变更后由 favoriteByIdProvider 重读，页面无需本地同步。
    ref
        .read(favoritesProvider.notifier)
        .rename(favorite.id, trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _showMoveDialog(
    BuildContext context,
    Favorite favorite,
    List<FavoriteCollection> collections,
  ) async {
    String? selectedCollectionId = favorite.collectionId;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('移动到收藏夹'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoveCollectionTile(
                  label: '未分类',
                  icon: Icons.folder_off_outlined,
                  selected: selectedCollectionId == null,
                  onTap: () => setState(() => selectedCollectionId = null),
                ),
                if (collections.isNotEmpty) ...[
                  const Divider(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: collections.length,
                      itemBuilder: (context, index) {
                        final collection = collections[index];
                        return _MoveCollectionTile(
                          label: collection.name,
                          icon: Icons.folder_outlined,
                          selected: selectedCollectionId == collection.id,
                          onTap: () => setState(
                            () => selectedCollectionId = collection.id,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedCollectionId != favorite.collectionId
                  ? () => Navigator.of(context).pop(selectedCollectionId ?? '')
                  : null,
              child: const Text('移动'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    ref
        .read(favoritesProvider.notifier)
        .moveTo(favorite.id, result.isEmpty ? null : result);
  }

  Future<void> _confirmDelete(BuildContext context, Favorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const AppConfirmDialog(
        title: '删除收藏',
        message: '确定要删除这条收藏记录吗？',
        confirmLabel: '删除',
      ),
    );

    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).remove(favorite.id);
      if (context.mounted) context.pop();
    }
  }

  void _goToConversation(BuildContext context, Favorite favorite) {
    ref
        .read(favoriteSourceConversationCommandProvider)
        .selectSourceConversation(
          conversationId: favorite.sourceConversationId!,
          assistantMessageId: favorite.sourceAssistantMessageId,
        );
    context.go(AppDestination.chat.path);
  }
}

/// 收藏详情恢复页：参数无效或收藏不存在时的可返回页面级状态。
class _FavoriteDetailRecoveryPage extends StatelessWidget {
  const _FavoriteDetailRecoveryPage({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏详情')),
      body: AppEmptyState(
        icon: Icons.bookmark_remove_rounded,
        title: title,
        description: description,
        action: FilledButton(
          onPressed: () {
            if (router.canPop()) {
              router.pop();
            } else {
              router.go(AppDestination.favorites.path);
            }
          },
          child: const Text('返回收藏列表'),
        ),
      ),
    );
  }
}

/// 移动收藏夹对话框中的选项行。
class _MoveCollectionTile extends StatelessWidget {
  const _MoveCollectionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
