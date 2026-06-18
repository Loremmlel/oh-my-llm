import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/font_size_settings.dart';

const String fontSizeSettingsStorageKey = 'settings.font_size';

final fontSizeSettingsProvider =
    NotifierProvider<FontSizeSettingsController, FontSizeSettings>(
      FontSizeSettingsController.new,
    );

/// 正文字号全局设置控制器。
class FontSizeSettingsController extends Notifier<FontSizeSettings> {
  @override
  FontSizeSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rawJson = prefs.getString(fontSizeSettingsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const FontSizeSettings();
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const FontSizeSettings();
      }
      return FontSizeSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      // ignore: avoid_print — 持久化层无 logger 依赖，异常用 print 记录便于排查。
      debugPrint('FontSizeSettings 解析失败，使用默认值: $e');
      return const FontSizeSettings();
    }
  }

  /// 仅更新内存状态，不写入 SharedPreferences。
  /// 适合拖拽滑块等高频操作，磁盘写入由 [save] 在拖拽结束时负责。
  void updateLocal(FontSizeSettings settings) {
    state = settings;
  }

  /// 持久化写入并同步内存状态。先写磁盘再更新 state，
  /// 避免写入失败导致重启后回退的"幽灵值"问题。
  Future<void> save(FontSizeSettings settings) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      fontSizeSettingsStorageKey,
      jsonEncode(settings.toJson()),
    );
    state = settings;
  }
}
