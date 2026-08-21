import 'package:equatable/equatable.dart';

import 'collection.dart';

/// 收藏夹卡片投影：归属数量与最近收录时间。
class FavoriteCollectionSummary extends Equatable {
  const FavoriteCollectionSummary({
    required this.collection,
    required this.itemCount,
    required this.recentAssignedAt,
  });

  /// 收藏夹本体。
  final FavoriteCollection collection;

  /// 夹内收藏数量。
  final int itemCount;

  /// 最近收录时间；空夹回退收藏夹创建时间。
  final DateTime recentAssignedAt;

  @override
  List<Object?> get props => [collection, itemCount, recentAssignedAt];
}
