import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../application/favorites_controller.dart';
import '../application/collections_controller.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import 'widgets/favorite_card.dart';

/// 单条收藏的详情页，展示完整对话内容。
///
/// 通过 GoRouter extra 接收 [Favorite] 对象，读取 collectionsProvider
/// 获取收藏夹名称。支持重命名收藏标题和移动到其它收藏夹。
class FavoriteDetailScreen extends ConsumerStatefulWidget {
  const FavoriteDetailScreen({required this.favorite, super.key});

  final Favorite favorite;

  @override
  ConsumerState<FavoriteDetailScreen> createState() =>
      _FavoriteDetailScreenState();
}

class _FavoriteDetailScreenState extends ConsumerState<FavoriteDetailScreen> {
  late Favorite _favorite = widget.favorite;

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = _favorite.collectionId != null
        ? collectionById[_favorite.collectionId]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_favorite.title ?? '收藏详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: '重命名',
            onPressed: () => _showRenameDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除收藏',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: FavoriteCard(
          favorite: _favorite,
          collectionName: collection?.name,
          onDeletePressed: () => _confirmDelete(context),
          onMoveToCollection: () => _showMoveDialog(context, collections),
          onGoToConversation: _favorite.sourceConversationId != null
              ? () => _goToConversation(context)
              : null,
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: _favorite.title ?? '');
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
    ref.read(favoritesProvider.notifier).rename(
          _favorite.id,
          trimmed.isEmpty ? null : trimmed,
        );
    _refreshFavorite();
  }

  Future<void> _showMoveDialog(
    BuildContext context,
    List<FavoriteCollection> collections,
  ) async {
    String? selectedCollectionId = _favorite.collectionId;

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
                  onTap: () =>
                      setState(() => selectedCollectionId = null),
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
              onPressed: selectedCollectionId != _favorite.collectionId
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
        .moveTo(_favorite.id, result.isEmpty ? null : result);
    _refreshFavorite();
  }

  void _refreshFavorite() {
    final favorites = ref.read(favoritesProvider);
    final updated = favorites.where((f) => f.id == _favorite.id).firstOrNull;
    if (updated != null) {
      setState(() => _favorite = updated);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const AppConfirmDialog(
        title: '删除收藏',
        message: '确定要删除这条收藏记录吗？',
        confirmLabel: '删除',
      ),
    );

    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).remove(_favorite.id);
      if (context.mounted) context.pop();
    }
  }

  void _goToConversation(BuildContext context) {
    ref
        .read(chatSessionsProvider.notifier)
        .selectConversation(_favorite.sourceConversationId!);
    context.go(AppDestination.chat.path);
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
      color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
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
