import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/features/chat/application/favorites/chat_favorites_facade.dart';

void main() {
  test('snapshot 按助手内容定位收藏，并暴露收藏夹选项', () {
    const draft = ChatFavoriteDraft(
      userMessageContent: '问题',
      assistantContent: '回复',
      assistantReasoningContent: '',
      assistantModelDisplayName: 'Test',
      collectionId: null,
      sourceAssistantMessageId: 'message-1',
      sourceConversationId: 'conversation-1',
      sourceConversationTitle: '对话',
    );
    const snapshot = ChatFavoritesSnapshot(
      entries: [ChatFavoriteEntry(id: 'favorite-1', draft: draft)],
      collections: [
        ChatFavoriteCollectionOption(id: 'collection-1', name: '工作'),
      ],
    );

    expect(snapshot.favoritedAssistantContents, {'回复'});
    expect(snapshot.findByAssistantContent('回复')?.id, 'favorite-1');
    expect(snapshot.collections.single.name, '工作');
  });
}
