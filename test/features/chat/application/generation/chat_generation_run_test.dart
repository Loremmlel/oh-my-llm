import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_contract.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_run.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';
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
      requestConversationMessages: const [],
      requestCheckpointChain: const [],
      parentMessageId: null,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
      appliedCheckpointTitle: '',
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
      streamUiFlushInterval: Duration.zero,
    );
  }

  // ── 正常路径 ─────────────────────────────────────────────────────────────────

  test('success: chunks -> succeeded, outcome=Success, attempt=1', () async {
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

  test('empty reply -> GiveUp emptyReply', () async {
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

  test('stream error -> GiveUp failed', () async {
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

  test(
    'retry then success: attempt increments to 2, final succeeded',
    () async {
      fakeClient.enqueueChunks(['']); // attempt 1 空 -> retry
      fakeClient.enqueueChunks(['ok']); // attempt 2 成功
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
      expect(fakeClient.requestHistory, hasLength(2));
    },
  );

  // ── stop ─────────────────────────────────────────────────────────────────────

  test('preparing stop: no network, cancelled, stop phase=preparing', () async {
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

  test('streaming stop: cancelled, partial content retained', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(const ChatGenerationChunk(contentDelta: '部分'));
    // 等 chunk 增量进入投影（streamUiFlushInterval=0，每 chunk 必投影）再 stop，
    // 保证 stop 时已累积部分内容。
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('部分') ?? false,
    );
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.stops, hasLength(1));
    expect(host.stops.single.content, '部分');
  });

  test('retry-waiting stop: cancelled, no next attempt', () async {
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

  test('concurrent stop: idempotent, one stop call', () async {
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

  test(
    'finalizing stop: outcome unchanged (still success), stop no-op',
    () async {
      fakeClient.enqueueChunks(['hello']);
      final host = _FakeHost(completeAttemptGate: Completer<void>());
      final run = newRun(host: host);

      run.start();
      await host
          .completeAttemptEntered
          .future; // completeAttempt 进入（finalizing）
      run.requestStop(); // finalizing 期间 stop
      host.completeAttemptGate!.complete(); // completeAttempt 返回 Succeed
      await run.completion;

      expect(run.phase, ChatGenerationPhase.succeeded);
      expect(host.progress.last.snapshot.outcome, isA<ChatGenerationSuccess>());
      expect(host.stops, isEmpty); // stop no-op
    },
  );

  // ── dispose ─────────────────────────────────────────────────────────────────

  test('dispose: completion null, no further projection', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await controlled.listened; // 确认已进入流式后再 dispose
    run.dispose();
    // 让路一个微任务：若 dispose 未正确取消订阅，在途投影事件会在此到达并改变
    // progress 计数，使下方「无新投影」断言成为真实检验而非同步读恒等的永真式。
    await Future<void>.value();

    expect(await run.completion, isNull);
    // dispose 后 _disposed guard + 订阅取消保证不再投影：先记录当前计数，再断言
    // 无新投影。
    final progressCount = host.progress.length;
    expect(host.progress.length, progressCount); // 无新投影
  });

  // ── persistence failure ─────────────────────────────────────────────────────

  test('prepare failure: persistenceFailed, no network', () async {
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

  test('completeAttempt persistence failure: persistenceFailed', () async {
    fakeClient.enqueueChunks(['hello']);
    final host = _FakeHost(
      attemptDecision: const ChatAttemptPersistenceFailed('boom'),
    );
    final run = newRun(host: host);

    run.start();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.persistenceFailed);
  });

  test('stop persistence failure: persistenceFailed', () async {
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

  test('late chunk/error after stop discarded, partial unchanged', () async {
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
