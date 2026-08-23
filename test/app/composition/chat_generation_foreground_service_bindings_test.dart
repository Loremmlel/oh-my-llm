import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/app.dart';
import 'package:oh_my_llm/app/composition/chat_generation_foreground_service_bindings.dart';
import 'package:oh_my_llm/app/platform/android_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/platform/noop_chat_generation_foreground_service.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/chat_screen.dart';
import 'package:oh_my_llm/features/media/presentation/pages/video_player_platform_bindings.dart';

import '../../features/media/helpers/fake_video_player_platform_bindings.dart';
import '../../features/chat/presentation/chat_screen/chat_screen_test_helpers.dart';
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

/// 把 OhMyLlmApp 挂到 /settings（ChatScreen 不挂载），注入 fake 端口与 fake
/// 生成客户端，返回存活 ProviderContainer。
Future<ProviderContainer> _pumpCompositionRoot(
  WidgetTester tester, {
  required AppDatabase db,
  required SharedPreferences preferences,
  required FakeChatGenerationClient fakeClient,
  required FakeForegroundPort fakePort,
}) async {
  await pumpTestApp(
    tester,
    child: const OhMyLlmApp(),
    preferences: preferences,
    database: db,
    bindChatGenerationForegroundService: false,
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
  return ProviderScope.containerOf(tester.element(find.byType(OhMyLlmApp)));
}

void main() {
  group('createChatGenerationForegroundService 平台选择', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('Android 调用注入工厂恰好一次并返回其端口', () {
      var calls = 0;
      late AndroidChatGenerationForegroundService adapter;
      final port = createChatGenerationForegroundService(
        platform: TargetPlatform.android,
        androidFactory: () {
          calls++;
          adapter = AndroidChatGenerationForegroundService();
          return adapter;
        },
      );
      expect(calls, 1);
      expect(port, same(adapter));
    });

    for (final platform in const [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      test('$platform 返回 noop 且绝不创建 Android adapter', () {
        final port = createChatGenerationForegroundService(
          platform: platform,
          androidFactory: () {
            throw StateError('非 Android 平台不得创建 Android adapter');
          },
        );
        expect(port, isA<NoopChatGenerationForegroundService>());
      });
    }
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

      final container = await _pumpCompositionRoot(
        tester,
        db: db,
        preferences: preferences,
        fakeClient: fakeClient,
        fakePort: fakePort,
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

      final container = await _pumpCompositionRoot(
        tester,
        db: db,
        preferences: preferences,
        fakeClient: fakeClient,
        fakePort: fakePort,
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
}
