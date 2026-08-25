import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';

import '../../domain/models/preferences/custom_headers_config.dart';

const String customHeadersStorageKey = 'settings.custom_headers';

final customHeadersProvider =
    NotifierProvider<CustomHeadersController, CustomHeadersConfig>(
      CustomHeadersController.new,
    );

final customHeadersStoreProvider =
    Provider<VersionedJsonStore<CustomHeadersConfig>>(
      (ref) => VersionedJsonStore<CustomHeadersConfig>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: customHeadersStorageKey,
        subject: 'custom headers',
        fallback: () => const CustomHeadersConfig(),
        fromJson: CustomHeadersConfig.fromJson,
        toJson: (config) => config.toJson(),
      ),
    );

/// 自定义 HTTP 请求头全局控制器。
class CustomHeadersController extends Notifier<CustomHeadersConfig> {
  @override
  CustomHeadersConfig build() => ref.read(customHeadersStoreProvider).load();

  /// 持久化保存配置。
  ///
  /// 先写持久化再更新 state，避免并发 save 时乱序写入导致
  /// SharedPreferences 与 state 不一致。
  Future<void> save(CustomHeadersConfig config) async {
    await ref.read(customHeadersStoreProvider).save(config);
    state = config;
  }

  /// 添加一条请求头规则。
  Future<void> addHeader(String key, String value) async {
    final newHeaders = [
      ...state.headers,
      CustomHeaderEntry(key: key, value: value),
    ];
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
