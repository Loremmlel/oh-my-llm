import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';

import '../../data/prompts/template_prompt_repository.dart';
import '../../domain/models/prompts/template_prompt.dart';
import 'settings_entity_controller.dart';

final templatePromptsProvider =
    NotifierProvider<TemplatePromptsController, List<TemplatePrompt>>(
      TemplatePromptsController.new,
    );

class TemplatePromptsController
    extends SettingsEntityController<TemplatePrompt> {
  @override
  SqliteEntityRepository<TemplatePrompt> get repository =>
      ref.read(templatePromptRepositoryProvider);
}
