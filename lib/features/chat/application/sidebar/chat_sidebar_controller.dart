import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

enum ChatSidebarFunction { history, preset }

const _prefsKeyActiveFunction = 'sidebar_activeFunction';

/// 只记住抽屉分段；开关由 Scaffold 管理，宽度由响应式布局决定。
final chatSidebarProvider =
    NotifierProvider<ChatSidebarController, ChatSidebarFunction>(
      ChatSidebarController.new,
    );

class ChatSidebarController extends Notifier<ChatSidebarFunction> {
  @override
  ChatSidebarFunction build() {
    final saved = ref
        .watch(sharedPreferencesProvider)
        .getString(_prefsKeyActiveFunction);
    return ChatSidebarFunction.values
            .where((function) => function.name == saved)
            .firstOrNull ??
        ChatSidebarFunction.history;
  }

  Future<void> selectFunction(ChatSidebarFunction function) async {
    if (state == function) return;
    state = function;
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setString(_prefsKeyActiveFunction, function.name);
    } catch (e) {
      debugPrint('[ChatSidebar] 保存分段失败: $e');
    }
  }
}
