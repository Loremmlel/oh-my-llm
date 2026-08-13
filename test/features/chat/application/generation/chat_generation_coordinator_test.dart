import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_contract.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_coordinator.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/sessions/chat_sessions_state.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_conversation.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/preferences/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/providers/llm_model_config.dart';

import '../../../../helpers/fake_chat_generation_client.dart';

/// ChatGenerationCoordinator 是 run 的薄包装：start/stop/dispose 转发到 run，
/// 逻辑由 [ChatGenerationRun] 的 transition matrix 测试覆盖。此处只验证
/// coordinator 的包装契约：start 返回 completion、stop 返回同一 completion（幂等）、
/// dispose complete null、hasActive 随 terminal 翻转。
void main() {
  late FakeChatGenerationClient fakeClient;
  late ChatGenerationCoordinator coordinator;

  setUp(() {
    fakeClient = FakeChatGenerationClient();
    coordinator = ChatGenerationCoordinator(client: fakeClient);
  });
  // 用 lambda 而非 tear-off：tearDown 在 main 顶层注册，此时 `coordinator`（late）
  // 尚未由 setUp 初始化；且每个 test 的 setUp 会重赋值 coordinator，tear-off 会绑定
  // 到首个实例，lambda 才能在实际执行时读取当前实例。
  tearDown(() => coordinator.dispose());

  ChatGenerationCommand newCommand() {
    return ChatGenerationCommand(
      conversation: ChatConversation(
        id: 'c1',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      modelConfig: _testModel,
      presetPrompt: null,
      requestConversationMessages: const [],
      requestCheckpointChain: const [],
      parentMessageId: null,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
      appliedCheckpointTitle: '',
      retryPolicy: _disabledRetry,
    );
  }

  test('start 返回 completion，run terminal 后 complete 且 hasActive 翻转', () async {
    fakeClient.enqueueChunks(['hello']);
    final host = _FakeHost();
    expect(coordinator.hasActive, isFalse);

    final completion = coordinator.start(newCommand(), host);
    expect(coordinator.hasActive, isTrue);

    final result = await completion;
    expect(result, isNotNull);
    expect(coordinator.hasActive, isFalse); // terminal 后 hasActive false
    expect(host.progress.last.snapshot.phase, ChatGenerationPhase.succeeded);
  });

  test('active run 存在时并发 start 返回同一 completion 且不启动第二个 run', () async {
    fakeClient.enqueueChunks(['hello']);
    final firstHost = _FakeHost();
    final secondHost = _FakeHost();

    final firstCompletion = coordinator.start(newCommand(), firstHost);
    final secondCompletion = coordinator.start(newCommand(), secondHost);

    expect(secondCompletion, same(firstCompletion));
    await firstCompletion;
    expect(firstHost.prepareCallCount, 1);
    expect(secondHost.prepareCallCount, 0);
    expect(fakeClient.requestHistory, hasLength(1));
  });

  test('stop 返回同一 completion，最终 cancelled', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final completion = coordinator.start(newCommand(), host);
    await controlled.listened; // 等待 run 开始监听后再投递 chunk
    controlled.add(const ChatGenerationChunk(contentDelta: '部分'));
    await host.waitForProjection(
      (p) => p.streamingReply?.content.contains('部分') ?? false,
    );

    final stopCompletion = coordinator.stop();
    expect(stopCompletion, same(completion)); // 幂等：返回同一 completion

    expect(await completion, isNull); // cancelled -> null
    expect(host.progress.last.snapshot.phase, ChatGenerationPhase.cancelled);
  });

  test('dispose complete null 且 hasActive false', () async {
    final controlled = fakeClient.enqueueControlledStream();
    addTearDown(controlled.close);
    final host = _FakeHost();
    final completion = coordinator.start(newCommand(), host);
    await controlled.listened; // 确认已开始监听后再 dispose

    coordinator.dispose();
    expect(await completion, isNull);
    expect(coordinator.hasActive, isFalse);
  });

  test('无 run 时 stop 返回同步 null', () async {
    expect(await coordinator.stop(), isNull);
  });
}

final _testModel = LlmModelConfig(
  id: 'm1',
  displayName: 'M',
  apiUrl: 'https://example.com',
  apiKey: 'k',
  modelName: 'm',
  supportsReasoning: false,
);

final _disabledRetry = ChatRetryPolicy(
  enabled: false,
  maxRetryCount: 0,
  retryMode: RetryMode.fixedInterval,
  maxJitterSeconds: 0,
  retryOnAbnormalFinishReason: false,
  retryOnTimeout: false,
  timeout: Duration.zero,
);

/// 最小 host：prepare 返回默认 success，completeAttempt 返回 Succeed，
/// stop 返回 Cancelled，projectProgress 记录。
class _FakeHost implements ChatGenerationHost {
  final List<ChatGenerationProgress> progress = [];
  final List<ChatGenerationProgress> projections = [];
  final List<(bool Function(ChatGenerationProgress), Completer<void>)>
  _projectionWaiters = [];
  int prepareCallCount = 0;

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
    prepareCallCount++;
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

  @override
  Future<ChatAttemptDecision> completeAttempt(
    ChatAttemptSnapshot attempt,
  ) async {
    return ChatAttemptSucceed(attempt.streamingConversation);
  }

  @override
  Future<ChatStopDecision> stop(ChatPartialSnapshot partial) async {
    return ChatStopCancelled(partial.streamingConversation);
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
}
