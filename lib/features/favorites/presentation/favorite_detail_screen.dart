import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import '../application/collections_controller.dart';
import '../application/favorite_source_conversation_command.dart';
import '../application/favorites_controller.dart';
import '../domain/models/favorite.dart';
import 'widgets/dialogs/move_favorites_dialog.dart';
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

    final theme = Theme.of(context);
    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = collectionById[favorite.collectionId];

    final hasSource = (favorite.sourceConversationId ?? '').trim().isNotEmpty;
    final sourceTitle = favorite.sourceConversationTitle?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(favorite.title ?? '收藏详情'),
        actions: [
          // 重命名/移动/删除收进溢出菜单，保持 AppBar 轻量。
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _showRenameDialog(context, favorite),
                child: const Text('重命名'),
              ),
              MenuItemButton(
                onPressed: () => _showMoveDialog(context, favorite),
                child: const Text('移动到收藏夹'),
              ),
              MenuItemButton(
                style: MenuItemButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _confirmDelete(context, favorite),
                child: const Text('删除'),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              onPressed: () => controller.open(),
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
      body: Center(
        // 宽屏限宽可读宽度，窄屏由 ConstrainedBox 自然占满父宽。
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppContentWidths.readable,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 来源对话主操作 ────────────────────────────────────────
                FilledButton.tonalIcon(
                  onPressed: hasSource
                      ? () => _goToConversation(context, favorite)
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('查看来源对话'),
                ),
                if (!hasSource)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '这条收藏没有关联的来源对话。',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (sourceTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      sourceTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 12),
                FavoriteCard(
                  favorite: favorite,
                  collectionName: collection?.name,
                  onCollectionTap: collection == null
                      ? null
                      : () => _openCollection(collection.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCollection(String collectionId) {
    context.pushNamed(
      AppRouteName.favoriteCollectionItems,
      pathParameters: {AppRouteParameter.collectionId: collectionId},
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
    // 变更后由 favoriteByIdProvider 随 revision 重读，页面无需本地同步。
    ref
        .read(favoritesLibraryProvider.notifier)
        .rename(favorite.id, trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _showMoveDialog(BuildContext context, Favorite favorite) async {
    final targetCollectionId = await showDialog<String>(
      context: context,
      builder: (context) => const MoveFavoritesDialog(),
    );
    if (targetCollectionId == null || !mounted) return;

    // 移动成功后留在详情页；所属收藏夹随 revision 重读自动更新。
    ref.read(favoritesLibraryProvider.notifier).moveMany({
      favorite.id,
    }, targetCollectionId: targetCollectionId);
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
      ref.read(favoritesLibraryProvider.notifier).remove(favorite.id);
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
