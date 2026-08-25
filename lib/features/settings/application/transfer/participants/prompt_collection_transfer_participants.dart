import '../../../domain/models/prompts/fixed_prompt_sequence.dart';
import '../../../domain/models/prompts/memory_prompt.dart';
import '../../../domain/models/prompts/preset_prompt.dart';
import '../../../domain/models/prompts/template_prompt.dart';
import '../../../domain/template_prompt_language/template_prompt_compiler.dart';
import '../settings_transfer_participant.dart';
import '../settings_transfer_payload.dart';
import '../settings_transfer_types.dart';

abstract class _JsonMergingCollectionTransferParticipant<T>
    extends MergingCollectionParticipant<T> {
  _JsonMergingCollectionTransferParticipant({
    required super.key,
    required super.group,
    required super.label,
    required super.order,
    required super.sensitivity,
    required this._readLocal,
    required this._write,
    required this._encodeItem,
    required this._decodeItem,
    required this._isEquivalentItem,
    this._validateItem,
  });

  final List<T> Function() _readLocal;
  final Future<void> Function(List<T>) _write;
  final Object Function(T) _encodeItem;
  final T Function(Map<String, dynamic>) _decodeItem;
  final bool Function(T, T) _isEquivalentItem;
  final void Function(T)? _validateItem;

  @override
  List<T> readLocal() => _readLocal();

  @override
  Object encode(List<T> value) {
    return value.map(_encodeItem).toList(growable: false);
  }

  @override
  List<T> decode(Object? payload) {
    final values = decodeTransferObjectList(
      payload,
      label,
    ).map(_decodeItem).toList(growable: false);
    final validateItem = _validateItem;
    if (validateItem != null) {
      for (final value in values) {
        validateItem(value);
      }
    }
    return values;
  }

  @override
  bool isEquivalent(T existing, T incoming) {
    return _isEquivalentItem(existing, incoming);
  }

  @override
  Future<void> applyImport(List<T> value) => _write(value);
}

/// 预设提示词的 Settings transfer participant。
final class PresetPromptTransferParticipant
    extends _JsonMergingCollectionTransferParticipant<PresetPrompt> {
  PresetPromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('presetPrompts'),
         group: SettingsTransferGroup.presets,
         label: '预设提示词',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeItem: (value) => value.toJson(),
         decodeItem: PresetPrompt.fromJson,
         isEquivalentItem: _samePresetPrompt,
       );
}

/// 记忆提示词的 Settings transfer participant。
final class MemoryPromptTransferParticipant
    extends _JsonMergingCollectionTransferParticipant<MemoryPrompt> {
  MemoryPromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('memoryPrompts'),
         group: SettingsTransferGroup.prompts,
         label: '记忆提示词',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeItem: (value) => value.toJson(),
         decodeItem: MemoryPrompt.fromJson,
         isEquivalentItem: (existing, incoming) =>
             existing.content == incoming.content,
       );
}

/// 模板提示词的 Settings transfer participant。
final class TemplatePromptTransferParticipant
    extends _JsonMergingCollectionTransferParticipant<TemplatePrompt> {
  TemplatePromptTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('templatePrompts'),
         group: SettingsTransferGroup.prompts,
         label: '模板提示词',
         order: 1,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeItem: (value) => value.toJson(),
         decodeItem: TemplatePrompt.fromJson,
         isEquivalentItem: _sameTemplatePrompt,
         validateItem: _validateTemplatePrompt,
       );
}

/// 固定提示词序列的 Settings transfer participant。
final class FixedPromptSequenceTransferParticipant
    extends _JsonMergingCollectionTransferParticipant<FixedPromptSequence> {
  FixedPromptSequenceTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('fixedPromptSequences'),
         group: SettingsTransferGroup.prompts,
         label: '固定提示词序列',
         order: 2,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeItem: (value) => value.toJson(),
         decodeItem: FixedPromptSequence.fromJson,
         isEquivalentItem: _sameFixedPromptSequence,
       );
}

bool _samePresetPrompt(PresetPrompt existing, PresetPrompt incoming) {
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

bool _sameTemplatePrompt(TemplatePrompt existing, TemplatePrompt incoming) {
  if (existing.content != incoming.content ||
      existing.variables.length != incoming.variables.length) {
    return false;
  }
  for (var index = 0; index < existing.variables.length; index += 1) {
    if (existing.variables[index] != incoming.variables[index]) return false;
  }
  return true;
}

void _validateTemplatePrompt(TemplatePrompt template) {
  final compilation = compileTemplatePromptDefinition(template);
  if (!compilation.isValid) {
    throw FormatException('模板「${template.title}」定义无效');
  }
}

bool _sameFixedPromptSequence(
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
