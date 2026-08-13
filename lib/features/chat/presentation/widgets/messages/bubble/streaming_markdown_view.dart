import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart'
    as smooth_md;

const Map<String, String> _latexCommandSymbolMap = {
  'LeftArrow': '←',
  'leftarrow': '←',
  'RightArrow': '→',
  'rightarrow': '→',
  'LeftRightArrow': '↔',
  'leftrightarrow': '↔',
  'Longleftarrow': '⟸',
  'Longrightarrow': '⟹',
  'Longleftrightarrow': '⟺',
};

/// 对常见 TeX 控制序列做轻量文本兼容。
///
/// 当前不引入完整公式引擎，仅将形如 `$\\LeftArrow$` 的常见符号写法降级为可读字符，
/// 未识别的命令保持原样，避免误改普通文本。
String normalizeLatexLikeTextForDisplay(String input) {
  return input.replaceAllMapped(RegExp(r'\$\\([A-Za-z]+)\$'), (match) {
    final command = match.group(1);
    if (command == null) {
      return match.group(0) ?? '';
    }
    return _latexCommandSymbolMap[command] ?? (match.group(0) ?? '');
  });
}

/// 基于 smooth markdown 的流式渲染组件。
class StreamingMarkdownView extends StatefulWidget {
  const StreamingMarkdownView({
    required this.content,
    required this.isStreaming,
    super.key,
  });

  final String content;
  final bool isStreaming;

  @override
  State<StreamingMarkdownView> createState() => _StreamingMarkdownViewState();
}

class _StreamingMarkdownViewState extends State<StreamingMarkdownView> {
  /// smooth 流式渲染输入流控制器；每次进入流式会话时重建。
  StreamController<String>? _smoothStreamController;

  /// smooth 流式路径下，已推送给 [StreamMarkdown] 的累计文本。
  String _smoothAccumulatedContent = '';

  /// smooth 路径的实时尾部文本，用于在 StreamMarkdown 内部节流窗口中即时回显最新增量。
  String _smoothLiveTail = '';

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.isStreaming) {
      _startSmoothStreamingSession();
      _pushSmoothNormalizedContent(widget.content);
    }
  }

  @override
  void didUpdateWidget(covariant StreamingMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isStreaming && widget.isStreaming) {
      _startSmoothStreamingSession();
      _pushSmoothNormalizedContent(widget.content);
    } else if (widget.isStreaming) {
      _pushSmoothNormalizedContent(widget.content);
    } else if (oldWidget.isStreaming && !widget.isStreaming) {
      _pushSmoothNormalizedContent(widget.content);
      _closeSmoothStreamingSession();
    }
  }

  @override
  void dispose() {
    _closeSmoothStreamingSession();
    super.dispose();
  }

  /// 启动 smooth 流式会话。
  void _startSmoothStreamingSession() {
    _closeSmoothStreamingSession();
    _smoothStreamController = StreamController<String>();
    _smoothAccumulatedContent = '';
    _smoothLiveTail = '';
  }

  /// 结束 smooth 流式会话。
  void _closeSmoothStreamingSession() {
    final controller = _smoothStreamController;
    _smoothStreamController = null;
    _smoothAccumulatedContent = '';
    _smoothLiveTail = '';
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  /// 把当前全量内容转换成 smooth 需要的增量 chunk 推入流。
  ///
  /// 当归一化后文本不再以前缀关系延展（例如 TeX 命令在后续 chunk 到达后被整体替换），
  /// 重新开始一次流式会话并推送完整文本，确保显示结果正确。
  void _pushSmoothNormalizedContent(String fullContent) {
    if (!widget.isStreaming) {
      return;
    }
    var controller = _smoothStreamController;
    if (controller == null || controller.isClosed) {
      _startSmoothStreamingSession();
      controller = _smoothStreamController;
      if (controller == null) {
        return;
      }
    }

    final normalized = normalizeLatexLikeTextForDisplay(fullContent);
    if (normalized == _smoothAccumulatedContent) {
      return;
    }

    if (normalized.startsWith(_smoothAccumulatedContent)) {
      final delta = normalized.substring(_smoothAccumulatedContent.length);
      _smoothLiveTail = delta;
      if (delta.isNotEmpty) {
        controller.add(delta);
      }
      _smoothAccumulatedContent = normalized;
      return;
    }

    _startSmoothStreamingSession();
    controller = _smoothStreamController;
    if (controller == null || controller.isClosed) {
      return;
    }
    if (normalized.isNotEmpty) {
      controller.add(normalized);
    }
    _smoothAccumulatedContent = normalized;
    _smoothLiveTail = normalized;
  }

  /// 构建带主题样式的 Markdown。
  Widget _buildMarkdownWidget(BuildContext context, String content) {
    final theme = Theme.of(context);
    final normalizedContent = normalizeLatexLikeTextForDisplay(content);
    final data = normalizedContent.isEmpty && widget.isStreaming
        ? '_正在等待模型返回内容..._'
        : normalizedContent;
    return smooth_md.SmoothMarkdown(
      data: data,
      selectable: true,
      styleSheet: smooth_md.MarkdownStyleSheet.fromTheme(theme),
    );
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.isStreaming) {
      return _buildMarkdownWidget(context, widget.content);
    }

    final controller = _smoothStreamController;
    final theme = Theme.of(context);
    if (controller == null || controller.isClosed) {
      return Text(
        '正在等待模型返回内容...',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        smooth_md.StreamMarkdown(
          stream: controller.stream,
          selectable: true,
          styleSheet: smooth_md.MarkdownStyleSheet.fromTheme(theme),
          loadingWidget: Text(
            '正在等待模型返回内容...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        if (_smoothLiveTail.isNotEmpty) ...[
          const SizedBox(height: 4),
          SelectableText(_smoothLiveTail, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}
