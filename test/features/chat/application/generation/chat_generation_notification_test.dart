import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/generation/chat_generation_lifecycle.dart';
import 'package:oh_my_llm/features/chat/application/generation/chat_generation_notification.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_generation_client.dart';

void main() {
  test('终态错误只投影安全摘要，原始凭据不进入通知', () {
    const secret = 'sk-secret-123';
    for (final error in [
      ChatGenerationException(
        'Authorization: $secret',
        statusCode: 401,
        responseBody: '用户正文和 $secret',
      ),
      StateError(secret),
    ]) {
      final projection = const ChatGenerationNotificationProjector().project(
        snapshot: ChatGenerationSnapshot(
          generationId: 1,
          conversationId: 'conversation',
          attempt: 1,
          phase: ChatGenerationPhase.failed,
          outcome: ChatGenerationFailure(
            generationId: 1,
            attempt: 1,
            error: error,
          ),
        ),
        counts: ChatGenerationCharacterCounts.zero,
      );
      final payload = projection.payload;
      expect(
        [
          payload.title,
          payload.text,
          payload.publicTitle,
          payload.publicText,
        ].join(),
        isNot(contains(secret)),
      );
    }
  });
}
