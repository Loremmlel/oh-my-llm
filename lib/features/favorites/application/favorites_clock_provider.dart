import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Favorites 域的时间源：返回当前时刻。
///
/// 生产绑定 [DateTime.now]；测试 override 固定时间。
/// 新增收藏、批量移动、删除收藏夹的归属时间都从该 seam 取得并
/// 显式传给 repository，repository 不读取系统时钟。
final favoritesClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});
