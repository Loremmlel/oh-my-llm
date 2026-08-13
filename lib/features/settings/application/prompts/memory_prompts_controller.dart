import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';
import '../../data/prompts/sqlite_memory_prompt_repository.dart';
import '../../domain/models/prompts/memory_prompt.dart';
import 'settings_entity_controller.dart';

final memoryPromptsProvider =
    NotifierProvider<MemoryPromptsController, List<MemoryPrompt>>(
      MemoryPromptsController.new,
    );

class MemoryPromptsController extends SettingsEntityController<MemoryPrompt> {
  @override
  SqliteEntityRepository<MemoryPrompt> get repository =>
      ref.read(memoryPromptRepositoryProvider);
}
