import '../../../application/ports/chat_generation_client.dart';

/// 内联 reasoning 标签分割结果。
class InlineReasoningSplitResult {
  const InlineReasoningSplitResult({this.content = '', this.reasoning = ''});

  final String content;
  final String reasoning;

  bool get isEmpty => content.isEmpty && reasoning.isEmpty;
}

/// 从正文流中识别并分离 `<thought>`/`<thinking>`/`<think>` 标签内容，
/// 转入 reasoning 通道。
///
/// 规则：
/// - 标签名大小写不敏感；opening tag 允许空白和属性，closing tag 允许空白。
/// - 标签可横跨任意 SSE chunk；标签自身不输出，内部文本进入 reasoningDelta。
/// - 未闭合 opening tag 后的内容在流结束前持续视为 reasoning。
/// - 流末尾的不完整标签文本按当前通道原样刷新（[flushRemainder]）。
/// - 未配对的 closing tag 按普通正文处理。
///
/// 每个请求创建一个新实例，以保持跨 chunk 的标签解析状态，
/// 不跨请求共享状态。
class InlineReasoningTagSplitter {
  InlineReasoningTagSplitter({
    String customTag = '',
    bool includeDefaultTags = true,
  }) {
    final names = [
      if (includeDefaultTags) ...['thought', 'thinking', 'think'],
      if (customTag.trim().isNotEmpty) RegExp.escape(customTag.trim()),
    ].join('|');
    _openingTag = RegExp(
      '^<\\s*($names)(?:\\s[^>]*)?>\$',
      caseSensitive: false,
    );
    _closingTag = RegExp('^<\\s*/\\s*($names)\\s*>\$', caseSensitive: false);
  }

  late final RegExp _openingTag;
  late final RegExp _closingTag;

  String? _activeTag;
  bool get _insideReasoningTag => _activeTag != null;
  String _tail = '';

  InlineReasoningSplitResult splitContent(String delta) {
    if (delta.isEmpty && _tail.isEmpty) {
      return const InlineReasoningSplitResult();
    }

    final input = '$_tail$delta';
    _tail = '';
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    var cursor = 0;

    while (cursor < input.length) {
      final tagStart = input.indexOf('<', cursor);
      if (tagStart == -1) {
        final remaining = input.substring(cursor);
        if (_insideReasoningTag) {
          reasoningBuffer.write(remaining);
        } else {
          contentBuffer.write(remaining);
        }
        break;
      }

      final beforeTag = input.substring(cursor, tagStart);
      if (_insideReasoningTag) {
        reasoningBuffer.write(beforeTag);
      } else {
        contentBuffer.write(beforeTag);
      }

      final tagEnd = input.indexOf('>', tagStart + 1);
      if (tagEnd == -1) {
        // 标签可能被拆到下一个 chunk，先缓存尾部，等下次拼接后重新判断。
        _tail = input.substring(tagStart);
        break;
      }

      final candidateTag = input.substring(tagStart, tagEnd + 1);
      final opening = _openingTag.firstMatch(candidateTag);
      if (!_insideReasoningTag && opening != null) {
        _activeTag = opening.group(1)!.toLowerCase();
        cursor = tagEnd + 1;
        continue;
      }

      if (_insideReasoningTag &&
          _closingTag.firstMatch(candidateTag)?.group(1)?.toLowerCase() ==
              _activeTag) {
        _activeTag = null;
        cursor = tagEnd + 1;
        continue;
      }

      // 非标签的 `<`：原样保留在当前通道，从 `<` 之后继续扫描。
      if (_insideReasoningTag) {
        reasoningBuffer.write('<');
      } else {
        contentBuffer.write('<');
      }
      cursor = tagStart + 1;
    }

    return InlineReasoningSplitResult(
      content: contentBuffer.toString(),
      reasoning: reasoningBuffer.toString(),
    );
  }

  /// 刷新缓冲区中残留的不完整标签内容。
  ///
  /// 流结束时调用；残留文本按当前所在通道原样输出。
  ChatGenerationChunk? flushRemainder() {
    if (_tail.isEmpty) return null;

    final remainder = _tail;
    _tail = '';
    if (_insideReasoningTag) {
      return ChatGenerationChunk(reasoningDelta: remainder);
    }
    return ChatGenerationChunk(contentDelta: remainder);
  }
}
