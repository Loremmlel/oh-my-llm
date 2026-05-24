import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_preferences_provider.dart';
import '../domain/models/auto_retry_settings.dart';

const String autoRetrySettingsStorageKey = 'settings.auto_retry';

final autoRetrySettingsProvider =
    NotifierProvider<AutoRetrySettingsController, AutoRetrySettings>(
      AutoRetrySettingsController.new,
    );

/// 自动重试全局设置控制器。
class AutoRetrySettingsController extends Notifier<AutoRetrySettings> {
  @override
  AutoRetrySettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final rawJson = prefs.getString(autoRetrySettingsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return const AutoRetrySettings();
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return const AutoRetrySettings();
      }
      return AutoRetrySettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const AutoRetrySettings();
    }
  }

  Future<void> save(AutoRetrySettings settings) async {
    state = settings;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      autoRetrySettingsStorageKey,
      jsonEncode(settings.toJson()),
    );
  }
}
