/// 受控分页 module：状态与页码算法、分页栏与固定底栏列表外壳。
///
/// 只拥有通用分页能力；不感知任何 feature、Riverpod 或业务文案之外的
/// 领域语义。查询、搜索与 mutation 归各消费方所有。
export 'app_paginated_list_shell.dart';
export 'app_pagination_bar.dart';
export 'app_pagination_state.dart';
