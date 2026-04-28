import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../application/favorites_controller.dart';
import '../application/collections_controller.dart';
import '../domain/models/favorite.dart';
import 'widgets/favorite_card.dart';

/// 单条收藏的详情页，展示完整对话内容。
///
/// 通过 GoRouter extra 接收 [Favorite] 对象，读取 collectionsProvider
/// 获取收藏夹名称。
class FavoriteDetailScreen extends ConsumerWidget {
  const FavoriteDetailScreen({required this.favorite, super.key});

  final Favorite favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = favorite.collectionId != null
        ? collectionById[favorite.collectionId]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除收藏',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: FavoriteCard(
          favorite: favorite,
          collectionName: collection?.name,
          onDeletePressed: () => _confirmDelete(context, ref),
          onGoToConversation: favorite.sourceConversationId != null
              ? () => _goToConversation(context, ref)
              : null,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏'),
        content: const Text('确定要删除这条收藏记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).remove(favorite.id);
      if (context.mounted) context.pop();
    }
  }

  void _goToConversation(BuildContext context, WidgetRef ref) {
    ref
        .read(chatSessionsProvider.notifier)
        .selectConversation(favorite.sourceConversationId!);
    context.go(AppDestination.chat.path);
  }
}
