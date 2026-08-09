import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';
import 'package:oh_my_llm/features/chat/application/chat_sidebar_controller.dart';

void main() {
  group('ChatSidebarController', () {
    late SharedPreferences preferences;
    late ProviderContainer container;
    late ChatSidebarController controller;

    Future<void> boot(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      controller = container.read(chatSidebarProvider.notifier);
    }

    ChatSidebarState readState() => container.read(chatSidebarProvider);

    test('无持久化数据时返回默认状态', () async {
      await boot({});

      expect(readState().activeFunction, ChatSidebarFunction.history);
      expect(readState().isExpanded, isTrue);
      expect(readState().panelWidth, 260.0);
    });

    test('一次恢复 activeFunction、展开状态与面板宽度', () async {
      await boot({
        'sidebar_activeFunction': 'preset',
        'sidebar_isExpanded': false,
        'sidebar_panelWidth': 300.0,
      });

      expect(readState().activeFunction, ChatSidebarFunction.preset);
      expect(readState().isExpanded, isFalse);
      expect(readState().panelWidth, 300.0);
    });

    test('无法识别的 function 值降级为 history', () async {
      await boot({'sidebar_activeFunction': 'nonexistent'});
      expect(readState().activeFunction, ChatSidebarFunction.history);
    });

    test('恢复时把 panelWidth 夹取到上下限', () async {
      for (final entry in const [
        MapEntry(500.0, 400.0),
        MapEntry(100.0, 180.0),
      ]) {
        await boot({'sidebar_panelWidth': entry.key});
        expect(readState().panelWidth, entry.value);
      }
    });

    test('toggleFunction 区分当前项折叠与新项切换展开', () async {
      await boot({});

      controller.toggleFunction(ChatSidebarFunction.history);
      expect(readState().activeFunction, ChatSidebarFunction.history);
      expect(readState().isExpanded, isFalse);

      controller.toggleFunction(ChatSidebarFunction.preset);
      expect(readState().activeFunction, ChatSidebarFunction.preset);
      expect(readState().isExpanded, isTrue);
    });

    test('collapse 折叠后再次调用保持幂等', () async {
      await boot({});

      controller.collapse();
      expect(readState().isExpanded, isFalse);
      controller.collapse();
      expect(readState().isExpanded, isFalse);
    });

    test('setPanelWidth 更新正常值并夹取上下限', () async {
      await boot({});

      for (final entry in const [
        MapEntry(350.0, 350.0),
        MapEntry(999.0, 400.0),
        MapEntry(50.0, 180.0),
      ]) {
        controller.setPanelWidth(entry.key);
        expect(readState().panelWidth, entry.value);
      }
    });

    test('setPanelWidth 忽略小于 0.5 的抖动', () async {
      await boot({});

      controller.setPanelWidth(260.3);
      expect(readState().panelWidth, 260.0);
      controller.setPanelWidth(260.6);
      expect(readState().panelWidth, 260.6);
    });

    test('操作后的完整状态可由新容器恢复', () async {
      await boot({});
      controller.toggleFunction(ChatSidebarFunction.preset);
      controller.collapse();
      controller.setPanelWidth(350.0);

      final revived = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(revived.dispose);

      final restored = revived.read(chatSidebarProvider);
      expect(restored.activeFunction, ChatSidebarFunction.preset);
      expect(restored.isExpanded, isFalse);
      expect(restored.panelWidth, 350.0);
    });
  });
}
