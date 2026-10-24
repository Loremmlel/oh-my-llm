import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_llm/core/llm/llm_reasoning_effort.dart';
import 'package:oh_my_llm/core/llm/llm_usage.dart';
import 'package:oh_my_llm/core/llm/llm_usage_summary.dart';
import 'package:oh_my_llm/features/chat/application/workspace/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/chat_composer_card.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/composer_helpers.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/controls/thinking_toggle.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/composer/controls/composer_send_button.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/workspace/chat_workspace_bindings.dart';
import 'package:oh_my_llm/features/settings/domain/models/prompts/template_prompt.dart';

ChatWorkspaceComposerState _composerState({
  double? cacheHitRate,
  bool isCollapsed = false,
  bool supportsReasoning = false,
}) => ChatWorkspaceComposerState(
  readModel: ChatWorkspaceComposerReadModel(
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
    supportsReasoning: supportsReasoning,
    autoRetryEnabled: false,
    isBusy: false,
    isStreaming: false,
    isAutoRetryWaiting: false,
    excludedMessageCount: 0,
    usageSummary: LlmUsageSummary(
      tokens: cacheHitRate == null
          ? const LlmUsage()
          : const LlmUsage(
              inputTokens: 800,
              cachedInputTokens: 300,
              outputTokens: 200,
            ),
      cacheHitRate: cacheHitRate,
    ),
  ),
  selectedTemplatePrompt: null,
  isEditingMessage: false,
);

ChatWorkspaceComposerBindings _bindings({
  required TextEditingController controller,
  required FocusNode focusNode,
  Future<void> Function()? onOpenMessageFilter,
  VoidCallback? onToggleComposerCollapsed,
}) => ChatWorkspaceComposerBindings(
  messageController: controller,
  messageFocusNode: focusNode,
  templateVariableControllers: const {},
  onProviderSelected: (_) {},
  onModelSelected: (_) {},
  onTemplatePromptSelected: (_) {},
  onToggleComposerCollapsed: onToggleComposerCollapsed ?? () {},
  onOpenFixedPromptSequenceRunner: () async {},
  onOpenMessageFilter: onOpenMessageFilter ?? () async {},
);

/// 以指定 formActions 父约束宽度挂载 composer。
///
/// 断点由输入工作区的父约束决定，不受内部边框和留白影响。
Future<void> _pumpComposer(
  WidgetTester tester,
  double constraintWidth, {
  required ChatWorkspaceComposerState state,
  required ChatWorkspaceComposerBindings bindings,
  Size viewport = const Size(1000, 900),
  double textScale = 1,
  double keyboardHeight = 0,
}) async {
  tester.view.physicalSize = viewport;
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: Scaffold(
          // 本测试验证浮层避让键盘，底层输入区保留独立的布局约束。
          resizeToAvoidBottomInset: false,
          body: Center(
            child: SizedBox(
              width: constraintWidth,
              child: ChatComposerCard(state: state, bindings: bindings),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('校验阻止发送时禁用按钮，但运行中的停止仍然可用', (tester) async {
    var stopped = false;
    Future<void> pumpButton({required bool streaming}) => tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ComposerSendButton(
              theme: Theme.of(context),
              isBusy: streaming,
              isStreaming: streaming,
              isAutoRetryWaiting: false,
              hasModels: true,
              onSendPressed: null,
              onStopStreaming: () async {
                stopped = true;
              },
            ),
          ),
        ),
      ),
    );
    await pumpButton(streaming: false);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('发送'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await pumpButton(streaming: true);
    await tester.tap(find.byTooltip('终止回答'));
    expect(stopped, isTrue);
  });

  testWidgets('窄屏大字号展开思考后仍可打开上下文过滤', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var filterOpened = false;
    await _pumpComposer(
      tester,
      312,
      viewport: const Size(320, 640),
      textScale: 1.5,
      keyboardHeight: 240,
      state: _composerState(supportsReasoning: true),
      bindings: _bindings(
        controller: controller,
        focusNode: focusNode,
        onOpenMessageFilter: () async {
          filterOpened = true;
        },
      ),
    );
    await tester.tap(find.byTooltip('更多设置 · 思考关 · 重试关'));
    await tester.pumpAndSettle();
    expect(find.text('思考强度'), findsNothing);
    await tester.tap(find.widgetWithText(ThinkingToggle, '深度思考').last);
    await tester.pump();
    expect(find.text('思考强度'), findsOneWidget);
    expect(find.text(effortLabel(ReasoningEffort.low)), findsOneWidget);
    expect(tester.takeException(), isNull);
    final filter = find.widgetWithText(ListTile, '上下文过滤');
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(filterOpened, isTrue);
  });

  for (final width in [679.0, 680.0]) {
    testWidgets('$width: 操作行分支正确切换', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      var collapsed = false;
      await _pumpComposer(
        tester,
        width,
        state: _composerState(),
        bindings: _bindings(
          controller: controller,
          focusNode: focusNode,
          onToggleComposerCollapsed: () {
            collapsed = true;
          },
        ),
      );

      if (width < 680) {
        // 679：紧凑分支，摘要以「更多设置」开头。
        expect(find.byTooltip('更多设置 · 思考关 · 重试关'), findsOneWidget);
      } else {
        // 680：等号进入完整操作行。
        expect(find.text('固定顺序提示词'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('收起输入区'));
      expect(collapsed, isTrue);
    });
  }

  testWidgets('工具栏总 Token 打开包含分项和缓存命中率的详情', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final bindings = _bindings(controller: controller, focusNode: focusNode);

    await _pumpComposer(
      tester,
      680,
      state: _composerState(cacheHitRate: 0.375),
      bindings: bindings,
    );
    await tester.tap(find.text('总 Token 1,000'));
    await tester.pump();
    expect(find.textContaining('输入未缓存：500'), findsOneWidget);
    expect(find.textContaining('输入缓存命中：300'), findsOneWidget);
    expect(find.textContaining('输出：200'), findsOneWidget);
    expect(find.textContaining('缓存命中率：37.5%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收起输入区时隐藏会话总 Token', (tester) async {
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

    expect(find.textContaining('总 Token').hitTestable(), findsNothing);
  });

  testWidgets('启用模板提示词时收起输入区按钮固定在右上角', (tester) async {
    final controller = TextEditingController();
    final variableController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(variableController.dispose);
    addTearDown(focusNode.dispose);

    final template = TemplatePrompt(
      id: 'tpl-1',
      title: '翻译模板',
      content: '把{{正文}}翻译成{{目标语言}}',
      variables: const [
        TemplatePromptVariable(name: '正文'),
        TemplatePromptVariable(name: '目标语言'),
      ],
      updatedAt: DateTime(2026),
    );
    final baseState = _composerState();
    await _pumpComposer(
      tester,
      680,
      state: ChatWorkspaceComposerState(
        readModel: ChatWorkspaceComposerReadModel(
          modelProviders: baseState.readModel.modelProviders,
          modelConfigs: baseState.readModel.modelConfigs,
          selectedProviderId: baseState.readModel.selectedProviderId,
          selectedModel: baseState.readModel.selectedModel,
          templatePrompts: [template],
          selectedTemplatePrompt: template,
          fixedPromptSequences: baseState.readModel.fixedPromptSequences,
          isComposerCollapsed: false,
          reasoningEnabled: false,
          reasoningEffort: ReasoningEffort.low,
          supportsReasoning: false,
          autoRetryEnabled: false,
          isBusy: false,
          isStreaming: false,
          isAutoRetryWaiting: false,
          excludedMessageCount: 0,
          usageSummary: baseState.readModel.usageSummary,
        ),
        selectedTemplatePrompt: template,
        isEditingMessage: false,
      ),
      bindings: ChatWorkspaceComposerBindings(
        messageController: controller,
        messageFocusNode: focusNode,
        templateVariableControllers: {'目标语言': variableController},
        onProviderSelected: (_) {},
        onModelSelected: (_) {},
        onTemplatePromptSelected: (_) {},
        onToggleComposerCollapsed: () {},
        onOpenFixedPromptSequenceRunner: () async {},
        onOpenMessageFilter: () async {},
      ),
    );

    final collapseTopRight = tester.getTopRight(find.byTooltip('收起输入区'));
    final variableTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('template-variable-目标语言')),
    );
    final messageTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('chat-message-composer')),
    );

    expect(collapseTopRight.dy, lessThanOrEqualTo(variableTopLeft.dy));
    expect(collapseTopRight.dy, lessThan(messageTopLeft.dy));
    expect(collapseTopRight.dx, greaterThan(variableTopLeft.dx));
  });
}
