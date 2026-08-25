import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';

import '../../domain/models/preferences/auto_retry_settings.dart';

const String autoRetrySettingsStorageKey = 'settings.auto_retry';

final autoRetrySettingsProvider =
    NotifierProvider<AutoRetrySettingsController, AutoRetrySettings>(
      AutoRetrySettingsController.new,
    );

final autoRetrySettingsStoreProvider =
    Provider<VersionedJsonStore<AutoRetrySettings>>((ref) {
      return VersionedJsonStore<AutoRetrySettings>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: autoRetrySettingsStorageKey,
        subject: 'auto retry settings',
        fallback: () => const AutoRetrySettings(),
        fromJson: AutoRetrySettings.fromJson,
        toJson: (settings) => settings.toJson(),
      );
    });

/// 自动重试全局设置控制器。
class AutoRetrySettingsController extends Notifier<AutoRetrySettings> {
  @override
  AutoRetrySettings build() => ref.read(autoRetrySettingsStoreProvider).load();

  Future<void> save(AutoRetrySettings settings) async {
    await ref.read(autoRetrySettingsStoreProvider).save(settings);
    state = settings;
  }
}
