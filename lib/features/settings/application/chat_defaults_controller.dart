import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_defaults_repository.dart';
import '../domain/models/chat_defaults.dart';

final chatDefaultsProvider =
    NotifierProvider<ChatDefaultsController, ChatDefaults>(
      ChatDefaultsController.new,
    );

/// 聊天默认项状态控制器，负责默认模型和默认 Prompt 的持久化。
class ChatDefaultsController extends Notifier<ChatDefaults> {
  ChatDefaultsRepository get _repository =>
      ref.read(chatDefaultsRepositoryProvider);

  @override
  /// 读取持久化默认项并作为初始状态。
  ChatDefaults build() {
    return _repository.load();
  }

  /// 设置默认模型；传入空值时会清除默认模型。
  Future<void> setDefaultModelId(String? modelId) async {
    state = state.copyWith(
      defaultModelId: modelId,
      clearDefaultModelId: modelId == null,
    );
    await _repository.save(state);
  }

  /// 设置默认 Prompt 模板；传入空值时会清除默认模板。
  Future<void> setDefaultPromptTemplateId(String? promptTemplateId) async {
    state = state.copyWith(
      defaultPromptTemplateId: promptTemplateId,
      clearDefaultPromptTemplateId: promptTemplateId == null,
    );
    await _repository.save(state);
  }

  /// 当指定模型恰好是默认模型时，清除默认模型引用。
  Future<void> clearDefaultModelIdIfMatches(String modelId) async {
    if (state.defaultModelId != modelId) {
      return;
    }

    await setDefaultModelId(null);
  }

  /// 当指定模板恰好是默认模板时，清除默认模板引用。
  Future<void> clearDefaultPromptTemplateIdIfMatches(
    String promptTemplateId,
  ) async {
    if (state.defaultPromptTemplateId != promptTemplateId) {
      return;
    }

    await setDefaultPromptTemplateId(null);
  }
}
