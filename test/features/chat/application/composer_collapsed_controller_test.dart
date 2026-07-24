import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/composer_collapsed_controller.dart';

void main() {
  group('ComposerCollapsedController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late ComposerCollapsedController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      controller = container.read(composerCollapsedProvider.notifier);
    }

    bool readState() => container.read(composerCollapsedProvider);

    // ── build() 恢复 ────────────────────────────────────────────

    test('无持久化数据时默认展开（false）', () async {
      await boot({});
      expect(readState(), false);
    });

    test('从持久化恢复折叠状态为 true', () async {
      await boot({'composer_isCollapsed': true});
      expect(readState(), true);
    });

    test('从持久化恢复折叠状态为 false', () async {
      await boot({'composer_isCollapsed': false});
      expect(readState(), false);
    });

    // ── toggle ────────────────────────────────────────────────

    test('toggle 从展开切换为折叠', () async {
      await boot({});
      expect(readState(), false);

      controller.toggle();
      expect(readState(), true);
    });

    test('toggle 从折叠切换为展开', () async {
      await boot({'composer_isCollapsed': true});
      controller.toggle();
      expect(readState(), false);
    });

    test('多次 toggle 在两端之间切换', () async {
      await boot({});
      controller.toggle();
      expect(readState(), true);
      controller.toggle();
      expect(readState(), false);
      controller.toggle();
      expect(readState(), true);
    });

    // ── setCollapsed ───────────────────────────────────────────

    test('setCollapsed 设相同值时无操作', () async {
      await boot({'composer_isCollapsed': false});
      controller.setCollapsed(false);
      expect(readState(), false);
    });

    test('setCollapsed 设不同值时更新状态', () async {
      await boot({});
      controller.setCollapsed(true);
      expect(readState(), true);
    });

    test('setCollapsed 后写入 SharedPreferences', () async {
      await boot({});
      controller.setCollapsed(true);
      await Future.microtask(() {});
      expect(sp.getBool('composer_isCollapsed'), true);
    });

    // ── 持久化 ──────────────────────────────────────────────────

    test('toggle 后写入 SharedPreferences', () async {
      await boot({});
      controller.toggle();
      // _save 异步写回，等待微任务落地后再断言持久化值。
      await Future.microtask(() {});
      expect(sp.getBool('composer_isCollapsed'), true);
    });

    test('重建容器后能恢复上次折叠状态', () async {
      await boot({});
      controller.toggle();
      await Future.microtask(() {});

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      expect(revived.read(composerCollapsedProvider), true);
    });
  });
}
