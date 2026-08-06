import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_generation_contract.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/chat_generation_run.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/application/chat_sessions_state.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

import '../../../helpers/fake_chat_completion_client.dart';

/// ChatGenerationRun 的 transition matrix 测试。
///
/// 用 [_FakeHost]（可控返回 prepare/completeAttempt/stop 决策 + gate）+
/// [FakeChatCompletionClient]（enqueueStream/chunks）覆盖完整状态机：
/// success / empty / failure / retry / 各阶段 stop / concurrent stop /
/// finalizing stop / dispose / persistence failure / late callback。
/// 不依赖 Riverpod 或真实 repository，只验证 run 的状态机不变量。
void main() {
  late FakeChatCompletionClient fakeClient;

  setUp(() {
    fakeClient = FakeChatCompletionClient();
  });

  Future<void> pump([int ms = 10]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

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
    final sc = StreamController<ChatCompletionChunk>();
    addTearDown(sc.close);
    fakeClient.enqueueStream(sc.stream);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await pump();
    sc.add(const ChatCompletionChunk(contentDelta: '部分'));
    await pump();
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
    await pump(50);
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.cancelled);
    expect(host.attempts, hasLength(1)); // 未跑第二 attempt
    expect(fakeClient.requestHistory, hasLength(1));
  });

  test('concurrent stop: idempotent, one stop call', () async {
    final sc = StreamController<ChatCompletionChunk>();
    addTearDown(sc.close);
    fakeClient.enqueueStream(sc.stream);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await pump();
    sc.add(const ChatCompletionChunk(contentDelta: 'x'));
    await pump();
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
    final sc = StreamController<ChatCompletionChunk>();
    addTearDown(sc.close);
    fakeClient.enqueueStream(sc.stream);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await pump();
    run.dispose();

    expect(await run.completion, isNull);
    final progressCount = host.progress.length;
    await pump();
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
    final sc = StreamController<ChatCompletionChunk>();
    addTearDown(sc.close);
    fakeClient.enqueueStream(sc.stream);
    final host = _FakeHost(
      stopDecision: const ChatStopPersistenceFailed('boom'),
    );
    final run = newRun(host: host);

    run.start();
    await pump();
    sc.add(const ChatCompletionChunk(contentDelta: 'x'));
    await pump();
    run.requestStop();
    await run.completion;

    expect(run.phase, ChatGenerationPhase.persistenceFailed);
  });

  // ── late callbacks ──────────────────────────────────────────────────────────

  test('late chunk/error after stop discarded, partial unchanged', () async {
    final sc = StreamController<ChatCompletionChunk>();
    addTearDown(sc.close);
    fakeClient.enqueueStream(sc.stream);
    final host = _FakeHost();
    final run = newRun(host: host);

    run.start();
    await pump();
    sc.add(const ChatCompletionChunk(contentDelta: 'part'));
    await pump();
    run.requestStop(); // cancel subscription, terminal cancelled
    await run.completion;

    // 迟到回调：token 失效后必须被丢弃。
    sc.add(const ChatCompletionChunk(contentDelta: 'late'));
    sc.addError(StateError('late err'));
    sc.close();
    await pump();

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
  final List<ChatAttemptSnapshot> attempts = [];
  final List<ChatPartialSnapshot> stops = [];
  final Completer<void> prepareEntered = Completer<void>();
  final Completer<void> completeAttemptEntered = Completer<void>();

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
      conversationId: command.conversation.id,
      assistantMessageId: assistantMessage.id,
      modelConfig: command.modelConfig,
      messages: const [],
      retryPolicy: command.retryPolicy,
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
