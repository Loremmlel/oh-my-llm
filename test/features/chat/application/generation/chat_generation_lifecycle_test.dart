import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/settings/domain/models/auto_retry_settings.dart';

void main() {
  test('snapshot 值相等刻意忽略 terminal outcome 内容', () {
    ChatGenerationSnapshot snapshot(ChatGenerationOutcome outcome) {
      return ChatGenerationSnapshot(
        generationId: 1,
        conversationId: 'conv-1',
        assistantMessageId: 'a1',
        attempt: 1,
        phase: ChatGenerationPhase.succeeded,
        outcome: outcome,
      );
    }

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

    expect(snapshot(outcomeA), equals(snapshot(outcomeB)));
  });

  test('retry policy 映射会话开关与 AutoRetrySettings 全部字段', () {
    const settings = AutoRetrySettings(
      maxRetryCount: 3,
      retryMode: RetryMode.fixedInterval,
      maxJitterSeconds: 5,
      retryOnAbnormalFinishReason: true,
      retryOnTimeout: true,
      timeoutSeconds: 20,
    );

    final enabled = ChatRetryPolicy.fromSnapshot(
      conversationAutoRetryEnabled: true,
      settings: settings,
    );
    final disabled = ChatRetryPolicy.fromSnapshot(
      conversationAutoRetryEnabled: false,
      settings: settings,
    );

    expect(enabled.enabled, isTrue);
    expect(disabled.enabled, isFalse);
    expect(enabled.maxRetryCount, 3);
    expect(enabled.retryMode, RetryMode.fixedInterval);
    expect(enabled.maxJitterSeconds, 5);
    expect(enabled.retryOnAbnormalFinishReason, isTrue);
    expect(enabled.retryOnTimeout, isTrue);
    expect(enabled.timeout, const Duration(seconds: 20));
  });
}
