import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/http/http_route_handler.dart';
import '../../core/http/peer_http_client_provider.dart';
import '../../features/chat/application/chat_favorites_facade.dart';
import '../../features/chat/application/chat_sessions_controller.dart';
import '../../features/favorites/application/collections_controller.dart';
import '../../features/favorites/application/favorite_source_conversation_command.dart';
import '../../features/favorites/application/favorites_controller.dart';
import '../../features/media/application/media_root_directory_controller.dart';
import '../../features/media/data/media_directory_scanner.dart';
import '../../features/media/data/media_http_handler.dart';
import '../../features/media/data/media_image_http_handler.dart';
import '../../features/media/data/media_recursive_videos_handler.dart';
import '../../features/media/data/media_thumbnail_cache.dart';
import '../../features/media/data/media_thumbnail_generator.dart';
import '../../features/media/data/media_thumbnail_http_handler.dart';
import '../../features/media/data/media_video_http_handler.dart';
import '../../features/settings/application/settings_sync_facade.dart';
import '../../features/sync/application/ports/settings_sync_facade.dart';
import '../../features/sync/application/ports/sync_client_transport.dart';
import '../../features/sync/application/ports/sync_media_route_factory.dart';
import '../../features/sync/application/ports/sync_server_transport.dart';
import '../../features/sync/data/http_sync_client_transport.dart';
import '../../features/sync/data/http_udp_sync_server_transport.dart';

/// 组合跨 feature 的 concrete implementation。
///
/// 此处是 Sync transport、Settings snapshot 及媒体服务路由唯一的生产绑定点；
/// 外层可在该列表之后覆盖任一 port 以注入测试 fake。
List<dynamic> appCompositionOverrides() {
  return [
    syncClientTransportProvider.overrideWith(
      (ref) => HttpSyncClientTransport(ref.watch(peerHttpClientProvider)),
    ),
    syncServerTransportProvider.overrideWith(
      (ref) => HttpUdpSyncServerTransport(),
    ),
    settingsSyncFacadeProvider.overrideWith(
      (ref) => RiverpodSettingsSyncFacade(ref),
    ),
    syncMediaRouteFactoryProvider.overrideWith(
      (ref) => _CompositionSyncMediaRouteFactory(ref),
    ),
    chatFavoritesFacadeProvider.overrideWith(
      (ref) => _CompositionChatFavoritesFacade(
        ref,
        ChatFavoritesSnapshot(
          entries: [
            for (final favorite in ref.watch(favoritesProvider))
              ChatFavoriteEntry(
                id: favorite.id,
                draft: ChatFavoriteDraft(
                  userMessageContent: favorite.userMessageContent,
                  assistantContent: favorite.assistantContent,
                  assistantReasoningContent: favorite.assistantReasoningContent,
                  assistantModelDisplayName:
                      favorite.assistantModelDisplayName,
                  collectionId: favorite.collectionId,
                  sourceAssistantMessageId: favorite.sourceAssistantMessageId,
                  sourceConversationId: favorite.sourceConversationId,
                  sourceConversationTitle: favorite.sourceConversationTitle,
                ),
              ),
          ],
          collections: [
            for (final collection in ref.watch(collectionsProvider))
              ChatFavoriteCollectionOption(
                id: collection.id,
                name: collection.name,
              ),
          ],
        ),
      ),
    ),
    favoriteSourceConversationCommandProvider.overrideWith(
      (ref) => _CompositionFavoriteSourceConversationCommand(ref),
    ),
  ];
}

final class _CompositionChatFavoritesFacade implements ChatFavoritesFacade {
  const _CompositionChatFavoritesFacade(this._ref, this.snapshot);

  final Ref _ref;
  @override
  final ChatFavoritesSnapshot snapshot;

  @override
  void add(ChatFavoriteDraft draft) {
    _ref
        .read(favoritesProvider.notifier)
        .add(
          userMessageContent: draft.userMessageContent,
          assistantContent: draft.assistantContent,
          assistantReasoningContent: draft.assistantReasoningContent,
          assistantModelDisplayName: draft.assistantModelDisplayName,
          collectionId: draft.collectionId,
          sourceAssistantMessageId: draft.sourceAssistantMessageId,
          sourceConversationId: draft.sourceConversationId,
          sourceConversationTitle: draft.sourceConversationTitle,
        );
  }

  @override
  String createCollection(String name) {
    return _ref.read(collectionsProvider.notifier).create(name);
  }

  @override
  void remove(String favoriteId) {
    _ref.read(favoritesProvider.notifier).remove(favoriteId);
  }
}

final class _CompositionFavoriteSourceConversationCommand
    implements FavoriteSourceConversationCommand {
  const _CompositionFavoriteSourceConversationCommand(this._ref);

  final Ref _ref;

  @override
  void selectSourceConversation({
    required String conversationId,
    String? assistantMessageId,
  }) {
    _ref
        .read(chatSessionsProvider.notifier)
        .selectConversationAndNavigateToMessage(
          conversationId,
          messageId: assistantMessageId,
        );
  }
}

final class _CompositionSyncMediaRouteFactory implements SyncMediaRouteFactory {
  const _CompositionSyncMediaRouteFactory(this._ref);

  final Ref _ref;

  @override
  Future<List<HttpRouteHandler>> createRoutes() async {
    if (!Platform.isWindows) return const [];
    final rootDirectory = _ref.read(mediaRootDirectoryProvider);
    if (rootDirectory == null || rootDirectory.isEmpty) return const [];

    final scanner = MediaDirectoryScanner(rootDirectory);
    final cache = await MediaThumbnailCache.defaultLocation();
    return [
      MediaHttpHandler(scanner: scanner),
      MediaImageHttpHandler(scanner: scanner),
      MediaVideoHttpHandler(scanner: scanner),
      MediaRecursiveVideosHandler(scanner: scanner),
      MediaThumbnailHttpHandler(
        scanner: scanner,
        generator: MediaThumbnailGenerator(scanner: scanner),
        cache: cache,
      ),
    ];
  }
}
