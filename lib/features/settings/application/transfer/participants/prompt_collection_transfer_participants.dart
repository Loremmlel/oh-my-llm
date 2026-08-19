import '../../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../../domain/models/prompts/memory_prompt.dart';
import '../../../domain/models/prompts/preset_prompt.dart';
import '../../../domain/models/prompts/template_prompt.dart';
import '../../../domain/template_prompt_language/template_prompt_compiler.dart';
import '../settings_transfer_participant.dart';
import '../settings_transfer_types.dart';

abstract class _PromptCollectionTransferParticipant<T>
    extends MergingCollectionParticipant<T> {
  _PromptCollectionTransferParticipant({
    required super.key,
    required super.group,
    required super.label,
    required super.order,
    required super.sensitivity,
    required List<T> Function() readLocal,
    required Future<void> Function(List<T>) write,
  }) : _readLocal = readLocal,
       _write = write;

  final List<T> Function() _readLocal;
  final Future<void> Function(List<T>) _write;

  @override
  List<T> readLocal() => _readLocal();

  @override
  Future<void> applyImport(List<T> value) => _write(value);
}

/// 预设提示词的 Settings transfer participant。
final class PresetPromptTransferParticipant
    extends _PromptCollectionTransferParticipant<PresetPrompt> {
  PresetPromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('presetPrompts'),
         group: SettingsTransferGroup.presets,
         label: '预设提示词',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  @override
  Object encode(List<PresetPrompt> value) {
    return value.map((prompt) => prompt.toJson()).toList(growable: false);
  }

  @override
  List<PresetPrompt> decode(Object? payload) {
    return _decodeMapList(
      payload,
      '预设提示词',
    ).map(PresetPrompt.fromJson).toList(growable: false);
  }

  @override
  bool isEquivalent(PresetPrompt existing, PresetPrompt incoming) {
    if (existing.messages.length != incoming.messages.length) return false;
    for (var index = 0; index < existing.messages.length; index += 1) {
      final left = existing.messages[index];
      final right = incoming.messages[index];
      if (left.title != right.title ||
          left.role != right.role ||
          left.placement != right.placement ||
          left.content != right.content) {
        return false;
      }
    }
    return true;
  }
}

/// 记忆提示词的 Settings transfer participant。
final class MemoryPromptTransferParticipant
    extends _PromptCollectionTransferParticipant<MemoryPrompt> {
  MemoryPromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('memoryPrompts'),
         group: SettingsTransferGroup.prompts,
         label: '记忆提示词',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  @override
  Object encode(List<MemoryPrompt> value) {
    return value.map((prompt) => prompt.toJson()).toList(growable: false);
  }

  @override
  List<MemoryPrompt> decode(Object? payload) {
    return _decodeMapList(
      payload,
      '记忆提示词',
    ).map(MemoryPrompt.fromJson).toList(growable: false);
  }

  @override
  bool isEquivalent(MemoryPrompt existing, MemoryPrompt incoming) =>
      existing.content == incoming.content;
}

/// 模板提示词的 Settings transfer participant。
final class TemplatePromptTransferParticipant
    extends _PromptCollectionTransferParticipant<TemplatePrompt> {
  TemplatePromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('templatePrompts'),
         group: SettingsTransferGroup.prompts,
         label: '模板提示词',
         order: 1,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  @override
  Object encode(List<TemplatePrompt> value) {
    return value.map((prompt) => prompt.toJson()).toList(growable: false);
  }

  @override
  List<TemplatePrompt> decode(Object? payload) {
    final templates = _decodeMapList(
      payload,
      '模板提示词',
    ).map(TemplatePrompt.fromJson).toList(growable: false);
    for (final template in templates) {
      final compilation = compileTemplatePromptDefinition(template);
      if (!compilation.isValid) {
        throw FormatException('模板「${template.title}」定义无效');
      }
    }
    return templates;
  }

  @override
  bool isEquivalent(TemplatePrompt existing, TemplatePrompt incoming) {
    if (existing.content != incoming.content ||
        existing.variables.length != incoming.variables.length) {
      return false;
    }
    for (var index = 0; index < existing.variables.length; index += 1) {
      if (existing.variables[index] != incoming.variables[index]) {
        return false;
      }
    }
    return true;
  }
}

/// 固定提示词序列的 Settings transfer participant。
final class FixedPromptSequenceTransferParticipant
    extends _PromptCollectionTransferParticipant<FixedPromptSequence> {
  FixedPromptSequenceTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('fixedPromptSequences'),
         group: SettingsTransferGroup.prompts,
         label: '固定提示词序列',
         order: 2,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  @override
  Object encode(List<FixedPromptSequence> value) {
    return value.map((sequence) => sequence.toJson()).toList(growable: false);
  }

  @override
  List<FixedPromptSequence> decode(Object? payload) {
    return _decodeMapList(
      payload,
      '固定提示词序列',
    ).map(FixedPromptSequence.fromJson).toList(growable: false);
  }

  @override
  bool isEquivalent(
    FixedPromptSequence existing,
    FixedPromptSequence incoming,
  ) {
    if (existing.steps.length != incoming.steps.length) return false;
    for (var index = 0; index < existing.steps.length; index += 1) {
      final left = existing.steps[index];
      final right = incoming.steps[index];
      if (left.title != right.title || left.content != right.content) {
        return false;
      }
    }
    return true;
  }
}

List<Map<String, dynamic>> _decodeMapList(Object? payload, String label) {
  if (payload is! List) {
    throw FormatException('$label 传输值必须是列表');
  }
  return payload
      .map((item) {
        if (item is! Map) {
          throw FormatException('$label 列表元素必须是对象');
        }
        try {
          return Map<String, dynamic>.from(item);
        } on Object {
          throw FormatException('$label 列表元素必须是字符串键对象');
        }
      })
      .toList(growable: false);
}
