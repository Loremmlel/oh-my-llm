import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/app/attention/app_attention_observer.dart';
import 'package:oh_my_llm/app/composition/app_attention_bindings.dart';
import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/notifications/default_chat_generation_terminal_notifications.dart'
    show chatGenerationTerminalNotificationAdapterProvider;
import 'package:oh_my_llm/app/platform/windows_app_window.dart';
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
import 'package:oh_my_llm/features/chat/application/ports/history_page_query.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/persistence/history_page_query_adapter.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/favorites/application/collections_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_source_conversation_command.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_browse_preferences_controller.dart';
import 'package:oh_my_llm/features/favorites/application/favorites_controller.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/domain/models/favorite.dart';
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
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';
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
/// [bindChatGenerationClient] / [bindChatConversationRepository] /
/// [bindChatGenerationNotifications] / [bindAppWindow]：测试 harness 需要以
/// fake 覆盖对应 port 时传 false——Riverpod 不允许同一容器内重复 override
/// 同一 provider，生产绑定与测试 fake 必须由调用方二选一。
///
/// [notificationPlatformBindingsFactory] / [appWindowFactory] 仅供 bootstrap
/// 的测试参数透传；非 null 时替换平台默认工厂（仍按 [hostPlatform] 判断的
/// 同一套角色装配点），生产调用恒为 null。
List<dynamic> appCompositionOverrides({
  bool useInMemorySyncSecureStore = false,
  bool bindChatGenerationClient = true,
  bool bindChatConversationRepository = true,
  bool bindHistoryPageQuery = true,
  bool bindMediaLibraryFactory = true,
  bool bindChatGenerationNotifications = true,
  bool bindAppWindow = true,
  bool bindFavoritesRepositories = true,
  TargetPlatform? hostPlatform,
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,
  AppWindowFactory? appWindowFactory,
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
    chatFavoritesFacadeProvider.overrideWith((ref) {
      // watch revision：任何成功 mutation 使本 provider 重建，
      // 从而让消费方重新执行定向查询；不加载全量收藏 catalog。
      ref.watch(favoritesLibraryProvider);
      return _CompositionChatFavoritesFacade(ref);
    }),
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
    if (bindHistoryPageQuery)
      // History page query：文件库走独立 read worker isolate（查询移出
      // UI isolate），内存库复用同一连接；测试以 controllable fake 覆盖时
      // 由开关排除本绑定。
      historyPageQueryProvider.overrideWith((ref) {
        final adapter = SqliteHistoryPageQueryAdapter(
          ref.watch(appDatabaseProvider),
        );
        ref.onDispose(() => unawaited(adapter.dispose()));
        return adapter;
      }),
    if (bindChatGenerationNotifications) ...[
      // 生成通知平台绑定记录：一次创建、一处 shared disposer（Android bridge
      // 或 Windows host client 只在这里释放一次）；三个角色 provider 只投影
      // 记录字段，端口各自的 dispose 不触碰共享 owner。
      chatGenerationNotificationPlatformBindingsProvider.overrideWith((ref) {
        final bindings =
            (notificationPlatformBindingsFactory ??
            () => createChatGenerationNotificationPlatformBindings(
              platform: effectivePlatform,
            ))();
        ref.onDispose(() => unawaited(bindings.disposeShared()));
        return bindings;
      }),
      chatGenerationForegroundServiceProvider.overrideWith(
        (ref) => ref
            .watch(chatGenerationNotificationPlatformBindingsProvider)
            .foregroundService,
      ),
      chatGenerationTerminalNotificationAdapterProvider.overrideWith(
        (ref) => ref
            .watch(chatGenerationNotificationPlatformBindingsProvider)
            .terminalAdapter,
      ),
      systemNotificationSettingsProvider.overrideWith(
        (ref) => ref
            .watch(chatGenerationNotificationPlatformBindingsProvider)
            .systemNotificationSettings,
      ),
    ],
    if (bindAppWindow)
      // 应用窗口端口：Windows 绑真实 WindowsAppWindow（生产诊断接结构化日志，
      // 固定分类在 release 可回读），其余平台绑恒 focused 的 NoopAppWindow；
      // 测试注入受控窗口时以开关排除本绑定后自行 override。
      appWindowProvider.overrideWith((ref) {
        final window =
            (appWindowFactory ??
            () => createAppWindow(
              platform: effectivePlatform,
              windowsFactory: () => _productionWindowsAppWindowFactory(ref),
            ))();
        ref.onDispose(() => unawaited(window.dispose()));
        return window;
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
    // 收藏仓库：测试需要以故障注入装饰器覆盖时由开关排除生产绑定。
    if (bindFavoritesRepositories) ...[
      favoritesRepositoryProvider.overrideWith(
        (ref) => SqliteFavoritesRepository(ref.watch(appDatabaseProvider)),
      ),
      collectionsRepositoryProvider.overrideWith(
        (ref) => SqliteCollectionsRepository(ref.watch(appDatabaseProvider)),
      ),
    ],
  ];
}

/// Windows 窗口诊断写入结构化日志时使用的命名 URI；只承载固定分类。
final Uri _windowsAppWindowDiagnosticUri = Uri(
  scheme: 'oh-my-llm',
  host: 'windows-app-window',
);

/// 生产 Windows 窗口工厂：诊断接 core/logging 结构化日志（默认 debugPrint 在
/// release 不可回读）；固定分类不含窗口句柄、异常原文或堆栈。测试注入的
/// [AppWindowFactory] 不经过本路径，不受影响。
WindowsAppWindow _productionWindowsAppWindowFactory(Ref ref) {
  return WindowsAppWindow(
    client: WindowManagerWindowsWindowClient(),
    diagnosticReporter: (category) {
      unawaited(
        ref
            .read(appNetworkLoggerProvider)
            .logError(uri: _windowsAppWindowDiagnosticUri, error: category),
      );
    },
  );
}

final class _CompositionChatFavoritesFacade implements ChatFavoritesFacade {
  const _CompositionChatFavoritesFacade(this._ref);

  final Ref _ref;

  @override
  int get revision => _ref.read(favoritesLibraryProvider);

  @override
  ChatFavoritesSnapshot snapshotFor(Set<String> assistantContents) {
    // 定向查询：只解析当前会话消息命中的收藏，不加载全量 catalog。
    final favoritesRepository = _ref.read(favoritesRepositoryProvider);
    final favoritedContents = favoritesRepository
        .loadFavoritedAssistantContents(assistantContents);
    final entries = <ChatFavoriteEntry>[];
    for (final content in favoritedContents) {
      final favorite = favoritesRepository.findByAssistantContent(content);
      if (favorite != null) {
        entries.add(
          ChatFavoriteEntry(id: favorite.id, draft: _draftOf(favorite)),
        );
      }
    }

    return ChatFavoritesSnapshot(
      entries: entries,
      collections: [
        for (final collection in _ref.watch(collectionsProvider))
          ChatFavoriteCollectionOption(
            id: collection.id,
            name: collection.name,
            isSystem: collection.isSystem,
          ),
      ],
      defaultCollectionId: _ref.read(favoritesLastCollectionProvider),
    );
  }

  ChatFavoriteDraft _draftOf(Favorite favorite) {
    return ChatFavoriteDraft(
      userMessageContent: favorite.userMessageContent,
      assistantContent: favorite.assistantContent,
      assistantReasoningContent: favorite.assistantReasoningContent,
      assistantModelDisplayName: favorite.assistantModelDisplayName,
      collectionId: favorite.collectionId,
      sourceAssistantMessageId: favorite.sourceAssistantMessageId,
      sourceConversationId: favorite.sourceConversationId,
      sourceConversationTitle: favorite.sourceConversationTitle,
    );
  }

  @override
  void add(ChatFavoriteDraft draft) {
    _ref
        .read(favoritesLibraryProvider.notifier)
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
    return _ref.read(favoritesLibraryProvider.notifier).createCollection(name);
  }

  @override
  void remove(String favoriteId) {
    _ref.read(favoritesLibraryProvider.notifier).remove(favoriteId);
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
