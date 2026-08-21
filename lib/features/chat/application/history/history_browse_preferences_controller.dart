import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_page_sizes.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

/// 历史页浏览偏好的存储键；与收藏页的 page size 偏好互不共用。
const String historyPageSizeStorageKey = 'app.feature.history.page_size';

/// 每页容量写入函数；测试可注入替身。
typedef HistoryPageSizeWriter = Future<bool> Function(int size);

final historyPageSizeWriterProvider = Provider<HistoryPageSizeWriter>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return (size) => preferences.setInt(historyPageSizeStorageKey, size);
});

/// 历史页每页条数偏好。
///
/// 仅接受 [appPageSizeOptions] 中的值；持久化值非法时回退
/// [appDefaultPageSize]。写入失败只保留内存选择，不阻塞浏览。
final historyBrowsePreferencesProvider =
    NotifierProvider<HistoryBrowsePreferencesController, int>(
      HistoryBrowsePreferencesController.new,
    );

class HistoryBrowsePreferencesController extends Notifier<int> {
  @override
  int build() {
    final raw = ref
        .watch(sharedPreferencesProvider)
        .getInt(historyPageSizeStorageKey);
    return appPageSizeOptions.contains(raw) ? raw! : appDefaultPageSize;
  }

  /// 记住最近使用的每页容量。
  Future<void> save(int size) async {
    if (!appPageSizeOptions.contains(size)) return;
    state = size;
    try {
      await ref.read(historyPageSizeWriterProvider)(size);
    } catch (_) {
      // 容量是非关键本地偏好；内存选择继续生效，写入失败不阻塞浏览。
    }
  }
}
