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
}
