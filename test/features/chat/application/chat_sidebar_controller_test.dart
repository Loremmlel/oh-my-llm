import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sidebar_controller.dart';

void main() {
  group('ChatSidebarController', () {
    late SharedPreferences sp;
    late ProviderContainer container;
    late ChatSidebarController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      sp = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      controller = container.read(chatSidebarProvider.notifier);
    }

    ChatSidebarState readState() => container.read(chatSidebarProvider);

    // ── build() 恢复 ────────────────────────────────────────────

    test('无持久化数据时返回默认值', () async {
      await boot({});
      expect(readState().activeFunction, ChatSidebarFunction.history);
      expect(readState().isExpanded, true);
      expect(readState().panelWidth, 260.0);
    });

    test('从持久化恢复 activeFunction', () async {
      await boot({'sidebar_activeFunction': 'preset'});
      expect(readState().activeFunction, ChatSidebarFunction.preset);
    });

    test('无法识别的 function 值降级为 history', () async {
      await boot({'sidebar_activeFunction': 'nonexistent'});
      expect(readState().activeFunction, ChatSidebarFunction.history);
    });

    test('从持久化恢复 isExpanded', () async {
      await boot({'sidebar_isExpanded': false});
      expect(readState().isExpanded, false);
    });

    test('从持久化恢复 panelWidth', () async {
      await boot({'sidebar_panelWidth': 300.0});
      expect(readState().panelWidth, 300.0);
    });

    test('panelWidth 超出上限被 clamp', () async {
      await boot({'sidebar_panelWidth': 500.0});
      expect(readState().panelWidth, 400.0);
    });

    test('panelWidth 低于下限被 clamp', () async {
      await boot({'sidebar_panelWidth': 100.0});
      expect(readState().panelWidth, 180.0);
    });

    // ── toggleFunction ──────────────────────────────────────────

    test('点击已激活项 → 切换展开/折叠', () async {
      await boot({});
      expect(readState().activeFunction, ChatSidebarFunction.history);
      expect(readState().isExpanded, true);

      controller.toggleFunction(ChatSidebarFunction.history);
      expect(readState().activeFunction, ChatSidebarFunction.history);
      expect(readState().isExpanded, false);
    });

    test('点击新项 → 切换功能并展开', () async {
      await boot({});
      controller.toggleFunction(ChatSidebarFunction.history);
      expect(readState().isExpanded, false);

      controller.toggleFunction(ChatSidebarFunction.preset);
      expect(readState().activeFunction, ChatSidebarFunction.preset);
      expect(readState().isExpanded, true);
    });

    // ── collapse ────────────────────────────────────────────────

    test('已展开时 collapse → 折叠', () async {
      await boot({});
      expect(readState().isExpanded, true);

      controller.collapse();
      expect(readState().isExpanded, false);
    });

    test('已折叠时 collapse → 无操作', () async {
      await boot({});
      controller.collapse();
      expect(readState().isExpanded, false);

      controller.collapse();
      expect(readState().isExpanded, false);
    });

    // ── setPanelWidth ──────────────────────────────────────────

    test('setPanelWidth 正常更新并 clamp', () async {
      await boot({});
      controller.setPanelWidth(350.0);
      expect(readState().panelWidth, 350.0);
    });

    test('setPanelWidth 差值小于0.5 → 忽略（去抖）', () async {
      await boot({});
      expect(readState().panelWidth, 260.0);

      controller.setPanelWidth(260.3);
      expect(readState().panelWidth, 260.0);

      controller.setPanelWidth(260.6);
      expect(readState().panelWidth, 260.6);
    });

    test('setPanelWidth 超范围被 clamp', () async {
      await boot({});
      controller.setPanelWidth(999.0);
      expect(readState().panelWidth, 400.0);

      controller.setPanelWidth(50.0);
      expect(readState().panelWidth, 180.0);
    });

    // ── 持久化 ──────────────────────────────────────────────────

    test('操作后 _save 写入 SharedPreferences', () async {
      await boot({});
      controller.toggleFunction(ChatSidebarFunction.preset);
      controller.collapse();

      expect(sp.getString('sidebar_activeFunction'), 'preset');
      expect(sp.getBool('sidebar_isExpanded'), false);
    });

    test('_save 后重建容器能恢复完整状态', () async {
      await boot({});
      controller.toggleFunction(ChatSidebarFunction.preset);
      controller.setPanelWidth(350.0);

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(revived.dispose);

      final restored = revived.read(chatSidebarProvider);
      expect(restored.activeFunction, ChatSidebarFunction.preset);
      expect(restored.panelWidth, 350.0);
    });
  });
}
