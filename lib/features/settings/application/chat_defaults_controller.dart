import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_defaults_repository.dart';
import '../domain/models/chat_defaults.dart';

final chatDefaultsProvider =
    NotifierProvider<ChatDefaultsController, ChatDefaults>(
      ChatDefaultsController.new,
    );

class ChatDefaultsController extends Notifier<ChatDefaults> {
  ChatDefaultsRepository get _repository =>
      ref.read(chatDefaultsRepositoryProvider);

  @override
  ChatDefaults build() {
    return _repository.load();
  }

  Future<void> setDefaultModelId(String? modelId) async {
    state = state.copyWith(
      defaultModelId: modelId,
      clearDefaultModelId: modelId == null,
    );
    await _repository.save(state);
  }

  Future<void> setDefaultPromptTemplateId(String? promptTemplateId) async {
    state = state.copyWith(
      defaultPromptTemplateId: promptTemplateId,
      clearDefaultPromptTemplateId: promptTemplateId == null,
    );
    await _repository.save(state);
  }

  Future<void> clearDefaultModelIdIfMatches(String modelId) async {
    if (state.defaultModelId != modelId) {
      return;
    }

    await setDefaultModelId(null);
  }

  Future<void> clearDefaultPromptTemplateIdIfMatches(
    String promptTemplateId,
  ) async {
    if (state.defaultPromptTemplateId != promptTemplateId) {
      return;
    }

    await setDefaultPromptTemplateId(null);
  }
}
