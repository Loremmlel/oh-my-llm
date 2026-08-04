import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/http/http_route_handler.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_source_conversation_command.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/data/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/media_http_handler.dart';
import 'package:oh_my_llm/features/media/data/media_image_http_handler.dart';
import 'package:oh_my_llm/features/media/data/media_recursive_videos_handler.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_cache.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_generator.dart';
import 'package:oh_my_llm/features/media/data/media_thumbnail_http_handler.dart';
import 'package:oh_my_llm/features/media/data/media_video_http_handler.dart';
import 'package:oh_my_llm/features/settings/application/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_crypto.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_media_route_factory.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_server_transport.dart';
import 'package:oh_my_llm/features/sync/data/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/data/http_sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/data/http_udp_sync_server_transport.dart';
import 'package:oh_my_llm/features/sync/data/secure_sync_pairing_repository.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

/// 组合跨 feature 的 concrete implementation。
///
/// 此处是 Sync transport、Settings snapshot 及媒体服务路由唯一的生产绑定点；
/// 外层可在该列表之后覆盖任一 port 以注入测试 fake。
List<dynamic> appCompositionOverrides({
  bool useInMemorySyncSecureStore = false,
}) {
  return [
    syncClientTransportProvider.overrideWith(
      (ref) => HttpSyncClientTransport(ref.watch(peerHttpClientProvider)),
    ),
    syncServerTransportProvider.overrideWith(
      (ref) => HttpUdpSyncServerTransport(),
    ),
    syncClockProvider.overrideWith((ref) => const SystemSyncClock()),
    syncCryptoProvider.overrideWith((ref) => CryptographySyncCrypto()),
    syncPairingRepositoryProvider.overrideWith(
      (ref) => SecureSyncPairingRepository(
        preferences: ref.watch(sharedPreferencesProvider),
        secureStore: useInMemorySyncSecureStore
            ? InMemorySyncSecureStore()
            : const FlutterSyncSecureStore(),
      ),
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
                  assistantModelDisplayName: favorite.assistantModelDisplayName,
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
