/// 应用内保留的固定实体常量。
///
/// 这些实体以真实数据行存在，不可被用户创建、重命名或删除。
/// 常量放在 core 供 persistence 与各 feature 共同引用；
/// core persistence 不 import 任何 feature，依赖方向保持单向。
abstract final class AppReservedEntities {
  /// 系统"未分类"收藏夹的固定 ID；全新安装与旧库迁移都以它播种。
  static const String uncategorizedFavoriteCollectionId =
      '__uncategorized_favorites__';

  /// 系统"未分类"收藏夹的固定显示名；普通收藏夹禁止使用该名称。
  static const String uncategorizedFavoriteCollectionName = '未分类';
}
