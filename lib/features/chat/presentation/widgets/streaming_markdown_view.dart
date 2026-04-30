import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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

/// 流式 Markdown 渲染组件。
///
/// 流式期间将内容分为两个层次展示：
/// - **已渲染快照**：上一次 [MarkdownBody] 渲染的结果，以 Timer 按动态间隔定期刷新；
/// - **实时尾部**：快照之后新增的文本，以 [SelectableText] 每次 build 即时更新，成本极低。
///
/// 动态渲染间隔公式：`clamp(length × 0.4 + 1000, 1000, 5000)` 毫秒。
/// 内容越长，渲染一次的开销越大，因此间隔也随之拉长，最高 5 秒。
///
/// 流式结束（[isStreaming] 变为 `false`）后，
/// 取消 Timer，对完整内容做最终全量 [MarkdownBody] 渲染。
///
/// 示例用法：
/// ```dart
/// StreamingMarkdownView(
///   content: message.content,
///   isStreaming: message.isStreaming,
/// )
/// ```
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
  /// 上一次完整渲染时对应的内容字符串。
  String _renderedContent = '';

  /// 上一次渲染生成的 [MarkdownBody] 缓存；只在定时器触发或流式结束时才替换。
  Widget? _renderedMarkdown;

  /// 控制定期刷新 Markdown 快照的定时器。
  Timer? _markdownRefreshTimer;

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isStreaming) {
      // 主题等 InheritedWidget 可能发生变化，重建缓存快照以保证样式正确。
      // 这是低频操作（如深色模式切换），重建一次的成本可接受。
      _doRenderMarkdown();
      if (_markdownRefreshTimer == null) {
        _scheduleNextRefresh();
      }
    }
  }

  @override
  void didUpdateWidget(covariant StreamingMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.isStreaming && widget.isStreaming) {
      // 进入流式状态：初始化快照并启动定时器。
      _doRenderMarkdown();
      _scheduleNextRefresh();
    } else if (oldWidget.isStreaming && !widget.isStreaming) {
      // 流式结束：取消定时器并做最终全量渲染。
      _cancelTimer();
      _doRenderMarkdown();
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  // ── 定时器逻辑 ────────────────────────────────────────────────────────────

  /// 取消现有定时器。
  void _cancelTimer() {
    _markdownRefreshTimer?.cancel();
    _markdownRefreshTimer = null;
  }

  /// 根据当前内容长度计算下次渲染的等待时间。
  ///
  /// 公式：`clamp(length × 0.4 + 1000, 1000, 5000)` ms。
  /// 短内容约 1-1.5s，万字以上约 5s（上限），避免长文本频繁解析拖慢主线程。
  Duration _resolveMarkdownInterval() {
    final ms = (widget.content.length * 0.4 + 1000)
        .clamp(1000.0, 5000.0)
        .toInt();
    return Duration(milliseconds: ms);
  }

  /// 安排下次 Markdown 定时渲染。
  void _scheduleNextRefresh() {
    _cancelTimer();
    final interval = _resolveMarkdownInterval();
    _markdownRefreshTimer = Timer(interval, () {
      if (!mounted || !widget.isStreaming) {
        return;
      }
      // 定时触发：重建快照并再次安排下次刷新。
      setState(() {
        _doRenderMarkdown();
        _scheduleNextRefresh();
      });
    });
  }

  // ── 渲染逻辑 ──────────────────────────────────────────────────────────────

  /// 用当前内容生成并缓存 [MarkdownBody] 快照。
  ///
  /// 此方法不调用 [setState]；调用方负责触发重建（定时器内用 [setState]，
  /// 生命周期方法中由框架自动重建）。
  void _doRenderMarkdown() {
    _renderedContent = widget.content;
    _renderedMarkdown = _buildMarkdownWidget(_renderedContent);
  }

  /// 构建带主题样式的 [MarkdownBody]。
  Widget _buildMarkdownWidget(String content) {
    final theme = Theme.of(context);
    final normalizedContent = normalizeLatexLikeTextForDisplay(content);
    final data = normalizedContent.isEmpty && widget.isStreaming
        ? '_正在等待模型返回内容..._'
        : normalizedContent;
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge,
        blockquote: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 非流式状态：直接展示缓存的最终渲染结果（由 didUpdateWidget 在流结束时生成）。
    if (!widget.isStreaming) {
      return _renderedMarkdown ?? _buildMarkdownWidget(widget.content);
    }

    // 流式状态：快照之后新增的部分作为纯文本尾部，每次 build 即时更新，成本极低。
    final tail = normalizeLatexLikeTextForDisplay(
      widget.content.substring(_renderedContent.length).trimLeft(),
    );
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_renderedMarkdown != null) ...[
          _renderedMarkdown!,
          if (tail.isNotEmpty) const SizedBox(height: 4),
        ],
        if (tail.isNotEmpty)
          SelectableText(tail, style: theme.textTheme.bodyLarge)
        else if (widget.content.isEmpty && _renderedMarkdown == null)
          Text(
            '正在等待模型返回内容...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}
