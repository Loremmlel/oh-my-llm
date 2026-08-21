import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_reserved_entities.dart';
import 'package:oh_my_llm/features/chat/application/favorites/chat_favorites_facade.dart';

void main() {
  test('snapshot 按助手内容定位收藏，并暴露收藏夹选项与默认归属', () {
    const draft = ChatFavoriteDraft(
      userMessageContent: '问题',
      assistantContent: '回复',
      assistantReasoningContent: '',
      assistantModelDisplayName: 'Test',
      collectionId: AppReservedEntities.uncategorizedFavoriteCollectionId,
      sourceAssistantMessageId: 'message-1',
      sourceConversationId: 'conversation-1',
      sourceConversationTitle: '对话',
    );
    const snapshot = ChatFavoritesSnapshot(
      entries: [ChatFavoriteEntry(id: 'favorite-1', draft: draft)],
      collections: [
        ChatFavoriteCollectionOption(id: 'collection-1', name: '工作'),
      ],
      defaultCollectionId:
          AppReservedEntities.uncategorizedFavoriteCollectionId,
    );

    expect(snapshot.favoritedAssistantContents, {'回复'});
    expect(snapshot.findByAssistantContent('回复')?.id, 'favorite-1');
    expect(snapshot.findByAssistantContent('不存在'), isNull);
    expect(snapshot.collections.single.name, '工作');
    // draft 归属必填非空，默认归属来自最近有效收藏夹。
    expect(
      snapshot.entries.single.draft.collectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
    expect(
      snapshot.defaultCollectionId,
      AppReservedEntities.uncategorizedFavoriteCollectionId,
    );
  });
}
