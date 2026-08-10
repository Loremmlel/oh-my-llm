import 'llm_api_protocol.dart';

/// LLM 端点解析异常：配置的 API URL 无法解析为生成或模型列表端点。
class LlmEndpointResolverException implements Exception {
  const LlmEndpointResolverException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 版本段正则：path 末段形如 `/v1`、`/v2`、`/v3` 等（如 Ark `/api/v3`、
/// 智谱 `/api/paas/v4`），视为 API 根已含版本号，不再补 `/v1`。
final _versionSegmentPattern = RegExp(r'^/v\d+$');

/// LLM 端点解析器：从配置保存的 API 根地址解析生成端点与模型列表端点。
///
/// 配置只保存用户原始输入（首尾空白由配置层清理），实际请求时由本类解析，
/// 避免设置界面暗中重写用户配置。解析策略：
/// - 终端段匹配：URL 已以目标协议末段（`/chat/completions`、`/responses`、
///   `/messages`、`/models`）结尾时原样使用、不再追加任何内容。这样既兼容
///   不带 `/v1` 根的服务商（如 Perplexity 只认 `/chat/completions`），也让
///   用户直接粘贴完整端点即可生效，不必关心 `/v1` 是否存在。
/// - 版本段识别：API 根若以 `/vN`（v1/v2/v3…）结尾则视为已含版本段，直接
///   拼接协议末段（如 Ark `/api/v3/responses`、智谱 `/api/paas/v4/chat/completions`）；
///   否则按 OpenAI 默认补 `/v1`（OpenAI、DeepSeek、自定义代理前缀等）。
/// 不为 Azure 等特殊路由推断 deployment / api-version。
final class LlmEndpointResolver {
  const LlmEndpointResolver();

  /// 各协议/模型的终端段（不含 `/v1` 前缀），用于「已完整则不再填充」判定。
  static const chatCompletionsTerminal = '/chat/completions';
  static const responsesTerminal = '/responses';
  static const anthropicTerminal = '/messages';
  static const modelsTerminal = '/models';

  static const _knownTerminalSegments = <String>[
    chatCompletionsTerminal,
    responsesTerminal,
    anthropicTerminal,
    modelsTerminal,
  ];

  /// 解析目标协议的生成端点。
  ///
  /// 规则：
  /// 1. 忽略 path 末尾 `/` 进行匹配；
  /// 2. 已是目标协议终端段结尾时原样使用（不自动填充）；
  /// 3. 否则解析 API 根（含版本段识别），末尾拼接目标协议终端段。
  ///
  /// host、port、自定义反向代理前缀和 query 均保留。
  Uri resolveGenerationEndpoint({
    required String rawUrl,
    required LlmApiProtocol protocol,
  }) {
    final uri = _parseAndValidate(rawUrl);
    final terminal = _terminalFor(protocol);
    final path = _stripTrailingSlashes(uri.path);

    if (path.endsWith(terminal)) {
      // 已是目标协议终端段，直接使用用户原始输入。
      return uri;
    }

    final root = resolveApiRoot(rawUrl);
    return root.replace(path: '${root.path}$terminal');
  }

  /// 解析模型列表端点。
  ///
  /// 已是 `/models` 结尾时原样返回；否则从 API 根（含版本段识别）追加
  /// `/models`。host、port、前缀与 query 保留。
  Uri resolveModelsEndpoint(String apiUrl) {
    final uri = _parseAndValidate(apiUrl);
    final path = _stripTrailingSlashes(uri.path);

    if (path.endsWith(modelsTerminal)) {
      // 已是模型列表端点：原样返回用户输入，避免二次拼接。
      return uri;
    }

    final root = resolveApiRoot(apiUrl);
    return root.replace(path: '${root.path}$modelsTerminal');
  }

  /// 解析统一 API 根地址，供端点生成与服务商等价判断复用。
  ///
  /// 已知协议终端段会先剥离；剩余 path 以 `/vN` 结尾时视为已含版本段保持
  /// 不变，否则按 OpenAI 默认补 `/v1`。port 与 query 保持不变。
  Uri resolveApiRoot(String rawUrl) {
    final uri = _parseAndValidate(rawUrl);
    var path = _stripTrailingSlashes(uri.path);

    for (final terminal in _knownTerminalSegments) {
      if (path.endsWith(terminal)) {
        path = path.substring(0, path.length - terminal.length);
        break;
      }
    }

    final rootPath = _hasVersionSegment(path) ? path : '$path/v1';
    return uri.replace(path: rootPath);
  }

  static String _terminalFor(LlmApiProtocol protocol) {
    switch (protocol) {
      case LlmApiProtocol.chatCompletions:
        return chatCompletionsTerminal;
      case LlmApiProtocol.responses:
        return responsesTerminal;
      case LlmApiProtocol.anthropic:
        return anthropicTerminal;
    }
  }

  /// path 末段是否为版本段（`/vN`）。
  static bool _hasVersionSegment(String path) {
    if (path.isEmpty) {
      return false;
    }
    final lastSegment = path.substring(path.lastIndexOf('/'));
    return _versionSegmentPattern.hasMatch(lastSegment);
  }

  /// 解析并校验配置 URL：仅接受绝对 http/https URI，fragment 视为配置错误。
  static Uri _parseAndValidate(String apiUrl) {
    Uri uri;
    try {
      uri = Uri.parse(apiUrl.trim());
    } on FormatException catch (e) {
      throw LlmEndpointResolverException('API URL 格式无效：${e.message}');
    }
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw LlmEndpointResolverException('API URL 必须为绝对 http/https 地址：$apiUrl');
    }
    if (uri.host.isEmpty) {
      throw LlmEndpointResolverException('API URL 必须包含非空 host：$apiUrl');
    }
    if (uri.hasFragment) {
      throw LlmEndpointResolverException('API URL 不允许包含 fragment（#）：$apiUrl');
    }
    return uri;
  }

  /// 去除 path 末尾所有 `/`（匹配时忽略末尾斜杠）。
  static String _stripTrailingSlashes(String path) {
    var result = path;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
