import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

const String syncWorkspaceLastTabIndexKey = 'sync.tab.last_index';

/// Sync workspace 的持久化 Tab 偏好，不拥有 socket 或媒体进程生命周期。
final syncWorkspaceTabPreferenceProvider =
    NotifierProvider<SyncWorkspaceTabPreferenceController, int>(
      SyncWorkspaceTabPreferenceController.new,
    );

class SyncWorkspaceTabPreferenceController extends Notifier<int> {
  @override
  int build() {
    return ref
            .watch(sharedPreferencesProvider)
            .getInt(syncWorkspaceLastTabIndexKey) ??
        0;
  }

  /// 将当前选择写回既有 preference key，并针对当前平台 tab 数量裁剪。
  Future<void> select(int index, {required int tabCount}) async {
    final nextIndex = index.clamp(0, tabCount - 1);
    state = nextIndex;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(syncWorkspaceLastTabIndexKey, nextIndex);
  }
}
