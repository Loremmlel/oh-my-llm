import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';
import '../domain/models/font_size_settings.dart';

const String fontSizeSettingsStorageKey = 'settings.font_size';

final fontSizeSettingsProvider =
    NotifierProvider<FontSizeSettingsController, FontSizeSettings>(
      FontSizeSettingsController.new,
    );

final fontSizeSettingsStoreProvider =
    Provider<VersionedJsonStore<FontSizeSettings>>(
      (ref) => VersionedJsonStore<FontSizeSettings>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: fontSizeSettingsStorageKey,
        subject: 'font size settings',
        fallback: () => const FontSizeSettings(),
        fromJson: FontSizeSettings.fromJson,
        toJson: (settings) => settings.toJson(),
      ),
    );

/// 正文字号全局设置控制器。
class FontSizeSettingsController extends Notifier<FontSizeSettings> {
  @override
  FontSizeSettings build() => ref.read(fontSizeSettingsStoreProvider).load();

  /// 仅更新内存状态，不写入 SharedPreferences。
  /// 适合拖拽滑块等高频操作，磁盘写入由 [save] 在拖拽结束时负责。
  void updateLocal(FontSizeSettings settings) {
    state = settings;
  }

  /// 持久化写入并同步内存状态。先写磁盘再更新 state，
  /// 避免写入失败导致重启后回退的"幽灵值"问题。
  Future<void> save(FontSizeSettings settings) async {
    await ref.read(fontSizeSettingsStoreProvider).save(settings);
    state = settings;
  }
}
