import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../../app/shell/app_shell_scaffold.dart';
import '../application/collections_controller.dart';
import '../application/favorites_controller.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite.dart';
import '../presentation/widgets/dialogs/manage_collections_dialog.dart';
import '../presentation/widgets/favorite_list_item.dart';

/// 收藏页，展示按收藏夹筛选的收藏记录。
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favorites = ref.watch(favoritesProvider);
    final collections = ref.watch(collectionsProvider);
    final filter = ref.watch(favoritesFilterProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.favorites,
      title: '收藏',
      actions: [
        IconButton(
          onPressed: () => _showManageCollectionsDialog(context),
          tooltip: '管理收藏夹',
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 收藏夹筛选条 ────────────────────────────────────────────────
          _buildFilterBar(theme, collections, filter),

          // ── 收藏列表 ────────────────────────────────────────────────────
          Expanded(
            child: favorites.isEmpty
                ? _buildEmptyView(theme, filter)
                : _buildFavoritesList(favorites, collections),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
    ThemeData theme,
    List<FavoriteCollection> collections,
    String? filter,
  ) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          _FilterChip(
            label: '全部',
            selected: filter == null,
            onSelected: () =>
                ref.read(favoritesFilterProvider.notifier).setFilter(null),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '未分类',
            selected: filter == '',
            onSelected: () =>
                ref.read(favoritesFilterProvider.notifier).setFilter(''),
          ),
          for (final collection in collections) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: collection.name,
              selected: filter == collection.id,
              onSelected: () =>
                  ref.read(favoritesFilterProvider.notifier).setFilter(
                    collection.id,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFavoritesList(
    List<Favorite> favorites,
    List<FavoriteCollection> collections,
  ) {
    final collectionById = {for (final c in collections) c.id: c};

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: favorites.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final favorite = favorites[index];
        final collection = favorite.collectionId != null
            ? collectionById[favorite.collectionId]
            : null;

        return FavoriteListItem(
          favorite: favorite,
          collectionName: collection?.name,
          onTap: () => context.push('/favorites/detail', extra: favorite),
        );
      },
    );
  }

  Widget _buildEmptyView(ThemeData theme, String? filter) {
    final message = filter == null
        ? '暂无收藏。在聊天页点击模型回复的书签图标开始收藏。'
        : filter.isEmpty
        ? '未分类下暂无收藏。'
        : '该收藏夹暂无收藏。';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManageCollectionsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const ManageCollectionsDialog(),
    );
  }
}

/// 收藏夹筛选 Chip。
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
