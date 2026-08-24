import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/app/attention/app_attention_observer.dart';
import 'package:oh_my_llm/app/attention/app_window.dart';
import 'package:oh_my_llm/app/composition/chat_generation_notification_platform_bindings.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_platform_bridge.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/android_system_notification_settings.dart';
import 'package:oh_my_llm/app/platform/noop_app_window.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/noop_system_notification_settings.dart';
import 'package:oh_my_llm/app/platform/windows_chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/platform/windows_notification_host_client.dart';
import 'package:oh_my_llm/app/platform/windows_system_notification_settings.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification_payload_codec.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/media/helpers/fake_video_player_platform_bindings.dart';
import '../../helpers/chat/fake_chat_generation_client.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_harness.dart';

/// 测试用视频 bindings 工厂：本组用例不打开视频页，仅满足路由构建契约。
VideoPlayerPlatformBindings _unusedVideoBindings() =>
    MobileVideoPlayerBindings(systemUi: FakeMobileVideoSystemUiController());

/// 供组合测试注入的确定性前台端口 fake：命令调用同步记录，dispose 计数。
final class FakeForegroundPort implements ChatGenerationForegroundServicePort {
  final actionsController =
      StreamController<ChatGenerationForegroundAction>.broadcast();
  final calls = <String>[];
  int disposeCount = 0;

  @override
  Stream<ChatGenerationForegroundAction> get actions =>
      actionsController.stream;

  @override
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() {
    calls.add('ensureNotificationPermission');
    return Future.value(ChatNotificationPermissionStatus.granted);
  }

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) {
    calls.add('start');
    return Future.value(const ChatForegroundCommandResult.accepted());
  }

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) {
    calls.add('update');
    return Future.value(const ChatForegroundCommandResult.accepted());
  }

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) {
    calls.add('remove');
    return Future.value(const ChatForegroundCommandResult.accepted());
  }

  @override
  Future<String?> takePendingOpenConversation() async {
    calls.add('takePendingOpenConversation');
    return null;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}

/// 记录调用顺序与次数的终态通知 adapter fake：供根部装配契约测试注入。
final class _RecordingTerminalAdapter
    implements ChatGenerationTerminalNotificationAdapter {
  final events = <String>[];
  int initializeCount = 0;
  int showCount = 0;
  int disposeCount = 0;
  ChatGenerationNotificationActivation? pendingActivation;
  final shown = <ChatGenerationSafeNotification>[];

  late final StreamController<ChatGenerationNotificationActivation>
  _activations = StreamController.broadcast(
    onListen: () => events.add('subscribe'),
  );

  @override
  Stream<ChatGenerationNotificationActivation> get activations =>
      _activations.stream;

  @override
  Future<void> initialize() async {
    events.add('initialize');
    initializeCount += 1;
  }

  @override
  Future<void> show(ChatGenerationSafeNotification notification) async {
    showCount += 1;
    shown.add(notification);
  }

  @override
  Future<ChatGenerationNotificationActivation?> takePendingActivation() async {
    events.add('pending');
    return pendingActivation;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

/// 记录焦点订阅与查询的窗口 fake：供根部装配契约测试注入。
final class _RecordingAppWindow implements AppWindow {
  int focusSubscriptions = 0;
  int isFocusedQueries = 0;

  @override
  Stream<bool> get focusChanges {
    focusSubscriptions += 1;
    return const Stream.empty();
  }

  @override
  Future<bool> isFocused() async {
    isFocusedQueries += 1;
    return true;
  }

  @override
  Future<void> restoreAndFocus() async {}

  @override
  Future<void> dispose() async {}
}

/// 只计数 dispose 的 Windows host client fake：验证共享 owner 恰好释放一次。
final class _CountingWindowsHostClient
    implements WindowsNotificationHostClient {
  int disposeCount = 0;

  @override
  Stream<String> get activationPayloads => const Stream.empty();

  @override
  Future<bool> getAvailable() async => false;

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async => false;

  @override
  Future<List<String>> takePendingActivationPayloads() async => const [];

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

/// 把 OhMyLlmApp 挂到指定路由，注入受控 adapter/window 的根部装配环境，
/// 返回 (存活 container, 注入 router)。
Future<(ProviderContainer, GoRouter)> _pumpRootWithFakes(
  WidgetTester tester, {
  required AppDatabase db,
  required SharedPreferences preferences,
  _RecordingTerminalAdapter? terminalAdapter,
  _RecordingAppWindow? appWindow,
  String initialLocation = '/settings',
}) async {
  final adapter = terminalAdapter ?? _RecordingTerminalAdapter();
  final window = appWindow ?? _RecordingAppWindow();
  final router = createAppRouter(
    initialLocation: initialLocation,
    videoPlayerBindingsFactory: _unusedVideoBindings,
  );
  await pumpTestApp(
    tester,
    child: const OhMyLlmApp(),
    preferences: preferences,
    database: db,
    notificationPlatformBindingsFactory: () => (
      foregroundService: NoopChatGenerationForegroundService(),
      terminalAdapter: adapter,
      systemNotificationSettings: NoopSystemNotificationSettings(),
      disposeShared: () async {},
    ),
    appWindowFactory: () => window,
    extraOverrides: [appRouterProvider.overrideWithValue(router)],
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OhMyLlmApp)),
  );
  return (container, router);
}

/// 构造带一条用户消息的会话；用于真实 SQLite 种子数据。
ChatConversation _conversation(String id, String title) {
  final messageId = '$id-user';
  return ChatConversation(
    id: id,
    title: title,
    messageNodes: [
      TestFixtures.userMessage(
        id: messageId,
        content: '$id 的用户消息',
        createdAt: DateTime(2026, 6, 1),
        parentId: rootConversationParentId,
      ),
    ],
    selectedChildByParentId: {rootConversationParentId: messageId},
    createdAt: DateTime(2026, 6, 1),
    updatedAt: DateTime(2026, 6, 1),
  );
}

void main() {
  group('通知平台绑定工厂选择', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('Android 绑定共享 bridge 与三个窄端口', () {
      var factoryCalls = 0;
      final bindings = createChatGenerationNotificationPlatformBindings(
        platform: TargetPlatform.android,
        androidFactory: () {
          factoryCalls += 1;
          return createAndroidChatGenerationNotificationPlatformBindings();
        },
        windowsFactory: () => throw StateError('Android 选择不得调用 windowsFactory'),
        otherFactory: () => throw StateError('Android 选择不得调用 otherFactory'),
      );

      expect(factoryCalls, 1);
      final foreground =
          bindings.foregroundService as AndroidChatGenerationForegroundService;
      final terminal =
          bindings.terminalAdapter
              as AndroidChatGenerationTerminalNotificationAdapter;
      final settings =
          bindings.systemNotificationSettings
              as AndroidSystemNotificationSettings;
      expect(identical(foreground.bridge, terminal.bridge), isTrue);
      expect(identical(terminal.bridge, settings.bridge), isTrue);
    });

    test(
      'Windows 平台选择只调用注入的 windowsFactory 并得到前台 no-op/terminal/settings 三个角色',
      () {
        var factoryCalls = 0;
        final expectedForeground = NoopChatGenerationForegroundService();
        final expectedTerminal =
            NoopChatGenerationTerminalNotificationAdapter();
        final expectedSettings = NoopSystemNotificationSettings();
        final bindings = createChatGenerationNotificationPlatformBindings(
          platform: TargetPlatform.windows,
          androidFactory: () =>
              throw StateError('Windows 选择不得调用 androidFactory'),
          windowsFactory: () {
            factoryCalls += 1;
            return (
              foregroundService: expectedForeground,
              terminalAdapter: expectedTerminal,
              systemNotificationSettings: expectedSettings,
              disposeShared: () async {},
            );
          },
          otherFactory: () => throw StateError('Windows 选择不得调用 otherFactory'),
        );

        expect(factoryCalls, 1);
        expect(
          identical(bindings.foregroundService, expectedForeground),
          isTrue,
        );
        expect(identical(bindings.terminalAdapter, expectedTerminal), isTrue);
        expect(
          identical(bindings.systemNotificationSettings, expectedSettings),
          isTrue,
        );
      },
    );

    test(
      'Windows production factory 只创建一个共享 host client 且只 dispose 一次',
      () async {
        var clientCreations = 0;
        late final _CountingWindowsHostClient client;
        final bindings =
            createWindowsChatGenerationNotificationPlatformBindings(
              hostClientFactory: () {
                clientCreations += 1;
                client = _CountingWindowsHostClient();
                return client;
              },
            );

        // 从构造源头只创建一个 client；前台为 no-op，terminal 直接持有它。
        expect(clientCreations, 1);
        expect(
          bindings.foregroundService,
          isA<NoopChatGenerationForegroundService>(),
        );
        expect(
          identical(
            (bindings.terminalAdapter
                    as WindowsChatGenerationTerminalNotificationAdapter)
                .client,
            client,
          ),
          isTrue,
        );
        expect(
          bindings.systemNotificationSettings,
          isA<WindowsSystemNotificationSettings>(),
        );

        await bindings.disposeShared();
        await bindings.disposeShared(); // 幂等：重复调用不得二次释放共享 client。
        expect(client.disposeCount, 1);
      },
    );

    for (final platform in const [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      test('$platform 其他平台只绑定 no-op', () {
        final bindings = createChatGenerationNotificationPlatformBindings(
          platform: platform,
          androidFactory: () => throw StateError('$platform 不得创建 Android 绑定'),
          windowsFactory: () => throw StateError('$platform 不得创建 Windows 绑定'),
        );
        expect(
          bindings.foregroundService,
          isA<NoopChatGenerationForegroundService>(),
        );
        expect(
          bindings.terminalAdapter,
          isA<NoopChatGenerationTerminalNotificationAdapter>(),
        );
        expect(
          bindings.systemNotificationSettings,
          isA<NoopSystemNotificationSettings>(),
        );
      });
    }

    test('shared bridge 只 dispose 一次', () async {
      final bridge = AndroidChatGenerationPlatformBridge();
      final bindings = createChatGenerationNotificationPlatformBindings(
        platform: TargetPlatform.android,
        androidFactory: () =>
            createAndroidChatGenerationNotificationPlatformBindings(
              bridge: bridge,
            ),
      );
      final foreground =
          bindings.foregroundService as AndroidChatGenerationForegroundService;
      final terminal =
          bindings.terminalAdapter
              as AndroidChatGenerationTerminalNotificationAdapter;
      final settings =
          bindings.systemNotificationSettings
              as AndroidSystemNotificationSettings;
      expect(identical(foreground.bridge, bridge), isTrue);
      expect(identical(terminal.bridge, bridge), isTrue);
      expect(identical(settings.bridge, bridge), isTrue);

      // 共享 owner 的释放信号：bridge 前台动作流关闭即代表 dispose 已执行；
      // 关闭事件恰好一次（重复 close 不再产生新事件），且端口各自 dispose
      // 之后 bridge 仍由 disposeShared 独占释放。
      final bridgeClosed = Completer<void>();
      bridge.foregroundActions.listen((_) {}, onDone: bridgeClosed.complete);

      foreground.dispose();
      await terminal.dispose();

      await bindings.disposeShared();
      await bridgeClosed.future.timeout(const Duration(seconds: 5));
      await bindings.disposeShared(); // 幂等：重复调用安全。
    });
  });

  group('组合 eager 生命周期', () {
    testWidgets('ChatScreen 未挂载时 generation 进入 preparing 也记录 start', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final preferences = await TestFixtures.seedPreferences(
        database: db,
        models: [TestFixtures.gpt41()],
        conversations: [
          TestFixtures.conversation(
            'conv-eager',
            'Eager 会话',
            DateTime(2026, 1, 3),
          ),
        ],
      );
      final fakePort = FakeForegroundPort();
      final fakeClient = FakeChatGenerationClient();
      final controlled = fakeClient.enqueueControlledStream();

      await pumpTestApp(
        tester,
        child: const OhMyLlmApp(),
        preferences: preferences,
        database: db,
        bindChatGenerationNotifications: false,
        extraOverrides: [
          chatGenerationForegroundServiceProvider.overrideWith((ref) {
            ref.onDispose(fakePort.dispose);
            return fakePort;
          }),
          appRouterProvider.overrideWithValue(
            createAppRouter(
              initialLocation: '/settings',
              videoPlayerBindingsFactory: _unusedVideoBindings,
            ),
          ),
          chatGenerationClientProvider.overrideWithValue(fakeClient),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OhMyLlmApp)),
      );
      // 路由初始落在 /settings：ChatScreen 确实未挂载。
      expect(find.byType(ChatScreen), findsNothing);

      final sendFuture = container
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '你好',
            modelConfig: TestFixtures.gpt41(),
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      await controlled.listened.timeout(const Duration(seconds: 10));
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      // 即使聊天页未挂载，preparing 快照也已记录 start。
      expect(fakePort.calls, contains('start'));

      controlled.add(const ChatGenerationChunk(contentDelta: '你好'));
      await controlled.close();
      await sendFuture;
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      expect(fakePort.calls, contains('remove'));

      // 卸载根：coordinator 取消动作订阅、端口 dispose 恰好一次。
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fakePort.disposeCount, 1);
      expect(fakePort.actionsController.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('组合 stop：有效 token 触发停止一次，stale/重复 token 被忽略', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final preferences = await TestFixtures.seedPreferences(
        database: db,
        models: [TestFixtures.gpt41()],
        conversations: [
          TestFixtures.conversation('conv-stop', '停止会话', DateTime(2026, 1, 3)),
        ],
      );
      final fakePort = FakeForegroundPort();
      final fakeClient = FakeChatGenerationClient();
      final controlled = fakeClient.enqueueControlledStream();

      await pumpTestApp(
        tester,
        child: const OhMyLlmApp(),
        preferences: preferences,
        database: db,
        bindChatGenerationNotifications: false,
        extraOverrides: [
          chatGenerationForegroundServiceProvider.overrideWith((ref) {
            ref.onDispose(fakePort.dispose);
            return fakePort;
          }),
          appRouterProvider.overrideWithValue(
            createAppRouter(
              initialLocation: '/settings',
              videoPlayerBindingsFactory: _unusedVideoBindings,
            ),
          ),
          chatGenerationClientProvider.overrideWithValue(fakeClient),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OhMyLlmApp)),
      );

      final sendFuture = container
          .read(chatSessionsProvider.notifier)
          .sendMessage(
            content: '你好',
            modelConfig: TestFixtures.gpt41(),
            presetPrompt: null,
            reasoningEnabled: false,
            reasoningEffort: ReasoningEffort.medium,
          );
      await controlled.listened;
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      expect(fakePort.calls, contains('start'));

      final snapshot = container.read(chatSessionsProvider).generation!;
      final token = snapshot.generationId;
      final conversationId = snapshot.conversationId;

      // 有效 token：stop 动作触发既有 durable stop，run 进入 cancelled 终态。
      fakePort.actionsController.add(
        ChatGenerationStopRequested(
          token: token,
          conversationId: conversationId,
        ),
      );
      await sendFuture;
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      expect(
        container.read(chatSessionsProvider).generation!.phase,
        ChatGenerationPhase.cancelled,
      );
      expect(fakePort.calls.where((c) => c == 'remove'), ['remove']);

      // 重复 stop：terminal 已投递，不重复清理。
      fakePort.actionsController.add(
        ChatGenerationStopRequested(
          token: token,
          conversationId: conversationId,
        ),
      );
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      expect(fakePort.calls.where((c) => c == 'remove').length, 1);

      // stale token：忽略，不再产生任何命令。
      fakePort.actionsController.add(
        ChatGenerationStopRequested(
          token: token + 1,
          conversationId: conversationId,
        ),
      );
      // pumpEventQueue 的 Future() 链依赖零延迟 Timer，在 testWidgets 的
      // FakeAsync 区域里不会自动推进，必须用 tester.pump() 推进并触发。
      await tester.pump();
      expect(fakePort.calls.where((c) => c == 'remove').length, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('根部装配契约', () {
    testWidgets('测试 harness 默认不触发真实 MethodChannel 或 Windows runner', (
      tester,
    ) async {
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

      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final preferences = await TestFixtures.seedPreferences(database: db);
      final router = createAppRouter(
        initialLocation: '/settings',
        videoPlayerBindingsFactory: _unusedVideoBindings,
      );
      await pumpTestApp(
        tester,
        child: const OhMyLlmApp(),
        preferences: preferences,
        database: db,
        extraOverrides: [appRouterProvider.overrideWithValue(router)],
      );
      await tester.pump(); // 排空根部 eager 启动的微任务链。

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OhMyLlmApp)),
      );
      final bindings = container.read(
        chatGenerationNotificationPlatformBindingsProvider,
      );
      expect(
        bindings.foregroundService,
        isA<NoopChatGenerationForegroundService>(),
      );
      expect(
        bindings.terminalAdapter,
        isA<NoopChatGenerationTerminalNotificationAdapter>(),
      );
      expect(
        bindings.systemNotificationSettings,
        isA<NoopSystemNotificationSettings>(),
      );
      expect(container.read(appWindowProvider), isA<NoopAppWindow>());
      // 固定 session 由 harness 统一 override，测试不读取随机状态。
      expect(
        container.read(chatGenerationNotificationSessionIdProvider),
        testChatGenerationNotificationSessionId,
      );
      expect(attemptedMethods, isEmpty, reason: 'harness 默认绑定绝不允许触达通道');
    });

    testWidgets('应用根部 eager 启动注意力 observer 和终态通知模块', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final preferences = await TestFixtures.seedPreferences(database: db);
      final adapter = _RecordingTerminalAdapter();
      final window = _RecordingAppWindow();

      final (container, _) = await _pumpRootWithFakes(
        tester,
        db: db,
        preferences: preferences,
        terminalAdapter: adapter,
        appWindow: window,
      );
      await tester.pump(); // 排空根部启动微任务链。

      // 仅根部构建（未发送任何 generation）就应完成两侧 eager 启动。
      expect(
        adapter.initializeCount,
        1,
        reason: '根部构建必须显式启动终态通知深模块以消费冷启动 pending',
      );
      expect(
        window.isFocusedQueries,
        greaterThanOrEqualTo(1),
        reason: '注意力 observer 必须已在根部订阅窗口焦点并完成初始查询',
      );
      final attention = container.read(appAttentionStateProvider);
      expect(attention.location.path, '/settings');
    });

    testWidgets('深模块先订阅激活流再触发 adapter 初始化与 pending 取走', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final preferences = await TestFixtures.seedPreferences(database: db);
      final adapter = _RecordingTerminalAdapter();

      await _pumpRootWithFakes(
        tester,
        db: db,
        preferences: preferences,
        terminalAdapter: adapter,
      );
      await tester.pump();
      await tester.pump();

      // 装配顺序契约：broadcast 流必须先有 listener，initialize/takePending
      // 才允许执行；若 composition 在深模块订阅前自行初始化或取 pending，
      // 多余合法激活会在无 listener 期间静默丢失。
      expect(adapter.events, ['subscribe', 'initialize', 'pending']);
    });

    testWidgets('chatSessionsProvider 首次同步加载摘要时 cold activation 不误判为已删除', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      const conversationId = 'conv-cold-seed';
      await SqliteChatConversationRepository(
        db,
      ).saveConversations([_conversation(conversationId, '冷启动会话')]);
      final preferences = await TestFixtures.seedPreferences(database: db);
      final adapter = _RecordingTerminalAdapter()
        ..pendingActivation = const ChatGenerationNotificationActivation(
          eventKey: 'v1:000102030405060708090a0b0c0d0e0f:1:succeeded',
          conversationId: conversationId,
        );

      final (_, router) = await _pumpRootWithFakes(
        tester,
        db: db,
        preferences: preferences,
        terminalAdapter: adapter,
      );
      // 冷启动 pending 在根部 eager start 中消费；存在性判定必须在导航帧
      // 读取首次同步加载的摘要，而不是启动期捕获的空快照。
      await tester.pump();
      await tester.pump();

      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, AppDestination.chat.path);
      expect(
        uri.queryParameters[AppRouteParameter.conversationId],
        conversationId,
        reason: '存在的会话必须携带 ID 导航，不得回退聊天根页',
      );
    });
  });
}
