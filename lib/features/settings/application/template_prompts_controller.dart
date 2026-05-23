import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../data/template_prompt_repository.dart';
import '../domain/models/template_prompt.dart';
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
