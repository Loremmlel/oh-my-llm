import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

const String mediaRootDirectoryStorageKey = 'media.root_directory';

/// 媒体根目录配置 Provider。
///
/// 仅在 Windows 端读取与设置：同步服务端的 HTTP handlers 与本地媒体库会话共用此根目录；
/// Android 客户端不设置此值（恒为 null）。
/// 它是持久化应用配置；scanner 的生命周期由 handlers / 本地媒体库会话各自拥有。
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
