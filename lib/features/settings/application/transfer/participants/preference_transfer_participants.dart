import '../../../domain/models/preferences/auto_retry_settings.dart';
import '../../../domain/models/preferences/custom_headers_config.dart';
import '../../../domain/models/preferences/font_size_settings.dart';
import '../../../domain/models/preferences/output_processing_settings.dart';
import '../settings_transfer_participant.dart';
import '../settings_transfer_types.dart';

/// 自定义请求头的整体替换 participant。
final class CustomHeadersTransferParticipant
    extends ReplacingValueParticipant<CustomHeadersConfig> {
  CustomHeadersTransferParticipant({
    required CustomHeadersConfig Function() readLocal,
    required Future<void> Function(CustomHeadersConfig) write,
  }) : _readLocal = readLocal,
       _write = write,
       super(
         key: const SettingsTransferKey('customHeaders'),
         group: SettingsTransferGroup.network,
         label: '自定义请求头',
         order: 0,
         sensitivity: SettingsTransferSensitivity.credentialBearing,
       );

  final CustomHeadersConfig Function() _readLocal;
  final Future<void> Function(CustomHeadersConfig) _write;

  @override
  CustomHeadersConfig readLocal() => _readLocal();

  @override
  Object encode(CustomHeadersConfig value) => value.toJson();

  @override
  CustomHeadersConfig decode(Object? payload) {
    return CustomHeadersConfig.fromJson(_decodeMap(payload, '自定义请求头'));
  }

  @override
  bool isEquivalent(
    CustomHeadersConfig existing,
    CustomHeadersConfig incoming,
  ) => existing == incoming;

  @override
  bool isEmpty(CustomHeadersConfig value) => value.headers.isEmpty;

  @override
  Future<void> applyImport(CustomHeadersConfig value) => _write(value);
}

/// 输出正则处理设置的整体替换 participant。
final class OutputProcessingTransferParticipant
    extends ReplacingValueParticipant<OutputProcessingSettings> {
  OutputProcessingTransferParticipant({
    required OutputProcessingSettings Function() readLocal,
    required Future<void> Function(OutputProcessingSettings) write,
  }) : _readLocal = readLocal,
       _write = write,
       super(
         key: const SettingsTransferKey('outputProcessing'),
         group: SettingsTransferGroup.outputProcessing,
         label: '输出处理',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  final OutputProcessingSettings Function() _readLocal;
  final Future<void> Function(OutputProcessingSettings) _write;

  @override
  OutputProcessingSettings readLocal() => _readLocal();

  @override
  Object encode(OutputProcessingSettings value) => value.toJson();

  @override
  OutputProcessingSettings decode(Object? payload) {
    return OutputProcessingSettings.fromJson(_decodeMap(payload, '输出处理'));
  }

  @override
  bool isEquivalent(
    OutputProcessingSettings existing,
    OutputProcessingSettings incoming,
  ) => existing == incoming;

  @override
  bool isEmpty(OutputProcessingSettings value) => value.rules.isEmpty;

  @override
  Future<void> applyImport(OutputProcessingSettings value) => _write(value);
}

/// 正文字号设置的整体替换 participant。
final class FontSizeSettingsTransferParticipant
    extends ReplacingValueParticipant<FontSizeSettings> {
  FontSizeSettingsTransferParticipant({
    required FontSizeSettings Function() readLocal,
    required Future<void> Function(FontSizeSettings) write,
  }) : _readLocal = readLocal,
       _write = write,
       super(
         key: const SettingsTransferKey('fontSizeSettings'),
         group: SettingsTransferGroup.other,
         label: '正文字号设置',
         order: 0,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  final FontSizeSettings Function() _readLocal;
  final Future<void> Function(FontSizeSettings) _write;

  @override
  FontSizeSettings readLocal() => _readLocal();

  @override
  Object encode(FontSizeSettings value) => value.toJson();

  @override
  FontSizeSettings decode(Object? payload) {
    return FontSizeSettings.fromJson(_decodeMap(payload, '正文字号设置'));
  }

  @override
  bool isEquivalent(FontSizeSettings existing, FontSizeSettings incoming) =>
      existing == incoming;

  @override
  Future<void> applyImport(FontSizeSettings value) => _write(value);
}

/// 自动重试设置的整体替换 participant。
final class AutoRetrySettingsTransferParticipant
    extends ReplacingValueParticipant<AutoRetrySettings> {
  AutoRetrySettingsTransferParticipant({
    required AutoRetrySettings Function() readLocal,
    required Future<void> Function(AutoRetrySettings) write,
  }) : _readLocal = readLocal,
       _write = write,
       super(
         key: const SettingsTransferKey('autoRetrySettings'),
         group: SettingsTransferGroup.other,
         label: '自动重试设置',
         order: 1,
         sensitivity: SettingsTransferSensitivity.standard,
       );

  final AutoRetrySettings Function() _readLocal;
  final Future<void> Function(AutoRetrySettings) _write;

  @override
  AutoRetrySettings readLocal() => _readLocal();

  @override
  Object encode(AutoRetrySettings value) => value.toJson();

  @override
  AutoRetrySettings decode(Object? payload) {
    return AutoRetrySettings.fromJson(_decodeMap(payload, '自动重试设置'));
  }

  @override
  bool isEquivalent(AutoRetrySettings existing, AutoRetrySettings incoming) =>
      existing == incoming;

  @override
  Future<void> applyImport(AutoRetrySettings value) => _write(value);
}

Map<String, dynamic> _decodeMap(Object? payload, String label) {
  if (payload is! Map) {
    throw FormatException('$label 传输值必须是对象');
  }
  try {
    return Map<String, dynamic>.from(payload);
  } on Object {
    throw FormatException('$label 传输值必须是字符串键对象');
  }
}
