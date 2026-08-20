import '../../../domain/models/preferences/auto_retry_settings.dart';
import '../../../domain/models/preferences/custom_headers_config.dart';
import '../../../domain/models/preferences/font_size_settings.dart';
import '../../../domain/models/preferences/output_processing_settings.dart';
import '../settings_transfer_participant.dart';
import '../settings_transfer_payload.dart';
import '../settings_transfer_types.dart';

abstract class _JsonReplacingTransferParticipant<T>
    extends ReplacingValueParticipant<T> {
  _JsonReplacingTransferParticipant({
    required super.key,
    required super.group,
    required super.label,
    required super.order,
    required super.sensitivity,
    required T Function() readLocal,
    required Future<void> Function(T) write,
    required Object Function(T) encodeValue,
    required T Function(Map<String, dynamic>) decodeValue,
    bool Function(T)? isEmptyValue,
  }) : _readLocal = readLocal,
       _write = write,
       _encodeValue = encodeValue,
       _decodeValue = decodeValue,
       _isEmptyValue = isEmptyValue;

  final T Function() _readLocal;
  final Future<void> Function(T) _write;
  final Object Function(T) _encodeValue;
  final T Function(Map<String, dynamic>) _decodeValue;
  final bool Function(T)? _isEmptyValue;

  @override
  T readLocal() => _readLocal();

  @override
  Object encode(T value) => _encodeValue(value);

  @override
  T decode(Object? payload) {
    return _decodeValue(decodeTransferObject(payload, label));
  }

  @override
  bool isEquivalent(T existing, T incoming) => existing == incoming;

  @override
  bool isEmpty(T value) => _isEmptyValue?.call(value) ?? super.isEmpty(value);

  @override
  Future<void> applyImport(T value) => _write(value);
}

/// 自定义请求头的整体替换 participant。
final class CustomHeadersTransferParticipant
    extends _JsonReplacingTransferParticipant<CustomHeadersConfig> {
  CustomHeadersTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('customHeaders'),
         group: SettingsTransferGroup.network,
         label: '自定义请求头',
         order: 0,
         sensitivity: SettingsTransferSensitivity.credentialBearing,
         encodeValue: (value) => value.toJson(),
         decodeValue: CustomHeadersConfig.fromJson,
         isEmptyValue: (value) => value.headers.isEmpty,
       );
}

/// 输出正则处理设置的整体替换 participant。
final class OutputProcessingTransferParticipant
    extends _JsonReplacingTransferParticipant<OutputProcessingSettings> {
  OutputProcessingTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('outputProcessing'),
         group: SettingsTransferGroup.outputProcessing,
         label: '输出处理',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeValue: (value) => value.toJson(),
         decodeValue: OutputProcessingSettings.fromJson,
         isEmptyValue: (value) => value.rules.isEmpty,
       );
}

/// 正文字号设置的整体替换 participant。
final class FontSizeSettingsTransferParticipant
    extends _JsonReplacingTransferParticipant<FontSizeSettings> {
  FontSizeSettingsTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('fontSizeSettings'),
         group: SettingsTransferGroup.other,
         label: '正文字号设置',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeValue: (value) => value.toJson(),
         decodeValue: FontSizeSettings.fromJson,
       );
}

/// 自动重试设置的整体替换 participant。
final class AutoRetrySettingsTransferParticipant
    extends _JsonReplacingTransferParticipant<AutoRetrySettings> {
  AutoRetrySettingsTransferParticipant({
    required super.readLocal,
    required super.write,
  }) : super(
         key: const SettingsTransferKey('autoRetrySettings'),
         group: SettingsTransferGroup.other,
         label: '自动重试设置',
         order: 1,
         sensitivity: SettingsTransferSensitivity.standard,
         encodeValue: (value) => value.toJson(),
         decodeValue: AutoRetrySettings.fromJson,
       );
}
