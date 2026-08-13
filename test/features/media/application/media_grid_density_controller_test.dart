import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';

/// 用内存 SharedPreferences 与注入的默认密度创建容器。
Future<ProviderContainer> boot({
  required AppLayoutDensity defaultDensity,
  List<dynamic> extraOverrides = const [],
}) async {
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      mediaGridDensityDefaultProvider.overrideWithValue(defaultDensity),
      ...extraOverrides,
    ],
  );
}

void main() {
  for (final testCase in [
    ('compact', AppLayoutDensity.compact),
    ('standard', AppLayoutDensity.standard),
    ('comfortable', AppLayoutDensity.comfortable),
  ]) {
    test('持久化值 ${testCase.$1} 恢复为对应密度', () async {
      SharedPreferences.setMockInitialValues({
        mediaGridDensityStorageKey: testCase.$1,
      });
      final container = await boot(defaultDensity: AppLayoutDensity.standard);
      expect(container.read(mediaGridDensityProvider), testCase.$2);
    });
  }

  test('无持久化值时使用注入的默认密度', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await boot(defaultDensity: AppLayoutDensity.comfortable);
    expect(
      container.read(mediaGridDensityProvider),
      AppLayoutDensity.comfortable,
    );
  });

  test('未知字符串回退到注入的默认密度', () async {
    SharedPreferences.setMockInitialValues({
      mediaGridDensityStorageKey: 'unknown-garbage',
    });
    final container = await boot(defaultDensity: AppLayoutDensity.compact);
    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.compact);
  });

  test('select 立即更新 state 并写入持久化键', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await boot(defaultDensity: AppLayoutDensity.standard);
    await container
        .read(mediaGridDensityProvider.notifier)
        .select(AppLayoutDensity.comfortable);
    expect(
      container.read(mediaGridDensityProvider),
      AppLayoutDensity.comfortable,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(mediaGridDensityStorageKey), 'comfortable');
  });

  test('销毁后使用同一 SharedPreferences revive 得到 comfortable', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await boot(defaultDensity: AppLayoutDensity.standard);
    await container
        .read(mediaGridDensityProvider.notifier)
        .select(AppLayoutDensity.comfortable);
    final preferences = await SharedPreferences.getInstance();
    container.dispose();

    final revived = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        mediaGridDensityDefaultProvider.overrideWithValue(
          AppLayoutDensity.standard,
        ),
      ],
    );
    expect(
      revived.read(mediaGridDensityProvider),
      AppLayoutDensity.comfortable,
    );
  });

  test('writer 抛异常时 select 正常完成且 state 保持新值', () async {
    SharedPreferences.setMockInitialValues({});
    final container = await boot(
      defaultDensity: AppLayoutDensity.standard,
      extraOverrides: [
        mediaGridDensityWriterProvider.overrideWithValue(
          (_) async => throw StateError('写入失败'),
        ),
      ],
    );
    await container
        .read(mediaGridDensityProvider.notifier)
        .select(AppLayoutDensity.compact);
    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.compact);
  });
}
