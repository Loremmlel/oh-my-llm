import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';

const String mediaRootDirectoryStorageKey = 'media.root_directory';

/// 媒体根目录配置 Provider。
///
/// 仅服务端使用，客户端此值为 null。
final mediaRootDirectoryProvider =
    NotifierProvider<MediaRootDirectoryController, String?>(
  MediaRootDirectoryController.new,
);

/// 媒体根目录配置控制器。
///
/// 读写 [SharedPreferences] 中的 `media.root_directory` 键。
/// 服务端用户在同步页的"连接"Tab 中设置此值。
class MediaRootDirectoryController extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(mediaRootDirectoryStorageKey);
  }

  /// 保存根目录路径。传 `null` 清除配置。
  Future<void> setDirectory(String? directory) async {
    final trimmed = directory?.trim();
    final cleaned = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = cleaned;
    final prefs = ref.read(sharedPreferencesProvider);
    if (cleaned == null) {
      await prefs.remove(mediaRootDirectoryStorageKey);
    } else {
      await prefs.setString(mediaRootDirectoryStorageKey, cleaned);
    }
  }
}
