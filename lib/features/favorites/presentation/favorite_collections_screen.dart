import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';
import 'package:oh_my_llm/core/widgets/dialogs/app_confirm_dialog.dart';
import '../application/collections_controller.dart';
import '../application/favorites_controller.dart';
import '../domain/models/favorite_collection_summary.dart';
import 'widgets/dialogs/edit_collection_dialog.dart';
import 'widgets/favorite_collection_grid.dart';

/// 收藏总览页：以动态网格呈现全部收藏夹，作为收藏浏览的入口层级。
///
/// 系统收藏夹恒置顶且无管理操作；普通收藏夹支持新建、重命名与空夹删除，
/// 点击卡片进入对应收藏夹的浏览路由。
class FavoriteCollectionsScreen extends ConsumerStatefulWidget {
  const FavoriteCollectionsScreen({super.key});

  @override
  ConsumerState<FavoriteCollectionsScreen> createState() =>
      _FavoriteCollectionsScreenState();
}

class _FavoriteCollectionsScreenState
    extends ConsumerState<FavoriteCollectionsScreen> {
  /// 刚新建完成、应获得焦点的收藏夹 ID；卡片渲染后不再保留。
  String? _focusCollectionId;

  FavoritesLibraryController get _library =>
      ref.read(favoritesLibraryProvider.notifier);

  Future<void> _createCollection() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          const EditCollectionDialog(mode: EditCollectionDialogMode.create),
    );
    if (name == null || !mounted) return;

    final collectionId = _library.createCollection(name);
    setState(() => _focusCollectionId = collectionId);
  }

  Future<void> _renameCollection(FavoriteCollectionSummary summary) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => EditCollectionDialog(
        mode: EditCollectionDialogMode.rename,
        initialName: summary.collection.name,
      ),
    );
    if (name == null) return;

    _library.renameCollection(summary.collection.id, name);
  }

  Future<void> _deleteCollection(FavoriteCollectionSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: '删除收藏夹',
        message: '将删除空收藏夹"${summary.collection.name}"，夹内没有收藏。',
        confirmLabel: '删除',
      ),
    );
    if (confirmed != true) return;

    _library.deleteCollection(summary.collection.id);
    if (_focusCollectionId == summary.collection.id) {
      setState(() => _focusCollectionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(collectionsSummariesProvider);

    return AppShellScaffold(
      currentDestination: AppDestination.favorites,
      title: '收藏',
      actions: [
        IconButton(
          onPressed: _createCollection,
          tooltip: '新建收藏夹',
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
      body: FavoriteCollectionGrid(
        summaries: summaries,
        focusCollectionId: _focusCollectionId,
        onOpen: (summary) => context.pushNamed(
          AppRouteName.favoriteCollectionItems,
          pathParameters: {
            AppRouteParameter.collectionId: summary.collection.id,
          },
        ),
        onRename: _renameCollection,
        onDelete: _deleteCollection,
      ),
    );
  }
}
