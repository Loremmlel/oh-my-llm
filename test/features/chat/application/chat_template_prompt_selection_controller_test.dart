import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_template_prompt_selection_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('ChatTemplatePromptSelectionController', () {
    test('build 初始值为 null', () {
      expect(container.read(chatTemplatePromptSelectionProvider), isNull);
    });

    test('select 写入非 null 模板 ID', () {
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');
      expect(container.read(chatTemplatePromptSelectionProvider), 'tpl-a');
    });

    test('select(null) 显式清除选择', () {
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');
      container.read(chatTemplatePromptSelectionProvider.notifier).select(null);
      expect(container.read(chatTemplatePromptSelectionProvider), isNull);
    });

    test('select 写入与当前相同的值时不触发状态变更', () {
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');

      var changeCount = 0;
      container.listen(
        chatTemplatePromptSelectionProvider,
        (_, _) => changeCount += 1,
        fireImmediately: false,
      );

      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');
      expect(changeCount, 0);
    });

    test('clear 将非 null 选择置空', () {
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');
      container.read(chatTemplatePromptSelectionProvider.notifier).clear();
      expect(container.read(chatTemplatePromptSelectionProvider), isNull);
    });

    test('clear 在已为 null 时不触发状态变更', () {
      var changeCount = 0;
      container.listen(
        chatTemplatePromptSelectionProvider,
        (_, _) => changeCount += 1,
        fireImmediately: false,
      );

      container.read(chatTemplatePromptSelectionProvider.notifier).clear();
      expect(changeCount, 0);
    });

    test('切换会话场景：clear 后再 select 下一会话的模板', () {
      // 模拟 ChatScreen 在 activeConversationId 变化时调用 clear。
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-a');
      container.read(chatTemplatePromptSelectionProvider.notifier).clear();
      expect(container.read(chatTemplatePromptSelectionProvider), isNull);

      // 新会话选择新模板。
      container
          .read(chatTemplatePromptSelectionProvider.notifier)
          .select('tpl-b');
      expect(container.read(chatTemplatePromptSelectionProvider), 'tpl-b');
    });
  });
}
