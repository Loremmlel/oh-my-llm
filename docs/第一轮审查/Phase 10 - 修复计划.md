# Phase 10 修复计划：跨模板变量串写回归与测试覆盖补齐

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal：** 修复 Phase 10 实现审查发现的 1 个高严重度回归（同名模板变量跨模板切换时输入串写、发送被静默替换为默认值），补齐 4 个中等级别的计划完成度缺口（view-state 契约测试、preset resolver 迁移、测试粒度拆分、composer command 契约测试），并纳入 3 个低级别易修项（draft 防御复制、死代码清理、编辑瞬态残留清理）。

**Architecture：** 核心 bug 的根因是「`_templateVariableControllers` 按变量名作 key + listener 闭包捕获创建时的 templateId + 发送值改从 draft 读取」三者叠加。修复采用**重绑 listener** 方案：controller 对象与 key 约定全部不变（组件层零波及），模板切换时解绑旧 listener 并绑定当前 templateId，用「变量名 → 当前 templateId」记录避免每 build 重复重绑。测试补齐沿既有 case-file decomposition 与容器测试模式。

**Tech Stack：** Flutter、Dart 3、Riverpod 3.4.2、flutter_test（widget + ProviderContainer 纯容器）、现有 `FakeChatCompletionClient` / `pumpChatScreen` helper、`TestFixtures`。

## Global Constraints

- 提交前对本次改动 Dart 文件执行 `dart format`；暂存后 `dart format --output=none --set-exit-if-changed <staged>` 非零不得提交。
- 测试必须用重定向模式：`flutter test <file> --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log`，要求 `EXIT=0`。
- 提交在 Bash 执行，第一行用 conventional message（`fix:` / `refactor:` / `test:`），多行用多个 `-m`；post-commit hook 自动 bump 版本，不手工改 `pubspec.yaml`。
- 注释简体中文；不出现「Phase 9」「P1-2」「第一轮审查」等审查编号引用（`ChatGenerationPhase` 枚举等既有符号除外）。
- 新 widget 测试 Setup 用 `pump()`，仅动画/对话框等待用 `pumpAndSettle`；禁止 `find.byKey` 断言内部实现 key（既有 production test-key 可继续用）；一个测试只验证一个交互场景；线性操作 >30 行应拆分。
- 本修复不触碰：generation lifecycle、消息树规则、SQLite schema、路由、断点、Favorites concrete feature。

---

### Task 1：修复同名模板变量跨模板切换串写（H1，回归 bug）

**Files:**
- Modify: `lib/features/chat/presentation/chat_screen.dart`（`_syncTemplateVariableControllers` 561-625、`_updateEditingTemplateVariable` 666-685）
- Test: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`

**Interfaces:**
- Consumes: `_templateVariableControllers`（`Map<String, TextEditingController>`，key 为变量名）、`_isApplyingComposerDraft`、`_editingMessageId`、`_activeConversationIdOrNull`、`composerDraftProvider`
- Produces: 新增页面私有方法 `_bindTemplateVariableListener(String templateId, String variableName, TextEditingController controller)` 与 `_onTemplateVariableChanged(...)`；新增 State 字段 `_templateVariableTemplateIds` / `_templateVariableListeners`（均 `Map<String, ...>`）

- [ ] **Step 1：写红灯 widget 测试**

在 `chat_screen_workspace_ownership_cases.dart` 末尾（`registerChatScreenWorkspaceOwnershipTests` 内、最后一个 `});` 之前）追加：

```dart
testWidgets('同名模板变量跨模板切换：输入写入当前模板，发送不回落默认值', (tester) async {
  final fakeClient = FakeChatCompletionClient()..enqueueChunks(['模板二回复']);
  await pumpChatScreen(tester, fakeClient: fakeClient);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ChatScreen)),
  );
  final convId = container.read(chatSessionsProvider).activeConversation.id;

  // 两个模板各有同名变量 title，默认值不同，便于区分「用户输入」与「默认值」。
  await container.read(templatePromptsProvider.notifier).upsert(
    TemplatePrompt(
      id: 'tp-1',
      title: '模板一',
      content: '一：{{title}}。',
      variables: const [
        TemplatePromptVariable(name: 'title', defaultValue: '默认一'),
      ],
      updatedAt: DateTime(2026, 5, 5, 0, 1),
    ),
  );
  await container.read(templatePromptsProvider.notifier).upsert(
    TemplatePrompt(
      id: 'tp-2',
      title: '模板二',
      content: '二：{{title}}。',
      variables: const [
        TemplatePromptVariable(name: 'title', defaultValue: '默认二'),
      ],
      updatedAt: DateTime(2026, 5, 5, 0, 2),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 250));

  final titleField = find.byKey(const ValueKey('template-variable-title'));

  // 模板一：输入 '甲'。
  await _selectTemplate(tester, '模板一');
  await tester.pump();
  await tester.enterText(titleField, '甲');
  await tester.pump();

  // 切模板二：字段回落到模板二默认值（既有语义），随后输入 '乙'。
  await _selectTemplate(tester, '模板二');
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
  expect(tester.widget<TextField>(titleField).controller!.text, '默认二');
  await tester.enterText(titleField, '乙');
  await tester.pump();

  // 发送：请求内容必须包含用户输入的 '乙'，而不是回落 '默认二'。
  await tester.enterText(_composerFinder, '正文');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '发送'));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));

  final sent = fakeClient.requestHistory.single;
  expect(sent.content, contains('乙'));
  expect(sent.content, isNot(contains('默认二')));
  // draft 变量写入当前模板 tp-2 名下（修复前会错误写入 tp-1）。
  expect(
    container
        .read(composerDraftProvider.notifier)
        .draftFor(convId)
        .templateVariableValuesByTemplateId['tp-2']?['title'],
    '乙',
  );
});
```

若该用例中 `_selectTemplate` 需要先点开下拉再选中（既有 helper 语义），沿用既有用例的调用方式，不要改 helper。

- [ ] **Step 2：运行该用例，确认红灯**

```bash
flutter test test/features/chat/chat_screen_test.dart --plain-name "同名模板变量跨模板切换" --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 60 fltest.log
```

预期：FAIL——发出的 content 为 `二：默认二。`（或含 `默认二`），`tp-2` 名下无值。

- [ ] **Step 3：实现修复（重绑 listener）**

在 `_ChatScreenState` 中新增两个字段（放在 `_templateVariableControllers` 声明旁）：

```dart
/// 模板变量字段当前绑定的模板 ID（变量名 -> templateId），用于判断是否需要重绑。
final Map<String, String> _templateVariableTemplateIds = {};

/// 模板变量字段当前的 listener（变量名 -> listener），重绑前先解绑旧的。
final Map<String, VoidCallback> _templateVariableListeners = {};
```

将 `_syncTemplateVariableControllers` 内的 controller 创建与复用分支改为统一走 `_bindTemplateVariableListener`：

```dart
    for (final variable in template.inputVariables) {
      final templateId = template.id;
      // 已存在也必须按当前会话 draft 重赋值，不能因 key 存在直接 continue，
      // 否则同名模板变量会跨会话泄漏。
      final savedValue = conversationId == null
          ? null
          : draft.templateVariableValuesByTemplateId[templateId]?[variable
                .name];
      final existing = _templateVariableControllers[variable.name];
      if (existing == null) {
        final controller = TextEditingController(
          text: savedValue ?? variable.defaultValue,
        );
        _bindTemplateVariableListener(
          templateId,
          variable.name,
          controller,
        );
        _templateVariableControllers[variable.name] = controller;
      } else {
        // 目标会话没有该变量草稿值时必须回落到模板默认值，不能只覆盖「有值」的情况，
        // 否则 B 选了同名模板但未输入时，字段会残留 A 会话上一次的值（跨会话泄漏）。
        final targetValue = savedValue ?? variable.defaultValue;
        if (existing.text != targetValue) {
          _isApplyingComposerDraft = true;
          existing.text = targetValue;
          _isApplyingComposerDraft = false;
        }
        // 同名变量可能来自不同模板：模板切换后必须重绑 listener 捕获当前
        // templateId，否则输入仍写进旧模板名下、发送时被静默替换为默认值。
        _bindTemplateVariableListener(
          templateId,
          variable.name,
          existing,
        );
      }
    }
```

注意 `removedNames` 清理循环也要同步清两个新 map（否则变量名再次出现时 `_templateVariableTemplateIds` 残留旧值会导致**新 controller 跳过绑定**，输入完全不写 draft）：

```dart
    for (final name in removedNames) {
      _templateVariableControllers.remove(name)?.dispose();
      _templateVariableListeners.remove(name);
      _templateVariableTemplateIds.remove(name);
    }
```

新增两个方法（放在 `_syncTemplateVariableControllers` 之后）：

```dart
  /// 绑定/重绑模板变量字段的 listener：同一变量名切到新模板时先解绑旧
  /// listener 再绑定当前 templateId，避免输入写进错误模板名下。
  void _bindTemplateVariableListener(
    String templateId,
    String variableName,
    TextEditingController controller,
  ) {
    if (_templateVariableTemplateIds[variableName] == templateId) return;
    final previous = _templateVariableListeners[variableName];
    if (previous != null) {
      controller.removeListener(previous);
    }
    final listener = () => _onTemplateVariableChanged(
      templateId,
      variableName,
      controller,
    );
    controller.addListener(listener);
    _templateVariableListeners[variableName] = listener;
    _templateVariableTemplateIds[variableName] = templateId;
  }

  /// 模板变量输入的统一入口：编辑中写页面本地草稿，否则写会话级 draft。
  void _onTemplateVariableChanged(
    String templateId,
    String variableName,
    TextEditingController controller,
  ) {
    if (_isApplyingComposerDraft) return;
    if (_editingMessageId != null) {
      _updateEditingTemplateVariable(
        templateId,
        variableName,
        controller.text,
      );
      return;
    }
    final cid = _activeConversationIdOrNull();
    if (cid == null) return;
    ref
        .read(composerDraftProvider.notifier)
        .setTemplateVariable(cid, templateId, variableName, controller.text);
  }
```

`_updateEditingTemplateVariable` 与 `_resolveTemplatePromptValues` 不需要改（listener 现在传入正确的 templateId）。

- [ ] **Step 4：运行该用例，确认绿灯**

```bash
flutter test test/features/chat/chat_screen_test.dart --plain-name "同名模板变量跨模板切换" --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 60 fltest.log
```

预期：PASS。

- [ ] **Step 5：回归 chat_screen 全量 widget 测试**

```bash
flutter test test/features/chat/chat_screen_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`（含既有「跨会话同名模板变量」用例，确认无回归）。

- [ ] **Step 6：格式化并提交**

```bash
dart format lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git add lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
dart format --output=none --set-exit-if-changed lib/features/chat/presentation/chat_screen.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git commit -m "fix(chat): 修复同名模板变量跨模板切换时输入串写" -m "模板变量字段按变量名复用 controller，listener 捕获创建时的模板 ID；切换模板后输入仍写入旧模板名下，发送时从当前模板读取为空而回落默认值。切换模板时重绑 listener 绑定当前模板 ID。"
```

---

### Task 2：preset 解析迁入 application 纯函数，删除页面重复 resolver（M2）

**Files:**
- Modify: `lib/features/chat/application/chat_workspace_view_state.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Test: `test/features/chat/application/chat_workspace_view_state_test.dart`

**Interfaces:**
- Consumes: `PresetPrompt` / `noPresetPromptSelectedId`（`package:oh_my_llm/features/settings/domain/models/preset_prompt.dart`，已被 barrel 导出）
- Produces: `TemplatePrompt? resolveSelectedPresetPrompt(List<PresetPrompt> presetPrompts, String? selectedPresetPromptId)`——纯函数，null / sentinel（`noPresetPromptSelectedId`）/ missing ID 返回 null，valid 返回匹配项；Screen 经 `widgets.dart` barrel 直接使用（无需新 import）

- [ ] **Step 1：写四分支红灯测试**

在 `chat_workspace_view_state_test.dart` 追加（import 增加 `preset_prompt.dart`）：

```dart
  group('resolveSelectedPresetPrompt', () {
    test('null 选择返回 null', () {
      expect(resolveSelectedPresetPrompt(const [], null), isNull);
    });

    test('sentinel（noPresetPromptSelectedId）返回 null', () {
      expect(
        resolveSelectedPresetPrompt(const [], noPresetPromptSelectedId),
        isNull,
      );
    });

    test('命中返回对应预设', () {
      final prompt = TestFixtures.presetPrompt();
      expect(
        resolveSelectedPresetPrompt([prompt], prompt.id),
        same(prompt),
      );
    });

    test('选择不存在时返回 null', () {
      expect(
        resolveSelectedPresetPrompt(
          [TestFixtures.presetPrompt()],
          'preset-missing',
        ),
        isNull,
      );
    });
  });
```

若 `TestFixtures` 无 `presetPrompt()` 工厂，改用真实构造（`PresetPrompt(id: ..., title: ..., content: ..., updatedAt: ...)`，字段以 domain 模型为准）。

- [ ] **Step 2：实现纯函数**

在 `chat_workspace_view_state.dart` 的「纯 resolver」小节（`resolveSelectedTemplatePrompt` 之后）追加：

```dart
/// 预设 Prompt 解析：null / sentinel / ID 无效均视为未选。
PresetPrompt? resolveSelectedPresetPrompt(
  List<PresetPrompt> presetPrompts,
  String? selectedPresetPromptId,
) {
  if (selectedPresetPromptId == null ||
      selectedPresetPromptId == noPresetPromptSelectedId) {
    return null;
  }
  return presetPrompts
      .where((prompt) => prompt.id == selectedPresetPromptId)
      .firstOrNull;
}
```

文件顶部 import 增加 `package:oh_my_llm/features/settings/domain/models/preset_prompt.dart`。

- [ ] **Step 3：Screen 改用 application 纯函数**

`chat_screen.dart`：

1. 删除 `_resolveSelectedPresetPrompt`（538-547 行整方法）。
2. 两处调用点改为：

```dart
    final selectedPresetPrompt = resolveSelectedPresetPrompt(
      presetPrompts,
      conversation.selectedPresetPromptId,
    );
```

   （`_buildEndDrawer` / `_buildSidebarContent` 中 `PresetPromptPanel` 的 `selectedPresetPromptId` 直接读 conversation 字段，不动。）
3. 删除 `_resolveSelectedTemplatePrompt`（549-559 行整方法），两处调用点（`_applyDraftToControllers` 内、`_handleTemplatePromptSelected` 内）改用 application 的 `resolveSelectedTemplatePrompt`（经 barrel 已可用）：

```dart
    final template = resolveSelectedTemplatePrompt(
      ref.read(templatePromptsProvider),
      effectiveDraft.selectedTemplatePromptId,
    );
```

- [ ] **Step 4：跑 view-state 与 chat_screen 测试**

```bash
flutter test test/features/chat/application/chat_workspace_view_state_test.dart test/features/chat/chat_screen_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`。

- [ ] **Step 5：格式化并提交**

```bash
dart format lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/chat_workspace_view_state_test.dart
git add lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/chat_workspace_view_state_test.dart
dart format --output=none --set-exit-if-changed lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/chat_workspace_view_state_test.dart
git commit -m "refactor(chat): 预设 Prompt 解析迁入 workspace 纯函数" -m "删除页面私有 preset/template resolver，统一走 application 层公开纯函数，行为不变。"
```

---

### Task 3：补齐 workspace view-state 契约测试（M1）

**Files:**
- Test: `test/features/chat/application/chat_workspace_view_state_test.dart`

**Interfaces:**
- Consumes: `chatWorkspaceReadModelProvider`、`resolveSelectedPresetPrompt`（Task 2）、`ChatWorkspaceViewState.compose`；容器 overrides 模式沿用 `chat_composer_command_test.dart`（`appDatabaseProvider` / `sharedPreferencesProvider` / `chatCompletionClientProvider` / `chatConversationRepositoryProvider`）
- Produces: 无新生产代码；本 Task 是纯测试补覆盖

- [ ] **Step 1：写 compose overlay 与 immutability 测试**

compose 是纯构造（不依赖 Provider），直接在现有测试文件追加：

```dart
  group('ChatWorkspaceViewState.compose', () {
    ChatWorkspaceComposerReadModel composerReadModel({
      TemplatePrompt? selectedTemplatePrompt,
    }) {
      return ChatWorkspaceComposerReadModel(
        modelProviders: const [],
        modelConfigs: const [],
        selectedProviderId: null,
        selectedModel: null,
        templatePrompts: const [],
        selectedTemplatePrompt: selectedTemplatePrompt,
        fixedPromptSequences: const [],
        isComposerCollapsed: false,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
        supportsReasoning: false,
        autoRetryEnabled: false,
        isBusy: false,
        isStreaming: false,
        isAutoRetryWaiting: false,
        excludedMessageCount: 0,
      );
    }

    ChatWorkspaceReadModel readModel({
      TemplatePrompt? selectedTemplatePrompt,
    }) {
      return ChatWorkspaceReadModel(
        messages: ChatWorkspaceMessagesState(
          conversation: TestFixtures.conversation(),
          messages: const [],
          userMessages: const [],
          hasModels: false,
          isBusy: false,
          errorMessage: null,
          errorMessageAssistantId: null,
          emptyReplyAssistantId: null,
          errorModelDisplayName: '模型',
          autoRetryCount: 0,
          favoritedAssistantContents: const {},
        ),
        composer: composerReadModel(
          selectedTemplatePrompt: selectedTemplatePrompt,
        ),
      );
    }

    test('非编辑态使用 read-model 的 normal selection', () {
      final template = TestFixtures.templatePrompt(id: 'tp-1');
      final viewState = ChatWorkspaceViewState.compose(
        readModel: readModel(selectedTemplatePrompt: template),
        editingDraft: ComposerDraft.empty,
        isEditingMessage: false,
        templatePrompts: [template],
      );
      expect(viewState.composer.selectedTemplatePrompt, same(template));
      expect(viewState.composer.isEditingMessage, isFalse);
    });

    test('编辑态用 editingDraft 的选择覆盖；无模板编辑不回落 normal selection', () {
      final normalTemplate = TestFixtures.templatePrompt(id: 'tp-normal');
      final editingTemplate = TestFixtures.templatePrompt(id: 'tp-edit');
      final editingDraft = ComposerDraft(
        selectedTemplatePromptId: editingTemplate.id,
      );
      final viewState = ChatWorkspaceViewState.compose(
        readModel: readModel(selectedTemplatePrompt: normalTemplate),
        editingDraft: editingDraft,
        isEditingMessage: true,
        templatePrompts: [normalTemplate, editingTemplate],
      );
      expect(viewState.composer.selectedTemplatePrompt, same(editingTemplate));
      expect(viewState.composer.isEditingMessage, isTrue);
      expect(viewState.messages, same(readModel(selectedTemplatePrompt: normalTemplate).messages));

      // 编辑无模板消息：effective 为 null，不回落会话级 normal selection。
      final noTemplateEdit = ChatWorkspaceViewState.compose(
        readModel: readModel(selectedTemplatePrompt: normalTemplate),
        editingDraft: ComposerDraft.empty,
        isEditingMessage: true,
        templatePrompts: [normalTemplate],
      );
      expect(noTemplateEdit.composer.selectedTemplatePrompt, isNull);
    });

    test('编辑选择指向已删除模板时解析为 null', () {
      final viewState = ChatWorkspaceViewState.compose(
        readModel: readModel(),
        editingDraft: const ComposerDraft(selectedTemplatePromptId: 'tp-gone'),
        isEditingMessage: true,
        templatePrompts: const [],
      );
      expect(viewState.composer.selectedTemplatePrompt, isNull);
    });
  });
```

注意：`ChatWorkspaceMessagesState` 的构造参数名以 `chat_workspace_view_state.dart` 实际签名为准（`conversation/messages/userMessages/hasModels/isBusy/errorMessage/errorMessageAssistantId/emptyReplyAssistantId/errorModelDisplayName/autoRetryCount/favoritedAssistantContents`）；`TestFixtures.conversation()` 若不存在则用 `TestFixtures` 中实际会话工厂或手写最小 `ChatConversation`（字段以 domain 模型为准）。`ComposerDraft` 主构造器在 Task 6 之前仍是 const（本 Task 若 Task 6 已先行完成，则 `const ComposerDraft(...)` 用法去掉 const 即可）。

- [ ] **Step 2：写 provider 行为测试（reasoning / userMessages / excluded / immutability）**

在 `chat_workspace_view_state_test.dart` 新增 `main()` 中第二个 group（`setUp` 模式仿照 `chat_composer_command_test.dart`：`SharedPreferences.setMockInitialValues` + 内存 DB + `FakeChatCompletionClient` + `ControllableChatConversationRepository`，overrides 四个 Provider）：

```dart
  group('chatWorkspaceReadModelProvider', () {
    late AppDatabase database;
    late ControllableChatConversationRepository repository;
    late FakeChatCompletionClient fakeClient;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        llmModelConfigsStorageKey: VersionedJsonStorage.encodeObjectList(
          items: const [
            LlmProviderConfig(
              id: 'provider-1',
              name: 'Test Provider',
              apiUrl: 'https://api.example.com/v1/chat/completions',
              apiKey: 'sk-test',
              models: [
                LlmProviderModelConfig(
                  id: 'model-1',
                  displayName: 'Test Model',
                  modelName: 'test-model',
                  supportsReasoning: false,
                ),
              ],
            ),
          ],
          toJson: (provider) => provider.toJson(),
        ),
      });
      database = AppDatabase.inMemory();
      repository = ControllableChatConversationRepository(database);
      fakeClient = FakeChatCompletionClient();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          chatCompletionClientProvider.overrideWithValue(fakeClient),
          chatConversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });
    tearDown(() {
      container.dispose();
      database.close();
    });

    test('不支持 reasoning 的模型：effective enabled 为 false 且不改写 conversation flag', () async {
      final model = container.read(llmModelConfigsProvider).first;
      // 打开 conversation 的 reasoningEnabled（即使模型不支持）。
      await container.read(chatSessionsProvider.notifier)
          .updateActiveConversationPreferences(reasoningEnabled: true);

      final readModel = container.read(chatWorkspaceReadModelProvider);
      expect(readModel.composer.reasoningEnabled, isFalse);
      expect(readModel.composer.supportsReasoning, isFalse);
      expect(
        container.read(activeChatConversationProvider).reasoningEnabled,
        isTrue,
      );
    });

    test('userMessages 只含 user；excluded count 按可见消息计', () async {
      fakeClient.enqueueChunks(['回复']);
      await container.read(chatSessionsProvider.notifier).sendMessage(
        content: '问题',
        modelConfig: container.read(llmModelConfigsProvider).first,
        presetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
      );
      await container.read(chatSessionsProvider.notifier)
          .setMessagesExcluded(messageIds: ['消息id占位'], excluded: true);

      final readModel = container.read(chatWorkspaceReadModelProvider);
      expect(
        readModel.messages.userMessages.every(
          (m) => m.role == ChatMessageRole.user,
        ),
        isTrue,
      );
      // excluded count 与 conversation.isMessageExcluded 一致。
      final conversation = readModel.messages.conversation;
      final expectedExcluded = readModel.messages.messages
          .where((m) => conversation.isMessageExcluded(m.id))
          .length;
      expect(readModel.composer.excludedMessageCount, expectedExcluded);
    });

    test('read-model 的 messages / favoritedAssistantContents 不可外部修改', () {
      final readModel = container.read(chatWorkspaceReadModelProvider);
      expect(
        () => readModel.messages.messages.add(readModel.messages.messages.first),
        throwsUnsupportedError,
      );
      expect(
        () => readModel.messages.favoritedAssistantContents.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => readModel.composer.templatePrompts.add(
          readModel.composer.templatePrompts.first,
        ),
        throwsUnsupportedError,
      );
    });
  });
```

`setMessagesExcluded` 传真实存在的消息 id（发送后从 conversation.messages 取第一条的 id）；excluded 断言以「与 `isMessageExcluded` 一致」为准，不要硬编码数字。若 `FakeChatCompletionClient.enqueueChunks` 后 sendMessage 需要等微任务，`await container.read(...)` 的 Future 已包含。

- [ ] **Step 3：跑测试**

```bash
flutter test test/features/chat/application/chat_workspace_view_state_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`。

- [ ] **Step 4：格式化并提交**

```bash
dart format test/features/chat/application/chat_workspace_view_state_test.dart
git add test/features/chat/application/chat_workspace_view_state_test.dart
dart format --output=none --set-exit-if-changed test/features/chat/application/chat_workspace_view_state_test.dart
git commit -m "test(chat): 补 workspace view-state 契约测试" -m "覆盖 preset 四分支、compose 编辑 overlay、reasoning 不改写 flag、userMessages/excluded 投影与 read-model 不可变性。"
```

---

### Task 4：拆分「编辑带模板消息」双场景测试（M3）

**Files:**
- Test: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`

**Interfaces:**
- Consumes: `_selectTemplate` / `_tapEditMessage` / `_composerFinder` / `pumpChatScreen` / `sendMessage` helper（文件内既有）
- Produces: 两个独立 `testWidgets`，各验证一个场景

- [ ] **Step 1：拆分测试**

将 `chat_screen_workspace_ownership_cases.dart:272-386` 的单个 `testWidgets('编辑带模板消息变量随提交生效；编辑无模板消息不显示会话模板输入', ...)` 拆成两个独立测试，模板注册部分提取为文件内私有 helper：

```dart
/// 注册「变量模板」（tp-var，变量 title 默认值「默认标题」），返回容器。
Future<void> _seedVariableTemplate(WidgetTester tester, ProviderContainer container) async {
  await container.read(templatePromptsProvider.notifier).upsert(
    TemplatePrompt(
      id: 'tp-var',
      title: '变量模板',
      content: '请按{{title}}输出。',
      variables: const [
        TemplatePromptVariable(name: 'title', defaultValue: '默认标题'),
      ],
      updatedAt: DateTime(2026, 5, 5, 0, 1),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}
```

**测试一**（原路径 B，fakeClient 只留 2 个 chunk）：

```dart
  testWidgets('编辑无模板消息不显示会话模板变量输入，提交分支不带模板', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['普通回复'])
      ..enqueueChunks(['普通消息修改回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;
    await _seedVariableTemplate(tester, container);

    await sendMessage(tester, '普通消息');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    final plainMessageId = container
        .read(activeChatConversationProvider)
        .messages
        .lastWhere((m) => m.role == ChatMessageRole.user)
        .id;

    // 会话级 draft 选中模板；编辑无模板消息时不应显示变量输入框。
    await _selectTemplate(tester, '变量模板');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    await _tapEditMessage(tester, plainMessageId);
    expect(
      find.byKey(const ValueKey('template-variable-title')),
      findsNothing,
    );

    // 提交编辑：新分支不带模板，会话级模板选择保留。
    await tester.enterText(_composerFinder, '普通消息修改');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    final afterPlainEdit = container.read(activeChatConversationProvider);
    final plainBranch = afterPlainEdit.messageNodes.firstWhere((m) {
      return m.role == ChatMessageRole.user && m.content == '普通消息修改';
    });
    expect(plainBranch.templatePromptId, isNull);
    expect(plainBranch.templateVariableValues, isEmpty);
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(convId)
          .selectedTemplatePromptId,
      'tp-var',
    );
  });
```

**测试二**（原路径 A，fakeClient 只留 2 个 chunk：模板回复、编辑后模板回复）：

```dart
  testWidgets('编辑带模板消息：变量输入框携带已保存值，修改后提交新分支', (tester) async {
    final fakeClient = FakeChatCompletionClient()
      ..enqueueChunks(['模板回复'])
      ..enqueueChunks(['编辑后模板回复']);
    await pumpChatScreen(tester, fakeClient: fakeClient);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final convId = container.read(chatSessionsProvider).activeConversation.id;
    await _seedVariableTemplate(tester, container);

    // 发送带模板消息（变量 '甲'）。
    await _selectTemplate(tester, '变量模板');
    await tester.pump();
    await tester.enterText(_composerFinder, '模板问题');
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('template-variable-title')),
      '甲',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 编辑该消息：变量框携带 '甲'，改为 '乙' 后提交。
    final templatedMessageId = container
        .read(activeChatConversationProvider)
        .messages
        .lastWhere(
          (m) =>
              m.role == ChatMessageRole.user && m.templatePromptId == 'tp-var',
        )
        .id;
    await _tapEditMessage(tester, templatedMessageId);
    final titleField = find.byKey(const ValueKey('template-variable-title'));
    expect(tester.widget<TextField>(titleField).controller!.text, '甲');
    await tester.enterText(titleField, '乙');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    // 新分支携带 '乙' 与模板 id；会话级 draft 变量仍为 '甲'（编辑未污染）。
    final afterTemplatedEdit = container.read(activeChatConversationProvider);
    final templatedBranch = afterTemplatedEdit.messageNodes.firstWhere((m) {
      return m.role == ChatMessageRole.user &&
          m.templateVariableValues['title'] == '乙';
    });
    expect(templatedBranch.templatePromptId, 'tp-var');
    expect(templatedBranch.templateVariableValues['title'], '乙');
    expect(
      container
          .read(composerDraftProvider.notifier)
          .draftFor(convId)
          .templateVariableValuesByTemplateId['tp-var']?['title'],
      '甲',
    );
  });
```

若拆分后与既有用例（编辑取消/编辑切会话等）出现顺序或命名冲突，调整位置保持文件内测试组织清晰即可；不要改动其他用例。

- [ ] **Step 2：跑 chat_screen 全量测试**

```bash
flutter test test/features/chat/chat_screen_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`，用例总数 +1（一个变两个）。

- [ ] **Step 3：格式化并提交**

```bash
dart format test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git add test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
dart format --output=none --set-exit-if-changed test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git commit -m "test(chat): 拆分编辑模板双场景测试为独立用例" -m "一个测试一个交互场景，消除双场景合并与 114 行线性操作。"
```

---

### Task 5：补齐 composer command 契约测试（M4）

**Files:**
- Test: `test/features/chat/application/chat_composer_command_test.dart`

**Interfaces:**
- Consumes: `ChatComposerSubmitIntent` / `ChatDirectSubmitIntent` / `ChatComposerCommand`（`chat_composer_command.dart`）、`templatePromptsProvider`（`template_prompts_controller.dart`）、`composerTemplateSelectionProvider`
- Produces: 无新生产代码

- [ ] **Step 1：扩展 `intentFor` 支持模板参数，并修正「selection 保留」标题**

`intentFor` 增加可选参数：

```dart
  ChatComposerSubmitIntent intentFor(
    String body, {
    String? editingMessageId,
    String? conversationId,
    Object? selectedModel = _useDefaultModel,
    TemplatePrompt? templatePrompt,
    Map<String, String> variableValues = const {},
  }) {
    return ChatComposerSubmitIntent(
      conversationId:
          conversationId ?? container.read(activeConversationIdProvider),
      body: body,
      templatePrompt: templatePrompt,
      variableValues: variableValues,
      selectedModel: identical(selectedModel, _useDefaultModel)
          ? model()
          : selectedModel as LlmModelConfig?,
      reasoningEnabled: false,
      reasoningEffort: ReasoningEffort.medium,
      editingMessageId: editingMessageId,
    );
  }
```

（import 增加 `package:oh_my_llm/features/settings/domain/models/template_prompt.dart`。）

`normal accepted` 测试（119 行）补 selection 断言，让标题承诺成立：dispatch 前

```dart
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-1');
```

dispatch 后（draft body 断言之后）追加：

```dart
    expect(
      container.read(composerTemplateSelectionProvider(conversationId)),
      'tp-1',
    );
```

- [ ] **Step 2：写模板 dispatch 契约测试**

```dart
  test('templated dispatch：变量值随 intent 传入，draft 只清 body 保留模板选择', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    const template = TemplatePrompt(
      id: 'tp-1',
      title: '变量模板',
      content: '请按{{title}}输出。',
      variables: [
        TemplatePromptVariable(name: 'title', defaultValue: '默认标题'),
      ],
      updatedAt: null,
    );
    // 构造一个可 const 的模板（updatedAt 以实际模型字段为准，无法 const 时去掉 const）。
    container
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, 'tp-1');
    fakeClient.enqueueChunks(['回复']);

    final result = command.dispatch(
      intentFor('正文', templatePrompt: template, variableValues: {'title': '甲'}),
    );
    expect(result, isA<ChatComposerAccepted>());
    final accepted = result as ChatComposerAccepted;
    await accepted.completion;

    final sent = fakeClient.requestHistory.single;
    expect(sent.content, contains('甲'));
    expect(sent.content, isNot(contains('默认标题')));
    // accepted 后：body 清空、模板选择保留。
    final draft = container
        .read(composerDraftProvider.notifier)
        .draftFor(conversationId);
    expect(draft.body, '');
    expect(draft.selectedTemplatePromptId, 'tp-1');
  });
```

若 `TemplatePrompt` 的 `updatedAt` 非空/非 const 可构造，改为 `final template = TemplatePrompt(id: 'tp-1', ...)` 非 const 形式。

- [ ] **Step 3：写 dispatchDirect 与 toolbar 方法测试**

```dart
  test('dispatchDirect 直接发送步骤文本，不消费 composer draft', () async {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);
    container.read(composerDraftProvider.notifier).setBody(conversationId, '普通草稿');
    fakeClient.enqueueChunks(['步骤回复']);

    await command.dispatchDirect(
      ChatDirectSubmitIntent(
        conversationId: conversationId,
        content: '步骤内容',
        selectedModel: model(),
        selectedPresetPrompt: null,
        reasoningEnabled: false,
        reasoningEffort: ReasoningEffort.medium,
      ),
    );

    expect(fakeClient.requestHistory.single.content, '步骤内容');
    // 普通草稿完整保留，不被消费。
    expect(
      container.read(composerDraftProvider.notifier).draftFor(conversationId).body,
      '普通草稿',
    );
  });

  test('selectTemplate 只写目标会话 draft；setReasoning/AutoRetry 更新 conversation', () {
    final command = container.read(chatComposerCommandProvider);
    final conversationId = container.read(activeConversationIdProvider);

    command.selectTemplate(conversationId, 'tp-1');
    expect(
      container.read(composerTemplateSelectionProvider(conversationId)),
      'tp-1',
    );
    // 其他会话不受影响。
    expect(
      container.read(composerTemplateSelectionProvider('other-conv')),
      isNull,
    );

    command.setReasoningEnabled(true);
    command.setReasoningEffort(ReasoningEffort.high);
    command.setAutoRetryEnabled(true);
    final conversation = container.read(activeChatConversationProvider);
    expect(conversation.reasoningEnabled, isTrue);
    expect(conversation.reasoningEffort, ReasoningEffort.high);
    expect(conversation.autoRetryEnabled, isTrue);
  });
```

`selectTemplate` 后 `composerTemplateSelectionProvider` 的 watch 是即时的（`Provider.family`），容器读立即生效。

- [ ] **Step 4：跑 composer command 测试**

```bash
flutter test test/features/chat/application/chat_composer_command_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`（原 6 个 + 新增 4 个）。

- [ ] **Step 5：格式化并提交**

```bash
dart format test/features/chat/application/chat_composer_command_test.dart
git add test/features/chat/application/chat_composer_command_test.dart
dart format --output=none --set-exit-if-changed test/features/chat/application/chat_composer_command_test.dart
git commit -m "test(chat): 补 composer command 模板与工具栏契约测试" -m "覆盖 templated dispatch 变量传递、dispatchDirect 不消费草稿、selectTemplate 会话隔离与 reasoning/auto-retry 更新；normal accepted 用例补齐 selection 保留断言。"
```

---

### Task 6：draft 防御复制、死代码清理与编辑瞬态残留清理（L1/L2/低）

**Files:**
- Modify: `lib/features/chat/application/composer_draft_controller.dart`
- Modify: `lib/features/chat/application/chat_workspace_view_state.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Test: `test/features/chat/application/composer_draft_controller_test.dart`

**Interfaces:**
- Consumes: `ComposerDraft.copyWith`（已有 `_deepCopy`）
- Produces: `ComposerDraft.replaceDraft` 内部深拷贝；删除 `ChatWorkspaceComposerReadModel.copyWith`

- [ ] **Step 1：写 replaceDraft 防御复制红灯测试**

在 `composer_draft_controller_test.dart` 追加：

```dart
  test('replaceDraft 存入 state 后，外部对原 draft 内层 map 的修改不可见', () {
    final notifier = container.read(composerDraftProvider.notifier);
    final mutableInner = <String, String>{'title': '甲'};
    final draft = ComposerDraft(
      body: '正文',
      templateVariableValuesByTemplateId: {'tp-1': mutableInner},
    );
    notifier.replaceDraft('conv-a', draft);

    // 修改外部 map：state 内的 draft 不得受影响。
    mutableInner['title'] = '乙';
    final stored = notifier.draftFor('conv-a');
    expect(
      stored.templateVariableValuesByTemplateId['tp-1']?['title'],
      '甲',
    );
    // 且 state 内的内层 map 不可变。
    expect(
      () => stored.templateVariableValuesByTemplateId['tp-1']!['title'] = '丙',
      throwsUnsupportedError,
    );
  });
```

（测试文件若已有容器化 `setUp` 则复用；若为纯 controller 测试需先建 `ProviderContainer`。）

- [ ] **Step 2：实现防御复制与清理**

1. `composer_draft_controller.dart` 的 `replaceDraft`：存入前深拷贝，并更新类注释说明「进入 state 的唯一直接入口，内部防御复制」：

```dart
  /// 整体替换草稿（仅恢复/提交事务使用）。
  ///
  /// state 入口处的防御复制：外部构造的 draft 内层 map 可能可变，
  /// 直接存储会破坏不可变性契约，故先深拷贝再放入 state。
  void replaceDraft(String conversationId, ComposerDraft draft) {
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: draft.copyWith(),
      },
    );
  }
```

   `draft.copyWith()` 会走 `_deepCopy` 对嵌套 map 防御复制（`ComposerDraft.copyWith` 现有实现，无需改）。
2. `chat_workspace_view_state.dart` 删除 `ChatWorkspaceComposerReadModel.copyWith`（103-125 行整方法；`compose` 走 `fromReadModel`，已确认全仓零调用）。删除前用 `rg -n "copyWith" lib test` 复查该方法的调用（若无命中再删）。
3. `chat_screen.dart` `ref.listenManual` 的 `setState`（78-84 行）追加 `_preEditCollapsed = false;`，使会话切换丢弃编辑事务时同时清空折叠偏好残留：

```dart
      setState(() {
        _editingMessageId = null;
        _editingDraft = null;
        _preEditDraft = null;
        _preEditCollapsed = false;
      });
```

- [ ] **Step 3：跑定向测试**

```bash
flutter test test/features/chat/application/composer_draft_controller_test.dart test/features/chat/application/chat_workspace_view_state_test.dart test/features/chat/chat_screen_test.dart --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`。

- [ ] **Step 4：格式化并提交**

```bash
dart format lib/features/chat/application/composer_draft_controller.dart lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/composer_draft_controller_test.dart
git add lib/features/chat/application/composer_draft_controller.dart lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/composer_draft_controller_test.dart
dart format --output=none --set-exit-if-changed lib/features/chat/application/composer_draft_controller.dart lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/composer_draft_controller_test.dart
git commit -m "fix(chat): 补全 composer draft 防御复制与清理残留" -m "replaceDraft 存入 state 前深拷贝嵌套 map，保证不可变契约；删除零调用 copyWith 死代码；会话切换时清空编辑折叠偏好残留。"
```

---

### Task 7：全量验证

**Files：** 无（只跑门禁）

- [ ] **Step 1：analyze**

```bash
flutter analyze 2>&1 | tee flanalyze-phase10-fix.log | tail -5
```

预期：`No issues found!`、`EXIT=0`。

- [ ] **Step 2：全量测试（强制重定向）**

```bash
flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log
```

预期：`EXIT=0`、末尾 `All tests passed!`。失败只从 `fltest.log` 查（`grep -nE " -[1-9]" fltest.log`）。

- [ ] **Step 3：格式门禁复查**

```bash
git diff --name-only -- '*.dart' | xargs dart format --output=none --set-exit-if-changed
```

预期：exit 0。

- [ ] **Step 4：范围审计**

```bash
git diff 66bf178 --stat
rg -n "ChatGenerationCoordinator|CREATE TABLE|ALTER TABLE|GoRoute|StatefulShellRoute" lib/features/chat/presentation/chat_screen.dart lib/features/chat/application/chat_composer_command.dart lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/application/composer_draft_controller.dart
git diff --check
```

预期：只含本计划 6 个 Task 的改动；无 generation/schema/路由改动；`git diff --check` 无空白错误。

---

## 自审记录

- **Spec coverage**：H1（Task 1）、M1（Task 3）、M2（Task 2）、M3（Task 4）、M4（Task 5）、L1/L2/_preEditCollapsed（Task 6）全部有对应任务。未纳入的评审项：build 期 `existing.text` 赋值脆弱模式（实测不炸、与 H1 同源已被重绑 listener 缓解）、sendStep 先清后发（modal+门控不可达、旧行为一致）、beginToggle mounted 顺序（同步调用无窗口、旧行为一致）——均为低收益改动，明确不修，与用户「修复方便、收益高的纳入」一致。
- **Placeholder scan**：无 TBD；测试代码均给出可执行骨架，`TestFixtures` 工厂名与模板字段以实际模型为准的说明已标注。
- **Type consistency**：`resolveSelectedPresetPrompt(List<PresetPrompt>, String?) -> PresetPrompt?` 在 Task 2/3 一致；`_bindTemplateVariableListener(String, String, TextEditingController)` 在 Task 1 内定义与使用一致；`ComposerDraft.copyWith()` 无参调用在 Task 6 依赖既有 `copyWith({...})` 可选参数语义（body/selection 保持、仅深拷贝嵌套 map）——已确认 `copyWith` 全参可选，无参调用等价于深拷贝。

**完成定义：** Task 1 红灯测试先失败后通过；Task 1-6 定向测试 `EXIT=0`；Task 7 全量 `EXIT=0`、analyze 零问题、格式门禁通过、diff 无越界。
