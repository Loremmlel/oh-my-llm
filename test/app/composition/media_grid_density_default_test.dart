import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';
import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/media/application/media_grid_density_controller.dart';

/// 带生产组合绑定与内存 SharedPreferences 的容器。
///
/// 只读取媒体密度 provider；组合中的其余绑定为惰性，不会被本次读取触发。
Future<ProviderContainer> bootCompositionContainer() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...appCompositionOverrides(useInMemorySyncSecureStore: true),
    ],
  );
}

void main() {
  test('Windows 平台默认媒体密度为紧凑', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = await bootCompositionContainer();
    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.compact);
    container.dispose();
    // 测试框架在 body 末尾校验 foundation debug 变量已复位（addTearDown 在该
    // 校验之后才执行），故 body 内显式复位，addTearDown 仅作失败路径兜底。
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android 平台默认媒体密度为标准', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = await bootCompositionContainer();
    expect(container.read(mediaGridDensityProvider), AppLayoutDensity.standard);
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
