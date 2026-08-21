import 'package:equatable/equatable.dart';

/// 分页容量可选项；各 feature 共用同一组容量契约。
const List<int> appPageSizeOptions = <int>[10, 20, 50];

/// 默认每页条数。
const int appDefaultPageSize = 20;

/// 分页栏中显示的页码项：具体页码或省略标记。
typedef AppPaginationPageItem = ({int? page, bool isEllipsis});

/// 计算分页栏应显示的页码序列（含省略标记）。
///
/// 折叠规则：
/// - 总页数不超过 7 时显示 1..totalPages 全量；
/// - 否则保留首 2 页、末 2 页和当前页 ±1，中间以省略标记折叠。
List<AppPaginationPageItem> resolveVisiblePageNumbers(
  int totalPages,
  int currentPage,
) {
  if (totalPages <= 0) return const [];

  final current = currentPage < 1
      ? 1
      : (currentPage > totalPages ? totalPages : currentPage);
  if (totalPages <= 7) {
    return List.generate(totalPages, (i) => (page: i + 1, isEllipsis: false));
  }

  const leftEdge = 2;
  const rightEdge = 2;
  const surrounding = 1;

  final pages = <int>{};
  // 首部窗口
  for (var p = 1; p <= leftEdge; p++) {
    pages.add(p);
  }
  // 当前页窗口
  for (var p = current - surrounding; p <= current + surrounding; p++) {
    if (p >= 1 && p <= totalPages) pages.add(p);
  }
  // 尾部窗口
  for (var p = totalPages - rightEdge + 1; p <= totalPages; p++) {
    pages.add(p);
  }

  final sorted = pages.toList()..sort();
  final result = <AppPaginationPageItem>[];
  for (var i = 0; i < sorted.length; i++) {
    if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
      result.add((page: null, isEllipsis: true));
    }
    result.add((page: sorted[i], isEllipsis: false));
  }
  return result;
}

/// 受控分页状态：feature 层依据 route/查询结果组装，分页栏只负责渲染。
///
/// 当前页在构造时安全归一：总数为 0 归一为 1，越界收拢到有效区间，使派生
/// 属性在任何输入下自洽。归一以内联纯运算符完成，保证构造函数保持 const
/// 可用（const 表达式不允许方法调用）。
final class AppPaginationState extends Equatable {
  const AppPaginationState({
    int currentPage = 1,
    this.pageSize = appDefaultPageSize,
    this.totalItems = 0,
    this.isBusy = false,
  }) : currentPage = (pageSize <= 0 || totalItems <= 0)
           ? 1
           : currentPage < 1
           ? 1
           // ceil 除法的整数形式：(a + b - 1) ~/ b。
           : currentPage > (totalItems + pageSize - 1) ~/ pageSize
           ? (totalItems + pageSize - 1) ~/ pageSize
           : currentPage;

  /// 当前页码（从 1 开始，已归一到有效区间）。
  final int currentPage;

  /// 每页条目数；来自持久化偏好或 route 参数。
  final int pageSize;

  /// 满足当前查询条件的总条数。
  final int totalItems;

  /// 是否正在执行会改变当前窗口的加载；为真时分页栏禁用全部交互。
  final bool isBusy;

  /// 派生：总页数。
  int get totalPages => pageSize <= 0 ? 0 : (totalItems / pageSize).ceil();

  /// 派生：是否存在上一页。
  bool get hasPrevious => currentPage > 1;

  /// 派生：是否存在下一页。
  bool get hasNext => currentPage < totalPages;

  @override
  List<Object?> get props => [currentPage, pageSize, totalItems, isBusy];
}
