import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/persistence/settings_key_value_store.dart';
import 'package:oh_my_llm/core/persistence/versioned_json_store.dart';
import '../domain/models/output_processing_settings.dart';

const String outputProcessingSettingsStorageKey = 'settings.output_processing';

final outputProcessingSettingsProvider =
    NotifierProvider<
      OutputProcessingSettingsController,
      OutputProcessingSettings
    >(OutputProcessingSettingsController.new);

final outputProcessingSettingsStoreProvider =
    Provider<VersionedJsonStore<OutputProcessingSettings>>(
      (ref) => VersionedJsonStore<OutputProcessingSettings>(
        storage: ref.watch(settingsKeyValueStoreProvider),
        key: outputProcessingSettingsStorageKey,
        subject: 'output processing settings',
        fallback: () => const OutputProcessingSettings(),
        fromJson: OutputProcessingSettings.fromJson,
        toJson: (settings) => settings.toJson(),
      ),
    );

/// 输出正则处理的全局设置控制器。
class OutputProcessingSettingsController
    extends Notifier<OutputProcessingSettings> {
  @override
  OutputProcessingSettings build() =>
      ref.read(outputProcessingSettingsStoreProvider).load();

  Future<void> save(OutputProcessingSettings settings) async {
    await ref.read(outputProcessingSettingsStoreProvider).save(settings);
    state = settings;
  }
}
