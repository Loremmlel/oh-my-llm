import '../../providers/llm_provider_import_merger.dart';
import '../../../domain/models/providers/llm_provider_config.dart';
import '../settings_transfer_participant.dart';
import '../settings_transfer_payload.dart';
import '../settings_transfer_types.dart';

/// 服务商集合的 Settings transfer participant。
final class ModelProviderTransferParticipant
    extends MergingCollectionParticipant<LlmProviderConfig> {
  ModelProviderTransferParticipant({
    required this._readLocal,
    required this._write,
  }) : super(
         key: const SettingsTransferKey('modelProviders'),
         group: SettingsTransferGroup.providers,
         label: '服务商',
         order: 0,
         sensitivity: SettingsTransferSensitivity.credentialBearing,
       );

  final List<LlmProviderConfig> Function() _readLocal;
  final Future<void> Function(List<LlmProviderConfig>) _write;

  @override
  List<LlmProviderConfig> readLocal() => _readLocal();

  @override
  Object encode(List<LlmProviderConfig> value) {
    return value.map((provider) => provider.toJson()).toList(growable: false);
  }

  @override
  List<LlmProviderConfig> decode(Object? payload) {
    final items = decodeTransferObjectList(payload, '服务商');
    return items
        .map((item) {
          if (item['apiProtocol'] == null) {
            throw const FormatException('服务商缺少有效 apiProtocol');
          }
          return LlmProviderConfig.fromJson(item);
        })
        .toList(growable: false);
  }

  @override
  bool isEquivalent(LlmProviderConfig existing, LlmProviderConfig incoming) =>
      existing == incoming;

  @override
  SettingsTransferChange<List<LlmProviderConfig>>? prepareImport({
    required List<LlmProviderConfig> local,
    required List<LlmProviderConfig> incoming,
  }) {
    final merged = mergeImportedLlmProviders(local: local, incoming: incoming);
    final normalizedLocal = mergeImportedLlmProviders(
      local: local,
      incoming: const [],
    );
    if (_sameProviders(normalizedLocal, merged)) return null;

    final writeValue = List<LlmProviderConfig>.unmodifiable(merged);
    return SettingsTransferChange<List<LlmProviderConfig>>(
      incoming: List<LlmProviderConfig>.unmodifiable(incoming),
      writeValue: writeValue,
      fingerprint: fingerprintFor(writeValue),
      summary: SettingsTransferSummaryItem(
        key: key,
        label: label,
        action: SettingsTransferSummaryAction.add,
        count: incoming.length,
      ),
    );
  }

  @override
  SettingsTransferSummaryItem summarizeExport(List<LlmProviderConfig> value) {
    if (value.isEmpty) {
      throw StateError('空服务商集合不能生成 add 摘要');
    }
    return SettingsTransferSummaryItem(
      key: key,
      label: label,
      action: SettingsTransferSummaryAction.add,
      count: value.length,
    );
  }

  @override
  Future<void> applyImport(List<LlmProviderConfig> value) => _write(value);
}

bool _sameProviders(
  List<LlmProviderConfig> left,
  List<LlmProviderConfig> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
