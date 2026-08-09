import 'llm_api_protocol.dart';

/// LLM 端点解析异常：配置的 API URL 无法解析为生成或模型列表端点。
class LlmEndpointResolverException implements Exception {
  const LlmEndpointResolverException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// LLM 端点解析器：从配置保存的 API 根地址解析生成端点与模型列表端点。
///
/// 配置只保存用户原始输入（首尾空白由配置层清理），实际请求时由本类解析，
/// 避免设置界面暗中重写用户配置。仅识别三种标准生成后缀，不为 Azure 等
/// 特殊路由推断 deployment / api-version。
final class LlmEndpointResolver {
  const LlmEndpointResolver();

  /// 三种已知的生成端点标准后缀。
  static const chatCompletionsSuffix = '/v1/chat/completions';
  static const responsesSuffix = '/v1/responses';
  static const anthropicSuffix = '/v1/messages';
  static const modelsSuffix = '/v1/models';

  static const _knownGenerationSuffixes = <String>[
    chatCompletionsSuffix,
    responsesSuffix,
    anthropicSuffix,
  ];

  /// 解析目标协议的生成端点。
  ///
  /// 规则：
  /// 1. 忽略 path 末尾 `/` 进行匹配；
  /// 2. 已是目标协议完整后缀时原样使用；
  /// 3. 末尾是另外两种已知生成后缀时替换为目标后缀；
  /// 4. path 末尾是 `/v1` 时追加目标协议末段；
  /// 5. 其他情况追加完整 `/v1/...` 后缀。
  ///
  /// host、port、自定义反向代理前缀和 query 均保留。
  Uri resolveGenerationEndpoint({
    required String rawUrl,
    required LlmApiProtocol protocol,
  }) {
    final uri = _parseAndValidate(rawUrl);
    final targetSuffix = _suffixFor(protocol);
    final path = _stripTrailingSlashes(uri.path);

    if (path.endsWith(targetSuffix)) {
      // 已是目标协议完整后缀，直接使用用户原始输入。
      return uri;
    }

    final root = resolveApiRoot(rawUrl);
    final targetSegment = targetSuffix.substring('/v1'.length);
    return root.replace(path: '${root.path}$targetSegment');
  }

  /// 解析模型列表端点。
  ///
  /// 从 API 根地址生成 `/v1/models`；已是 `/v1/models` 结尾时原样返回，
  /// 完整生成端点先移除已知生成后缀再替换为 `/models`。host、port、前缀
  /// 与 query 保留。
  Uri resolveModelsEndpoint(String apiUrl) {
    final uri = _parseAndValidate(apiUrl);
    final path = _stripTrailingSlashes(uri.path);

    if (path.endsWith(modelsSuffix)) {
      // 已是模型列表端点：原样返回用户输入，避免二次拼接。
      return uri;
    }

    final root = resolveApiRoot(apiUrl);
    return root.replace(path: '${root.path}/models');
  }

  /// 解析统一 API 根地址，供端点生成与服务商等价判断复用。
  ///
  /// 已知生成端点和模型列表端点会先剥离；其余 path 视为代理前缀，
  /// 最终统一为以 `/v1` 结尾的根地址。port 与 query 保持不变。
  Uri resolveApiRoot(String rawUrl) {
    final uri = _parseAndValidate(rawUrl);
    var path = _stripTrailingSlashes(uri.path);

    for (final suffix in [..._knownGenerationSuffixes, modelsSuffix]) {
      if (path.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }

    final rootPath = path.endsWith('/v1') ? path : '$path/v1';
    return uri.replace(path: rootPath);
  }

  static String _suffixFor(LlmApiProtocol protocol) {
    switch (protocol) {
      case LlmApiProtocol.chatCompletions:
        return chatCompletionsSuffix;
      case LlmApiProtocol.responses:
        return responsesSuffix;
      case LlmApiProtocol.anthropic:
        return anthropicSuffix;
    }
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
