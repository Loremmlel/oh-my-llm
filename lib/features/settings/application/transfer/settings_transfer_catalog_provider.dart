import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/auto_retry_settings_controller.dart';
import '../preferences/custom_headers_controller.dart';
import '../preferences/font_size_settings_controller.dart';
import '../preferences/output_processing_settings_controller.dart';
import '../prompts/fixed_prompt_sequences_controller.dart';
import '../prompts/memory_prompts_controller.dart';
import '../prompts/preset_prompts_controller.dart';
import '../prompts/template_prompts_controller.dart';
import '../providers/llm_model_configs_controller.dart';
import 'participants/model_provider_transfer_participant.dart';
import 'participants/preference_transfer_participants.dart';
import 'participants/prompt_collection_transfer_participants.dart';
import 'settings_transfer_catalog.dart';
import 'settings_transfer_coordinator.dart';
import 'settings_transfer_participant.dart';

final settingsTransferCatalogProvider = Provider<SettingsTransferCatalog>(
  _buildSettingsTransferCatalog,
);

final settingsTransferCoordinatorProvider =
    Provider<SettingsTransferCoordinator>((ref) {
      return SettingsTransferCoordinator(
        catalog: ref.watch(settingsTransferCatalogProvider),
      );
    });

SettingsTransferCatalog _buildSettingsTransferCatalog(Ref ref) {
  return SettingsTransferCatalog([
    SettingsTransferParticipantBox.erase(
      ModelProviderTransferParticipant(
        readLocal: () => ref.read(llmProviderConfigsProvider),
        write: (value) => ref
            .read(llmProviderConfigsProvider.notifier)
            .replaceAllAfterImport(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      PresetPromptTransferParticipant(
        readLocal: () => ref.read(presetPromptsProvider),
        write: (value) =>
            ref.read(presetPromptsProvider.notifier).upsertAll(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      MemoryPromptTransferParticipant(
        readLocal: () => ref.read(memoryPromptsProvider),
        write: (value) =>
            ref.read(memoryPromptsProvider.notifier).upsertAll(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      TemplatePromptTransferParticipant(
        readLocal: () => ref.read(templatePromptsProvider),
        write: (value) =>
            ref.read(templatePromptsProvider.notifier).upsertAll(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      FixedPromptSequenceTransferParticipant(
        readLocal: () => ref.read(fixedPromptSequencesProvider),
        write: (value) =>
            ref.read(fixedPromptSequencesProvider.notifier).upsertAll(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      CustomHeadersTransferParticipant(
        readLocal: () => ref.read(customHeadersProvider),
        write: (value) => ref.read(customHeadersProvider.notifier).save(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      OutputProcessingTransferParticipant(
        readLocal: () => ref.read(outputProcessingSettingsProvider),
        write: (value) =>
            ref.read(outputProcessingSettingsProvider.notifier).save(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      FontSizeSettingsTransferParticipant(
        readLocal: () => ref.read(fontSizeSettingsProvider),
        write: (value) =>
            ref.read(fontSizeSettingsProvider.notifier).save(value),
      ),
    ),
    SettingsTransferParticipantBox.erase(
      AutoRetrySettingsTransferParticipant(
        readLocal: () => ref.read(autoRetrySettingsProvider),
        write: (value) =>
            ref.read(autoRetrySettingsProvider.notifier).save(value),
      ),
    ),
  ]);
}
