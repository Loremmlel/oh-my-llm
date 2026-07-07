import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/application/history_pagination_controller.dart';
import '../../../../core/constants/app_breakpoints.dart';

/// 分页栏中显示的页码项：具体页码或省略标记。
typedef _PageNumberItem = ({int? page, bool isEllipsis});

/// 历史页的固定翻页栏。
///
/// 位于 HistoryToolbar 与可滚动列表之间，始终固定、不参与列表滚动。
/// 提供上一页/下一页、页码省略号折叠、每页条数下拉以及跳转到指定页。
class HistoryPaginationBar extends ConsumerStatefulWidget {
  const HistoryPaginationBar({super.key});

  @override
  ConsumerState<HistoryPaginationBar> createState() =>
      _HistoryPaginationBarState();
}

class _HistoryPaginationBarState extends ConsumerState<HistoryPaginationBar> {
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

  /// 计算应显示的页码集合（包含省略标记）。
  ///
  /// 规则：
  /// - totalPages ≤ 7 时显示 1..totalPages 全量。
  /// - 否则保留首 2 页 + 末 2 页 + 当前页 ± 1，中间用省略标记。
  List<_PageNumberItem> _visiblePageNumbers(int totalPages, int currentPage) {
    if (totalPages <= 7) {
      return List.generate(
        totalPages,
        (i) => (page: i + 1, isEllipsis: false),
      );
    }

    const leftEdge = 2;
    const rightEdge = 2;
    const surrounding = 1;

    final pages = <int>{};
    // 头
    for (var p = 1; p <= leftEdge; p++) {
      pages.add(p);
    }
    // 当前页窗口
    for (var p = currentPage - surrounding;
        p <= currentPage + surrounding;
        p++) {
      if (p >= 1 && p <= totalPages) pages.add(p);
    }
    // 尾
    for (var p = totalPages - rightEdge + 1; p <= totalPages; p++) {
      pages.add(p);
    }

    final sorted = pages.toList()..sort();
    final result = <_PageNumberItem>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
        result.add((page: null, isEllipsis: true));
      }
      result.add((page: sorted[i], isEllipsis: false));
    }
    return result;
  }

  void _onJump() {
    final text = _jumpController.text.trim();
    if (text.isEmpty) return;
    final parsed = int.tryParse(text);
    if (parsed == null) return;

    ref.read(historyPaginationProvider.notifier).goToPage(parsed);
    _jumpController.clear();
  }

  Widget _buildPageButton(
    int pageNumber, {
    required bool isActive,
    required bool disabled,
    required bool compact,
  }) {
    final onTap = disabled ? null : () => ref
        .read(historyPaginationProvider.notifier)
        .goToPage(pageNumber);
    final minSize = compact ? const Size(32, 32) : const Size(40, 40);
    final textStyle = compact ? const TextStyle(fontSize: 13) : null;
    if (isActive) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: minSize,
          padding: EdgeInsets.zero,
          textStyle: textStyle,
        ),
        child: Text('$pageNumber'),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        padding: EdgeInsets.zero,
        textStyle: textStyle,
      ),
      child: Text('$pageNumber'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyPaginationProvider);
    final theme = Theme.of(context);
    final totalPages = state.totalPages;
    final disabled = state.isLoading;

    if (totalPages <= 0) return const SizedBox.shrink();

    final visiblePages = _visiblePageNumbers(totalPages, state.currentPage);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < AppBreakpoints.compact;
        final spacing = isCompact ? 4.0 : 8.0;
        final iconVisualDensity =
            isCompact ? VisualDensity.compact : VisualDensity.standard;
        final pageSizeWidth = isCompact ? 72.0 : 96.0;
        final pageSizePadding = isCompact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
        final jumpWidth = isCompact ? 48.0 : 64.0;
        final jumpContentPadding = isCompact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 10);
        final jumpTextStyle =
            isCompact ? const TextStyle(fontSize: 13) : null;
        final jumpButtonStyle = isCompact
            ? TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              )
            : null;
        final jumpButtonTextStyle =
            isCompact ? const TextStyle(fontSize: 13) : null;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '共 ${state.totalItems} 条 · ${state.currentPage}/$totalPages 页',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: spacing),
            IconButton(
              tooltip: '上一页',
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: iconVisualDensity,
              onPressed:
                  !disabled && state.hasPrevious
                      ? () =>
                          ref
                              .read(historyPaginationProvider.notifier)
                              .prev()
                      : null,
            ),
            for (final item in visiblePages)
              if (item.isEllipsis)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 2 : 4,
                  ),
                  child: Text(
                    '…',
                    style: isCompact
                        ? theme.textTheme.bodySmall
                        : theme.textTheme.bodyMedium,
                  ),
                )
              else
                _buildPageButton(
                  item.page!,
                  isActive: item.page == state.currentPage,
                  disabled: disabled,
                  compact: isCompact,
                ),
            IconButton(
              tooltip: '下一页',
              icon: const Icon(Icons.chevron_right_rounded),
              visualDensity: iconVisualDensity,
              onPressed:
                  !disabled && state.hasNext
                      ? () =>
                          ref
                              .read(historyPaginationProvider.notifier)
                              .next()
                      : null,
            ),
            SizedBox(width: spacing),
            SizedBox(
              width: pageSizeWidth,
              child: DropdownButtonFormField<int>(
                initialValue: state.pageSize,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '每页',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: pageSizePadding,
                ),
                items: [
                  for (final size in availablePageSizes)
                    DropdownMenuItem<int>(value: size, child: Text('$size')),
                ],
                onChanged: disabled
                    ? null
                    : (value) {
                        if (value == null) return;
                        ref
                            .read(historyPaginationProvider.notifier)
                            .setPageSize(value);
                      },
              ),
            ),
            SizedBox(
              width: jumpWidth,
              child: TextField(
                controller: _jumpController,
                enabled: !disabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: jumpTextStyle,
                decoration: InputDecoration(
                  labelText: '页码',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: jumpContentPadding,
                ),
                onSubmitted: (_) => _onJump(),
              ),
            ),
            TextButton(
              onPressed: disabled ? null : _onJump,
              style: jumpButtonStyle,
              child: Text('跳转', style: jumpButtonTextStyle),
            ),
          ],
        );
      },
    );
  }
}
