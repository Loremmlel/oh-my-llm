import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/sqlite_entity_repository.dart';
import '../data/prompt_template_repository.dart';
import '../domain/models/prompt_template.dart';
import 'settings_entity_controller.dart';

final promptTemplatesProvider =
    NotifierProvider<PromptTemplatesController, List<PromptTemplate>>(
      PromptTemplatesController.new,
    );

class PromptTemplatesController
    extends SettingsEntityController<PromptTemplate> {
  @override
  SqliteEntityRepository<PromptTemplate> get repository =>
      ref.read(promptTemplateRepositoryProvider);
}
