/// 生成通知协调器的跨层集成测试。
///
/// 把真实 Riverpod wiring（[chatGenerationNotificationCoordinatorProvider] 的
/// eager watch + [chatSessionsProvider]）与可控 repository、fake 生成客户端、
/// fake 平台端口和 fake 终态通知端口接在一起，验证四条跨层契约：
/// 1. 原生 stop 进入既有 durable stop：通知先显示 stopping、stop 落盘完成前不
///    remove，取消后部分正文/推理落盘并 remove；
/// 2. stop 落盘失败：投影 persistenceFailed、inline 错误保持既有文案、ongoing
///    清理后报告安全收据；
/// 3. 平台 start/update/remove 失败 fail-open：聊天结果与对照控制组完全一致，
///    不额外创建 assistant 消息；
/// 4. 成功/错误/空回复经既有多协议 fake 路由链路清理 ongoing 并投递正确终态收据。
///
/// 所有等待均基于 fake 端口调用信号与 repository ACK（gate reached），不使用
/// 任意延时或无条件的 pumpAndSettle。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:oh_my_llm/app/composition/chat_generation_notification_coordinator.dart';
import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_notification_session.dart';
import 'package:oh_my_llm/app/notifications/chat_generation_terminal_notification_adapter.dart';
import 'package:oh_my_llm/app/notifications/default_chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/core/http/llm_http_stream_transport.dart';
import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';
import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_terminal_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_foreground_service.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_terminal_notifications.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_controller.dart';
import 'package:oh_my_llm/features/chat/data/generation/anthropic/anthropic_messages_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/chat_completions/chat_completions_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/protocol_routing_chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/data/generation/responses/responses_client.dart';
import 'package:oh_my_llm/features/chat/data/persistence/sqlite_chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/domain/chat_error_messages.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

import '../helpers/async/async_test_signals.dart';
import '../helpers/chat/controllable_chat_conversation_repository.dart';
import '../helpers/chat/fake_chat_generation_client.dart';
import '../helpers/integration_test_helpers.dart';
import '../helpers/test_harness.dart';

/// 本文件所有 harness 共用的固定通知 session：断言 session 同时进入 ongoing
/// payload 与终态收据时不依赖全局随机状态。
const _fixedSession = testChatGenerationNotificationSessionId;

void main() {
  // ── 固定 session 贯穿 ongoing payload 与终态收据 ──────────────────────────

  test(
    '固定 session override 同时进入 coordinator ongoing payload 与 terminal receipt',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      harness.fakeClient.enqueueDeltas(const [
        ChatGenerationChunk(contentDelta: '正文'),
        ChatGenerationChunk(finishReason: 'stop'),
      ]);
      await _sendMessage(harness.container);

      await harness.port.waitForCall('remove');
      expect(harness.port.payloads, isNotEmpty);
      const codec = ChatGenerationNotificationPayloadCodec();
      for (final payload in harness.port.payloads) {
        final activation = codec.decode(payload.timeoutActivationPayload!);
        expect(activation, isNotNull);
        expect(
          activation!.eventKey,
          startsWith('v1:$_fixedSession:'),
          reason: 'ongoing 载荷中的保护超时激活必须携带同一固定 session',
        );
      }
      final receipt = harness.terminal.receipts.single;
      expect(receipt.notificationSessionId, _fixedSession);
    },
  );

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

      // 持久化会话包含取消前的部分正文与推理。
      final persisted = SqliteChatConversationRepository(
        harness.database,
      ).loadConversation(conversationId);
      expect(persisted, isNotNull);
      expect(persisted!.messages.last.content, '部分正文');
      expect(persisted.messages.last.reasoningContent, '部分推理');
    },
  );

  // ── stop 落盘失败：persistenceFailed + 安全 fail 载荷 ───────────────────────

  test(
    'native stop 落盘失败投影 persistenceFailed，inline 错误保持既有文案且端口收到安全载荷',
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

      // ongoing 清理后报告安全收据：只携带固定分类，不携带原始异常文本。
      await harness.port.waitForCall('remove');
      final receipt = harness.terminal.receipts.single;
      expect(
        receipt.terminalKind,
        ChatGenerationTerminalKind.persistenceFailed,
      );
      expect(
        receipt.failureKind,
        ChatGenerationTerminalFailureKind.persistence,
      );
      expect(harness.port.calls.where((c) => c == 'remove'), ['remove']);
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

  for (final protocol in LlmApiProtocol.values) {
    test('${protocol.name} 真实路由链路：成功时投递 start/update/remove 通知并报告收据', () async {
      final harness = await _createHarness(
        routingClient: _routingClient(protocol, fail: false),
      );
      addTearDown(harness.dispose);
      await _sendMessage(
        harness.container,
        modelConfig: _modelConfigFor(protocol),
        reasoningEnabled: true,
      );

      final state = harness.container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.succeeded);
      expect(state.isStreaming, isFalse);
      expect(
        state.activeConversation.messages.last.role,
        ChatMessageRole.assistant,
      );
      expect(state.activeConversation.messages.last.content, isNotEmpty);

      await harness.port.waitForCall('remove');
      expect(harness.port.calls, contains('start'));
      expect(harness.port.calls, contains('update'));
      expect(harness.port.calls, contains('remove'));
      expect(
        harness.terminal.receipts.single.terminalKind,
        ChatGenerationTerminalKind.succeeded,
      );
    });

    test('${protocol.name} 真实路由链路：错误时清理 ongoing 并报告 failed 收据', () async {
      final harness = await _createHarness(
        routingClient: _routingClient(protocol, fail: true),
      );
      addTearDown(harness.dispose);
      await _sendMessage(
        harness.container,
        modelConfig: _modelConfigFor(protocol),
        reasoningEnabled: true,
      );

      final state = harness.container.read(chatSessionsProvider);
      expect(state.generation?.phase, ChatGenerationPhase.failed);
      expect(state.isStreaming, isFalse);

      await harness.port.waitForCall('remove');
      final receipt = harness.terminal.receipts.single;
      expect(receipt.terminalKind, ChatGenerationTerminalKind.failed);
      // 安全收据：不携带原始错误文本，只携带固定失败分类。
      expect(receipt.failureKind, ChatGenerationTerminalFailureKind.unknown);
      expect(harness.port.calls.where((c) => c == 'remove'), ['remove']);
    });
  }

  // 空回复：多协议 SSE fake 助手（multi_protocol 集成测试）未提供空回复 SSE，
  // 此处经通用 fake 客户端链路验证空回复仍清理 ongoing 并报告 emptyReply 收据。
  test('空回复经 fake 链路投影 emptyReply 并报告安全收据', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);
    harness.fakeClient.enqueueChunks(const <String>[]);
    await _sendMessage(harness.container);

    final state = harness.container.read(chatSessionsProvider);
    expect(state.generation?.phase, ChatGenerationPhase.emptyReply);
    expect(state.generation?.outcome, isA<ChatGenerationEmptyReply>());

    await harness.port.waitForCall('remove');
    final receipt = harness.terminal.receipts.single;
    expect(receipt.terminalKind, ChatGenerationTerminalKind.emptyReply);
    expect(receipt.failureKind, ChatGenerationTerminalFailureKind.emptyReply);
    expect(harness.port.calls.where((c) => c == 'remove'), ['remove']);
  });
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

/// 构造指定协议的模型配置，供真实协议路由链路使用。
LlmModelConfig _modelConfigFor(LlmApiProtocol protocol) {
  return LlmModelConfig(
    id: 'model-${protocol.name}',
    displayName: protocol.displayName,
    apiUrl: 'https://api.example.com',
    apiKey: 'protocol-key',
    modelName: 'test-model',
    supportsReasoning: true,
    apiProtocol: protocol,
  );
}

/// 构造经共享传输层路由的真实协议客户端（多协议集成测试同款装配）。
ChatGenerationClient _routingClient(
  LlmApiProtocol protocol, {
  required bool fail,
}) {
  final transport = LlmHttpStreamTransport(
    httpClient: _ProtocolStreamingHttpClient(protocol: protocol, fail: fail),
  );
  return ProtocolRoutingChatGenerationClient(
    chatCompletions: ChatCompletionsClient(transport: transport),
    responses: ResponsesClient(transport: transport),
    anthropic: AnthropicMessagesClient(transport: transport),
  );
}

/// 构建真实 Riverpod wiring + fake 端口的集成测试装具。
///
/// 与生产组合一致地传入 [appCompositionOverrides]（排除三个 chat 端口的生产
/// 绑定，由测试 fake 接管），eager 读取通知协调器模拟应用根部的 watch。
/// [routingClient] 非空时接管生成客户端（多协议真实路由链路）。
Future<_Harness> _createHarness({
  FakeForegroundServicePort? port,
  ChatGenerationClient? routingClient,
}) async {
  final database = AppDatabase.inMemory();
  final preferences = await createSeededPreferences();
  final fakeClient = FakeChatGenerationClient();
  final repo = ControllableChatConversationRepository(database);
  final servicePort = port ?? FakeForegroundServicePort();
  final terminalNotifications = FakeTerminalNotifications();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...appCompositionOverrides(
        hostPlatform: TargetPlatform.windows,
        useInMemorySyncSecureStore: true,
        bindChatGenerationClient: false,
        bindChatConversationRepository: false,
        bindChatGenerationNotifications: false,
      ),
      // 固定 session：coordinator ongoing payload 与终态收据断言共用同一值。
      chatGenerationNotificationSessionIdProvider.overrideWithValue(
        _fixedSession,
      ),
      chatGenerationClientProvider.overrideWithValue(
        routingClient ?? fakeClient,
      ),
      chatConversationRepositoryProvider.overrideWithValue(repo),
      chatGenerationForegroundServiceProvider.overrideWithValue(servicePort),
      chatGenerationTerminalNotificationsProvider.overrideWithValue(
        terminalNotifications,
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
    terminal: terminalNotifications,
    container: container,
  );
}

final class _Harness {
  const _Harness({
    required this.database,
    required this.fakeClient,
    required this.repo,
    required this.port,
    required this.terminal,
    required this.container,
  });

  final AppDatabase database;
  final FakeChatGenerationClient fakeClient;
  final ControllableChatConversationRepository repo;
  final FakeForegroundServicePort port;
  final FakeTerminalNotifications terminal;
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
  Future<String?> takePendingOpenConversation() async {
    calls.add('takePendingOpenConversation');
    return null;
  }

  @override
  void dispose() {
    if (!actionsController.isClosed) actionsController.close();
  }
}

/// 终态通知端口 fake：记录 coordinator 经真实 Riverpod wiring 报告的收据。
class FakeTerminalNotifications implements ChatGenerationTerminalNotifications {
  final receipts = <ChatGenerationTerminalReceipt>[];

  @override
  Future<void> report(ChatGenerationTerminalReceipt receipt) async {
    receipts.add(receipt);
  }

  @override
  Future<void> dispose() async {}
}

/// 按协议返回固定 SSE 响应体的假 HTTP 客户端（多协议集成测试同款模式）。
final class _ProtocolStreamingHttpClient extends http.BaseClient {
  _ProtocolStreamingHttpClient({required this.protocol, required this.fail});

  final LlmApiProtocol protocol;
  final bool fail;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = fail ? _errorSse(protocol) : _successSse(protocol);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

const _finalContent = '正文';
const _finalReasoning = '思考';

String _successSse(LlmApiProtocol protocol) {
  return switch (protocol) {
    LlmApiProtocol.chatCompletions =>
      'data: {"choices":[{"delta":{"reasoning_content":"$_finalReasoning"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"$_finalContent"},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
    LlmApiProtocol.responses =>
      'data: {"type":"response.reasoning_summary_text.delta","delta":"$_finalReasoning"}\n\n'
          'data: {"type":"response.output_text.delta","delta":"$_finalContent"}\n\n'
          'data: {"type":"response.completed","response":{}}\n\n',
    LlmApiProtocol.anthropic =>
      'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"$_finalReasoning"}}\n\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"$_finalContent"}}\n\n'
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n'
          'data: {"type":"message_stop"}\n\n',
  };
}

String _errorSse(LlmApiProtocol protocol) {
  return switch (protocol) {
    LlmApiProtocol.chatCompletions =>
      'data: {"choices":[{"delta":{"content":"部分回复"}}]}\n\n'
          'data: {"error":{"message":"协议测试错误"}}\n\n',
    LlmApiProtocol.responses =>
      'data: {"type":"response.output_text.delta","delta":"部分回复"}\n\n'
          'data: {"type":"error","message":"协议测试错误","code":"test_error"}\n\n',
    LlmApiProtocol.anthropic =>
      'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"部分回复"}}\n\n'
          'data: {"type":"error","error":{"type":"test_error","message":"协议测试错误"}}\n\n',
  };
}
