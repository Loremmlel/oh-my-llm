import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/workspace/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/chat_composer_card.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/workspace/chat_workspace_bindings.dart';

ChatWorkspaceComposerState _composerState({
  double? cacheHitRate,
  bool isCollapsed = false,
}) => ChatWorkspaceComposerState(
  modelProviders: [],
  modelConfigs: [],
  selectedProviderId: null,
  selectedModel: null,
  templatePrompts: [],
  selectedTemplatePrompt: null,
  fixedPromptSequences: [],
  isComposerCollapsed: isCollapsed,
  reasoningEnabled: false,
  reasoningEffort: ReasoningEffort.low,
  supportsReasoning: false,
  autoRetryEnabled: false,
  isBusy: false,
  isStreaming: false,
  isAutoRetryWaiting: false,
  excludedMessageCount: 0,
  cacheHitRate: cacheHitRate,
  isEditingMessage: false,
);

ChatWorkspaceComposerBindings _bindings({
  required TextEditingController controller,
  required FocusNode focusNode,
}) => ChatWorkspaceComposerBindings(
  messageController: controller,
  messageFocusNode: focusNode,
  templateVariableControllers: const {},
  onProviderSelected: (_) {},
  onModelSelected: (_) {},
  onTemplatePromptSelected: (_) {},
  onToggleComposerCollapsed: () {},
  onOpenFixedPromptSequenceRunner: () async {},
  onOpenMessageFilter: () async {},
);

/// 以指定 formActions 父约束宽度挂载 composer。
///
/// Card 默认 4px 四周 margin 会把传给内部 LayoutBuilder 的最大宽度再收窄 8px，
/// 因此外层 SizedBox 宽度按 `constraintWidth + 8` 补回，让 `useCompactFormActions`
/// 收到与 [constraintWidth] 完全一致的父约束，断点判定不受卡片留白干扰。
Future<void> _pumpComposer(
  WidgetTester tester,
  double constraintWidth, {
  required ChatWorkspaceComposerState state,
  required ChatWorkspaceComposerBindings bindings,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // ChatComposerCard 已是 ConsumerWidget（消费模板编译 provider），
  // 直接挂载需包一层 ProviderScope；本测试不选模板，无需任何 override。
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: constraintWidth + 8,
              child: ChatComposerCard(state: state, bindings: bindings),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [679.0, 680.0]) {
    testWidgets('$width: 操作行分支正确切换', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await _pumpComposer(
        tester,
        width,
        state: _composerState(),
        bindings: _bindings(controller: controller, focusNode: focusNode),
      );

      if (width < 680) {
        // 679：紧凑分支，摘要以「更多设置」开头。
        expect(find.textContaining('更多设置'), findsOneWidget);
      } else {
        // 680：等号进入完整操作行。
        expect(find.text('固定顺序提示词'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('展开时显示一位小数命中率，无样本时显示暂无数据', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final bindings = _bindings(controller: controller, focusNode: focusNode);

    for (final width in [360.0, 680.0]) {
      await _pumpComposer(
        tester,
        width,
        state: _composerState(cacheHitRate: 0.375),
        bindings: bindings,
      );
      expect(find.text('当前会话缓存命中率：37.5%'), findsOneWidget, reason: '$width');
      expect(tester.takeException(), isNull, reason: '$width');
    }

    await _pumpComposer(
      tester,
      680,
      state: _composerState(),
      bindings: bindings,
    );
    expect(find.text('当前会话缓存命中率：暂无数据'), findsOneWidget);
  });

  testWidgets('收起输入区时隐藏会话命中率', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await _pumpComposer(
      tester,
      680,
      state: _composerState(cacheHitRate: 0.375, isCollapsed: true),
      bindings: _bindings(controller: controller, focusNode: focusNode),
    );

    expect(find.textContaining('当前会话缓存命中率'), findsNothing);
  });
}
