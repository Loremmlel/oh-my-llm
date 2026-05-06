import 'dart:convert';

import 'fixed_prompt_sequence.dart';
import 'llm_model_config.dart';
import 'llm_provider_config.dart';
import 'prompt_template.dart';
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
///   "version": 2,
///   "modelProviders": [...],
///   "promptTemplates": [...],
///   "fixedPromptSequences": [...]
/// }
/// ```
class SettingsExportData {
  const SettingsExportData({
    required this.modelProviders,
    required this.promptTemplates,
    required this.templatePrompts,
    required this.fixedPromptSequences,
  });

  /// 用于识别剪贴板内容是否为本应用导出数据的标识符。
  static const String identifier = 'shikiyuzu-oh-my-llm';

  /// 当前导出格式版本，未来格式变更时递增。
  static const int formatVersion = 2;

  final List<LlmProviderConfig> modelProviders;
  final List<PromptTemplate> promptTemplates;
  final List<TemplatePrompt> templatePrompts;
  final List<FixedPromptSequence> fixedPromptSequences;

  List<LlmModelConfig> get modelConfigs {
    return modelProviders
        .expand((provider) => provider.resolvedModels)
        .toList(growable: false);
  }

  /// 将导出数据序列化为 JSON 字符串（含标识符和版本号）。
  String toJsonString() {
    return jsonEncode({
      'identifier': identifier,
      'version': formatVersion,
      'modelProviders': modelProviders.map((p) => p.toJson()).toList(),
      'promptTemplates': promptTemplates.map((t) => t.toJson()).toList(),
      'templatePrompts': templatePrompts.map((t) => t.toJson()).toList(),
      'fixedPromptSequences':
          fixedPromptSequences.map((s) => s.toJson()).toList(),
    });
  }

  /// 尝试从字符串解析导出数据；若格式不匹配或解析失败则返回 null。
  ///
  /// 识别逻辑：先检查 `identifier` 字段，再读取各类列表；
  /// 任何字段缺失或类型不符均静默返回 null，不抛出异常。
  static SettingsExportData? tryParseJson(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    try {
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) return null;
      if (raw['identifier'] != identifier) return null;

      final rawProviders =
          raw['modelProviders'] as List<dynamic>? ?? const [];
      final rawTemplates = raw['promptTemplates'] as List<dynamic>? ?? const [];
      final rawTemplatePrompts =
          raw['templatePrompts'] as List<dynamic>? ?? const [];
      final rawSequences =
          raw['fixedPromptSequences'] as List<dynamic>? ?? const [];

      final modelProviders = rawProviders.isNotEmpty
          ? rawProviders
                .map((item) => LlmProviderConfig.fromJson(
                      Map<String, dynamic>.from(item as Map),
                    ))
                .toList(growable: false)
          : _migrateLegacyModelConfigs(
                raw['modelConfigs'] as List<dynamic>? ?? const [],
              );

      return SettingsExportData(
        modelProviders: modelProviders,
        promptTemplates: rawTemplates
            .map((item) => PromptTemplate.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        templatePrompts: rawTemplatePrompts
            .map((item) => TemplatePrompt.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        fixedPromptSequences: rawSequences
            .map((item) => FixedPromptSequence.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
      );
    } catch (_) {
      // 任何解析错误都视为非本应用的剪贴板内容，静默忽略。
      return null;
    }
  }

  /// 是否包含任何可导入的条目。
  bool get hasContent =>
      modelProviders.isNotEmpty ||
      promptTemplates.isNotEmpty ||
      templatePrompts.isNotEmpty ||
      fixedPromptSequences.isNotEmpty;

  static List<LlmProviderConfig> _migrateLegacyModelConfigs(
    List<dynamic> rawModels,
  ) {
    final legacyModels = rawModels
        .map((item) => LlmModelConfig.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    if (legacyModels.isEmpty) {
      return const [];
    }

    final providers = <LlmProviderConfig>[];
    final indexBySignature = <String, int>{};
    for (final model in legacyModels) {
      final signature = '${model.apiUrl}::${model.apiKey}';
      final existingIndex = indexBySignature[signature];
      final providerModel = LlmProviderModelConfig(
        id: model.id,
        displayName: model.displayName,
        modelName: model.modelName,
        supportsReasoning: model.supportsReasoning,
      );
      if (existingIndex == null) {
        indexBySignature[signature] = providers.length;
        providers.add(
          LlmProviderConfig(
            id: 'provider-${providers.length + 1}',
            name: '服务商${providers.length + 1}',
            apiUrl: model.apiUrl,
            apiKey: model.apiKey,
            models: [providerModel],
          ),
        );
      } else {
        final provider = providers[existingIndex];
        providers[existingIndex] = provider.copyWith(
          models: [...provider.models, providerModel],
        );
      }
    }
    return providers;
  }
}
