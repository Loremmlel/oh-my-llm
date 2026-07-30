import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

void main() {
  // ── 辅助工厂 ─────────────────────────────────────────────

  ChatGenerationSnapshot snapshot({
    int generationId = 1,
    String conversationId = 'conv-1',
    String? assistantMessageId = 'a1',
    int attempt = 1,
    ChatGenerationPhase phase = ChatGenerationPhase.streaming,
    ChatCancelReason? cancelReason,
    ChatGenerationOutcome? outcome,
  }) {
    return ChatGenerationSnapshot(
      generationId: generationId,
      conversationId: conversationId,
      assistantMessageId: assistantMessageId,
      attempt: attempt,
      phase: phase,
      cancelReason: cancelReason,
      outcome: outcome,
    );
  }

  AutoRetrySettings retrySettings({
    int maxRetryCount = 3,
    RetryMode retryMode = RetryMode.fixedInterval,
    int maxJitterSeconds = 5,
    bool retryOnAbnormalFinishReason = true,
    bool retryOnTimeout = true,
    int timeoutSeconds = 20,
  }) {
    return AutoRetrySettings(
      maxRetryCount: maxRetryCount,
      retryMode: retryMode,
      maxJitterSeconds: maxJitterSeconds,
      retryOnAbnormalFinishReason: retryOnAbnormalFinishReason,
      retryOnTimeout: retryOnTimeout,
      timeoutSeconds: timeoutSeconds,
    );
  }

  LlmModelConfig modelConfig() => const LlmModelConfig(
    id: 'model-1',
    displayName: 'Test',
    apiUrl: 'https://api.example.com/v1/chat/completions',
    apiKey: 'sk-test',
    modelName: 'test-model',
    supportsReasoning: true,
  );

  // ── ChatGenerationSnapshot ───────────────────────────────

  group('ChatGenerationSnapshot', () {
    test('copyWith 更新 phase 且保留其余字段', () {
      final s = snapshot(phase: ChatGenerationPhase.preparing);
      final next = s.copyWith(phase: ChatGenerationPhase.streaming);

      expect(next.phase, ChatGenerationPhase.streaming);
      expect(next.generationId, s.generationId);
      expect(next.conversationId, s.conversationId);
      expect(next.attempt, s.attempt);
    });

    test('copyWith 将 assistantMessageId 从 null 填充为值', () {
      final s = snapshot(
        assistantMessageId: null,
        phase: ChatGenerationPhase.preparing,
      );
      expect(s.assistantMessageId, isNull);

      final next = s.copyWith(assistantMessageId: 'a1');
      expect(next.assistantMessageId, 'a1');
    });

    test('Equatable：相同核心字段相等', () {
      expect(snapshot(), equals(snapshot()));
    });

    test('Equatable：phase 不同则不等', () {
      final a = snapshot(phase: ChatGenerationPhase.streaming);
      final b = snapshot(phase: ChatGenerationPhase.succeeded);
      expect(a, isNot(equals(b)));
    });

    test('Equatable：generationId 不同则不等（区分新旧 generation）', () {
      expect(
        snapshot(generationId: 1),
        isNot(equals(snapshot(generationId: 2))),
      );
    });

    test('outcome 不参与值相等：相同 phase 不同 outcome 实例仍相等', () {
      final outcomeA = ChatGenerationSuccess(
        generationId: 1,
        attempt: 1,
        content: 'x',
        reasoningContent: '',
      );
      final outcomeB = ChatGenerationSuccess(
        generationId: 1,
        attempt: 1,
        content: 'y',
        reasoningContent: '',
      );
      // phase 相同但 outcome 内容不同，snapshot 仍按核心字段判等。
      expect(
        snapshot(phase: ChatGenerationPhase.succeeded, outcome: outcomeA),
        equals(
          snapshot(phase: ChatGenerationPhase.succeeded, outcome: outcomeB),
        ),
      );
    });

    test('cancelReason 仅在 cancelled 阶段语义上有值', () {
      final s = snapshot(
        phase: ChatGenerationPhase.cancelled,
        cancelReason: ChatCancelReason.userStop,
      );
      expect(s.cancelReason, ChatCancelReason.userStop);
    });
  });

  // ── ChatRetryPolicy ──────────────────────────────────────

  group('ChatRetryPolicy.fromSnapshot', () {
    test('正确映射 AutoRetrySettings 的全部字段', () {
      final policy = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(),
      );

      expect(policy.enabled, isTrue);
      expect(policy.maxRetryCount, 3);
      expect(policy.retryMode, RetryMode.fixedInterval);
      expect(policy.maxJitterSeconds, 5);
      expect(policy.retryOnAbnormalFinishReason, isTrue);
      expect(policy.retryOnTimeout, isTrue);
      expect(policy.timeout, const Duration(seconds: 20));
    });

    test('enabled 来自会话开关而非全局设置', () {
      // 全局 maxRetryCount=3，但会话关闭 auto-retry，policy.enabled 应为 false。
      final policy = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: false,
        settings: retrySettings(maxRetryCount: 3),
      );

      expect(policy.enabled, isFalse);
      // 即便 enabled=false，其余字段仍按设置快照填充，供 coordinator 判断。
      expect(policy.maxRetryCount, 3);
    });

    test('timeoutSeconds 转换为 Duration', () {
      final policy = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(timeoutSeconds: 45),
      );

      expect(policy.timeout, const Duration(seconds: 45));
    });
  });

  group('ChatRetryPolicy Equatable', () {
    test('相同字段相等', () {
      final a = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(),
      );
      final b = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(),
      );

      expect(a, equals(b));
    });

    test('retryMode 不同则不等', () {
      final a = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(retryMode: RetryMode.fixedInterval),
      );
      final b = ChatRetryPolicy.fromSnapshot(
        conversationAutoRetryEnabled: true,
        settings: retrySettings(retryMode: RetryMode.perMinuteWindow),
      );

      expect(a, isNot(equals(b)));
    });
  });

  // ── ChatGenerationRequest ────────────────────────────────

  group('ChatGenerationRequest', () {
    ChatGenerationRequest request({
      String conversationId = 'conv-1',
      String assistantMessageId = 'a1',
      List<ChatCompletionRequestMessage> messages = const [
        ChatCompletionRequestMessage(role: ChatMessageRole.user, content: 'hi'),
      ],
    }) {
      return ChatGenerationRequest(
        conversationId: conversationId,
        assistantMessageId: assistantMessageId,
        modelConfig: modelConfig(),
        messages: messages,
        retryPolicy: ChatRetryPolicy.fromSnapshot(
          conversationAutoRetryEnabled: false,
          settings: AutoRetrySettings(),
        ),
      );
    }

    test('构造携带全部请求输入', () {
      final r = request();

      expect(r.conversationId, 'conv-1');
      expect(r.assistantMessageId, 'a1');
      expect(r.modelConfig.id, 'model-1');
      expect(r.messages, hasLength(1));
      expect(r.retryPolicy.enabled, isFalse);
    });

    test('Equatable：相同 messages 内容相等', () {
      expect(request(), equals(request()));
    });

    test('Equatable：messages 内容不同则不等', () {
      final a = request(
        messages: const [
          ChatCompletionRequestMessage(
            role: ChatMessageRole.user,
            content: 'a',
          ),
        ],
      );
      final b = request(
        messages: const [
          ChatCompletionRequestMessage(
            role: ChatMessageRole.user,
            content: 'b',
          ),
        ],
      );

      expect(a, isNot(equals(b)));
    });
  });

  // ── ChatGenerationOutcome 类型区分 ────────────────────────

  group('ChatGenerationOutcome', () {
    test('success 携带内容与 finishReason', () {
      const outcome = ChatGenerationSuccess(
        generationId: 1,
        attempt: 1,
        content: '正文',
        reasoningContent: '推理',
        finishReason: 'stop',
      );

      expect(outcome, isA<ChatGenerationSuccess>());
      expect(outcome.content, '正文');
      expect(outcome.reasoningContent, '推理');
      expect(outcome.finishReason, 'stop');
      expect(outcome.generationId, 1);
      expect(outcome.attempt, 1);
    });

    test('emptyReply 携带 finishReason', () {
      const outcome = ChatGenerationEmptyReply(
        generationId: 1,
        attempt: 2,
        finishReason: 'stop',
      );

      expect(outcome, isA<ChatGenerationEmptyReply>());
      expect(outcome.finishReason, 'stop');
    });

    test('failure 携带 error 与 stackTrace', () {
      final error = Exception('boom');
      const stack = StackTrace.empty;
      final outcome = ChatGenerationFailure(
        generationId: 1,
        attempt: 1,
        error: error,
        stackTrace: stack,
      );

      expect(outcome, isA<ChatGenerationFailure>());
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, stack);
    });

    test('cancelled 携带 reason 与部分内容', () {
      const outcome = ChatGenerationCancelled(
        generationId: 1,
        attempt: 1,
        reason: ChatCancelReason.userStop,
        partialContent: '已收到',
      );

      expect(outcome, isA<ChatGenerationCancelled>());
      expect(outcome.reason, ChatCancelReason.userStop);
      expect(outcome.partialContent, '已收到');
    });

    test('persistenceFailure 携带 error', () {
      final error = Exception('save failed');
      final outcome = ChatGenerationPersistenceFailure(
        generationId: 1,
        attempt: 1,
        error: error,
      );

      expect(outcome, isA<ChatGenerationPersistenceFailure>());
      expect(outcome.error, same(error));
    });

    test('五个终态子类互不相交', () {
      const success = ChatGenerationSuccess(
        generationId: 1,
        attempt: 1,
        content: '',
        reasoningContent: '',
      );
      const empty = ChatGenerationEmptyReply(generationId: 1, attempt: 1);
      final failure = ChatGenerationFailure(
        generationId: 1,
        attempt: 1,
        error: Exception(),
      );
      const cancelled = ChatGenerationCancelled(
        generationId: 1,
        attempt: 1,
        reason: ChatCancelReason.userStop,
      );
      final persistence = ChatGenerationPersistenceFailure(
        generationId: 1,
        attempt: 1,
        error: Exception(),
      );

      // 同一 generationId/attempt，但五种类型可被 switch 互斥分派。
      for (final outcome in [success, empty, failure, cancelled, persistence]) {
        switch (outcome) {
          case ChatGenerationSuccess():
            expect(outcome, same(success));
          case ChatGenerationEmptyReply():
            expect(outcome, same(empty));
          case ChatGenerationFailure():
            expect(outcome, same(failure));
          case ChatGenerationCancelled():
            expect(outcome, same(cancelled));
          case ChatGenerationPersistenceFailure():
            expect(outcome, same(persistence));
        }
      }
    });
  });
}
