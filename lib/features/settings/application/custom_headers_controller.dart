import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/custom_headers_config.dart';

const String customHeadersStorageKey = 'settings.custom_headers';

final customHeadersProvider =
    NotifierProvider<CustomHeadersController, CustomHeadersConfig>(
      CustomHeadersController.new,
    );

/// 自定义 HTTP 请求头全局控制器。
class CustomHeadersController extends Notifier<CustomHeadersConfig> {
  @override
  CustomHeadersConfig build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rawJson = prefs.getString(customHeadersStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const CustomHeadersConfig();
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const CustomHeadersConfig();
      }
      return CustomHeadersConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const CustomHeadersConfig();
    }
  }

  /// 持久化保存配置。
  ///
  /// 先写持久化再更新 state，避免并发 save 时乱序写入导致
  /// SharedPreferences 与 state 不一致。
  Future<void> save(CustomHeadersConfig config) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      customHeadersStorageKey,
      jsonEncode(config.toJson()),
    );
    state = config;
  }

  /// 添加一条请求头规则。
  Future<void> addHeader(String key, String value) async {
    final newHeaders = [...state.headers, CustomHeaderEntry(key: key, value: value)];
    await save(state.copyWith(headers: newHeaders));
  }

  /// 删除指定位置的请求头规则。
  Future<void> removeHeader(int index) async {
    if (index < 0 || index >= state.headers.length) return;
    final newHeaders = [...state.headers]..removeAt(index);
    await save(state.copyWith(headers: newHeaders));
  }

  /// 更新指定位置的请求头规则。
  Future<void> updateHeader(int index, String key, String value) async {
    if (index < 0 || index >= state.headers.length) return;
    final newHeaders = [...state.headers];
    newHeaders[index] = CustomHeaderEntry(key: key, value: value);
    await save(state.copyWith(headers: newHeaders));
  }
}
