import 'package:equatable/equatable.dart';

import 'favorite.dart';

/// 收藏分页查询结果：当前页条目 + 该过滤条件下的总条数。
///
/// caller 无需分别协调 count 与 page 查询。
class FavoritePage extends Equatable {
  const FavoritePage({required this.items, required this.totalItems});

  /// 当前页收藏条目，按 created_at DESC, id DESC 稳定排序。
  final List<Favorite> items;

  /// 过滤条件下的收藏总数。
  final int totalItems;

  @override
  List<Object?> get props => [items, totalItems];
}
