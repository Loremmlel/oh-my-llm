import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_defaults_repository.dart';
import '../domain/models/chat_defaults.dart';

final chatDefaultsProvider =
    NotifierProvider<ChatDefaultsController, ChatDefaults>(
      ChatDefaultsController.new,
    );

/// 聊天页最近一次选择记忆控制器。
class ChatDefaultsController extends Notifier<ChatDefaults> {
  ChatDefaultsRepository get _repository =>
      ref.read(chatDefaultsRepositoryProvider);

  @override
  /// 读取持久化的最近一次聊天选择并作为初始状态。
  ChatDefaults build() {
    return _repository.load();
  }

  /// 记住最近一次使用的模型；传入空值时会清除记忆。
  Future<void> rememberModelId(String? modelId) async {
    state = state.copyWith(
      defaultModelId: modelId,
      clearDefaultModelId: modelId == null,
    );
    await _repository.save(state);
  }

  /// 记住最近一次使用的前置 Prompt；传入空值时会清除记忆。
  Future<void> rememberPromptTemplateId(String? promptTemplateId) async {
    state = state.copyWith(
      defaultPromptTemplateId: promptTemplateId,
      clearDefaultPromptTemplateId: promptTemplateId == null,
    );
    await _repository.save(state);
  }

  /// 当指定模型恰好是最近一次使用模型时，清除对应记忆。
  Future<void> clearRememberedModelIdIfMatches(String modelId) async {
    if (state.defaultModelId != modelId) {
      return;
    }

    await rememberModelId(null);
  }

  /// 当指定模板恰好是最近一次使用的前置 Prompt 时，清除对应记忆。
  Future<void> clearRememberedPromptTemplateIdIfMatches(
    String promptTemplateId,
  ) async {
    if (state.defaultPromptTemplateId != promptTemplateId) {
      return;
    }

    await rememberPromptTemplateId(null);
  }
}
