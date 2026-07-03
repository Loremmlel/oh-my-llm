import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/application/history_pagination_controller.dart';

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
  static const _ellipsis = -1; // 在 _visiblePageNumbers 中的省略标记

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
  List<int> _visiblePageNumbers(int totalPages, int currentPage) {
    if (totalPages <= 7) {
      return List.generate(totalPages, (i) => i + 1);
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
    final result = <int>[];
    var prev = -1;
    for (final p in sorted) {
      if (prev != -1 && p - prev > 1) {
        result.add(_ellipsis);
      }
      result.add(p);
      prev = p;
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(historyPaginationProvider);
    final theme = Theme.of(context);
    final totalPages = state.totalPages;

    if (totalPages <= 0) return const SizedBox.shrink();

    final visiblePages = _visiblePageNumbers(totalPages, state.currentPage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 总数行
        Text(
          '共 ${state.totalItems} 条 · 第 ${state.currentPage}/$totalPages 页',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 上一页
            IconButton(
              tooltip: '上一页',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed:
                  state.hasPrevious
                      ? () =>
                          ref
                              .read(historyPaginationProvider.notifier)
                              .prev()
                      : null,
            ),
            // 页码按钮（含省略号）
            for (final p in visiblePages)
              if (p == _ellipsis)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('…', style: theme.textTheme.bodyMedium),
                )
              else
                _PageNumberButton(
                  pageNumber: p,
                  isActive: p == state.currentPage,
                  onPressed:
                      p == state.currentPage
                          ? null
                          : () => ref
                              .read(historyPaginationProvider.notifier)
                              .goToPage(p),
                ),
            // 下一页
            IconButton(
              tooltip: '下一页',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed:
                  state.hasNext
                      ? () =>
                          ref
                              .read(historyPaginationProvider.notifier)
                              .next()
                      : null,
            ),
            const SizedBox(width: 12),
            // 每页条数下拉
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<int>(
                key: const Key('pagination-page-size-dropdown'),
                initialValue: state.pageSize,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '每页',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: [
                  for (final size in availablePageSizes)
                    DropdownMenuItem<int>(
                      value: size,
                      child: Text('$size'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  ref
                      .read(historyPaginationProvider.notifier)
                      .setPageSize(value);
                },
              ),
            ),
            // 跳转输入框 + 按钮
            SizedBox(
              width: 64,
              child: TextField(
                key: const Key('pagination-jump-input'),
                controller: _jumpController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: '页码',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _onJump(),
              ),
            ),
            TextButton(
              onPressed: _onJump,
              child: const Text('跳转'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个页码按钮：当前页用 [FilledButton]，其余用 [OutlinedButton]。
class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.pageNumber,
    required this.isActive,
    required this.onPressed,
  });

  final int pageNumber;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
        child: Text('$pageNumber'),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      child: Text('$pageNumber'),
    );
  }
}
