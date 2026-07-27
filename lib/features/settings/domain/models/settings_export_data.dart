import 'dart:convert';

import 'auto_retry_settings.dart';
import 'custom_headers_config.dart';
import 'fixed_prompt_sequence.dart';
import 'font_size_settings.dart';
import 'llm_model_config.dart';
import 'llm_provider_config.dart';
import 'memory_prompt.dart';
import 'output_processing_settings.dart';
import 'preset_prompt.dart';
import 'settings_export_codec.dart';
import 'template_prompt.dart';

/// 配置导出/导入的数据包，包含三类设置项的完整快照。
///
/// 用于通过剪贴板在设备之间或用户之间共享应用配置。导出时序列化为
/// JSON 并写入剪贴板；导入时读取剪贴板并根据 [identifier] 字段识别。
///
/// 注意：导出内容包含模型 API Key，请在可信任的渠道共享。
///
/// 示例格式：
/// ```json
/// {
///   "identifier": "shikiyuzu-oh-my-llm",
///   "formatVersion": 6,
///   "modelProviders": [...],
///   "memoryPrompts": [...],
///   "presetPrompts": [...],
///   "fixedPromptSequences": [...]
/// }
/// ```
class SettingsExportData {
  const SettingsExportData({
    required this.modelProviders,
    required this.memoryPrompts,
    required this.presetPrompts,
    required this.templatePrompts,
    required this.fixedPromptSequences,
    this.autoRetrySettings,
    this.customHeadersConfig,
    this.fontSizeSettings,
    this.outputProcessingSettings,
  });

  /// 用于识别剪贴板内容是否为本应用导出数据的标识符。
  static const String identifier = 'shikiyuzu-oh-my-llm';

  /// 当前导出格式版本，未来格式变更时递增。
  static const int formatVersion = 6;

  final List<LlmProviderConfig> modelProviders;
  final List<MemoryPrompt> memoryPrompts;
  final List<PresetPrompt> presetPrompts;
  final List<TemplatePrompt> templatePrompts;
  final List<FixedPromptSequence> fixedPromptSequences;
  final AutoRetrySettings? autoRetrySettings;
  final CustomHeadersConfig? customHeadersConfig;
  final FontSizeSettings? fontSizeSettings;
  final OutputProcessingSettings? outputProcessingSettings;

  List<LlmModelConfig> get modelConfigs {
    return modelProviders
        .expand((provider) => provider.resolvedModels)
        .toList(growable: false);
  }

  /// 将导出数据序列化为 JSON 字符串（含标识符和版本号）。
  String toJsonString() => jsonEncode(SettingsExportCodec.encode(this));

  /// 结构化导出，仅供受认证的 Sync snapshot 使用。
  Map<String, Object?> toJson() => SettingsExportCodec.encode(this);

  /// 尝试从字符串解析导出数据；若格式不匹配或解析失败则返回 null。
  ///
  /// 识别逻辑：先检查 `identifier` 字段，再读取各类列表；
  /// 任何字段缺失或类型不符均静默返回 null，不抛出异常。
  static SettingsExportData? tryParseJson(String? text) {
    final result = SettingsExportCodec.decodeJson(text);
    return switch (result) {
      SettingsExportDecodeSuccess(:final data) => data,
      SettingsExportUnsupportedVersion() || SettingsExportMalformed() => null,
    };
  }

  /// 是否包含任何可导入的条目。
  bool get hasContent =>
      modelProviders.isNotEmpty ||
      memoryPrompts.isNotEmpty ||
      presetPrompts.isNotEmpty ||
      templatePrompts.isNotEmpty ||
      fixedPromptSequences.isNotEmpty ||
      autoRetrySettings != null ||
      fontSizeSettings != null ||
      (customHeadersConfig != null &&
          customHeadersConfig!.headers.isNotEmpty) ||
      (outputProcessingSettings != null &&
          outputProcessingSettings!.rules.isNotEmpty);
}
