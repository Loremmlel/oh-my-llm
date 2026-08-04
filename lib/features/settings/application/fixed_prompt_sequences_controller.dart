import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/sqlite_entity_repository.dart';
import '../data/fixed_prompt_sequence_repository.dart';
import '../domain/models/fixed_prompt_sequence.dart';
import 'settings_entity_controller.dart';

final fixedPromptSequencesProvider =
    NotifierProvider<FixedPromptSequencesController, List<FixedPromptSequence>>(
      FixedPromptSequencesController.new,
    );

class FixedPromptSequencesController
    extends SettingsEntityController<FixedPromptSequence> {
  @override
  SqliteEntityRepository<FixedPromptSequence> get repository =>
      ref.read(fixedPromptSequenceRepositoryProvider);
}
