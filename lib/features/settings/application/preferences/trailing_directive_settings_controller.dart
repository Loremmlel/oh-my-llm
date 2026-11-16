import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';

import '../../domain/models/preferences/trailing_directive_settings.dart';

const String trailingDirectiveSettingsStorageKey =
    'settings.trailing_directive';

final trailingDirectiveSettingsProvider =
    NotifierProvider<
      TrailingDirectiveSettingsController,
      TrailingDirectiveSettings
    >(TrailingDirectiveSettingsController.new);

final trailingDirectiveSettingsStoreProvider =
    Provider<VersionedJsonStore<TrailingDirectiveSettings>>((ref) {
      return VersionedJsonStore<TrailingDirectiveSettings>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: trailingDirectiveSettingsStorageKey,
        subject: 'trailing directive settings',
        fallback: () => const TrailingDirectiveSettings(),
        fromJson: TrailingDirectiveSettings.fromJson,
        toJson: (settings) => settings.toJson(),
      );
    });

/// 末尾指令全局设置控制器。
class TrailingDirectiveSettingsController
    extends Notifier<TrailingDirectiveSettings> {
  @override
  TrailingDirectiveSettings build() =>
      ref.read(trailingDirectiveSettingsStoreProvider).load();

  Future<void> save(TrailingDirectiveSettings settings) async {
    await ref.read(trailingDirectiveSettingsStoreProvider).save(settings);
    state = settings;
  }

  Future<void> updateContent(String content) {
    return save(state.copyWith(content: content));
  }

  Future<void> setAlternatingMode(bool alternatingMode) {
    return save(state.copyWith(alternatingMode: alternatingMode));
  }
}
