import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_contract.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_run.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';
import 'package:oh_my_llm/features/chat/application/requests/checkpoint_request_context.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

import '../../../../helpers/chat/fake_chat_generation_client.dart';

/// ChatGenerationRun 的 transition matrix 测试。
///
/// 用 [_FakeHost]（可控返回 prepare/completeAttempt/stop 决策 + gate）+
/// [FakeChatGenerationClient]（enqueueStream/chunks）覆盖完整状态机：
/// success / empty / failure / retry / 各阶段 stop / concurrent stop /
/// finalizing stop / dispose / persistence failure / late callback。
/// 不依赖 Riverpod 或真实 repository，只验证 run 的状态机不变量。
void main() {
  late FakeChatGenerationClient fakeClient;

  setUp(() {
    fakeClient = FakeChatGenerationClient();
  });

  ChatGenerationCommand newCommand({
    ChatRetryPolicy? retryPolicy,
    Duration? retryDelay,
  }) {
    return ChatGenerationCommand(
      conversation: ChatConversation(
        id: 'c1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      modelConfig: testModel,
      presetPrompt: null,
      requestContext: const CheckpointRequestContext(),
      parentMessageId: null,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
      retryPolicy: retryPolicy ?? disabledRetry,
      retryDelay: retryDelay,
    );
  }

  ChatGenerationRun newRun({_FakeHost? host, ChatGenerationCommand? command}) {
    return ChatGenerationRun(
      generationId: 1,
      client: fakeClient,
      host: host ?? _FakeHost(),
      command: command ?? newCommand(),
    );
  }

  // ── 正常路径 ─────────────────────────────────────────────────────────────────

  test('正文完成进入成功终态且首次尝试身份一致', () async {
    fakeClient.enqueueChunks(['hello']);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    final result = await run.completion;

    expect(run.phase, ChatGenerationPhase.succeeded);
    expect(result, isNotNull);
    final snapshot = host.progress.last.snapshot;
    expect(snapshot.phase, ChatGenerationPhase.succeeded);
    expect(snapshot.outcome, isA<ChatGenerationSuccess>());
    expect(snapshot.attempt, 1);
    expect(snapshot.generationId, 1);
    expect(host.attempts, hasLength(1));
  });

  test('连续协议 chunk 均立即投影完整累计内容', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened;
    for (final (delta, expected) in [
      ('第一段', '第一段'),
      ('第二段', '第一段第二段'),
      ('第三段', '第一段第二段第三段'),
    ]) {
      controlled.add(ChatGenerationChunk(contentDelta: delta));
      await host.waitForProjection(
        (progress) => progress.streamingReply?.content == expected,
      );
    }

    final projectedContents = host.progress
        .map((progress) => progress.streamingReply?.content)
        .whereType<String>()
        .where((content) => content.isNotEmpty)
        .toList();
    expect(projectedContents, ['第一段', '第一段第二段', '第一段第二段第三段']);

    await controlled.close();
    await run.completion;
  });

  test('空回复由结算决策进入空回复终态', () async {
    fakeClient.enqueueChunks(['']);
    final host = _FakeHost(
      attemptDecisionFor: (_) => const ChatAttemptGiveUp(
        ChatGenerationEmptyReply(generationId: 1, attempt: 1),
      ),
    );
    final run = newRun(host: host);

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.emptyReply);
    expect(
      host.progress.last.snapshot.outcome,
      isA<ChatGenerationEmptyReply>(),
    );
  });

  test('流错误由结算决策进入失败终态', () async {
    fakeClient.enqueueError(StateError('boom'));
    final host = _FakeHost(
      attemptDecisionFor: (s) => ChatAttemptGiveUp(
        ChatGenerationFailure(
          generationId: s.generationId,
          attempt: s.attempt,
          error: s.attemptOutcome,
        ),
      ),
    );
    final run = newRun(host: host);

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.failed);
    expect(host.progress.last.snapshot.outcome, isA<ChatGenerationFailure>());
  });

  test('重试后成功递增尝试编号，各次用量分别结算', () async {
    fakeClient.enqueueDeltas(const [
      ChatGenerationChunk(
        usage: LlmUsage(inputTokens: 10, cachedInputTokens: 5),
      ),
    ]); // attempt 1 空 -> retry
    fakeClient.enqueueDeltas(const [
      ChatGenerationChunk(
        contentDelta: 'ok',
        usage: LlmUsage(inputTokens: 7, cachedInputTokens: 0),
      ),
      ChatGenerationChunk(usage: LlmUsage(outputTokens: 3)),
    ]); // attempt 2 成功
    final host = _FakeHost(
      attemptDecisionFor: (s) => s.attempt == 1
          ? const ChatAttemptRetry()
          : ChatAttemptSucceed(s.streamingConversation),
    );
    final run = newRun(
      host: host,
      command: newCommand(
        retryPolicy: enabledRetry(maxRetryCount: 5),
        retryDelay: Duration.zero,
      ),
    );

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.succeeded);
    expect(host.attempts, hasLength(2));
    expect(host.attempts.first.attempt, 1);
    expect(host.attempts.last.attempt, 2);
    expect(
      host.attempts.first.usage,
      const LlmUsage(inputTokens: 10, cachedInputTokens: 5),
    );
    expect(
      host.attempts.last.usage,
      const LlmUsage(inputTokens: 7, outputTokens: 3, cachedInputTokens: 0),
    );
    expect(fakeClient.requestHistory, hasLength(2));
  });

  // ── stop ─────────────────────────────────────────────────────────────────────

  test('准备期间停止不发请求，取消快照保留停止来源', () async {
    fakeClient.enqueueChunks(['hello']); // 不应被消费
    final host = _FakeHost(prepareGate: Completer<void>());
    final run = newRun(host: host);

    run.start();
    await host.prepareEntered.future;
    run.requestStop();
    host.prepareGate!.complete();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(fakeClient.requestHistory, isEmpty); // 未启动网络
    expect(host.stops, hasLength(1));
    expect(host.stops.single.phase, ChatGenerationPhase.preparing);
    expect(host.stops.single.attempt, 1);
  });

  test('流式期间停止保留部分正文和用量', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(
      const ChatGenerationChunk(
        contentDelta: '部分',
        usage: LlmUsage(inputTokens: 8, cachedInputTokens: 2),
      ),
    );
    // 等 chunk 增量进入投影再 stop，保证 stop 时已累积部分内容。
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('部分') ?? false,
    );
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.stops, hasLength(1));
    expect(host.stops.single.content, '部分');
    expect(
      host.stops.single.usage,
      const LlmUsage(inputTokens: 8, cachedInputTokens: 2),
    );
  });

  test('等待重试期间停止不启动下一次尝试', () async {
    fakeClient.enqueueChunks(['']); // 空 -> retry
    fakeClient.enqueueChunks(['ok']); // 不应消费
    final host = _FakeHost(attemptDecisionFor: (_) => const ChatAttemptRetry());
    final run = newRun(
      host: host,
      command: newCommand(
        retryPolicy: enabledRetry(maxRetryCount: 5),
        retryDelay: const Duration(seconds: 1), // 长延迟，测试期间不 fire
      ),
    );

    run.start();
    // 等第一次 attempt 落空进入 retryWaiting 后再 stop，让 stop 落在重试等待窗口。
    await host.waitForProjection(
      (p) => p.snapshot.phase == ChatGenerationPhase.retryWaiting,
    );
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.attempts, hasLength(1)); // 未跑第二 attempt
    expect(fakeClient.requestHistory, hasLength(1));
  });

  test('并发停止只结算一次取消', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(const ChatGenerationChunk(contentDelta: 'x'));
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('x') ?? false,
    );
    run.requestStop();
    run.requestStop(); // 幂等

    expect(await run.completion, isNull);
    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.stops, hasLength(1)); // 只一次 stop
  });

  test('正在保存成功结果时停止不会覆盖已确定的终态', () async {
    fakeClient.enqueueChunks(['hello']);
    final host = _FakeHost(completeAttemptGate: Completer<void>());
    final run = newRun(host: host);

    run.start();
    await host.completeAttemptEntered.future; // completeAttempt 进入（finalizing）
    run.requestStop(); // finalizing 期间 stop
    host.completeAttemptGate!.complete(); // completeAttempt 返回 Succeed
    await run.completion;

    expect(run.phase, ChatGenerationPhase.succeeded);
    expect(host.progress.last.snapshot.outcome, isA<ChatGenerationSuccess>());
    expect(host.stops, isEmpty); // stop no-op
  });

  // ── dispose ─────────────────────────────────────────────────────────────────

  test('释放后返回空结果且迟到正文、错误和完成事件均不再投影', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 确认已进入流式后再 dispose
    final progressCount = host.progress.length;
    run.dispose();
    controlled.add(const ChatGenerationChunk(contentDelta: '迟到正文'));
    controlled.addError(StateError('迟到错误'));
    await controlled.close();
    expect(await run.completion, isNull);
    expect(host.progress, hasLength(progressCount));
    expect(host.attempts, isEmpty);
    expect(host.stops, isEmpty);
  });

  testWidgets('固定间隔重试实际等待配置时长，随后仅启动下一次尝试', (tester) async {
    const intervalSeconds = 2;
    const interval = Duration(seconds: intervalSeconds);
    const clockTick = Duration(milliseconds: 1);
    const jitterWindow = Duration(seconds: 1);
    fakeClient.enqueueChunks(['']);
    fakeClient.enqueueChunks(['成功']);
    final host = _FakeHost(
      attemptDecisionFor: (attempt) => attempt.attempt == 1
          ? const ChatAttemptRetry()
          : ChatAttemptSucceed(attempt.streamingConversation),
    );
    final run = newRun(
      host: host,
      command: newCommand(
        retryPolicy: const ChatRetryPolicy(
          enabled: true,
          maxRetryCount: 3,
          retryMode: RetryMode.fixedInterval,
          maxJitterSeconds: intervalSeconds,
          retryOnAbnormalFinishReason: false,
          retryOnTimeout: false,
          timeout: Duration.zero,
        ),
      ),
    );
    addTearDown(run.dispose);
    run.start();
    await tester.pump();
    expect(run.phase, ChatGenerationPhase.retryWaiting);
    await tester.pump(interval - clockTick);
    expect(fakeClient.requestHistory, hasLength(1));
    // 固定间隔含不足一秒的随机抖动；用虚拟时钟跨过整个区间。
    await tester.pump(jitterWindow + clockTick);
    await run.completion;
    expect(fakeClient.requestHistory, hasLength(2));
    expect(run.phase, ChatGenerationPhase.succeeded);
  });

  // ── persistence failure ─────────────────────────────────────────────────────

  test('准备落盘失败不发请求且进入持久化失败终态', () async {
    final host = _FakeHost(prepareResult: const ChatPrepareFailure('boom'));
    final run = newRun(host: host);

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.persistenceFailed);
    expect(
      host.progress.last.snapshot.outcome,
      isA<ChatGenerationPersistenceFailure>(),
    );
    expect(host.progress.last.snapshot.attempt, 1);
    expect(host.progress.last.snapshot.outcome?.attempt, 1);
    expect(fakeClient.requestHistory, isEmpty);
  });

  test('完成结算落盘失败进入持久化失败终态', () async {
    fakeClient.enqueueChunks(['hello']);
    final host = _FakeHost(
      attemptDecision: const ChatAttemptPersistenceFailed('boom'),
    );
    final run = newRun(host: host);

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.persistenceFailed);
  });

  test('停止落盘失败进入持久化失败终态', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost(
      stopDecision: const ChatStopPersistenceFailed('boom'),
    );
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(const ChatGenerationChunk(contentDelta: 'x'));
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('x') ?? false,
    );
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.persistenceFailed);
  });

  // ── late callbacks ──────────────────────────────────────────────────────────

  test('停止后的迟到正文和错误不改变已保存的部分内容', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(const ChatGenerationChunk(contentDelta: 'part'));
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('part') ?? false,
    );
    run.requestStop(); // cancel subscription, terminal cancelled
    await run.completion;

    // 迟到回调：订阅已随 stop 取消，事件被丢弃；run 已 terminal，无任何处理路径。
    controlled.add(const ChatGenerationChunk(contentDelta: 'late'));
    controlled.addError(StateError('late err'));
    await controlled.close();

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.stops.single.content, 'part'); // 不含 late
  });
}

final testModel = LlmModelConfig(
  id: 'm1',
  displayName: 'M',
  apiUrl: 'https://example.com',
  apiKey: 'k',
  modelName: 'm',
  supportsReasoning: false,
);

ChatRetryPolicy disabledRetry = ChatRetryPolicy(
  enabled: false,
  maxRetryCount: 0,
  retryMode: RetryMode.fixedInterval,
  maxJitterSeconds: 0,
  retryOnAbnormalFinishReason: false,
  retryOnTimeout: false,
  timeout: Duration.zero,
);

ChatRetryPolicy enabledRetry({int maxRetryCount = 3}) => ChatRetryPolicy(
  enabled: true,
  maxRetryCount: maxRetryCount,
  retryMode: RetryMode.fixedInterval,
  maxJitterSeconds: 0,
  retryOnAbnormalFinishReason: false,
  retryOnTimeout: false,
  timeout: Duration.zero,
);

/// 可控的 host：记录 progress/attempts/stops，按配置返回决策，支持 prepare /
/// completeAttempt 的 gate 以精确同步时序。
class _FakeHost implements ChatGenerationHost {
  _FakeHost({
    this.prepareResult,
    this.attemptDecision,
    this.attemptDecisionFor,
    this.stopDecision,
    this.prepareGate,
    this.completeAttemptGate,
  });

  final ChatPrepareResult? prepareResult;
  final ChatAttemptDecision? attemptDecision;
  final ChatAttemptDecision Function(ChatAttemptSnapshot)? attemptDecisionFor;
  final ChatStopDecision? stopDecision;
  final Completer<void>? prepareGate;
  final Completer<void>? completeAttemptGate;

  final List<ChatGenerationProgress> progress = [];
  final List<ChatGenerationProgress> projections = [];
  final List<(bool Function(ChatGenerationProgress), Completer<void>)>
  _projectionWaiters = [];
  final List<ChatAttemptSnapshot> attempts = [];
  final List<ChatPartialSnapshot> stops = [];
  final Completer<void> prepareEntered = Completer<void>();
  final Completer<void> completeAttemptEntered = Completer<void>();

  /// 等待 progress 投影满足 predicate；已满足时立即完成，不轮询。
  Future<void> waitForProjection(
    bool Function(ChatGenerationProgress) predicate,
  ) {
    for (final projection in projections) {
      if (predicate(projection)) return Future<void>.value();
    }
    final completer = Completer<void>();
    _projectionWaiters.add((predicate, completer));
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw TimeoutException('等待生成投影满足条件', const Duration(seconds: 5)),
    );
  }

  @override
  Future<ChatPrepareResult> prepare(ChatGenerationCommand command) async {
    if (!prepareEntered.isCompleted) prepareEntered.complete();
    if (prepareGate != null) await prepareGate!.future;
    return prepareResult ?? _defaultPrepare(command);
  }

  @override
  Future<ChatAttemptDecision> completeAttempt(
    ChatAttemptSnapshot attempt,
  ) async {
    attempts.add(attempt);
    if (!completeAttemptEntered.isCompleted) {
      completeAttemptEntered.complete();
    }
    if (completeAttemptGate != null) await completeAttemptGate!.future;
    return attemptDecisionFor?.call(attempt) ??
        attemptDecision ??
        ChatAttemptSucceed(attempt.streamingConversation);
  }

  @override
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial) async {
    stops.add(partial);
    return stopDecision ?? ChatStopCancelled(partial.streamingConversation);
  }

  @override
  void projectProgress(ChatGenerationProgress p) {
    progress.add(p);
    projections.add(p);
    // 完成即剪枝：已满足的 waiter 从列表移除，避免长测试中残留已完成项
    // 反复参与遍历。
    _projectionWaiters.removeWhere((waiter) {
      final (predicate, completer) = waiter;
      if (!completer.isCompleted && predicate(p)) {
        completer.complete();
        return true;
      }
      return false;
    });
  }

  /// 构造最小 prepare 成功结果：占位 assistant + 空 request + streamingReply。
  /// run 只驱动状态机，不验证树结构。
  ChatPrepareResult _defaultPrepare(ChatGenerationCommand command) {
    final assistantMessage = ChatMessage(
      id: 'a1',
      role: ChatMessageRole.assistant,
      content: '',
      createdAt: DateTime(2026, 1, 1),
      parentId: command.parentMessageId,
      isStreaming: true,
    );
    final request = ChatGenerationRequest(
      target: ChatGenerationRequestTarget(
        protocol: command.modelConfig.apiProtocol,
        endpoint: command.modelConfig.apiUrl.trim(),
        apiKey: command.modelConfig.apiKey,
        model: command.modelConfig.modelName,
      ),
      messages: const [],
    );
    return ChatPrepareSuccess(
      request: request,
      streamingConversation: command.conversation,
      assistantMessage: assistantMessage,
      streamingReply: ChatStreamingReply(
        conversationId: command.conversation.id,
        assistantMessageId: assistantMessage.id,
      ),
    );
  }
}
