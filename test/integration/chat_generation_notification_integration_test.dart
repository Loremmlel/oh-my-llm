library;

import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';

/// 生成通知协调器的跨层集成测试。
///
/// 把真实 Riverpod wiring（[chatGenerationNotificationCoordinatorProvider] 的
/// eager watch + [chatSessionsProvider]）与可控 repository、fake 生成客户端和
/// fake 平台端口接在一起，验证跨层契约：
/// 1. 原生 stop 进入既有 durable stop：通知先显示 stopping、stop 落盘完成前不
///    remove，取消后部分正文/推理落盘并 remove；
/// 2. stop 落盘失败：投影 persistenceFailed、inline 错误保持既有文案、端口收到
///    remove 且 terminal sender 收到安全载荷；
/// 3. 平台 start/update/remove 失败 fail-open：聊天结果与对照控制组完全一致，
///    不额外创建 assistant 消息；
///
/// 所有等待均基于 fake 端口调用信号与 repository ACK（gate reached），不使用
/// 任意延时或无条件的 pumpAndSettle。

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/app/composition/chat_generation_notification_coordinator.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/app/router/app_router.dart';
import 'package:oh_my_llm/app/platform/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

import '../helpers/async/async_test_signals.dart';
import '../helpers/chat/controllable_chat_conversation_repository.dart';
import '../helpers/chat/fake_chat_generation_client.dart';
import '../helpers/integration_test_helpers.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  for (final (label, lifecycle, path, otherConversation, suppressed) in [
    ('正在查看生成会话', AppLifecycleState.resumed, '/chat', false, true),
    ('应用进入后台', AppLifecycleState.hidden, '/chat', false, false),
    ('正在查看其他会话', AppLifecycleState.resumed, '/chat', true, false),
  ]) {
    test('$label时按当前可见会话决定终态提醒且始终清理前台服务', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      addTearDown(
        () =>
            binding.handleAppLifecycleStateChanged(AppLifecycleState.detached),
      );
      final activeId = harness.container.read(activeConversationIdProvider);
      final conversationId = otherConversation
          ? 'other-conversation'
          : activeId;
      harness.container.read(appRouterProvider).go(path);
      binding.handleAppLifecycleStateChanged(lifecycle);
      harness.container
          .read(chatGenerationNotificationCoordinatorProvider)
          .onStateChanged(
            snapshot: ChatGenerationSnapshot(
              generationId: 1,
              conversationId: conversationId,
              attempt: 1,
              phase: ChatGenerationPhase.succeeded,
              outcome: const ChatGenerationSuccess(
                generationId: 1,
                attempt: 1,
                content: '完成',
                reasoningContent: '',
              ),
            ),
            streamingReply: null,
          );
      await harness.port.waitForCall('remove');
      expect(harness.terminalNotifications, hasLength(suppressed ? 0 : 1));
      if (!suppressed) {
        expect(
          harness.terminalNotifications.single.conversationId,
          conversationId,
        );
      }
    });
  }

  // ── 原生 stop 进入既有 durable stop 路径 ────────────────────────────────────

  test(
    'native stop 进入 durable stop：stopping 更新先于 stop 落盘，取消后才 remove',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final controlled = harness.fakeClient.enqueueControlledStream();
      addTearDown(controlled.close);

      final sendFuture = _sendMessage(harness.container);
      await controlled.listened;
      final (generationId, conversationId) = await _awaitActiveGeneration(
        harness,
      );

      // 投递正文与推理增量，使停止时已有可落盘的部分内容。
      controlled.add(
        const ChatGenerationChunk(contentDelta: '部分正文', reasoningDelta: '部分推理'),
      );
      await waitForProviderState(
        container: harness.container,
        provider: chatSessionsProvider,
        matches: (s) =>
            s.streamingReply?.content == '部分正文' &&
            s.streamingReply?.reasoningContent == '部分推理',
        description: '等待正文与推理增量进入流式状态',
      );

      // 阻塞 stop 落盘（第 2 次 save）：native stop 必须卡在 durable stop 上，
      // 通知只显示 stopping、不提前 remove。
      final stopSaveGate = harness.repo.gateSave(2);
      harness.port.actionsController.add(
        ChatGenerationStopRequested(
          token: generationId,
          conversationId: conversationId,
        ),
      );
      await waitForProviderState(
        container: harness.container,
        provider: chatSessionsProvider,
        matches: (s) => s.generation?.phase == ChatGenerationPhase.stopping,
        description: '等待 native stop 进入 stopping 阶段',
      );
      await stopSaveGate.reached.future;
      await harness.port.waitForCall('update');

      expect(
        harness.port.payloads.where((p) => p.title == '正在停止'),
        isNotEmpty,
        reason: 'stop 落盘前应已投递 stopping 更新',
      );
      expect(harness.port.calls, isNot(contains('remove')));

      // 放行 stop 落盘：terminal cancelled 投影 + remove 清理。
      harness.repo.releaseSave(2);
      await sendFuture;
      await harness.port.waitForCall('remove');

      final state = harness.container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.cancelled);
      expect(state.generation?.cancelReason, ChatCancelReason.userStop);
      expect(state.generation?.outcome, isA<ChatGenerationCancelled>());
      expect(harness.port.calls, contains('remove'));
      expect(harness.terminalNotifications, isEmpty);

      // 持久化会话包含取消前的部分正文与推理。
      final persisted = SqliteChatConversationRepository(harness.database)
          .loadConversation(conversationId);
      expect(persisted, isNotNull);
      expect(persisted!.messages.last.content, '部分正文');
      expect(persisted.messages.last.reasoningContent, '部分推理');
    },
  );

  // ── stop 落盘失败：persistenceFailed + 安全终态载荷 ────────────────────────

  test(
    'native stop 落盘失败投影 persistenceFailed，inline 错误不变且终态 sender 收到安全载荷',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final controlled = harness.fakeClient.enqueueControlledStream();
      addTearDown(controlled.close);

      final sendFuture = _sendMessage(harness.container);
      await controlled.listened;
      final (generationId, conversationId) = await _awaitActiveGeneration(
        harness,
      );

      controlled.add(
        const ChatGenerationChunk(contentDelta: '部分正文', reasoningDelta: '部分推理'),
      );
      await waitForProviderState(
        container: harness.container,
        provider: chatSessionsProvider,
        matches: (s) => s.streamingReply?.content == '部分正文',
        description: '等待正文增量进入流式状态',
      );

      final stopSaveGate = harness.repo.gateSave(2);
      harness.port.actionsController.add(
        ChatGenerationStopRequested(
          token: generationId,
          conversationId: conversationId,
        ),
      );
      await waitForProviderState(
        container: harness.container,
        provider: chatSessionsProvider,
        matches: (s) => s.generation?.phase == ChatGenerationPhase.stopping,
        description: '等待 native stop 进入 stopping 阶段',
      );
      await stopSaveGate.reached.future;

      // 放行 stop 落盘但抛异常：run 投影 persistenceFailed（非 cancelled）。
      harness.repo.releaseSave(2, error: StateError('模拟 stop 落盘失败'));
      await sendFuture;

      final state = harness.container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.persistenceFailed);
      expect(
        state.generation?.outcome,
        isA<ChatGenerationPersistenceFailure>(),
      );
      // inline 错误保持既有持久化失败文案，不因通知链路改变。
      expect(state.errorMessage, ChatErrorMessages.persistenceFailed);

      // ongoing 端口完成清理，terminal sender 收到固定安全文案。
      await harness.port.waitForCall('remove');
      expect(
        harness.terminalNotifications.where((p) => p.title == '结果保存失败'),
        isNotEmpty,
      );
      expect(
        harness.terminalNotifications
            .lastWhere((p) => p.title == '结果保存失败')
            .text,
        startsWith('回复结果未能保存，请打开应用查看 · 正文 '),
      );
      expect(
        harness.terminalNotifications
            .lastWhere((p) => p.title == '结果保存失败')
            .text,
        isNot(contains('模拟 stop 落盘失败')),
      );
      expect(harness.port.calls, contains('remove'));
    },
  );

  // ── 平台失败 fail-open：不改写聊天结果 ─────────────────────────────────────

  test('平台 start/update/remove 失败不改变聊天结果（与对照控制组一致，不新增 assistant 消息）', () async {
    // 控制组：端口全部接受。
    final controlHarness = await _createHarness();
    addTearDown(controlHarness.dispose);
    controlHarness.fakeClient.enqueueDeltas(const [
      ChatGenerationChunk(contentDelta: '对照正文'),
      ChatGenerationChunk(finishReason: 'stop'),
    ]);
    await _sendMessage(controlHarness.container);

    // 失败组：start/update/remove 各预排一个平台失败。start 失败即标记 token
    // 不可用（fail-open），后续 update 被抑制；终态 remove 仍执行并失败后重试。
    // 任一平台失败都不得改写聊天结果。
    final failingPort = FakeForegroundServicePort();
    failingPort.queuedResults.addAll([
      Future.value(
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.startNotAllowed,
        ),
      ),
      Future.value(
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.channelTimeout,
        ),
      ),
      Future.value(
        const ChatForegroundCommandResult.unavailable(
          ChatForegroundFailureCode.serviceUnavailable,
        ),
      ),
    ]);
    final failingHarness = await _createHarness(port: failingPort);
    addTearDown(failingHarness.dispose);
    failingHarness.fakeClient.enqueueDeltas(const [
      ChatGenerationChunk(contentDelta: '对照正文'),
      ChatGenerationChunk(finishReason: 'stop'),
    ]);
    await _sendMessage(failingHarness.container);

    final control = controlHarness.container.read(chatSessionsProvider);
    final failing = failingHarness.container.read(chatSessionsProvider);

    // 聊天结果逐项与控制组一致：不额外创建 assistant 消息。
    expect(
      failing.activeConversation.messages.length,
      control.activeConversation.messages.length,
    );
    expect(
      failing.activeConversation.messages.map((m) => m.role),
      control.activeConversation.messages.map((m) => m.role),
    );
    expect(
      failing.activeConversation.messages.map((m) => m.content),
      control.activeConversation.messages.map((m) => m.content),
    );
    final failingAssistant = failing.activeConversation.messages.last;
    expect(failingAssistant.role, ChatMessageRole.assistant);
    expect(failingAssistant.content, '对照正文');
    expect(failingAssistant.finishReason, 'stop');

    expect(failing.generation?.phase, ChatGenerationPhase.succeeded);
    final failingOutcome = failing.generation?.outcome;
    final controlOutcome = control.generation?.outcome;
    expect(failingOutcome, isA<ChatGenerationSuccess>());
    expect(controlOutcome, isA<ChatGenerationSuccess>());
    expect(
      (failingOutcome as ChatGenerationSuccess).content,
      (controlOutcome as ChatGenerationSuccess).content,
    );
    expect(failingOutcome.finishReason, controlOutcome.finishReason);
  });

  // ── 多协议真实路由链路下的终态通知 ────────────────────────────────────────

  // 空回复：多协议 SSE fake 助手（multi_protocol 集成测试）未提供空回复 SSE，
  // 此处经通用 fake 客户端链路验证空回复仍投递安全终态载荷。
}

/// 等待 generation 进入 streaming 并返回 (generationId, conversationId)，
/// 供测试构造匹配 token 的 native stop 动作。
Future<(int, String)> _awaitActiveGeneration(_Harness harness) async {
  await waitForProviderState(
    container: harness.container,
    provider: chatSessionsProvider,
    matches: (s) => s.generation?.phase == ChatGenerationPhase.streaming,
    description: '等待 generation 进入 streaming 阶段',
  );
  final state = harness.container.read(chatSessionsProvider);
  return (state.generation!.generationId, state.activeConversation.id);
}

/// 发送一条消息并等待 generation 完成（含 durable 落盘）。
Future<void> _sendMessage(
  ProviderContainer container, {
  LlmModelConfig? modelConfig,
  bool reasoningEnabled = false,
}) {
  return container
      .read(chatSessionsProvider.notifier)
      .sendMessage(
        content: '新问题',
        modelConfig: modelConfig ?? testModel,
        presetPrompt: null,
        reasoningEnabled: reasoningEnabled,
        reasoningEffort: ReasoningEffort.medium,
      );
}

/// 构建真实 Riverpod wiring + fake 端口的集成测试装具。
///
/// 与生产组合一致地传入 [appCompositionOverrides]（排除三个 chat 端口的生产
/// 绑定，由测试 fake 接管），eager 读取通知协调器模拟应用根部的 watch。
Future<_Harness> _createHarness({FakeForegroundServicePort? port}) async {
  final database = AppDatabase.inMemory();
  final preferences = await createSeededPreferences();
  final fakeClient = FakeChatGenerationClient();
  final repo = ControllableChatConversationRepository(database);
  final servicePort = port ?? FakeForegroundServicePort();
  final terminalNotifications = <ChatGenerationForegroundPayload>[];
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...appCompositionOverrides(
        hostPlatform: TargetPlatform.windows,
        useInMemorySyncSecureStore: true,
        bindChatGenerationClient: false,
        bindChatConversationRepository: false,
        bindChatGenerationForegroundService: false,
      ),
      chatGenerationClientProvider.overrideWithValue(fakeClient),
      chatConversationRepositoryProvider.overrideWithValue(repo),
      chatGenerationForegroundServiceProvider.overrideWithValue(servicePort),
      chatGenerationTerminalNotificationSenderProvider.overrideWithValue(
        (payload) async => terminalNotifications.add(payload),
      ),
    ],
  );
  // eager 读取通知协调器：生命周期不依赖 ChatScreen，模拟应用根部 watch。
  container.read(chatGenerationNotificationCoordinatorProvider);
  return _Harness(
    database: database,
    fakeClient: fakeClient,
    repo: repo,
    port: servicePort,
    terminalNotifications: terminalNotifications,
    container: container,
  );
}

final class _Harness {
  const _Harness({
    required this.database,
    required this.fakeClient,
    required this.repo,
    required this.port,
    required this.terminalNotifications,
    required this.container,
  });

  final AppDatabase database;
  final FakeChatGenerationClient fakeClient;
  final ControllableChatConversationRepository repo;
  final FakeForegroundServicePort port;
  final List<ChatGenerationForegroundPayload> terminalNotifications;
  final ProviderContainer container;

  void dispose() {
    container.dispose();
    port.dispose();
    database.close();
  }
}

/// 测试用前台服务端口 fake：调用同步记录，支持按名称等待调用、结果队列注入
/// 失败，动作流可主动投递 native stop 等动作。
class FakeForegroundServicePort implements ChatGenerationForegroundServicePort {
  final actionsController =
      StreamController<ChatGenerationForegroundAction>.broadcast();
  final List<String> calls = [];
  final List<ChatGenerationForegroundPayload> payloads = [];
  final Queue<Future<ChatForegroundCommandResult>> queuedResults = Queue();
  final Map<String, Completer<void>> _callWaiters = {};

  ChatNotificationPermissionStatus permissionStatus =
      ChatNotificationPermissionStatus.granted;

  @override
  Stream<ChatGenerationForegroundAction> get actions =>
      actionsController.stream;

  Future<ChatForegroundCommandResult> _record(
    String name, [
    ChatGenerationForegroundPayload? payload,
  ]) {
    calls.add(name);
    if (payload != null) payloads.add(payload);
    final waiter = _callWaiters.putIfAbsent(name, Completer.new);
    if (!waiter.isCompleted) waiter.complete();
    return queuedResults.isEmpty
        ? Future.value(const ChatForegroundCommandResult.accepted())
        : queuedResults.removeFirst();
  }

  /// 等待名为 [name] 的端口调用出现（已出现则立即返回）。基于先注册 waiter
  /// 再查已记录的顺序，无 check-then-listen 竞态。
  Future<void> waitForCall(
    String name, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final waiter = _callWaiters.putIfAbsent(name, Completer.new);
    if (calls.contains(name)) return;
    await waiter.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('等待端口调用 $name 超时'),
    );
  }

  @override
  Future<ChatNotificationPermissionStatus> ensureNotificationPermission() {
    calls.add('ensureNotificationPermission');
    return Future.value(permissionStatus);
  }

  @override
  Future<ChatForegroundCommandResult> start(
    ChatGenerationForegroundPayload payload,
  ) => _record('start', payload);

  @override
  Future<ChatForegroundCommandResult> update(
    ChatGenerationForegroundPayload payload,
  ) => _record('update', payload);

  @override
  Future<ChatForegroundCommandResult> remove({
    required int token,
    required String conversationId,
  }) => _record('remove');

  @override
  Future<ChatForegroundCommandResult> fail(
    ChatGenerationForegroundPayload payload,
  ) => _record('fail', payload);

  @override
  Future<String?> takePendingOpenConversation() async {
    calls.add('takePendingOpenConversation');
    return null;
  }

  @override
  void dispose() {
    if (!actionsController.isClosed) actionsController.close();
  }
}
