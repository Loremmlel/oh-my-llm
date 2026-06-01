import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../data/preset_prompt_repository.dart';
import '../domain/models/preset_prompt.dart';
import 'settings_entity_controller.dart';

final presetPromptsProvider =
    NotifierProvider<PresetPromptsController, List<PresetPrompt>>(
      PresetPromptsController.new,
    );

class PresetPromptsController
    extends SettingsEntityController<PresetPrompt> {
  @override
  SqliteEntityRepository<PresetPrompt> get repository =>
      ref.read(presetPromptRepositoryProvider);

  /// 切换指定预设中某条消息的启用/禁用状态，并持久化到 SQLite。
  void toggleMessageEnabled(String presetId, String messageId) {
    final preset = state.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;
    final updatedMessages = preset.messages.map((m) {
      if (m.id == messageId) return m.copyWith(enabled: !m.enabled);
      return m;
    }).toList();
    upsert(preset.copyWith(messages: updatedMessages));
  }
}
