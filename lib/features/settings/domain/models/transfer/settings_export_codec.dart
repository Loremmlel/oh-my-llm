import 'dart:convert';

import '../preferences/auto_retry_settings.dart';
import '../preferences/custom_headers_config.dart';
import '../prompts/fixed_prompt_sequence.dart';
import '../preferences/font_size_settings.dart';
import '../providers/llm_provider_config.dart';
import '../prompts/memory_prompt.dart';
import '../preferences/output_processing_settings.dart';
import '../prompts/preset_prompt.dart';
import 'settings_export_data.dart';
import '../prompts/template_prompt.dart';
import '../../template_prompt_language/template_prompt_compiler.dart';

/// Settings 导出格式的解码结果，保留格式不支持和内容损坏的区别。
sealed class SettingsExportDecodeResult {
  const SettingsExportDecodeResult();
}

final class SettingsExportDecodeSuccess extends SettingsExportDecodeResult {
  const SettingsExportDecodeSuccess({
    required this.data,
    required this.sourceVersion,
  });

  final SettingsExportData data;

  /// 已解码快照的格式版本。当前只接受 v8，恒等于
  /// [SettingsExportData.formatVersion]；Sync snapshot 校验会用它与快照声明的
  /// 版本核对。
  final int sourceVersion;
}

final class SettingsExportUnsupportedVersion
    extends SettingsExportDecodeResult {
  const SettingsExportUnsupportedVersion(this.version);

  final int version;
}

final class SettingsExportMalformed extends SettingsExportDecodeResult {
  const SettingsExportMalformed();
}

/// 只在 Settings 域内处理结构化版本化 snapshot，不了解 Sync wire 协议。
final class SettingsExportCodec {
  const SettingsExportCodec._();

  /// 当前只接受格式版本 v8：最低与最高支持版本都等于当前版本，v5/v6/v7
  /// 及未来版本统一返回 unsupported。两个边界常量供 Sync snapshot 校验复用。
  static const int minimumSupportedVersion = SettingsExportData.formatVersion;
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
      // 版本号只从 formatVersion 读取；缺失（含仅有旧 version 字段）即 malformed。
      final version = source['formatVersion'];
      if (version is! int) return const SettingsExportMalformed();
      if (version < minimumSupportedVersion ||
          version > maximumSupportedVersion) {
        return SettingsExportUnsupportedVersion(version);
      }
      return SettingsExportDecodeSuccess(
        data: _decodeCurrent(source),
        sourceVersion: version,
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

    // 先解码到局部不可变列表，再逐条编译校验，任一无效即整体拒绝，
    // 不执行部分模板写入。
    final templatePrompts = list('templatePrompts')
        .map((item) => TemplatePrompt.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    for (final template in templatePrompts) {
      final compilation = compileTemplatePromptDefinition(template);
      if (!compilation.isValid) {
        final codes = compilation.diagnostics
            .map((diagnostic) => diagnostic.code.name)
            .toSet()
            .join('、');
        throw FormatException('模板「${template.title}」定义无效（$codes）');
      }
    }

    return SettingsExportData(
      modelProviders: list('modelProviders')
          .map((item) {
            // 当前格式必须显式声明协议；没有旧格式迁移器补默认值，缺失即 malformed。
            if (!item.containsKey('apiProtocol') ||
                item['apiProtocol'] == null) {
              throw const FormatException('v8 服务商缺少有效 apiProtocol');
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
      templatePrompts: templatePrompts,
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
