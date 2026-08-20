import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/composition/chat_generation_foreground_service_bindings.dart';
import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/http/http_route_handler.dart';
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/http/peer_http_client_provider.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/chat/application/favorites/chat_favorites_facade.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_source_conversation_command.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';
import 'package:oh_my_llm/features/media/application/media_root_directory_controller.dart';
import 'package:oh_my_llm/features/media/application/ports/media_library_factory.dart';
import 'package:oh_my_llm/features/media/data/libraries/default_media_library_factory.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_directory_scanner.dart';
import 'package:oh_my_llm/features/media/data/http/media_http_handler.dart';
import 'package:oh_my_llm/features/media/data/http/media_image_http_handler.dart';
import 'package:oh_my_llm/features/media/data/http/media_recursive_videos_handler.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_cache.dart';
import 'package:oh_my_llm/features/media/data/scanning/media_thumbnail_generator.dart';
import 'package:oh_my_llm/features/media/data/http/media_thumbnail_http_handler.dart';
import 'package:oh_my_llm/features/media/data/http/media_video_http_handler.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_sync_facade.dart';
import 'package:oh_my_llm/features/settings/application/transfer/settings_transfer_catalog_provider.dart';
import 'package:oh_my_llm/features/sync/application/ports/settings_sync_facade.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_clock.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_crypto.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_media_route_factory.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_pairing_repository.dart';
import 'package:oh_my_llm/features/sync/application/ports/sync_server_transport.dart';
import 'package:oh_my_llm/features/sync/data/security/cryptography_sync_crypto.dart';
import 'package:oh_my_llm/features/sync/data/http/http_sync_client_transport.dart';
import 'package:oh_my_llm/features/sync/data/http/http_udp_sync_server_transport.dart';
import 'package:oh_my_llm/features/sync/data/security/secure_sync_pairing_repository.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

/// 组合跨 feature 的 concrete implementation。
///
/// 此处是 Sync transport、Settings snapshot 及媒体服务路由唯一的生产绑定点；
/// 外层可在该列表之后覆盖其余 port 以注入测试 fake；chat 两 port
/// （[chatGenerationClientProvider] / [chatConversationRepositoryProvider]）
/// 已被本函数绑定，需先以对应 bind 开关排除生产绑定后再覆盖。
///
/// [bindChatGenerationClient] / [bindChatConversationRepository]：测试 harness
/// 需要以 fake 覆盖对应 port 时传 false——Riverpod 不允许同一容器内重复
/// override 同一 provider，生产绑定与测试 fake 必须由调用方二选一。
List<dynamic> appCompositionOverrides({
  bool useInMemorySyncSecureStore = false,
  bool bindChatGenerationClient = true,
  bool bindChatConversationRepository = true,
  bool bindMediaLibraryFactory = true,
  bool bindChatGenerationForegroundService = true,
  TargetPlatform? hostPlatform,
}) {
  // bootstrap 把既有 effectivePlatform 显式传入；测试 harness 固定传
  // TargetPlatform.windows，宿主 CI 绝不打开真实 Android MethodChannel。
  final effectivePlatform = hostPlatform ?? defaultTargetPlatform;
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
      (ref) => RiverpodSettingsSyncFacade(
        catalog: ref.read(settingsTransferCatalogProvider),
        coordinator: ref.read(settingsTransferCoordinatorProvider),
      ),
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
    if (bindChatGenerationClient)
      // Chat generation：生产环境绑定按请求协议路由的唯一客户端；
      // 三个协议客户端共享同一个流式传输（HTTP 客户端 / 日志 / 自定义 header）。
      chatGenerationClientProvider.overrideWith((ref) {
        final transport = LlmHttpStreamTransport(
          httpClient: ref.read(httpClientProvider),
          logger: ref.watch(appNetworkLoggerProvider),
          // 在请求构建阶段读取自定义 header，确保 logRequest 之前已附加到请求上。
          extraHeadersFactory: () => ref.read(customHeadersMapProvider),
        );
        return ProtocolRoutingChatGenerationClient(
          chatCompletions: ChatCompletionsClient(transport: transport),
          responses: ResponsesClient(transport: transport),
          anthropic: AnthropicMessagesClient(transport: transport),
        );
      }),
    if (bindChatConversationRepository)
      // Chat conversation：SQLite inner + 后台 Isolate 写入代理，
      // 与迁移前的 data-owned factory 保持相同装配语义。
      chatConversationRepositoryProvider.overrideWith((ref) {
        final database = ref.watch(appDatabaseProvider);
        return BackgroundChatConversationRepository(
          SqliteChatConversationRepository(database),
          database.path,
        );
      }),
    if (bindChatGenerationForegroundService)
      // 生成前台服务端口：Android 绑 MethodChannel adapter，其余平台绑 no-op；
      // 端口 dispose 随 provider 生命周期释放，测试注入 fake 时以开关排除本绑定。
      chatGenerationForegroundServiceProvider.overrideWith((ref) {
        final port = createChatGenerationForegroundService(
          platform: effectivePlatform,
        );
        ref.onDispose(port.dispose);
        return port;
      }),
    if (bindMediaLibraryFactory)
      // Media library：生产绑定默认工厂，peer HTTP 客户端走专用 provider，
      // 不继承 API key/自定义 Header；测试需要注入 fake 时由该开关排除本绑定。
      mediaLibraryFactoryProvider.overrideWith(
        (ref) => DefaultMediaLibraryFactory(
          peerHttpClient: ref.watch(peerHttpClientProvider),
        ),
      ),
    // 媒体网格密度是设备本地偏好：Windows 桌面默认紧凑，其余平台默认标准。
    mediaGridDensityDefaultProvider.overrideWithValue(
      defaultTargetPlatform == TargetPlatform.windows
          ? AppLayoutDensity.compact
          : AppLayoutDensity.standard,
    ),
    favoritesRepositoryProvider.overrideWith(
      (ref) => SqliteFavoritesRepository(ref.watch(appDatabaseProvider)),
    ),
    collectionsRepositoryProvider.overrideWith(
      (ref) => SqliteCollectionsRepository(ref.watch(appDatabaseProvider)),
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
