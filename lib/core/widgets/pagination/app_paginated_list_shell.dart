import 'package:flutter/material.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

import 'app_pagination_bar.dart';
import 'app_pagination_state.dart';

/// 正文构建器；获得 shell 持有的 [ScrollController]，caller 只构建列表内容。
typedef AppPaginatedBodyBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

/// 固定底部分页列表外壳：header 与分页栏固定，正文独立滚动。
///
/// - 正文通过 [bodyBuilder] 获得 shell 的 [ScrollController]；
/// - [pageIdentity] 描述当前数据窗口的身份（如 route query 序列化串），
///   identity 变化时正文回到顶部，identity 不变的等价重建保持滚动位置；
/// - [initialLoading] 期间正文区显示加载指示、不渲染正文；
/// - [error] 非空时在底栏上方追加内联错误区块，已有正文不清空，
///   提供 [onRetry] 时展示重试入口。
class AppPaginatedListShell extends StatefulWidget {
  const AppPaginatedListShell({
    super.key,
    this.header,
    required this.bodyBuilder,
    required this.paginationState,
    required this.onPageChanged,
    required this.onPageSizeChanged,
    this.pageSizeOptions = appPageSizeOptions,
    this.pageIdentity,
    this.initialLoading = false,
    this.error,
    this.onRetry,
  });

  /// 渲染在正文上方的固定头部（如工具栏）；可为空。
  final Widget? header;

  /// 正文构建器，负责 feature 自有的列表内容。
  final AppPaginatedBodyBuilder bodyBuilder;

  /// 当前受控分页状态，转发给底部分页栏。
  final AppPaginationState paginationState;

  /// 分页栏页码变化回调透传。
  final ValueChanged<int> onPageChanged;

  /// 分页栏容量变化回调透传。
  final ValueChanged<int> onPageSizeChanged;

  /// 容量可选项，转发给分页栏。
  final List<int> pageSizeOptions;

  /// 当前数据窗口的身份标识；变化时正文滚动位置归零。
  final Object? pageIdentity;

  /// 是否处于首次加载；为真时正文区显示加载指示。
  final bool initialLoading;

  /// 当前查询错误文案；非空时在底栏上方展示内联错误区块。
  final String? error;

  /// 错误重试回调；为空时不展示重试入口。
  final VoidCallback? onRetry;

  @override
  State<AppPaginatedListShell> createState() => _AppPaginatedListShellState();
}

class _AppPaginatedListShellState extends State<AppPaginatedListShell> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(AppPaginatedListShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在数据窗口身份真正变化时回顶；详情 push/pop 引起的等价重建
    // 不改变 identity，滚动位置得以保留。
    if (widget.pageIdentity != oldWidget.pageIdentity &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Expanded(
          child: widget.initialLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.bodyBuilder(context, _scrollController),
        ),
        if (!widget.initialLoading && widget.error != null)
          _InlineErrorBanner(error: widget.error!, onRetry: widget.onRetry),
        AppPaginationBar(
          state: widget.paginationState,
          onPageChanged: widget.onPageChanged,
          onPageSizeChanged: widget.onPageSizeChanged,
          pageSizeOptions: widget.pageSizeOptions,
        ),
      ],
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({required this.error, this.onRetry});

  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
