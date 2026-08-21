import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

import 'app_pagination_state.dart';

/// 受控分页栏：所有页码变化通过回调抛出，自身不持有页码状态。
///
/// 宽模式展示总数、页码折叠序列、容量选择与跳转入口；窄模式收缩为
/// 上一页/下一页、`当前页/总页数` 概览与容量选择。busy 期间禁用全部
/// 交互但不改变已有内容；总页数为 0 时整体不渲染。
class AppPaginationBar extends StatefulWidget {
  const AppPaginationBar({
    super.key,
    required this.state,
    required this.onPageChanged,
    required this.onPageSizeChanged,
    this.pageSizeOptions = appPageSizeOptions,
  });

  /// 当前受控分页状态。
  final AppPaginationState state;

  /// 目标页码回调；入参已按有效范围校验并夹取，相同页不触发。
  final ValueChanged<int> onPageChanged;

  /// 每页容量回调；仅当选择的容量与当前不同时触发。
  final ValueChanged<int> onPageSizeChanged;

  /// 容量可选项。
  final List<int> pageSizeOptions;

  @override
  State<AppPaginationBar> createState() => _AppPaginationBarState();
}

class _AppPaginationBarState extends State<AppPaginationBar> {
  late final TextEditingController _jumpController;

  @override
  void initState() {
    super.initState();
    _jumpController = TextEditingController();
  }

  @override
  void dispose() {
    _jumpController.dispose();
    super.dispose();
  }

  // ── 跳转 ────────────────────────────────────────────────

  void _submitJump() {
    final text = _jumpController.text.trim();
    if (text.isEmpty) return;
    final parsed = int.tryParse(text);
    if (parsed == null) return;

    final totalPages = widget.state.totalPages;
    final target = parsed < 1 ? 1 : (parsed > totalPages ? totalPages : parsed);
    if (target == widget.state.currentPage) return;
    widget.onPageChanged(target);
    _jumpController.clear();
  }

  // ── 页码按钮 ────────────────────────────────────────────

  Widget _buildPageButton(int pageNumber, {required bool isActive}) {
    if (isActive) {
      // 当前页保持激活视觉，AbsorbPointer 吸收点击避免重复回调。
      return AbsorbPointer(
        child: FilledButton(
          onPressed: () => widget.onPageChanged(pageNumber),
          style: FilledButton.styleFrom(
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero,
          ),
          child: Text('$pageNumber'),
        ),
      );
    }
    return OutlinedButton(
      onPressed: widget.state.isBusy
          ? null
          : () => widget.onPageChanged(pageNumber),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      child: Text('$pageNumber'),
    );
  }

  // ── 布局 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final totalPages = state.totalPages;
    final disabled = state.isBusy;

    if (totalPages <= 0) return const SizedBox.shrink();

    final visiblePages = resolveVisiblePageNumbers(
      totalPages,
      state.currentPage,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 沿用应用壳断点判定宽/紧凑，与既有历史分页栏保持一致收窄时机。
        final compact = AppBreakpoints.useCompactShell(constraints.maxWidth);
        final spacing = compact ? 2.0 : 8.0;
        final pageSizeWidth = compact ? 72.0 : 96.0;
        final pageSizePadding = compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
        final jumpWidth = compact ? 48.0 : 64.0;
        final jumpContentPadding = compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 10);

        final pageControls = <Widget>[
          IconButton(
            tooltip: '上一页',
            icon: const Icon(Icons.chevron_left_rounded),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: !disabled && state.hasPrevious
                ? () => widget.onPageChanged(state.currentPage - 1)
                : null,
          ),
          if (!compact)
            for (final item in visiblePages)
              if (item.isEllipsis)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('…', style: theme.textTheme.bodyMedium),
                )
              else
                _buildPageButton(
                  item.page!,
                  isActive: item.page == state.currentPage,
                ),
          IconButton(
            tooltip: '下一页',
            icon: const Icon(Icons.chevron_right_rounded),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: !disabled && state.hasNext
                ? () => widget.onPageChanged(state.currentPage + 1)
                : null,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (compact)
              Text('${state.currentPage}/$totalPages')
            else ...[
              Text(
                '共 ${state.totalItems} 条 · ${state.currentPage}/$totalPages 页',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(width: spacing),
              ...pageControls,
            ],
            if (compact) ...pageControls,
            SizedBox(
              width: pageSizeWidth,
              child: DropdownButtonFormField<int>(
                // 容量不在选项内（如 route 携带非法值）时不预选，交由上层回退。
                initialValue: widget.pageSizeOptions.contains(state.pageSize)
                    ? state.pageSize
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '每页',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: pageSizePadding,
                ),
                items: [
                  for (final size in widget.pageSizeOptions)
                    DropdownMenuItem<int>(value: size, child: Text('$size')),
                ],
                onChanged: disabled
                    ? null
                    : (value) {
                        if (value == null || value == state.pageSize) return;
                        widget.onPageSizeChanged(value);
                      },
              ),
            ),
            if (!compact) ...[
              SizedBox(
                width: jumpWidth,
                child: TextField(
                  controller: _jumpController,
                  enabled: !disabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: '页码',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: jumpContentPadding,
                  ),
                  onSubmitted: (_) => _submitJump(),
                ),
              ),
              TextButton(
                onPressed: disabled ? null : _submitJump,
                child: const Text('跳转'),
              ),
            ],
          ],
        );
      },
    );
  }
}
