/// 分页容量契约：所有 feature 的分页浏览共用同一组可选容量与默认值。
///
/// 纯常量文件，无框架依赖；domain 层与 core 分页模块均可引用。
/// core 分页模块（app_pagination_state.dart）re-export 本文件，
/// widget/application 消费方经分页模块引用，domain 直接引用本文件。
const List<int> appPageSizeOptions = <int>[10, 20, 50];

/// 默认每页条数。
const int appDefaultPageSize = 20;
