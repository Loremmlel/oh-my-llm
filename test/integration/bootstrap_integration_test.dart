/// bootstrap() 集成测试。
///
/// 验证应用完整启动流程：初始化 → 数据迁移 → Provider 注入 → UI 渲染。
/// 所有测试均使用内存数据库和空操作日志记录器，不依赖文件系统或网络。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/attention/app_attention_observer.dart';
import 'package:oh_my_llm/app/composition/app_attention_bindings.dart';
import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/notifications/default_chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/noop_system_notification_settings.dart';
import 'package:oh_my_llm/app/platform/windows_app_window.dart';
import 'package:oh_my_llm/app/platform/windows_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';
import 'package:oh_my_llm/app/platform/windows_system_notification_settings.dart';
import 'package:oh_my_llm/bootstrap.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/logging/network_logger.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/data/persistence/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
import 'package:oh_my_llm/features/settings/application/ports/system_notification_settings.dart';

const _viewportSize = Size(1440, 1024);

/// 仅用于验证 factory 透传的前台端口桩：不发起任何平台调用。
final class _StubForegroundPort implements ChatGenerationForegroundServicePort {
  @override
  Stream<ChatGenerationForegroundAction> get actions => const Stream.empty();

  @override
  Future<ChatNotificationPermissionStatus>
  ensureNotificationPermission() async =>
      ChatNotificationPermissionStatus.notRequired;

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) async => const ChatForegroundCommandResult.accepted();

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) async => const ChatForegroundCommandResult.accepted();

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) async => const ChatForegroundCommandResult.accepted();

  @override
  Future<String?> takePendingOpenConversation() async => null;

  @override
  void dispose() {}
}

Future<ProviderContainer> _pumpBootstrappedApp(
  WidgetTester tester, {
  WindowsWindowInitializer? windowsWindowInitializer,
  TargetPlatform hostPlatform = TargetPlatform.windows,
  ChatGenerationNotificationPlatformBindingsFactory?
  notificationPlatformBindingsFactory,
  AppWindowFactory? appWindowFactory,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = _viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final db = AppDatabase.inMemory();
  addTearDown(db.close);

  await bootstrap(
    database: db,
    networkLogger: const NoopNetworkLogger(),
    hostPlatform: hostPlatform,
    windowsWindowInitializer: windowsWindowInitializer ?? () async {},
    notificationPlatformBindingsFactory: notificationPlatformBindingsFactory,
    appWindowFactory: appWindowFactory,
  );
  await tester.pump();

  final context = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(context);
}

void main() {
  testWidgets('正常启动后渲染聊天页', (tester) async {
    await _pumpBootstrappedApp(tester);

    expect(find.byType(MaterialApp), findsOneWidget);

    // 验证导航壳层已渲染（Rail 或 Bar 均可）
    final hasNav =
        find.byType(NavigationRail).evaluate().isNotEmpty ||
        find.byType(NavigationBar).evaluate().isNotEmpty;
    expect(hasNav, isTrue);
  });

  testWidgets('启动后 ProviderScope override 正确注入', (tester) async {
    final container = await _pumpBootstrappedApp(tester);

    final preferences = container.read(sharedPreferencesProvider);
    expect(preferences, isNotNull);

    final database = container.read(appDatabaseProvider);
    expect(database, isNotNull);

    final logger = container.read(appNetworkLoggerProvider);
    expect(logger, isA<NoopNetworkLogger>());

    final completion = container.read(chatGenerationClientProvider);
    expect(completion, isA<ProtocolRoutingChatGenerationClient>());

    final conversation = container.read(chatConversationRepositoryProvider);
    expect(conversation, isA<BackgroundChatConversationRepository>());

    final favorites = container.read(favoritesRepositoryProvider);
    expect(favorites, isA<SqliteFavoritesRepository>());

    final collections = container.read(collectionsRepositoryProvider);
    expect(collections, isA<SqliteCollectionsRepository>());
  });

  testWidgets('Windows 平台 window runtime 恰好初始化一次且不触发真实插件', (tester) async {
    var calls = 0;
    await _pumpBootstrappedApp(
      tester,
      windowsWindowInitializer: () async => calls++,
    );

    expect(calls, 1); // 注入的 no-op 初始化器生效，真实插件未被触发
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('非 Windows 平台不初始化 window runtime，也不篡改全局平台', (tester) async {
    var calls = 0;
    await _pumpBootstrappedApp(
      tester,
      windowsWindowInitializer: () async => calls++,
      // 用 linux 而非 android：android 会绑定真实 MethodChannel adapter，
      // 其命令超时 Timer 在测试环境无法被解析而残留；Android→adapter 的平台
      // 选择契约已由 bindings 测试覆盖，此处只验证非 Windows 不初始化 window。
      hostPlatform: TargetPlatform.linux,
    );

    expect(calls, 0);
    expect(find.byType(MaterialApp), findsOneWidget);
    // bootstrap 通过 hostPlatform 参数显式选择平台，不修改全局平台 override
    expect(debugDefaultTargetPlatformOverride, isNull);
  });

  testWidgets('Windows 宿主把生成前台服务绑定到 no-op 端口', (tester) async {
    final container = await _pumpBootstrappedApp(tester);

    final port = container.read(chatGenerationForegroundServiceProvider);
    expect(port, isA<NoopChatGenerationForegroundService>());
  });

  testWidgets('生产默认绑定在 Windows 平台保持 no-op 前台与真实 Windows 角色', (tester) async {
    final container = await _pumpBootstrappedApp(tester);

    // 生产路径（不传 factory）按平台默认装配：前台保持 no-op，terminal 与
    // settings 共享真实 host client，窗口绑定真实 WindowsAppWindow。
    expect(
      container.read(chatGenerationForegroundServiceProvider),
      isA<NoopChatGenerationForegroundService>(),
    );
    expect(container.read(appWindowProvider), isA<WindowsAppWindow>());
    expect(
      container.read(chatGenerationTerminalNotificationAdapterProvider),
      isA<WindowsChatGenerationTerminalNotificationAdapter>(),
    );
    expect(
      container.read(systemNotificationSettingsProvider),
      isA<WindowsSystemNotificationSettings>(),
    );
    expect(debugDefaultTargetPlatformOverride, isNull);
  });

  testWidgets('bootstrap 的测试 factory 透传不改变生产默认绑定', (tester) async {
    final stubPort = _StubForegroundPort();
    final stubWindow = NoopAppWindow();

    // 注入 factory：端口/窗口来自 factory 本体；透传只影响注入来源，
    // 不改变 hostPlatform 的平台判断（仍为 Windows），也不篡改全局状态。
    final container = await _pumpBootstrappedApp(
      tester,
      hostPlatform: TargetPlatform.windows,
      notificationPlatformBindingsFactory: () => (
        foregroundService: stubPort,
        terminalAdapter: NoopChatGenerationTerminalNotificationAdapter(),
        systemNotificationSettings: NoopSystemNotificationSettings(),
        disposeShared: () async {},
      ),
      appWindowFactory: () => stubWindow,
    );

    expect(
      container.read(chatGenerationForegroundServiceProvider),
      same(stubPort),
    );
    expect(container.read(appWindowProvider), same(stubWindow));
    expect(debugDefaultTargetPlatformOverride, isNull);
  });

  testWidgets(
    'Windows 平台 fake factory 在 Ubuntu 不调用真实 MethodChannel 或 Windows runner',
    (tester) async {
      final attemptedMethods = <String>[];
      void guardChannel(MethodChannel channel) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            attemptedMethods.add('${channel.name}#${call.method}');
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
      }

      guardChannel(const MethodChannel(windowsNotificationHostChannelName));
      guardChannel(const MethodChannel('window_manager'));

      final container = await _pumpBootstrappedApp(
        tester,
        hostPlatform: TargetPlatform.windows,
        notificationPlatformBindingsFactory:
            createOtherPlatformChatGenerationNotificationBindings,
        appWindowFactory: () => NoopAppWindow(),
      );
      await tester.pump(); // 排空根部 eager 启动的微任务链。

      // 根部 eager 启动完成且全程零通道触达：Ubuntu CI 不依赖 Windows runner。
      expect(container.read(appAttentionStateProvider), isNotNull);
      expect(attemptedMethods, isEmpty);
    },
  );
}
