// 分页容量与页码推导契约：所有 feature 的分页浏览共用同一组容量、默认值
// 与页码夹取纯函数。零框架依赖；domain 层、data 层与 core 分页模块均可
// 直接引用，core 分页模块（app_pagination_state.dart）re-export 本文件，
// widget/application 消费方经分页模块引用。
library;

/// 可选的每页条数。
const List<int> appPageSizeOptions = <int>[10, 20, 50];

/// 默认每页条数。
const int appDefaultPageSize = 20;

/// 由总条数与容量推导总页数；容量非法（<= 0）时为 0。
int totalPagesForItems(int totalItems, int pageSize) =>
    pageSize <= 0 ? 0 : (totalItems / pageSize).ceil();

/// 把请求页码夹取到 [1, totalPages]；总页数为 0（空数据）时归一为 1。
///
/// `AppPaginationState` 构造器因 const 约束保留同语义的内联表达式，
/// 两者的一致性由 app_pagination_state_test 的参数化用例锁定。
int clampPageToValidRange(int page, int totalPages) => totalPages <= 0
    ? 1
    : page < 1
    ? 1
    : (page > totalPages ? totalPages : page);
