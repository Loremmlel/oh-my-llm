/// 删除普通收藏夹时，其内部收藏的处置方式。
///
/// 用类型区分两条事务路径，不用 nullable target 暗示模式：
/// 移动路径显式携带目标与归属时间，删除路径无附加参数。
sealed class CollectionDeleteRequest {
  const CollectionDeleteRequest();

  /// 把夹内收藏移动到 [targetCollectionId]，归属时间记为 [assignedAt]。
  factory CollectionDeleteRequest.moveItemsTo({
    required String targetCollectionId,
    required DateTime assignedAt,
  }) = MoveItemsOnCollectionDelete;

  /// 连同夹内收藏一起删除。
  factory CollectionDeleteRequest.deleteItems() = DeleteItemsOnCollectionDelete;
}

/// 移动处置：收藏全部转入目标收藏夹。
class MoveItemsOnCollectionDelete extends CollectionDeleteRequest {
  const MoveItemsOnCollectionDelete({
    required this.targetCollectionId,
    required this.assignedAt,
  });

  /// 移动目标收藏夹 ID；不得等于被删收藏夹本身。
  final String targetCollectionId;

  /// 移动后的归属时间；由调用方提供，repository 不读取系统时钟。
  final DateTime assignedAt;

  @override
  String toString() =>
      'MoveItemsOnCollectionDelete(target: $targetCollectionId, assignedAt: $assignedAt)';
}

/// 删除处置：夹内收藏一并删除。
class DeleteItemsOnCollectionDelete extends CollectionDeleteRequest {
  const DeleteItemsOnCollectionDelete();

  @override
  String toString() => 'DeleteItemsOnCollectionDelete()';
}
