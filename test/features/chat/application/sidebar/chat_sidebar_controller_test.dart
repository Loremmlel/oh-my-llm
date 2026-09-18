import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/sidebar/chat_sidebar_controller.dart';

void main() {
  for (final saved in [null, 'history', 'preset', 'unknown']) {
    test('恢复分段 $saved，缺省或无效值使用历史', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_activeFunction': ?saved,
        // 旧常驻侧栏的几何偏好不再影响抽屉。
        'sidebar_isExpanded': true,
        'sidebar_panelWidth': 180.0,
      });
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      expect(
        container.read(chatSidebarProvider),
        saved == 'preset'
            ? ChatSidebarFunction.preset
            : ChatSidebarFunction.history,
      );
    });
  }

  test('选择分段后重新建立容器仍恢复该分段', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final overrides = [
      sharedPreferencesProvider.overrideWithValue(preferences),
    ];
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container
        .read(chatSidebarProvider.notifier)
        .selectFunction(ChatSidebarFunction.preset);
    final restored = ProviderContainer(overrides: overrides);
    addTearDown(restored.dispose);
    expect(restored.read(chatSidebarProvider), ChatSidebarFunction.preset);
  });
}
