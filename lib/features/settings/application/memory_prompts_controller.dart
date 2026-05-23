import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../data/sqlite_memory_prompt_repository.dart';
import '../domain/models/memory_prompt.dart';
import 'settings_entity_controller.dart';

final memoryPromptsProvider =
    NotifierProvider<MemoryPromptsController, List<MemoryPrompt>>(
      MemoryPromptsController.new,
    );

class MemoryPromptsController
    extends SettingsEntityController<MemoryPrompt> {
  @override
  SqliteEntityRepository<MemoryPrompt> get repository =>
      ref.read(memoryPromptRepositoryProvider);
}
