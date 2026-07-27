import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/favorites/application/favorite_source_conversation_command.dart';

void main() {
  test('来源对话命令接收 conversation 与 assistant message 标识', () {
    final command = _RecordingCommand();

    command.selectSourceConversation(
      conversationId: 'conversation-1',
      assistantMessageId: 'assistant-1',
    );

    expect(command.conversationId, 'conversation-1');
    expect(command.assistantMessageId, 'assistant-1');
  });
}

final class _RecordingCommand implements FavoriteSourceConversationCommand {
  String? conversationId;
  String? assistantMessageId;

  @override
  void selectSourceConversation({
    required String conversationId,
    String? assistantMessageId,
  }) {
    this.conversationId = conversationId;
    this.assistantMessageId = assistantMessageId;
  }
}
