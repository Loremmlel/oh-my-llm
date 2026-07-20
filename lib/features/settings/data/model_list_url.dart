/// 从 chat completions URL 推导 models 列表端点 URL。
///
/// 规则：
/// 1. 如果路径以 /chat/completions 结尾，替换为 /models
/// 2. 否则在末尾追加 /models
String deriveModelsUrl(String chatCompletionsUrl) {
  if (chatCompletionsUrl.isEmpty) {
    throw ArgumentError('chatCompletionsUrl 不能为空');
  }

  final uri = Uri.parse(chatCompletionsUrl);
  if (!uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw FormatException('URL 协议不支持（需要 http/https）：$chatCompletionsUrl');
  }

  final path = uri.path;
  const chatCompletionsSuffix = '/chat/completions';

  if (path.endsWith('$chatCompletionsSuffix/')) {
    final basePath = path.substring(
      0,
      path.length - chatCompletionsSuffix.length - 1,
    );
    return uri.replace(path: '$basePath/models').toString();
  }

  if (path.endsWith(chatCompletionsSuffix)) {
    final basePath = path.substring(0, path.length - chatCompletionsSuffix.length);
    return uri.replace(path: '$basePath/models').toString();
  }

  // 兜底：路径不以 /chat/completions 结尾，追加 /models
  final normalizedPath = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return uri.replace(path: '$normalizedPath/models').toString();
}
