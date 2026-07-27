import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Favorites 发起的来源对话定位命令。
abstract interface class FavoriteSourceConversationCommand {
  void selectSourceConversation({
    required String conversationId,
    String? assistantMessageId,
  });
}

/// 必须由 app composition 或测试显式绑定的来源对话命令。
final favoriteSourceConversationCommandProvider =
    Provider<FavoriteSourceConversationCommand>((ref) {
      throw StateError('FavoriteSourceConversationCommand 尚未由应用组合层绑定');
    });
