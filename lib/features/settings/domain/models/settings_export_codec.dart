import 'dart:convert';

import 'package:oh_my_llm/core/llm/llm_api_protocol.dart';

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

/// Settings v5 到 v6 的唯一支持迁移：版本字段改名并落到 v6 结构。
///
/// 版本号固定写 6，后续版本升级由下一个迁移器接力完成（见
/// [SettingsExportFormatMigratorV6ToV7]）。
final class SettingsExportFormatMigratorV5ToV6 {
  const SettingsExportFormatMigratorV5ToV6();

  Map<String, Object?> migrate(Map<String, Object?> source) {
    return {...source, 'formatVersion': 6}..remove('version');
  }
}

/// Settings v6 到 v7 的唯一支持迁移：为全部服务商补默认协议。
final class SettingsExportFormatMigratorV6ToV7 {
  const SettingsExportFormatMigratorV6ToV7();

  Map<String, Object?> migrate(Map<String, Object?> source) {
    final rawProviders = source['modelProviders'];
    if (rawProviders is! List) {
      return {...source, 'formatVersion': SettingsExportData.formatVersion};
    }
    return {
      ...source,
      'formatVersion': SettingsExportData.formatVersion,
      'modelProviders': rawProviders
          .map((item) {
            if (item is! Map) return item;
            final provider = Map<String, Object?>.from(item);
            // 只补缺失协议的旧条目；显式写入的协议（含未知值）保持原样
            if (!provider.containsKey('apiProtocol')) {
              provider['apiProtocol'] =
                  LlmApiProtocol.chatCompletions.storageValue;
            }
            return provider;
          })
          .toList(growable: false),
    };
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
      final normalized = switch (version) {
        5 => _migrateV5ToCurrent(source),
        6 => _migrateV6ToCurrent(source),
        _ => source,
      };
      return SettingsExportDecodeSuccess(
        data: _decodeCurrent(normalized),
        sourceVersion: version,
        migrated: version != SettingsExportData.formatVersion,
      );
    } catch (_) {
      return const SettingsExportMalformed();
    }
  }

  /// 版本 5 快照先补 v6 结构，再经 v6→v7 迁移到当前版本。
  static Map<String, Object?> _migrateV5ToCurrent(Map<String, Object?> source) {
    final v6 = const SettingsExportFormatMigratorV5ToV6().migrate(source);
    return _migrateV6ToCurrent(v6);
  }

  /// 版本 6 快照经 v6→v7 迁移到当前版本。
  static Map<String, Object?> _migrateV6ToCurrent(Map<String, Object?> source) {
    return const SettingsExportFormatMigratorV6ToV7().migrate(source);
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
          .map((item) {
            // 当前格式必须显式声明协议；只有旧格式迁移器可以补默认值。
            if (!item.containsKey('apiProtocol') ||
                item['apiProtocol'] == null) {
              throw const FormatException('v7 服务商缺少有效 apiProtocol');
            }
            return LlmProviderConfig.fromJson(Map<String, dynamic>.from(item));
          })
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
