import '../domain/models/chat_message.dart';

/// 一次厂商 payload 修补的结果。
///
/// [thinkingConfig] 将作为顶层 `thinking` 字段注入请求体（DeepSeek 等）。
/// [extraBody] 将作为顶层 `extra_body` 字段注入请求体（Gemini 等）。
/// [skipStandardReasoningEffort] 为 true 时，不向请求体追加标准 `reasoning_effort` 字段。
class VendorPayloadPatch {
  const VendorPayloadPatch({
    this.thinkingConfig,
    this.extraBody,
    this.skipStandardReasoningEffort = false,
  });

  final Map<String, Object>? thinkingConfig;
  final Map<String, Object>? extraBody;
  final bool skipStandardReasoningEffort;

  static const empty = VendorPayloadPatch();
}

/// 处理不同厂商 OpenAI 兼容差异的 payload 构建策略。
///
/// 每种实现对应一类 API 主机，通过 [matches] 判断是否适用，
/// 通过 [buildPatch] 返回需要注入请求体的额外字段。
abstract class VendorPayloadAdapter {
  const VendorPayloadAdapter();

  bool matches(String host);
  VendorPayloadPatch buildPatch(ReasoningEffort? reasoningEffort);
}

/// DeepSeek 适配器：需要显式携带 thinking 开关。
///
/// DeepSeek API 不读取 `reasoning_effort`，而是通过
/// `thinking: {type: "enabled"|"disabled"}` 控制推理模式。
class DeepSeekPayloadAdapter extends VendorPayloadAdapter {
  const DeepSeekPayloadAdapter();

  @override
  bool matches(String host) => host.toLowerCase() == 'api.deepseek.com';

  @override
  VendorPayloadPatch buildPatch(ReasoningEffort? reasoningEffort) {
    return VendorPayloadPatch(
      thinkingConfig: {
        'type': reasoningEffort != null ? 'enabled' : 'disabled',
      },
    );
  }
}

/// Gemini OpenAI 兼容层适配器：通过 extra_body 透传 thinking 配置。
///
/// Google 的 OpenAI 兼容端点要求 `reasoning_effort` 与
/// `thinking_config` 二选一，因此开启深度思考时跳过标准
/// `reasoning_effort` 字段，改为在 `extra_body` 中传入
/// `google.thinking_config`。
class GoogleOpenAiCompatibleAdapter extends VendorPayloadAdapter {
  const GoogleOpenAiCompatibleAdapter();

  @override
  bool matches(String host) =>
      host.toLowerCase() == 'generativelanguage.googleapis.com';

  @override
  VendorPayloadPatch buildPatch(ReasoningEffort? reasoningEffort) {
    if (reasoningEffort == null) {
      return const VendorPayloadPatch();
    }
    return const VendorPayloadPatch(
      skipStandardReasoningEffort: true,
      extraBody: {
        'google': {
          'thinking_config': {'include_thoughts': true},
        },
      },
    );
  }
}

/// 默认适配器：标准 OpenAI 接口，不做额外处理。
class DefaultPayloadAdapter extends VendorPayloadAdapter {
  const DefaultPayloadAdapter();

  @override
  bool matches(String host) => true;

  @override
  VendorPayloadPatch buildPatch(ReasoningEffort? reasoningEffort) {
    return const VendorPayloadPatch();
  }
}

/// 根据 API 主机名选择对应厂商适配器的注册表。
///
/// 适配器按优先级顺序排列，[resolve] 返回第一个 [matches] 为 true 的适配器。
/// [DefaultPayloadAdapter] 作为兜底始终排在末尾。
class VendorPayloadAdapterRegistry {
  const VendorPayloadAdapterRegistry(this._adapters);

  final List<VendorPayloadAdapter> _adapters;

  /// 内置注册表，包含所有已知厂商适配器。
  static const standard = VendorPayloadAdapterRegistry([
    DeepSeekPayloadAdapter(),
    GoogleOpenAiCompatibleAdapter(),
    DefaultPayloadAdapter(),
  ]);

  VendorPayloadAdapter resolve(String host) {
    return _adapters.firstWhere(
      (adapter) => adapter.matches(host),
      orElse: () => const DefaultPayloadAdapter(),
    );
  }
}
