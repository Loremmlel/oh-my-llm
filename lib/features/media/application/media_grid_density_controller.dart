import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

const String mediaGridDensityStorageKey = 'app.feature.media.grid_density';

typedef MediaGridDensityWriter =
    Future<bool> Function(AppLayoutDensity density);

final mediaGridDensityDefaultProvider = Provider<AppLayoutDensity>(
  (ref) => AppLayoutDensity.standard,
);

final mediaGridDensityWriterProvider = Provider<MediaGridDensityWriter>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return (density) =>
      preferences.setString(mediaGridDensityStorageKey, density.name);
});

final mediaGridDensityProvider =
    NotifierProvider<MediaGridDensityController, AppLayoutDensity>(
      MediaGridDensityController.new,
    );

class MediaGridDensityController extends Notifier<AppLayoutDensity> {
  @override
  AppLayoutDensity build() {
    final fallback = ref.watch(mediaGridDensityDefaultProvider);
    final raw = ref
        .watch(sharedPreferencesProvider)
        .getString(mediaGridDensityStorageKey);
    return switch (raw) {
      'compact' => AppLayoutDensity.compact,
      'standard' => AppLayoutDensity.standard,
      'comfortable' => AppLayoutDensity.comfortable,
      _ => fallback,
    };
  }

  Future<void> select(AppLayoutDensity density) async {
    state = density;
    try {
      await ref.read(mediaGridDensityWriterProvider)(density);
    } catch (_) {
      // 密度是非关键本地偏好；内存选择继续生效，写入失败不阻塞浏览。
    }
  }
}
