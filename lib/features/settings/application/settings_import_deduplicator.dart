import '../domain/models/fixed_prompt_sequence.dart';
import '../domain/models/llm_provider_config.dart';
import '../domain/models/memory_prompt.dart';
import '../domain/models/prompt_template.dart';
import '../domain/models/settings_export_data.dart';
import '../domain/models/template_prompt.dart';

/// 导入去重时的内容比较策略。
abstract class SettingsImportComparator<T> {
  const SettingsImportComparator();

  bool isEquivalent(T existing, T incoming);
}

class MemoryPromptImportComparator
    extends SettingsImportComparator<MemoryPrompt> {
  const MemoryPromptImportComparator();

  @override
  bool isEquivalent(MemoryPrompt existing, MemoryPrompt incoming) {
    if (existing.content.length != incoming.content.length) {
      return false;
    }
    return existing.content == incoming.content;
  }
}

class PromptTemplateImportComparator
    extends SettingsImportComparator<PromptTemplate> {
  const PromptTemplateImportComparator();

  @override
  bool isEquivalent(PromptTemplate existing, PromptTemplate incoming) {
    if (existing.systemPromptTitle.length !=
        incoming.systemPromptTitle.length) {
      return false;
    }
    if (existing.systemPromptTitle != incoming.systemPromptTitle) {
      return false;
    }
    if (existing.systemPrompt.length != incoming.systemPrompt.length) {
      return false;
    }
    if (existing.systemPrompt != incoming.systemPrompt) {
      return false;
    }
    if (existing.messages.length != incoming.messages.length) {
      return false;
    }
    for (var index = 0; index < existing.messages.length; index += 1) {
      final left = existing.messages[index];
      final right = incoming.messages[index];
      if (left.title.length != right.title.length) {
        return false;
      }
      if (left.title != right.title) {
        return false;
      }
      if (left.role != right.role || left.placement != right.placement) {
        return false;
      }
      if (left.content.length != right.content.length) {
        return false;
      }
      if (left.content != right.content) {
        return false;
      }
    }
    return true;
  }
}

class TemplatePromptImportComparator
    extends SettingsImportComparator<TemplatePrompt> {
  const TemplatePromptImportComparator();

  @override
  bool isEquivalent(TemplatePrompt existing, TemplatePrompt incoming) {
    if (existing.content.length != incoming.content.length) {
      return false;
    }
    if (existing.content != incoming.content) {
      return false;
    }
    if (existing.variables.length != incoming.variables.length) {
      return false;
    }
    for (var index = 0; index < existing.variables.length; index += 1) {
      final left = existing.variables[index];
      final right = incoming.variables[index];
      if (left.name != right.name) {
        return false;
      }
      if (left.defaultValue.length != right.defaultValue.length) {
        return false;
      }
      if (left.defaultValue != right.defaultValue) {
        return false;
      }
    }
    return true;
  }
}

class FixedPromptSequenceImportComparator
    extends SettingsImportComparator<FixedPromptSequence> {
  const FixedPromptSequenceImportComparator();

  @override
  bool isEquivalent(
    FixedPromptSequence existing,
    FixedPromptSequence incoming,
  ) {
    if (existing.steps.length != incoming.steps.length) {
      return false;
    }
    for (var index = 0; index < existing.steps.length; index += 1) {
      final left = existing.steps[index];
      final right = incoming.steps[index];
      if (left.title.length != right.title.length) {
        return false;
      }
      if (left.title != right.title) {
        return false;
      }
      if (left.content.length != right.content.length) {
        return false;
      }
      if (left.content != right.content) {
        return false;
      }
    }
    return true;
  }
}

/// 设置导入数据的去重协调器。
final class SettingsImportDeduplicator {
  const SettingsImportDeduplicator({
    this.memoryPromptComparator = const MemoryPromptImportComparator(),
    this.promptTemplateComparator = const PromptTemplateImportComparator(),
    this.templatePromptComparator = const TemplatePromptImportComparator(),
    this.fixedPromptSequenceComparator =
        const FixedPromptSequenceImportComparator(),
  });

  final SettingsImportComparator<MemoryPrompt> memoryPromptComparator;
  final SettingsImportComparator<PromptTemplate> promptTemplateComparator;
  final SettingsImportComparator<TemplatePrompt> templatePromptComparator;
  final SettingsImportComparator<FixedPromptSequence>
  fixedPromptSequenceComparator;

  SettingsExportData deduplicate({
    required SettingsExportData data,
    required List<LlmProviderConfig> existingProviders,
    required List<MemoryPrompt> existingMemoryPrompts,
    required List<PromptTemplate> existingTemplates,
    required List<TemplatePrompt> existingTemplatePrompts,
    required List<FixedPromptSequence> existingSequences,
  }) {
    final existingModels = existingProviders
        .expand((provider) => provider.resolvedModels)
        .toList(growable: false);
    final newProviders = data.modelProviders
        .map((provider) {
          final nextModels = provider.models
              .where((model) {
                return !existingModels.any(
                  (existing) =>
                      existing.apiUrl == provider.apiUrl &&
                      existing.apiKey == provider.apiKey &&
                      existing.modelName == model.modelName,
                );
              })
              .toList(growable: false);
          return provider.copyWith(models: nextModels);
        })
        .where((provider) => provider.models.isNotEmpty)
        .toList(growable: false);

    final newMemoryPrompts = data.memoryPrompts
        .where((incoming) {
          return !existingMemoryPrompts.any(
            (existing) =>
                memoryPromptComparator.isEquivalent(existing, incoming),
          );
        })
        .toList(growable: false);

    final newTemplates = data.promptTemplates
        .where((incoming) {
          return !existingTemplates.any(
            (existing) =>
                promptTemplateComparator.isEquivalent(existing, incoming),
          );
        })
        .toList(growable: false);

    final newTemplatePrompts = data.templatePrompts
        .where((incoming) {
          return !existingTemplatePrompts.any(
            (existing) =>
                templatePromptComparator.isEquivalent(existing, incoming),
          );
        })
        .toList(growable: false);

    final newSequences = data.fixedPromptSequences
        .where((incoming) {
          return !existingSequences.any(
            (existing) =>
                fixedPromptSequenceComparator.isEquivalent(existing, incoming),
          );
        })
        .toList(growable: false);

    return SettingsExportData(
      modelProviders: newProviders,
      memoryPrompts: newMemoryPrompts,
      promptTemplates: newTemplates,
      templatePrompts: newTemplatePrompts,
      fixedPromptSequences: newSequences,
    );
  }
}
