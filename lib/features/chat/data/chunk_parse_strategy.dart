/// SSE data 块的解析结果，包含从正文和 delta 中提取出的正文与推理文本。
class ChunkTextExtraction {
  const ChunkTextExtraction({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;
}

/// 从 SSE delta/message payload 提取正文与推理增量的策略接口。
///
/// 每个实现负责处理一种特定的厂商返回格式。
/// 策略按顺序尝试匹配，首先匹配到的策略将被使用。
abstract class ChunkParseStrategy {
  const ChunkParseStrategy();

  /// 返回 `true` 表示本策略能够处理该 [delta]。
  bool canHandle(Map<String, dynamic> delta);

  /// 从 [delta] 中提取正文与推理文本。
  ChunkTextExtraction extract(Map<String, dynamic> delta);
}

/// 标准 OpenAI 兼容格式：content 为纯字符串。
class StandardOpenAiChunkStrategy implements ChunkParseStrategy {
  const StandardOpenAiChunkStrategy();

  @override
  bool canHandle(Map<String, dynamic> delta) => true;

  @override
  ChunkTextExtraction extract(Map<String, dynamic> delta) {
    return ChunkTextExtraction(content: extractTextPayload(delta['content']));
  }
}

/// DeepSeek 格式：额外包含 `reasoning_content` 或 `reasoning` 字段。
class DeepSeekChunkStrategy implements ChunkParseStrategy {
  const DeepSeekChunkStrategy();

  @override
  bool canHandle(Map<String, dynamic> delta) =>
      delta['reasoning_content'] != null || delta['reasoning'] != null;

  @override
  ChunkTextExtraction extract(Map<String, dynamic> delta) {
    return ChunkTextExtraction(
      content: extractTextPayload(delta['content']),
      reasoning: extractTextPayload(
        delta['reasoning_content'] ?? delta['reasoning'],
      ),
    );
  }
}

/// Gemini 格式：content 为 parts 列表，每个 part 可带有 `thought` 标志。
class GeminiPartsChunkStrategy implements ChunkParseStrategy {
  const GeminiPartsChunkStrategy();

  @override
  bool canHandle(Map<String, dynamic> delta) => delta['content'] is List;

  @override
  ChunkTextExtraction extract(Map<String, dynamic> delta) {
    return _extractContentPayload(delta['content']);
  }

  ChunkTextExtraction _extractContentPayload(Object? payload) {
    if (payload is String) {
      return ChunkTextExtraction(content: payload);
    }
    if (payload is List) {
      final content = StringBuffer();
      final reasoning = StringBuffer();
      for (final segment in payload) {
        final extracted = _extractContentPayload(segment);
        content.write(extracted.content);
        reasoning.write(extracted.reasoning);
      }
      return ChunkTextExtraction(
        content: content.toString(),
        reasoning: reasoning.toString(),
      );
    }
    if (payload is! Map) {
      return const ChunkTextExtraction();
    }

    final thoughtEnabled = _isThoughtPart(payload['thought']);
    final content = StringBuffer();
    final reasoning = StringBuffer();

    final text = payload['text'];
    if (text is String) {
      if (thoughtEnabled) {
        reasoning.write(text);
      } else {
        content.write(text);
      }
    }

    final nestedContent = _extractContentPayload(payload['content']);
    content.write(nestedContent.content);
    reasoning.write(nestedContent.reasoning);

    final nestedParts = _extractContentPayload(payload['parts']);
    content.write(nestedParts.content);
    reasoning.write(nestedParts.reasoning);

    return ChunkTextExtraction(
      content: content.toString(),
      reasoning: reasoning.toString(),
    );
  }

  bool _isThoughtPart(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }
}

/// 递归提取任意嵌套结构中的纯文本内容（不区分 thought 标志）。
String extractTextPayload(Object? payload) {
  if (payload is String) return payload;
  if (payload is List) return payload.map(extractSegmentText).join();
  if (payload is! Map) return '';

  final text = payload['text'];
  if (text is String) return text;

  final nestedText = payload['content'];
  if (nestedText is String) return nestedText;
  if (nestedText is List) return nestedText.map(extractSegmentText).join();

  return '';
}

String extractSegmentText(Object? segment) {
  if (segment is String) return segment;
  if (segment is! Map) return '';

  final text = segment['text'];
  if (text is String) return text;

  final nestedText = segment['content'];
  if (nestedText is String) return nestedText;
  if (nestedText is List) return nestedText.map(extractSegmentText).join();

  return '';
}
