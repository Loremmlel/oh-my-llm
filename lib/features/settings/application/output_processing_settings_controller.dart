import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/output_processing_settings.dart';

const String outputProcessingSettingsStorageKey = 'settings.output_processing';

final outputProcessingSettingsProvider =
    NotifierProvider<OutputProcessingSettingsController, OutputProcessingSettings>(
      OutputProcessingSettingsController.new,
    );

/// 输出正则处理的全局设置控制器。
class OutputProcessingSettingsController
    extends Notifier<OutputProcessingSettings> {
  @override
  OutputProcessingSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rawJson = prefs.getString(outputProcessingSettingsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const OutputProcessingSettings();
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const OutputProcessingSettings();
      }
      return OutputProcessingSettings.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const OutputProcessingSettings();
    }
  }

  Future<void> save(OutputProcessingSettings settings) async {
    state = settings;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      outputProcessingSettingsStorageKey,
      jsonEncode(settings.toJson()),
    );
  }
}
