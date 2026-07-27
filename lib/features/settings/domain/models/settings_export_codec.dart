import 'dart:convert';

import 'auto_retry_settings.dart';
import 'custom_headers_config.dart';
import 'fixed_prompt_sequence.dart';
import 'font_size_settings.dart';
import 'llm_provider_config.dart';
import 'memory_prompt.dart';
import 'output_processing_settings.dart';
import 'preset_prompt.dart';
import 'settings_export_data.dart';
import 'template_prompt.dart';

/// Settings 导出格式的解码结果，保留格式不支持和内容损坏的区别。
sealed class SettingsExportDecodeResult {
  const SettingsExportDecodeResult();
}

final class SettingsExportDecodeSuccess extends SettingsExportDecodeResult {
  const SettingsExportDecodeSuccess({
    required this.data,
    required this.sourceVersion,
    required this.migrated,
  });

  final SettingsExportData data;
  final int sourceVersion;
  final bool migrated;
}

final class SettingsExportUnsupportedVersion
    extends SettingsExportDecodeResult {
  const SettingsExportUnsupportedVersion(this.version);

  final int version;
}

final class SettingsExportMalformed extends SettingsExportDecodeResult {
  const SettingsExportMalformed();
}

/// Settings v5 到 v6 的唯一支持迁移。
final class SettingsExportFormatMigratorV5ToV6 {
  const SettingsExportFormatMigratorV5ToV6();

  Map<String, Object?> migrate(Map<String, Object?> source) {
    return {...source, 'formatVersion': SettingsExportData.formatVersion}
      ..remove('version');
  }
}

/// 只在 Settings 域内处理结构化版本化 snapshot，不了解 Sync wire 协议。
final class SettingsExportCodec {
  const SettingsExportCodec._();

  static const int minimumSupportedVersion = 5;
  static const int maximumSupportedVersion = SettingsExportData.formatVersion;

  static Map<String, Object?> encode(SettingsExportData data) {
    final map = <String, Object?>{
      'identifier': SettingsExportData.identifier,
      'formatVersion': SettingsExportData.formatVersion,
      'modelProviders': data.modelProviders.map((p) => p.toJson()).toList(),
      'memoryPrompts': data.memoryPrompts.map((p) => p.toJson()).toList(),
      'presetPrompts': data.presetPrompts.map((p) => p.toJson()).toList(),
      'templatePrompts': data.templatePrompts.map((p) => p.toJson()).toList(),
      'fixedPromptSequences': data.fixedPromptSequences
          .map((s) => s.toJson())
          .toList(),
    };
    if (data.autoRetrySettings case final value?) {
      map['autoRetrySettings'] = value.toJson();
    }
    if (data.customHeadersConfig case final value?) {
      map['customHeaders'] = value.toJson();
    }
    if (data.fontSizeSettings case final value?) {
      map['fontSizeSettings'] = value.toJson();
    }
    if (data.outputProcessingSettings case final value?) {
      map['outputProcessing'] = value.toJson();
    }
    return map;
  }

  static SettingsExportDecodeResult decodeJson(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const SettingsExportMalformed();
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const SettingsExportMalformed();
      return decode(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const SettingsExportMalformed();
    }
  }

  static SettingsExportDecodeResult decode(Map<String, Object?> source) {
    try {
      if (source['identifier'] != SettingsExportData.identifier) {
        return const SettingsExportMalformed();
      }
      final version = source['formatVersion'] ?? source['version'];
      if (version is! int) return const SettingsExportMalformed();
      if (version < minimumSupportedVersion ||
          version > maximumSupportedVersion) {
        return SettingsExportUnsupportedVersion(version);
      }
      final normalized = version == 5
          ? const SettingsExportFormatMigratorV5ToV6().migrate(source)
          : source;
      return SettingsExportDecodeSuccess(
        data: _decodeCurrent(normalized),
        sourceVersion: version,
        migrated: version != SettingsExportData.formatVersion,
      );
    } catch (_) {
      return const SettingsExportMalformed();
    }
  }

  static SettingsExportData _decodeCurrent(Map<String, Object?> raw) {
    List<Map<String, Object?>> list(String key) {
      final value = raw[key] ?? const <Object?>[];
      if (value is! List) throw const FormatException();
      return value
          .map((item) {
            if (item is! Map) throw const FormatException();
            return Map<String, Object?>.from(item);
          })
          .toList(growable: false);
    }

    Map<String, Object?>? optionalMap(String key) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! Map) throw const FormatException();
      return Map<String, Object?>.from(value);
    }

    final autoRetry = optionalMap('autoRetrySettings');
    final customHeaders = optionalMap('customHeaders');
    final fontSize = optionalMap('fontSizeSettings');
    final outputProcessing = optionalMap('outputProcessing');

    return SettingsExportData(
      modelProviders: list('modelProviders')
          .map(
            (item) =>
                LlmProviderConfig.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      memoryPrompts: list('memoryPrompts')
          .map((item) => MemoryPrompt.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      presetPrompts: list('presetPrompts')
          .map((item) => PresetPrompt.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      templatePrompts: list('templatePrompts')
          .map(
            (item) => TemplatePrompt.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      fixedPromptSequences: list('fixedPromptSequences')
          .map(
            (item) =>
                FixedPromptSequence.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      autoRetrySettings: autoRetry != null
          ? AutoRetrySettings.fromJson(Map<String, dynamic>.from(autoRetry))
          : null,
      customHeadersConfig: customHeaders != null
          ? CustomHeadersConfig.fromJson(
              Map<String, dynamic>.from(customHeaders),
            )
          : null,
      fontSizeSettings: fontSize != null
          ? FontSizeSettings.fromJson(Map<String, dynamic>.from(fontSize))
          : null,
      outputProcessingSettings: outputProcessing != null
          ? OutputProcessingSettings.fromJson(
              Map<String, dynamic>.from(outputProcessing),
            )
          : null,
    );
  }
}
