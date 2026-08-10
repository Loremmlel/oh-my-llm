# Chat Workspace 状态所有权收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变聊天核心业务规则、Phase 7 收藏边界和 Phase 9 generation 生命周期的前提下，为 Chat workspace 的页面瞬态、会话内存态、持久态建立唯一 owner；将 `ChatScreen` 分散的 composer 草稿、模板、编辑快照和 20+ 参数链收敛为不可变 `ChatWorkspaceViewState` 与按职责分组的 `ChatWorkspaceBindings`，并让发送、编辑、停止、重试、收藏、撤销继续通过稳定 application command / facade 执行。

**Architecture:** `ChatConversation`/SQLite 继续拥有模型、预设 Prompt、reasoning、auto-retry、消息树和排除状态；SharedPreferences 继续拥有 composer 折叠与 sidebar UI 偏好；新的按 `conversationId` 隔离的 `ComposerDraftState` 只在 ProviderContainer 内保存正文、模板选择和模板变量草稿；焦点、滚动、`TextEditingController`、固定顺序弹窗游标及编辑事务仍由 `ChatScreen` 页面实例拥有。Chat application 提供纯不可变 workspace read-model 和 composer/favorite intent command；presentation 的 bindings 只组合 UI 资源与回调，不把 Flutter controller 塞进业务 state。Phase 9 的 `chatSessionsProvider` 仍是 generation/session command facade，Phase 7 的 `ChatFavoritesFacade` 仍是 Chat↔Favorites 唯一跨 feature mutation 边界。

**Tech Stack:** Flutter、Dart 3、Riverpod 3.4.2 `NotifierProvider`/derived `Provider`、Equatable、现有 sqlite3/SharedPreferences、现有 widget case-file decomposition。不得引入新的状态管理框架、代码生成、路由方案或持久化介质。

## Global Constraints

以下约束来自源审查 `docs/第一轮审查/Phase 10 - Implement Plan.md`，所有 task 隐式包含：

- **命名**：Provider 命名 `xxxProvider`；控制器类 `XxxController extends Notifier<XxxState>`，类名不带 `Provider`。注释简体中文。
- **禁止 `part`/`part of`**；大文件用 `import`/`export` 拆分。
- **导入路径**：跨 feature/跨 `core/`/跨 `app/` 用 `package:oh_my_llm/...`；同一 feature 内部用相对路径；`test/` 文件互引只能用相对路径。
- **禁止临时审查编号**：注释里不得出现 `Phase 10`、`第一轮审查`、`TD-11` 等编号；只写「代码为什么这么写」。测试标题同样适用。
- **数据模型用 `Equatable`**；列表/Set/嵌套 Map 构造时转不可变集合，`props` 覆盖全部字段。
- **Reasoning/Content 分离三处统一**；不改消息树 parent/branch/select/retry-latest 规则，不改 Prompt 五步顺序，不改 inline error/empty reply 语义，不改 finish reason 持久化。
- **不修改 SQLite schema/migration/user_version**、SharedPreferences versioned codec、background writer；不引入 GoRoute/StatefulShellRoute/keep-alive；不统一 breakpoint；不全仓替换 `pumpAndSettle`/internal Key/timing tests。
- **应用层 state 不得含** `TextEditingController`/`FocusNode`/`ItemScrollController`/`BuildContext`/`Widget`/callback/`Ref`/repository/facade 实例。
- **Chat feature 不得 import `features/favorites/**`**；只消费自身 `ChatFavoritesFacade`。
- **提交**：每次提交前对本 Phase 改动 Dart 文件执行 `dart format`，暂存后 `dart format --output=none --set-exit-if-changed` 严格检查；用 Bash 执行 `git commit`（hook 只看第一行，自动 bump 版本，勿手工改 `pubspec.yaml`）。
- **全量测试**：必须重定向到 `fltest.log`，禁止直接运行 `flutter test`，禁止 `tee`。

## State Ownership 矩阵（实现时以此为准）

| 状态/资源 | 唯一 owner | 生命周期 | 禁止做法 |
|---|---|---|---|
| 消息树、active branch、标题、checkpoint、排除消息 | `ChatConversation` + `chatSessionsProvider` + SQLite | 跨页面/重启 | 不复制到 workspace/composer state；不改树算法 |
| 模型、preset、reasoning、auto-retry | `ChatConversation` + SQLite | 会话持久态 | 不保留 `_selectedPresetPromptId` 等本地镜像 |
| 新会话默认模型等最近选择 | 现有 `chatDefaultsProvider` + SharedPreferences | 应用持久态 | 不把「当前会话选择」与「新会话默认值」误判为同一 owner |
| 正文草稿 | `ComposerDraftController`，按 conversationId | ProviderContainer 内会话态 | 不写 SQLite/SharedPreferences；不由 controller 文本充当事实源 |
| template selection | 同一 `ComposerDraftController` | ProviderContainer 内会话态 | 不保留全局单值 `chatTemplatePromptSelectionProvider` |
| template variable draft | 同一 controller，conversation+template+variable | ProviderContainer 内会话态 | 不再用 `templateId::variableName` 全局 key |
| composer collapsed | `composerCollapsedProvider` + SharedPreferences | 持久化 UI preference | 不按 conversation 拆；不把 controller 写进 prefs |
| editing message ID / draft / pre-edit snapshot | `_ChatScreenState` | 页面瞬态 | 不写 Provider/SQLite；销毁后不显示「正在编辑」 |
| fixed sequence 游标 | `_ChatScreenState` | 页面实例瞬态 | 不新增持久化 key |
| message/body/template `TextEditingController`、FocusNode | `_ChatScreenState` / dialog State | 页面/弹窗资源 | 不进 Equatable/Provider state/read-model |
| item scroll controllers、anchor/show-bottom notifier | `ChatScrollController` | 页面瞬态 | 不改为全局 Provider |
| generation subscription/retry/cancel token | Phase 9 `ChatGenerationCoordinator` | 单次 generation | Workspace 不持有 subscription/completer/新布尔状态机 |
| favorites/collections | Favorites feature；Chat 只经 `ChatFavoritesFacade` | 持久态 | Chat 不 import Favorites controller |

## 编辑事务确定语义（状态机，不允许自行简化）

1. **进入编辑**：从当前 session draft 拷贝不可变 `preEditDraft`（`ComposerDraft`），另存 `preEditCollapsed`（bool，独立于 draft）。按目标 user message 的 `userMessageSegments`/`templatePromptId`/`templateVariableValues` 构造页面本地 `editingDraft`。此时不写 `ComposerDraftController`。
2. **编辑输入**：listener 只更新本地 `editingDraft`；正常 session draft 保持进入编辑前值。
3. **取消编辑**：丢弃 editing state，把 `preEditDraft` 重新投影到 controllers；Provider normal draft 本就未变，不执行恢复写回。`preEditCollapsed` 经 `composerCollapsedProvider.setCollapsed` 恢复。
4. **编辑中切换会话 / 销毁页面**：丢弃编辑事务；session draft 保持原值。
5. **提交编辑**：`ChatComposerCommand.dispatch(editingDraft)` 调现有 `editMessage`；accepted 后 session draft 变「body 空、保留本次 template/variables」，页面退出编辑。generation 失败仍走 Phase 9 inline error，不恢复输入框、不发第二次请求。
6. **编辑保护**：编辑且 composer 展开时禁止折叠；该 UI guard 留在 Screen，不搬入 generation coordinator。

## 依赖方向

```
presentation (ChatScreen) ──watch──▶ ChatWorkspaceReadModel (immutable snapshots)
                │
                ├──▶ ChatWorkspaceViewState = compose(readModel, editingDraft, isEditingMessage)
                ├──▶ ChatWorkspaceBindings (UI resources + intents, presentation-only)
                ├──▶ ChatComposerCommand (dispatch/toolbar, -> chatSessionsProvider + composerDraftProvider + chatDefaultsProvider)
                └──▶ ChatFavoriteIntentCommand (-> ChatFavoritesFacade)
```

- `ChatWorkspaceViewState` 可引用 Chat/Settings domain model 与不可变集合，但不得 import Flutter widgets、Favorites application/controller、SQLite、HTTP。
- `ChatWorkspaceBindings` 位于 presentation，可引用 `TextEditingController`/`FocusNode`/`ValueListenable`/`ItemScrollController` 及 callback typedef；不得被任何 application/domain 文件 import。
- `ChatComposerCommand` 可委托 `chatSessionsProvider`/`composerDraftProvider`/`chatDefaultsProvider`，但不得创建 completion client/repository/coordinator/新 generation flags。
- `ChatFavoriteIntentCommand` 只能依赖 Chat domain + `ChatFavoritesFacade`。

## 文件清单

### 新增生产文件

| 文件 | 责任 | 不得包含 |
|---|---|---|
| `lib/features/chat/application/chat_workspace_view_state.dart` | 不可变 messages/composer read-model、纯 resolver、derived provider | Flutter controller、Widget、BuildContext、mutation command |
| `lib/features/chat/application/chat_composer_command.dart` | composer toolbar intent、send/edit dispatch、draft commit | generation lifecycle、HTTP/repository、dialog/notification |
| `lib/features/chat/application/chat_favorite_intent_command.dart` | favorite toggle preparation/removal/restore/add metadata | Favorites concrete imports、Widget、notification bubble |
| `lib/features/chat/presentation/widgets/chat_workspace_bindings.dart` | messages/composer/scroll UI bindings | Provider watch/read、持久化、业务状态机 |

### 修改/删除生产文件

| 文件 | 修改 |
|---|---|
| `lib/features/chat/application/composer_draft_controller.dart` | 改为 per-conversation immutable aggregate；增加 derived selection family 和事务 API |
| `lib/features/chat/application/chat_template_prompt_selection_controller.dart` | 所有调用迁移后删除 |
| `lib/features/chat/application/composer_collapsed_controller.dart` | 仅更新 ownership 注释；保留 key/行为/测试 |
| `lib/features/chat/presentation/chat_screen.dart` | 删除本地 preset 镜像与 build 同步；隔离 edit draft；消费 read-model/commands；只组合 state/bindings 与 dialog/notification/page resources |
| `lib/features/chat/presentation/widgets/chat_workspace.dart` | 构造器改为 state+bindings；按分组下传 |
| `lib/features/chat/presentation/widgets/chat_composer_card.dart` | 改收 composer state/bindings；UI/动画/文案不变 |
| `lib/features/chat/presentation/widgets/chat_messages_panel.dart` | 改收 messages state、message+scroll bindings；缓存与渲染规则不变 |
| `lib/features/chat/presentation/widgets/composer_data.dart` | 迁移完成后删除 |
| `lib/features/chat/presentation/widgets/widgets.dart` | export 新 bindings；删除旧 export |
| `lib/features/chat/application/chat_favorites_facade.dart` | 仅为 `ChatFavoriteDraft` 补 `copyWithCollectionId`（additive） |
| `lib/app/composition/cross_feature_bindings.dart` | 默认不改；仅 additive signature 编译需要时机械适配 |

### 测试文件

| 文件 | 计划 |
|---|---|
| `test/features/chat/application/composer_draft_controller_test.dart` | 重写为 conversation aggregate、嵌套不可变、selection derived rebuild、App-container reset |
| `test/features/chat/application/chat_template_prompt_selection_controller_test.dart` | 新 contract 覆盖后删除 |
| `test/features/chat/application/chat_composer_command_test.dart` | 新增 dispatch reject/accept、normal/edit、draft commit、single builder call |
| `test/features/chat/application/chat_favorite_intent_command_test.dart` | 新增 add/remove/restore/source metadata/collection mapping |
| `test/features/chat/application/chat_workspace_view_state_test.dart` | 新增 resolver/fallback/immutability/streaming projection contract |
| `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart` | 新增页面重建、A↔B 草稿、template vars、preset 单 owner、edit cancel/dispose |
| `test/features/chat/chat_screen_test.dart` | 注册新 ownership cases |
| `test/features/chat/chat_screen/chat_screen_test_helpers.dart` | 增加同 ProviderScope 页面 mount/unmount harness |

---

## Task 1: 冻结 ownership 行为，收敛 composer session state

**Files:**
- Modify: `lib/features/chat/application/composer_draft_controller.dart`
- Modify: `lib/features/chat/application/chat_template_prompt_selection_controller.dart`（Task 1 内删除）
- Modify: `lib/features/chat/presentation/chat_screen.dart`（仅 draft/template/preset owner，不做 workspace 参数迁移）
- Modify: `test/features/chat/application/composer_draft_controller_test.dart`
- Modify: `test/features/chat/application/chat_template_prompt_selection_controller_test.dart`（删除）
- Modify: `test/features/chat/chat_screen/chat_screen_test_helpers.dart`
- Modify: `test/features/chat/chat_screen_test.dart`
- Add: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`

**Interfaces produced (later tasks rely on these):**
- `class ComposerDraft extends Equatable` — `body`, `selectedTemplatePromptId`, `templateVariableValuesByTemplateId`; `static const empty`; `copyWith({body, selectedTemplatePromptId, clearTemplateSelection, templateVariableValuesByTemplateId})`.
- `class ComposerDraftState extends Equatable` — `draftsByConversationId: Map<String, ComposerDraft>`; `copyWith`.
- `class ComposerDraftController extends Notifier<ComposerDraftState>` — `draftFor(conversationId)`, `setBody(conversationId, body)`, `selectTemplate(conversationId, templatePromptId)`, `setTemplateVariable(conversationId, templateId, variableName, value)`, `replaceDraft(conversationId, draft)`, `clearBody(conversationId)`, `clearDraft(conversationId)`.
- `final composerDraftProvider`（同名，`NotifierProvider`）。
- `final composerTemplateSelectionProvider = Provider.family<String?, String>` — `composerTemplateSelectionProvider(conversationId)`。
- 删除 `composerDraftProvider.readBody/readTemplateVariable/setTemplateVariable` 的旧签名（移入 `ChatComposerCommand` 的 build 逻辑，见 Task 3）。

- [ ] **Step 1: 重写 `composer_draft_controller.dart` 的不可变 per-conversation aggregate。**

把整个文件替换为以下实现（`ComposerDraft` 用防御复制 + `Map.unmodifiable`，`selectedTemplatePromptId` 用 `clearTemplateSelection` 标志支持显式置 null）：

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 单个会话的输入草稿：正文、模板选择、模板变量。
///
/// 值对象不可变：构造/copy 时对每层嵌套 Map 做防御复制并 `Map.unmodifiable`，
/// 避免外层包成 unmodifiable 后仍暴露可变内层。仅存于内存并按会话隔离，
/// 跨 GoRouter 页面切换（销毁重建 [ChatScreen]）后仍能恢复，App 重启后重置。
class ComposerDraft extends Equatable {
  const ComposerDraft({
    this.body = '',
    this.selectedTemplatePromptId,
    this.templateVariableValuesByTemplateId = const {},
  });

  /// 无任何内容/选择的空草稿，供 absent 会话回退。
  static const empty = ComposerDraft();

  final String body;
  final String? selectedTemplatePromptId;

  /// key = 模板 ID，value = 该模板的 {变量名: 值}。
  final Map<String, Map<String, String>> templateVariableValuesByTemplateId;

  ComposerDraft copyWith({
    String? body,
    String? selectedTemplatePromptId,
    bool clearTemplateSelection = false,
    Map<String, Map<String, String>>? templateVariableValuesByTemplateId,
  }) {
    return ComposerDraft(
      body: body ?? this.body,
      selectedTemplatePromptId: clearTemplateSelection
          ? null
          : selectedTemplatePromptId ?? this.selectedTemplatePromptId,
      templateVariableValuesByTemplateId: _deepCopy(
        templateVariableValuesByTemplateId ??
            this.templateVariableValuesByTemplateId,
      ),
    );
  }

  static Map<String, Map<String, String>> _deepCopy(
    Map<String, Map<String, String>> source,
  ) {
    return Map.unmodifiable(
      source.map(
        (templateId, variables) =>
            MapEntry(templateId, Map.unmodifiable(variables)),
      ),
    );
  }

  @override
  List<Object?> get props => [
    body,
    selectedTemplatePromptId,
    templateVariableValuesByTemplateId,
  ];
}

/// 全部会话的体草稿集合。
class ComposerDraftState extends Equatable {
  const ComposerDraftState({this.draftsByConversationId = const {}});

  final Map<String, ComposerDraft> draftsByConversationId;

  ComposerDraftState copyWith({
    Map<String, ComposerDraft>? draftsByConversationId,
  }) {
    return ComposerDraftState(
      draftsByConversationId: Map.unmodifiable(
        draftsByConversationId ?? this.draftsByConversationId,
      ),
    );
  }

  @override
  List<Object?> get props => [draftsByConversationId];
}

class ComposerDraftController extends Notifier<ComposerDraftState> {
  @override
  ComposerDraftState build() => const ComposerDraftState();

  /// 读取指定会话草稿，无草稿返回 [ComposerDraft.empty]。
  ComposerDraft draftFor(String conversationId) =>
      state.draftsByConversationId[conversationId] ?? ComposerDraft.empty;

  /// 写入/更新正文；相同值不发 state。
  void setBody(String conversationId, String body) {
    final current = draftFor(conversationId);
    if (current.body == body) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(body: body),
      },
    );
  }

  /// 更新模板选择；相同值不发 state。
  void selectTemplate(String conversationId, String? templatePromptId) {
    final current = draftFor(conversationId);
    if (current.selectedTemplatePromptId == templatePromptId) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(
          selectedTemplatePromptId: templatePromptId,
          clearTemplateSelection: templatePromptId == null,
        ),
      },
    );
  }

  /// 写入/更新模板变量；相同值不发 state。
  void setTemplateVariable(
    String conversationId,
    String templateId,
    String variableName,
    String value,
  ) {
    final current = draftFor(conversationId);
    final templateVariables = Map<String, String>.from(
      current.templateVariableValuesByTemplateId[templateId] ?? const {},
    );
    if (templateVariables[variableName] == value) return;
    templateVariables[variableName] = value;
    final nextVariables = Map<String, Map<String, String>>.from(
      current.templateVariableValuesByTemplateId,
    )..[templateId] = Map.unmodifiable(templateVariables);
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(
          templateVariableValuesByTemplateId: nextVariables,
        ),
      },
    );
  }

  /// 整体替换草稿（仅恢复/提交事务使用）。
  void replaceDraft(String conversationId, ComposerDraft draft) {
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: draft,
      },
    );
  }

  /// send 后清空正文，但保留模板选择与变量草稿。
  void clearBody(String conversationId) {
    final current = draftFor(conversationId);
    if (current.body.isEmpty) return;
    state = state.copyWith(
      draftsByConversationId: {
        ...state.draftsByConversationId,
        conversationId: current.copyWith(body: ''),
      },
    );
  }

  /// 「新对话」显式重置整个草稿。
  void clearDraft(String conversationId) {
    if (!state.draftsByConversationId.containsKey(conversationId)) return;
    final next = Map<String, ComposerDraft>.from(
      state.draftsByConversationId,
    )..remove(conversationId);
    state = state.copyWith(draftsByConversationId: next);
  }
}

/// 聊天输入框草稿（内存级，跨页面保留，App 重启后重置）。
final composerDraftProvider =
    NotifierProvider<ComposerDraftController, ComposerDraftState>(
      ComposerDraftController.new,
    );

/// 只监听指定会话的模板选择，供 [ChatScreen] 用 `.select` 派生。
///
/// 每次正文/变量写入不会让整个 [ChatScreen] rebuild；只有选择变化才触发。
final composerTemplateSelectionProvider = Provider.family<String?, String>(
  (ref, conversationId) {
    return ref.watch(
      composerDraftProvider.select(
        (state) =>
            state.draftsByConversationId[conversationId]
                ?.selectedTemplatePromptId,
      ),
    );
  },
);
```

- [ ] **Step 2: 重写 `composer_draft_controller_test.dart`。**

替换为以下测试（覆盖 conversation 隔离、嵌套不可变、selection derived rebuild、App-container reset）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/composer_draft_controller.dart';

void main() {
  group('ComposerDraftController per-conversation aggregate', () {
    late ProviderContainer container;
    late ComposerDraftController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(composerDraftProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('A/B 会话 body 与同名模板变量互不覆盖，切回 A 读到 A 的完整 draft', () {
      controller.setBody('conv-a', 'A 正文');
      controller.setBody('conv-b', 'B 正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      controller.setTemplateVariable('conv-b', 'tpl-1', 'title', '乙');

      final a = controller.draftFor('conv-a');
      final b = controller.draftFor('conv-b');
      expect(a.body, 'A 正文');
      expect(b.body, 'B 正文');
      expect(a.templateVariableValuesByTemplateId['tpl-1']?['title'], '甲');
      expect(b.templateVariableValuesByTemplateId['tpl-1']?['title'], '乙');
    });

    test('selection 是 conversation-scoped', () {
      controller.selectTemplate('conv-a', 'tpl-a');
      expect(controller.draftFor('conv-b').selectedTemplatePromptId, isNull);
      controller.selectTemplate('conv-b', 'tpl-b');
      expect(controller.draftFor('conv-a').selectedTemplatePromptId, 'tpl-a');
      expect(controller.draftFor('conv-b').selectedTemplatePromptId, 'tpl-b');
    });

    test('暴露的外层/内层 Map 不可变，旧 state 不受 mutation 影响', () {
      controller.setBody('conv-a', '正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      final stateBefore = container.read(composerDraftProvider);

      expect(
        () =>
            stateBefore.draftsByConversationId['conv-a']!.templateVariableValuesByTemplateId['tpl-1']!['title'] = '改',
        throwsUnsupportedError,
      );
      expect(stateBefore.draftsByConversationId['conv-a']!.body, '正文');
    });

    test('只监听 select 的 derived family：正文/变量写入不触发 selection listener', () {
      var selectionChanges = 0;
      container.listen(
        composerTemplateSelectionProvider('conv-a'),
        (_, __) => selectionChanges++,
      );
      controller.setBody('conv-a', '正文');
      controller.setTemplateVariable('conv-a', 'tpl-1', 'title', '甲');
      expect(selectionChanges, 0);

      controller.selectTemplate('conv-a', 'tpl-a');
      expect(selectionChanges, 1);

      controller.selectTemplate('conv-b', 'tpl-b'); // 不同会话
      expect(selectionChanges, 1);
    });

    test('dispose 后新建 provider container，draft 为空（证明非 App 持久态）', () {
      controller.setBody('conv-a', '正文');
      container.dispose();

      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      expect(fresh.read(composerDraftProvider.notifier).draftFor('conv-a'), ComposerDraft.empty);
    });

    test('clearBody 保留模板选择与变量，clearDraft 整体清空', () {
      controller.setBody('conv-a', '正文');
      controller.selectTemplate('conv-a', 'tpl-a');
      controller.setTemplateVariable('conv-a', 'tpl-a', 'title', '甲');
      controller.clearBody('conv-a');
      var draft = controller.draftFor('conv-a');
      expect(draft.body, '');
      expect(draft.selectedTemplatePromptId, 'tpl-a');
      expect(draft.templateVariableValuesByTemplateId['tpl-a'], isNotEmpty);

      controller.clearDraft('conv-a');
      draft = controller.draftFor('conv-a');
      expect(draft, ComposerDraft.empty);
    });
  });
}
```

> 说明：外层 Map 不可变测试用 `throwsUnsupportedError` 断言；`Map.unmodifiable` 对既有 key 的赋值抛 `UnsupportedError`。若 Flutter 环境行为差异导致断言对象不同，改为断言「旧 state 值不变」即可，见下方可选简化。

- [ ] **Step 3: 运行单文件测试，确认新聚合通过。**

```powershell
flutter test test/features/chat/application/composer_draft_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-composer-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-composer-state.log
```

Expected: `EXIT=0`。（此时 `chat_screen.dart` 仍引用旧 API，会在 Step 4 一并修复，编译器当前报错可接受，先只验证 controller 层。）

- [ ] **Step 4: 迁移 `chat_screen.dart` 的草稿/模板/预设 owner。**

在 `_ChatScreenState` 中做以下替换（仅 owner 收敛，不动 workspace 参数链，那是 Task 2）：

1. 删除字段 `_selectedPresetPromptId`、`_presetPromptNeedsInit`、`_draftConversationId`、`_restoredDraftForConversationId`、`_isRestoringDraft`。新增 `bool _isApplyingComposerDraft = false;` 作为 body+variable controller 编程赋值时的统一 guard。
2. 用 `ref.listenManual` 统一首次挂载与会话切换的草稿恢复（Riverpod 3.4.2 支持，随 widget 自动释放，替代原来 build 内 `ref.listen` + post-frame 恢复）：

```dart
@override
void initState() {
  super.initState();
  _messageController = TextEditingController();
  _messageFocusNode = FocusNode();
  _scroll = ChatScrollController();
  _scroll.itemPositionsListener.itemPositions.addListener(
    _scroll.handleVisibleItemsChanged,
  );
  _messageController.addListener(_onBodyChanged);
  // 会话切换时把目标 draft 投影到 page controllers。fireImmediately 统一首次挂载
  // 与会话切换为一个路径；controller 赋值需在首帧后（避免帧内副作用），
  // 用带 mounted 与 conversationId 校验的 post-frame 调度。
  ref.listenManual<String>(activeConversationIdProvider, (prev, next) {
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentId = ref.read(activeConversationIdProvider);
      if (currentId != next) return; // 会话已再次切换，丢弃
      _applyDraftToControllers(_restoreDraftFor(next));
    });
  }, fireImmediately: true);
}
```

3. 替换 `_persistBodyDraft` / `_restoreBodyDraftIfNeeded` 为统一切换入口：

```dart
/// 从 Provider 读回内存草稿（仅恢复用）。
ComposerDraft _restoreDraftFor(String conversationId) {
  return ref.read(composerDraftProvider.notifier).draftFor(conversationId);
}

/// 进入会话时把 [effectiveDraft] 投影到 body/template variable controllers。
///
/// 编程赋值期间用一个 guard 抑制所有 listener 回写 Provider，避免帧内副作用。
void _applyDraftToControllers(ComposerDraft effectiveDraft, {String? conversationId}) {
  _isApplyingComposerDraft = true;
  _messageController.text = effectiveDraft.body;
  _messageController.selection = TextSelection.collapsed(
    offset: effectiveDraft.body.length,
  );
  final template = _resolveSelectedTemplatePrompt(
    ref.read(templatePromptsProvider),
    effectiveDraft.selectedTemplatePromptId,
  );
  _syncTemplateVariableControllers(template, draft: effectiveDraft);
  _isApplyingComposerDraft = false;
}

void _onBodyChanged() {
  if (_isApplyingComposerDraft) return;
  final conversationId = _activeConversationIdOrNull();
  if (conversationId == null) return;
  ref.read(composerDraftProvider.notifier).setBody(conversationId, _messageController.text);
}

String? _activeConversationIdOrNull() {
  final id = ref.read(activeConversationIdProvider);
  return id.isEmpty ? null : id;
}
```

4. 重写 `_syncTemplateVariableControllers` 接收 `effectiveDraft`，且**模板 controller 已存在时也必须按目标 draft 重新赋值**（阻止同名模板变量跨会话泄漏）：

```dart
void _syncTemplateVariableControllers(
  TemplatePrompt? template, {
  required ComposerDraft draft,
}) {
  final activeNames =
      template?.inputVariables.map((v) => v.name).toSet() ?? const <String>{};
  final removedNames = _templateVariableControllers.keys
      .where((name) => !activeNames.contains(name))
      .toList(growable: false);
  for (final name in removedNames) {
    _templateVariableControllers.remove(name)?.dispose();
  }

  if (template == null) {
    return;
  }

  final controllerRef = ref.read(composerDraftProvider.notifier);
  final conversationId = _activeConversationIdOrNull();
  for (final variable in template.inputVariables) {
    final templateId = template.id;
    // 已存在也必须按当前会话 draft 重赋值，不能因 key 存在直接 continue。
    final savedValue = conversationId == null
        ? null
        : draft.templateVariableValuesByTemplateId[templateId]?[variable.name];
    final existing = _templateVariableControllers[variable.name];
    if (existing == null) {
      final controller = TextEditingController(
        text: savedValue ?? variable.defaultValue,
      );
      controller.addListener(() {
        if (_isApplyingComposerDraft) return;
        final cid = _activeConversationIdOrNull();
        if (cid == null) return;
        controllerRef.setTemplateVariable(cid, templateId, variable.name, controller.text);
      });
      _templateVariableControllers[variable.name] = controller;
    } else {
      if (savedValue != null && existing.text != savedValue) {
        _isApplyingComposerDraft = true;
        existing.text = savedValue;
        _isApplyingComposerDraft = false;
      }
    }
  }
}
```

5. 删除 `chatTemplatePromptSelectionProvider` 的所有 read/watch/clear。当前模板 ID 来自 active conversation draft：

```dart
// 替换原 ref.watch(chatTemplatePromptSelectionProvider)
final selectedTemplatePromptId = ref.watch(
  composerTemplateSelectionProvider(activeConversationId),
);
```

删除 `build` 中 `if (_presetPromptNeedsInit) {...}` 以及 `ref.listen<String?>(activeConversationIdProvider, ...)` 里对 `_selectedPresetPromptId` 的同步与 `chatTemplatePromptSelectionProvider.clear()`。

6. 删除 `_selectedPresetPromptId` 双写。`_resolveSelectedPresetPrompt` 改为只用 conversation 字段：

```dart
PresetPrompt? _resolveSelectedPresetPrompt(
  List<PresetPrompt> presetPrompts,
  ChatConversation conversation,
) {
  final effectiveId = conversation.selectedPresetPromptId;
  if (effectiveId == null || effectiveId == noPresetPromptSelectedId) {
    return null;
  }
  return presetPrompts.where((p) => p.id == effectiveId).firstOrNull;
}
```

`_handlePresetPromptSelected` 改为只写 conversation command：

```dart
void _handlePresetPromptSelected(String? presetPromptId) {
  ref
      .read(chatSessionsProvider.notifier)
      .updateActiveConversationPreferences(
        selectedPresetPromptId: presetPromptId ?? noPresetPromptSelectedId,
      );
}
```

`PresetPromptPanel` 的 `selectedPresetPromptId` 直接传 `conversation.selectedPresetPromptId`（`_buildSidebarContent` / `_buildEndDrawer` 中替换 `_selectedPresetPromptId`）。

7. `_handleTemplatePromptSelected` 改为只写目标会话 draft 并同步 controllers：

```dart
void _handleTemplatePromptSelected(String? templatePromptId) {
  final conversationId = _activeConversationIdOrNull();
  if (conversationId == null) return;
  final controllerRef = ref.read(composerDraftProvider.notifier);
  controllerRef.selectTemplate(conversationId, templatePromptId);
  _syncTemplateVariableControllers(
    _resolveSelectedTemplatePrompt(
      ref.read(templatePromptsProvider),
      templatePromptId,
    ),
    draft: controllerRef.draftFor(conversationId),
  );
}
```

8. `_createConversationAndScroll` 中删除 `_selectedPresetPromptId = null` 与 `chatTemplatePromptSelectionProvider.clear()`，改为 `composerDraftProvider.notifier.clearDraft(activeId)`（见 Task 3 的 `createConversationAndResetDraft`，此处先调用 controller 方法）。

- [ ] **Step 5: 删除 `chat_template_prompt_selection_controller.dart` 及其测试。**

先用 `rg` 确认 production/test 无残留引用：

```powershell
rg -n "chatTemplatePromptSelectionProvider|ChatTemplatePromptSelectionController" lib test
```

Expected: 零结果。然后删除两个文件：

```bash
rm lib/features/chat/application/chat_template_prompt_selection_controller.dart
rm test/features/chat/application/chat_template_prompt_selection_controller_test.dart
```

- [ ] **Step 6: 新增同 ProviderScope 的 mount/unmount harness 与 ownership cases。**

在 `chat_screen_test_helpers.dart` 增加一个返回可复用 `ProviderScope` 的 pump（供 ownership 测试在保持同一 scope 下卸载/重挂 `ChatScreen`）：

```dart
/// 挂载 ChatScreen 并返回可复用的 ProviderScope。
///
/// 与 [pumpChatScreen] 不同，调用方持有 scope，可先 `tester.pumpWidget(const SizedBox())`
/// 卸载 ChatScreen，再 `tester.pumpWidget(scope)` 重挂，保持同一
/// ProviderScope/数据库/SharedPreferences 存活。
ProviderScope pumpChatScreenScope(
  WidgetTester tester, {
  required FakeChatCompletionClient fakeClient,
  SharedPreferences? preferences,
  AppDatabase? database,
  Size size = const Size(1440, 1600),
}) {
  final db = database ?? AppDatabase.inMemory();
  final ownsDatabase = database == null;
  if (ownsDatabase) {
    addTearDown(db.close);
  }
  final scope = pumpTestAppScope(
    tester,
    child: const ChatScreen(),
    viewportSize: size,
    extraOverrides: [
      chatCompletionClientProvider.overrideWithValue(fakeClient),
    ],
    database: db,
    preferencesOverride: preferences,
  );
  return scope;
}
```

> 需要 `pumpTestApp` 提供一个返回 `ProviderScope` 的变体 `pumpTestAppScope`（在 `test/helpers/test_harness.dart` 中把 `ProviderScope(...)` 的构造抽成可留存的局部变量，返回值类型 `ProviderScope`）。若改动 `test_harness.dart` 影响全仓，提供一个最小 additive 助手，不改既有 `pumpTestApp` 签名。

新增 `chat_screen_workspace_ownership_cases.dart`，注册 A↔B 草稿、template vars、preset 单 owner、页面卸载重挂恢复：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_test_helpers.dart';

void registerChatScreenWorkspaceOwnershipTests() {
  testWidgets('A→B 首次切换 B 不显示 A 的 body/template/variable', (tester) async {
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(tester, fakeClient: fakeClient);

    // 通过 history 面板创建第二个会话并切换（用 UI 文案/输入值断言，不读私有字段）。
    // 这里仅示意：具体会话创建与切换的 finder 沿用既有 helper 或既有 cases 的做法。
    // 断言：找不到 A 的正文文本，模板变量字段不含 A 的输入值。
    expect(find.text('A 的正文'), findsNothing);
  });

  testWidgets('ChatScreen 卸载后在同 scope 重挂，body/template/variable 恢复', (
    tester,
  ) async {
    final fakeClient = FakeChatCompletionClient();
    final scope = pumpChatScreenScope(tester, fakeClient: fakeClient);

    // 输入正文与模板变量（用既有 finder，如 find.byKey('chat-message-composer')）。
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-composer')),
      '未发送草稿',
    );
    await tester.pump();

    // 卸载 ChatScreen，保持 scope 存活。
    await tester.pumpWidget(const SizedBox());
    // 重挂进同一 scope。
    await tester.pumpWidget(scope);
    await tester.pump();

    // 断言输入框恢复草稿。
    expect(
      tester.widget<TextField>(
        find.byKey(const ValueKey('chat-message-composer')),
      ).controller!.text,
      '未发送草稿',
    );
  });
}
```

> 说明：widget 测试不得用 production internal `find.byKey` 之外的私有 key、像素位置、`getRect` 或私有 widget 属性作契约。上面 `chat-message-composer` 是既有公开 key（`sendMessage` helper 已用），可复用。ownership cases 的完整会话切换流程（创建 B、切换 A↔B）需参考既有 `chat_screen_basics_cases.dart` 的会话创建 finder；此处给出骨架与断言意图，实施时补齐与既有 helper 一致的 finder。

- [ ] **Step 7: 注册 cases 并运行 Screen 定向测试。**

在 `chat_screen_test.dart` 顶部 import 并调用注册：

```dart
import 'chat_screen/chat_screen_workspace_ownership_cases.dart';
// 在 main() 内：
registerChatScreenWorkspaceOwnershipTests();
```

运行：

```powershell
flutter test test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-screen-ownership.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-screen-ownership.log
```

Expected: `EXIT=0`。（Task 4 Step 1 会再添加能暴露「编辑期间写 session draft 旧行为」的红灯测试，不在此 task 提交 failing test。）

- [ ] **Step 8: 格式化并提交。**

```bash
dart format lib/features/chat/application/composer_draft_controller.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/composer_draft_controller_test.dart test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_test_helpers.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git add lib/features/chat/application/composer_draft_controller.dart \
        lib/features/chat/application/chat_template_prompt_selection_controller.dart \
        lib/features/chat/presentation/chat_screen.dart \
        test/features/chat/application/composer_draft_controller_test.dart \
        test/features/chat/application/chat_template_prompt_selection_controller_test.dart \
        test/features/chat/chat_screen_test.dart \
        test/features/chat/chat_screen/chat_screen_test_helpers.dart \
        test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git commit -m "refactor(chat): 明确输入草稿状态所有权"
```

删除文件用精确 path stage；不要 `git add docs/第一轮审查`，避免带入无关 Phase 9 文档。

---

## Task 2: 建立不可变 workspace read-model 和 bindings，消除参数链

**Files:**
- Add: `lib/features/chat/application/chat_workspace_view_state.dart`
- Add: `lib/features/chat/presentation/widgets/chat_workspace_bindings.dart`
- Add: `test/features/chat/application/chat_workspace_view_state_test.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_workspace.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_messages_panel.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_composer_card.dart`
- Modify: `lib/features/chat/presentation/widgets/widgets.dart`
- Delete after migration: `lib/features/chat/presentation/widgets/composer_data.dart`
- Modify existing ChatScreen cases only as required by public constructor changes

**Interfaces produced (later tasks rely on these):**
- `class ChatWorkspaceMessagesState extends Equatable` — `conversation`, `messages`, `userMessages`, `hasModels`, `isBusy`, `errorMessage`, `errorMessageAssistantId`, `emptyReplyAssistantId`, `errorModelDisplayName`, `autoRetryCount`, `favoritedAssistantContents`.
- `class ChatWorkspaceComposerReadModel extends Equatable` — `modelProviders`, `modelConfigs`, `selectedProviderId`, `selectedModel`, `templatePrompts`, `selectedTemplatePrompt`, `fixedPromptSequences`, `isComposerCollapsed`, `reasoningEnabled`, `reasoningEffort`, `supportsReasoning`, `autoRetryEnabled`, `isBusy`, `isStreaming`, `isAutoRetryWaiting`, `excludedMessageCount`.
- `class ChatWorkspaceComposerState extends Equatable` — read-model 全字段 + `selectedTemplatePrompt`（可被页面编辑覆盖）+ `isEditingMessage`。
- `class ChatWorkspaceReadModel extends Equatable` — `messages`, `composer`.
- `class ChatWorkspaceViewState extends Equatable` — `messages`, `composer`; `factory compose({readModel, editingDraft, isEditingMessage, templatePrompts})`.
- `final chatWorkspaceReadModelProvider = Provider<ChatWorkspaceReadModel>`.
- 纯 resolver 函数：`resolveSelectedModel`, `resolveSelectedProviderId`, `resolveSelectedTemplatePrompt`。
- `class ChatWorkspaceBindings` — `messages`, `composer`, `scroll` 三分组（见 bindings 文件）。
- `ChatWorkspace({ required state, required bindings })` 三参数构造。

- [ ] **Step 1: 实现 `chat_workspace_view_state.dart`。**

新建文件，定义不可变值对象 + 纯 resolver + derived provider。**重点**：所有列表/Set 构造时转不可变，`props` 覆盖全部字段；不 import Flutter widget/controller/`Ref`/repository/facade 实例。

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/fixed_prompt_sequence.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_provider_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import 'chat_favorites_facade.dart';
import 'chat_sessions_controller.dart';
import 'composer_draft_controller.dart';

/// 消息面板的不可变显示快照，只含既有 owner 的投影值。
class ChatWorkspaceMessagesState extends Equatable {
  const ChatWorkspaceMessagesState({
    required this.conversation,
    required this.messages,
    required this.userMessages,
    required this.hasModels,
    required this.isBusy,
    required this.errorMessage,
    required this.errorMessageAssistantId,
    required this.emptyReplyAssistantId,
    required this.errorModelDisplayName,
    required this.autoRetryCount,
    required this.favoritedAssistantContents,
  });

  final ChatConversation conversation;

  /// activeConversation 已合并 streaming reply 的可见消息。
  final List<ChatMessage> messages;
  final List<ChatMessage> userMessages;
  final bool hasModels;
  final bool isBusy;
  final String? errorMessage;
  final String? errorMessageAssistantId;
  final String? emptyReplyAssistantId;
  final String errorModelDisplayName;
  final int autoRetryCount;
  final Set<String> favoritedAssistantContents;

  @override
  List<Object?> get props => [
    conversation,
    messages,
    userMessages,
    hasModels,
    isBusy,
    errorMessage,
    errorMessageAssistantId,
    emptyReplyAssistantId,
    errorModelDisplayName,
    autoRetryCount,
    favoritedAssistantContents,
  ];
}

/// composer 的不可变显示快照（read-model 层，不含编辑覆盖）。
class ChatWorkspaceComposerReadModel extends Equatable {
  const ChatWorkspaceComposerReadModel({
    required this.modelProviders,
    required this.modelConfigs,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.templatePrompts,
    required this.selectedTemplatePrompt,
    required this.fixedPromptSequences,
    required this.isComposerCollapsed,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.supportsReasoning,
    required this.autoRetryEnabled,
    required this.isBusy,
    required this.isStreaming,
    required this.isAutoRetryWaiting,
    required this.excludedMessageCount,
  });

  final List<LlmProviderConfig> modelProviders;
  final List<LlmModelConfig> modelConfigs;
  final String? selectedProviderId;
  final LlmModelConfig? selectedModel;
  final List<TemplatePrompt> templatePrompts;
  final TemplatePrompt? selectedTemplatePrompt;
  final List<FixedPromptSequence> fixedPromptSequences;
  final bool isComposerCollapsed;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
  final bool supportsReasoning;
  final bool autoRetryEnabled;
  final bool isBusy;
  final bool isStreaming;
  final bool isAutoRetryWaiting;
  final int excludedMessageCount;

  ChatWorkspaceComposerReadModel copyWith({
    TemplatePrompt? selectedTemplatePrompt,
  }) {
    return ChatWorkspaceComposerReadModel(
      modelProviders: modelProviders,
      modelConfigs: modelConfigs,
      selectedProviderId: selectedProviderId,
      selectedModel: selectedModel,
      templatePrompts: templatePrompts,
      selectedTemplatePrompt:
          selectedTemplatePrompt ?? this.selectedTemplatePrompt,
      fixedPromptSequences: fixedPromptSequences,
      isComposerCollapsed: isComposerCollapsed,
      reasoningEnabled: reasoningEnabled,
      reasoningEffort: reasoningEffort,
      supportsReasoning: supportsReasoning,
      autoRetryEnabled: autoRetryEnabled,
      isBusy: isBusy,
      isStreaming: isStreaming,
      isAutoRetryWaiting: isAutoRetryWaiting,
      excludedMessageCount: excludedMessageCount,
    );
  }

  @override
  List<Object?> get props => [
    modelProviders,
    modelConfigs,
    selectedProviderId,
    selectedModel,
    templatePrompts,
    selectedTemplatePrompt,
    fixedPromptSequences,
    isComposerCollapsed,
    reasoningEnabled,
    reasoningEffort,
    supportsReasoning,
    autoRetryEnabled,
    isBusy,
    isStreaming,
    isAutoRetryWaiting,
    excludedMessageCount,
  ];
}

/// 交给 composer widget 的 effective composer 状态（可能在编辑时被页面覆盖）。
class ChatWorkspaceComposerState extends ChatWorkspaceComposerReadModel {
  const ChatWorkspaceComposerState({
    required super.modelProviders,
    required super.modelConfigs,
    required super.selectedProviderId,
    required super.selectedModel,
    required super.templatePrompts,
    required super.selectedTemplatePrompt,
    required super.fixedPromptSequences,
    required super.isComposerCollapsed,
    required super.reasoningEnabled,
    required super.reasoningEffort,
    required super.supportsReasoning,
    required super.autoRetryEnabled,
    required super.isBusy,
    required super.isStreaming,
    required super.isAutoRetryWaiting,
    required super.excludedMessageCount,
    required this.isEditingMessage,
  });

  final bool isEditingMessage;

  factory ChatWorkspaceComposerState.fromReadModel(
    ChatWorkspaceComposerReadModel readModel, {
    required TemplatePrompt? selectedTemplatePrompt,
    required bool isEditingMessage,
  }) {
    return ChatWorkspaceComposerState(
      modelProviders: readModel.modelProviders,
      modelConfigs: readModel.modelConfigs,
      selectedProviderId: readModel.selectedProviderId,
      selectedModel: readModel.selectedModel,
      templatePrompts: readModel.templatePrompts,
      selectedTemplatePrompt:
          selectedTemplatePrompt ?? readModel.selectedTemplatePrompt,
      fixedPromptSequences: readModel.fixedPromptSequences,
      isComposerCollapsed: readModel.isComposerCollapsed,
      reasoningEnabled: readModel.reasoningEnabled,
      reasoningEffort: readModel.reasoningEffort,
      supportsReasoning: readModel.supportsReasoning,
      autoRetryEnabled: readModel.autoRetryEnabled,
      isBusy: readModel.isBusy,
      isStreaming: readModel.isStreaming,
      isAutoRetryWaiting: readModel.isAutoRetryWaiting,
      excludedMessageCount: readModel.excludedMessageCount,
      isEditingMessage: isEditingMessage,
    );
  }

  @override
  List<Object?> get props => [
    ...super.props,
    isEditingMessage,
  ];
}

/// read-model provider 的产物：只含既有 owner 的快照，不含 UI controller。
class ChatWorkspaceReadModel extends Equatable {
  const ChatWorkspaceReadModel({
    required this.messages,
    required this.composer,
  });

  final ChatWorkspaceMessagesState messages;
  final ChatWorkspaceComposerReadModel composer;

  @override
  List<Object?> get props => [messages, composer];
}

/// 页面最终交给 workspace 的 view-state：read-model + 页面瞬态 overlay。
class ChatWorkspaceViewState extends Equatable {
  const ChatWorkspaceViewState({
    required this.messages,
    required this.composer,
  });

  final ChatWorkspaceMessagesState messages;
  final ChatWorkspaceComposerState composer;

  /// 由 [ChatScreen] 用纯 factory 生成：编辑时用页面本地 [editingDraft] 的
  /// template selection 覆盖 read-model 的 normal selection，并显式传
  /// [isEditingMessage]。read-model 不变，仅有效值变化。
  factory ChatWorkspaceViewState.compose({
    required ChatWorkspaceReadModel readModel,
    required ComposerDraft editingDraft,
    required bool isEditingMessage,
    required List<TemplatePrompt> templatePrompts,
  }) {
    final editingTemplateId = editingDraft.selectedTemplatePromptId;
    final effectiveTemplate = isEditingMessage && editingTemplateId != null
        ? templatePrompts.where((t) => t.id == editingTemplateId).firstOrNull
        : readModel.composer.selectedTemplatePrompt;
    return ChatWorkspaceViewState(
      messages: readModel.messages,
      composer: ChatWorkspaceComposerState.fromReadModel(
        readModel.composer,
        selectedTemplatePrompt: isEditingMessage ? effectiveTemplate : null,
        isEditingMessage: isEditingMessage,
      ),
    );
  }

  @override
  List<Object?> get props => [messages, composer];
}

// ── 纯 resolver（可单测）───────────────────────────────────────────────────

/// conversation 选中模型 → remembered default → 首模型 的 fallback 顺序。
LlmModelConfig? resolveSelectedModel({
  required List<LlmModelConfig> modelConfigs,
  required String? selectedModelId,
  required String? rememberedModelId,
}) {
  if (modelConfigs.isEmpty) return null;
  final conversationSelected = modelConfigs
      .where((config) => config.id == selectedModelId)
      .firstOrNull;
  if (conversationSelected != null) return conversationSelected;
  final rememberedSelected = modelConfigs
      .where((config) => config.id == rememberedModelId)
      .firstOrNull;
  if (rememberedSelected != null) return rememberedSelected;
  return modelConfigs.first;
}

String? resolveSelectedProviderId({
  required List<LlmProviderConfig> providers,
  required LlmModelConfig? selectedModel,
}) {
  if (providers.isEmpty) return null;
  if (selectedModel != null &&
      providers.any((p) => p.id == selectedModel.providerId)) {
    return selectedModel.providerId;
  }
  return providers.first.id;
}

TemplatePrompt? resolveSelectedTemplatePrompt(
  List<TemplatePrompt> templatePrompts,
  String? selectedTemplatePromptId,
) {
  if (selectedTemplatePromptId == null) return null;
  return templatePrompts
      .where((templatePrompt) => templatePrompt.id == selectedTemplatePromptId)
      .firstOrNull;
}

// ── derived provider ───────────────────────────────────────────────────────

/// workspace 的不可变只读快照；只 watch 输入并调用纯函数。
final chatWorkspaceReadModelProvider = Provider<ChatWorkspaceReadModel>((ref) {
  final conversation = ref.watch(activeChatConversationProvider);
  final isStreaming = ref.watch(isChatStreamingProvider);
  final isAutoRetryWaiting = ref.watch(
    chatSessionsProvider.select((state) => state.isAutoRetryWaiting),
  );
  final isBusy = ref.watch(isChatBusyProvider);
  final autoRetryCount = ref.watch(
    chatSessionsProvider.select((state) => state.autoRetryCount),
  );
  final errorMessage = ref.watch(chatErrorMessageProvider);
  final errorMessageAssistantId = ref.watch(
    chatErrorMessageAssistantIdProvider,
  );
  final emptyReplyAssistantId = ref.watch(
    chatSessionsProvider.select((state) => state.emptyReplyAssistantId),
  );
  final rememberedSelections = ref.watch(chatDefaultsProvider);
  final fixedPromptSequences = ref.watch(fixedPromptSequencesProvider);
  final modelProviders = ref.watch(llmProviderConfigsProvider);
  final modelConfigs = ref.watch(llmModelConfigsProvider);
  final templatePrompts = ref.watch(templatePromptsProvider);
  final activeConversationId = ref.watch(activeConversationIdProvider);
  final selectedTemplatePromptId = ref.watch(
    composerTemplateSelectionProvider(activeConversationId),
  );
  final isComposerCollapsed = ref.watch(composerCollapsedProvider);
  final favorites = ref.watch(chatFavoritesFacadeProvider).snapshot;

  final selectedModel = resolveSelectedModel(
    modelConfigs,
    conversation.selectedModelId,
    rememberedSelections.defaultModelId,
  );
  final selectableProviders = modelProviders
      .where((provider) => provider.models.isNotEmpty)
      .toList(growable: false);
  final selectedProviderId = resolveSelectedProviderId(
    selectableProviders,
    selectedModel,
  );
  final selectableModels = selectedProviderId == null
      ? const <LlmModelConfig>[]
      : modelConfigs
            .where((config) => config.providerId == selectedProviderId)
            .toList(growable: false);
  final selectedTemplatePrompt = resolveSelectedTemplatePrompt(
    templatePrompts,
    selectedTemplatePromptId,
  );
  final activeMessages = conversation.messages;
  final userMessages = activeMessages
      .where((message) => message.role == ChatMessageRole.user)
      .toList(growable: false);
  final excludedVisibleMessageCount = activeMessages
      .where((message) => conversation.isMessageExcluded(message.id))
      .length;
  final supportsReasoning = selectedModel?.supportsReasoning ?? false;

  return ChatWorkspaceReadModel(
    messages: ChatWorkspaceMessagesState(
      conversation: conversation,
      messages: List.unmodifiable(activeMessages),
      userMessages: List.unmodifiable(userMessages),
      hasModels: modelConfigs.isNotEmpty,
      isBusy: isBusy,
      errorMessage: errorMessage,
      errorMessageAssistantId: errorMessageAssistantId,
      emptyReplyAssistantId: emptyReplyAssistantId,
      errorModelDisplayName: selectedModel?.displayName ?? '模型',
      autoRetryCount: autoRetryCount,
      favoritedAssistantContents: Set.unmodifiable(
        favorites.favoritedAssistantContents,
      ),
    ),
    composer: ChatWorkspaceComposerReadModel(
      modelProviders: List.unmodifiable(selectableProviders),
      modelConfigs: List.unmodifiable(selectableModels),
      selectedProviderId: selectedProviderId,
      selectedModel: selectedModel,
      templatePrompts: List.unmodifiable(templatePrompts),
      selectedTemplatePrompt: selectedTemplatePrompt,
      fixedPromptSequences: List.unmodifiable(fixedPromptSequences),
      isComposerCollapsed: isComposerCollapsed,
      reasoningEnabled: supportsReasoning && conversation.reasoningEnabled,
      reasoningEffort: conversation.reasoningEffort,
      supportsReasoning: supportsReasoning,
      autoRetryEnabled: conversation.autoRetryEnabled,
      isBusy: isBusy,
      isStreaming: isStreaming,
      isAutoRetryWaiting: isAutoRetryWaiting,
      excludedMessageCount: excludedVisibleMessageCount,
    ),
  );
});
```

> 注意：`chatDefaultsProvider` 的 `rememberedSelections.defaultModelId` / `chatErrorMessageProvider` / `chatErrorMessageAssistantIdProvider` / `fixedPromptSequencesProvider` / `llmProviderConfigsProvider` / `llmModelConfigsProvider` / `templatePromptsProvider` / `composerCollapsedProvider` 均为既有 provider，签名与 `chat_screen.dart` 当前 watch 一致。若 `chatDefaultsProvider` 字段名不同（如 `.defaultModelId`），以 `chat_screen.dart` 现有 `rememberedSelections.defaultModelId` 为准。

- [ ] **Step 2: 实现 `chat_workspace_bindings.dart`。**

新建文件，按职责分组，不创建 50 字段垃圾袋。所有回调 typedef 直接使用既有签名（`ValueChanged<ChatMessage>`、`Future<void> Function()` 等）：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/models/chat_message.dart';

/// 消息面板的 UI 回调分组。
class ChatWorkspaceMessageBindings {
  const ChatWorkspaceMessageBindings({
    required this.onEditMessage,
    required this.onRetryLatestAssistant,
    required this.onDeleteMessage,
    required this.onToggleRequestExclusion,
    required this.onSelectMessageVersion,
    this.onFavoritePressed,
  });

  final ValueChanged<ChatMessage> onEditMessage;
  final Future<void> Function() onRetryLatestAssistant;
  final ValueChanged<ChatMessage> onDeleteMessage;
  final ValueChanged<ChatMessage> onToggleRequestExclusion;
  final Future<void> Function(String parentId, String messageId)
  onSelectMessageVersion;
  final ValueChanged<ChatMessage>? onFavoritePressed;
}

/// composer 的 UI 资源与回调分组。
class ChatWorkspaceComposerBindings {
  const ChatWorkspaceComposerBindings({
    required this.messageController,
    required this.messageFocusNode,
    required this.templateVariableControllers,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onTemplatePromptSelected,
    required this.onToggleComposerCollapsed,
    this.onReasoningEnabledChanged,
    this.onReasoningEffortChanged,
    this.onAutoRetryEnabledChanged,
    required this.onOpenFixedPromptSequenceRunner,
    required this.onOpenMessageFilter,
    this.onSendPressed,
    this.onStopStreaming,
    this.onCancelEdit,
  });

  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final Map<String, TextEditingController> templateVariableControllers;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String?> onTemplatePromptSelected;
  final VoidCallback onToggleComposerCollapsed;
  final ValueChanged<bool>? onReasoningEnabledChanged;
  final ValueChanged<ReasoningEffort>? onReasoningEffortChanged;
  final ValueChanged<bool>? onAutoRetryEnabledChanged;
  final Future<void> Function() onOpenFixedPromptSequenceRunner;
  final Future<void> Function() onOpenMessageFilter;
  final Future<void> Function()? onSendPressed;
  final Future<void> Function()? onStopStreaming;
  final VoidCallback? onCancelEdit;
}

/// 滚动/锚点的 UI 资源与回调分组。
class ChatWorkspaceScrollBindings {
  const ChatWorkspaceScrollBindings({
    required this.activeAnchorMessageIdListenable,
    required this.showScrollToBottomListenable,
    required this.messageItemScrollController,
    required this.messageItemPositionsListener,
    required this.onScrollToBottomPressed,
    required this.onSelectMessage,
  });

  final ValueListenable<String?> activeAnchorMessageIdListenable;
  final ValueListenable<bool> showScrollToBottomListenable;
  final ItemScrollController messageItemScrollController;
  final ItemPositionsListener messageItemPositionsListener;
  final VoidCallback onScrollToBottomPressed;
  final ValueChanged<String> onSelectMessage;
}

/// workspace 的 UI bindings 根；只在 presentation 组合，不持久化、不进 state。
class ChatWorkspaceBindings {
  const ChatWorkspaceBindings({
    required this.messages,
    required this.composer,
    required this.scroll,
  });

  final ChatWorkspaceMessageBindings messages;
  final ChatWorkspaceComposerBindings composer;
  final ChatWorkspaceScrollBindings scroll;
}
```

> `ReasoningEffort` 来自 `package:oh_my_llm/features/settings/domain/models/llm_model_config.dart`，需在文件顶部 import（上面已通过 `chat_message.dart` 间接引入部分，若 `ReasoningEffort` 解析不到则补 `import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';`）。

- [ ] **Step 3: 写 `chat_workspace_view_state_test.dart` 的纯 contract 红灯测试。**

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('resolveSelectedModel', () {
    test('conversation selected 优先', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: 'claude-sonnet',
        rememberedModelId: 'gpt-4.1',
      );
      expect(selected!.id, 'claude-sonnet');
    });

    test('无 conversation 选中时回退 remembered default', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: 'claude-sonnet',
      );
      expect(selected!.id, 'claude-sonnet');
    });

    test('无 remembered 时回退首模型', () {
      final selected = resolveSelectedModel(
        modelConfigs: [TestFixtures.gpt41(), TestFixtures.claudeSonnet()],
        selectedModelId: null,
        rememberedModelId: null,
      );
      expect(selected!.id, 'gpt-4.1');
    });

    test('空列表返回 null', () {
      expect(
        resolveSelectedModel(
          modelConfigs: const [],
          selectedModelId: null,
          rememberedModelId: null,
        ),
        isNull,
      );
    });
  });

  test('view-state compose 的 messages state 与 base read-model 相同', () {
    // 构造一个最小 read-model，编辑 overlay 不改 messages。
    // 完整构造需真实 conversation/messages；此处断言 compose 把 readModel.messages
    // 原样透传，composer 替换 selectedTemplatePrompt 与 isEditingMessage。
  });
}
```

> 说明：`chat_workspace_view_state_test.dart` 的完整 read-model 构造需要真实 `ChatConversation`/消息及 Facade snapshot 的 fixture，工作量大。建议除 resolver 纯函数（上面已给）外，补一个「streaming projection」与「immutability」测试：用 `TestFixtures` 构造会话与消息，先手动组装 `ChatFavoritesSnapshot`，构造 `ChatWorkspaceReadModel`，断言 `compose` 透传 messages、且 `editingDraft` 覆盖 `selectedTemplatePrompt` 时 readModel.composer 不变。若 `TestFixtures` 暂缺生成的 fixture，可在此 task 先用 resolver 单测覆盖纯逻辑，把 view-state compose 的透传断言放到 favorites/streaming 集成层（Task 4）。实施时优先保证 resolver fallback 四分支 + preset null/sentinel/missing 四分支已覆盖。

- [ ] **Step 4: 迁移 `ChatWorkspace` / `ChatMessagesPanel` / `ChatComposerCard`。**

1. 重写 `chat_workspace.dart` 构造器为 `state` + `bindings`，删除全部旧参数：

```dart
import 'package:flutter/material.dart';

import 'chat_composer_card.dart';
import 'chat_messages_panel.dart';
import 'chat_workspace_bindings.dart';
import 'chat_workspace_view_state.dart';

/// 聊天页主工作区，组合消息列表、锚点条和消息输入区。
class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({
    required this.state,
    required this.bindings,
    super.key,
  });

  final ChatWorkspaceViewState state;
  final ChatWorkspaceBindings bindings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ChatMessagesPanel(
            conversation: state.messages.conversation,
            messages: state.messages.messages,
            userMessages: state.messages.userMessages,
            hasModels: state.messages.hasModels,
            activeAnchorMessageIdListenable:
                bindings.scroll.activeAnchorMessageIdListenable,
            messageItemScrollController:
                bindings.scroll.messageItemScrollController,
            messageItemPositionsListener:
                bindings.scroll.messageItemPositionsListener,
            isBusy: state.messages.isBusy,
            errorMessage: state.messages.errorMessage,
            errorMessageAssistantId: state.messages.errorMessageAssistantId,
            emptyReplyAssistantId: state.messages.emptyReplyAssistantId,
            errorModelDisplayName: state.messages.errorModelDisplayName,
            showScrollToBottomListenable:
                bindings.scroll.showScrollToBottomListenable,
            autoRetryCount: state.messages.autoRetryCount,
            onEditMessage: bindings.messages.onEditMessage,
            onRetryLatestAssistant: bindings.messages.onRetryLatestAssistant,
            onDeleteMessage: bindings.messages.onDeleteMessage,
            onToggleRequestExclusion:
                bindings.messages.onToggleRequestExclusion,
            onScrollToBottomPressed: bindings.scroll.onScrollToBottomPressed,
            onSelectMessage: bindings.scroll.onSelectMessage,
            onSelectMessageVersion: bindings.messages.onSelectMessageVersion,
            onFavoritePressed: bindings.messages.onFavoritePressed,
            favoritedAssistantContents:
                state.messages.favoritedAssistantContents,
          ),
        ),
        SizedBox(height: AppBreakpoints.isCompact(context) ? 8 : 12),
        ChatComposerCard(
          state: state.composer,
          bindings: bindings.composer,
        ),
      ],
    );
  }
}
```

`ChatComposerCard` 在本 Task 一次到位改为收 `ChatWorkspaceComposerState` + `ChatWorkspaceComposerBindings`，并删除 `composer_data.dart`（`ComposerData`/`ComposerCallbacks` 不再存在，不得两套并存），与下方提交清单中 `composer_data.dart` 的删除一致。

1. 重写 `chat_composer_card.dart` 构造器为 `state` + `bindings`，内部把 `state.composer` 字段替换原 `data.*`，把 `bindings.composer.*` 替换原 `callbacks.*`，UI/动画/文案逻辑原样保留（`AnimatedCrossFade`、`compactComposerBreakpoint`、`isCompactComposer`、按钮 disable、快捷键等）。构造参数改为：

```dart
const ChatComposerCard({
  required this.state,
  required this.bindings,
  super.key,
});

final ChatWorkspaceComposerState state;
final ChatWorkspaceComposerBindings bindings;
```

3. `chat_messages_panel.dart` 保持现有构造器不变（它本就不依赖 `ComposerData`）；`ChatMessagesPanel` 仍接收展平的 `conversation/messages/...` 与 callbacks，由 `ChatWorkspace` 从 `state.messages` + `bindings.messages/scroll` 注入。若实施中把 `ChatMessagesPanel` 也改为收 `ChatWorkspaceMessagesState` + bindings，二者等价，但不得让叶 widget watch 页面级 Provider。

4. 更新 `widgets.dart` barrel：export `chat_workspace_bindings.dart` 与 `chat_workspace_view_state.dart`（若 Screen 经 barrel 使用），删除 `composer_data.dart` 的 export。

- [ ] **Step 5: 收缩 `ChatScreen` build/body。**

在 `_ChatScreenState` 中：

1. `build` 读取 read-model，用本地 edit state 经纯 factory 生成 effective view-state，再创建一次 bindings：

```dart
@override
Widget build(BuildContext context) {
  final readModel = ref.watch(chatWorkspaceReadModelProvider);
  final conversation = readModel.messages.conversation;
  final activeConversationId = ref.watch(activeConversationIdProvider);
  final editingDraft = _editingMessageId == null
      ? ComposerDraft.empty
      : (_editingDraft ?? ComposerDraft.empty);
  final workspaceState = ChatWorkspaceViewState.compose(
    readModel: readModel,
    editingDraft: editingDraft,
    isEditingMessage: _editingMessageId != null,
    templatePrompts: readModel.composer.templatePrompts,
  );
  final workspaceBindings = _buildWorkspaceBindings(
    conversation: conversation,
    readModel: readModel,
  );
  // ... 其余 sidebar/history shell state 与 AppShellScaffold 不变
}
```

> 注意：`ChatWorkspaceViewState.compose` 的 `editingDraft` 参数在编辑未开始时传 `ComposerDraft.empty`；`_editingDraft`（页面本地）在 Task 3 才引入，此 task 先传 `ComposerDraft.empty` 并让 `isEditingMessage` 基于 `_editingMessageId != null`。Task 3 再替换为真实 `_editingDraft`。

2. 新增 `_buildWorkspaceBindings`，把原来散落在 `_buildWorkspace` 里的 closure 归拢到三个分组（`onRetryLatestAssistant`/`onDeleteMessage`/`onToggleRequestExclusion`/`onSelectMessageVersion`/`onStopStreaming`/`onCancelEdit`/`onToggleComposerCollapsed`/`onOpenFixedPromptSequenceRunner`/`onOpenMessageFilter`/fav 等，逻辑与现状一致，仅按分组放置）。`onSendPressed`/`onProviderSelected`/`onModelSelected`/`onTemplatePromptSelected`/reasoning/auto-retry 在 Task 3 才改走 `ChatComposerCommand`，此 task 先保持现状逻辑。

3. 删除 `_buildWorkspace`；`_buildBody` 只接收 `sidebarState`、history summaries/active ID/draft/busy 与 `workspaceState`/`workspaceBindings`。若参数仍超 8 个，新增只含 history/sidebar 值的 `ChatScreenPanelsState`，不塞进 workspace。`_buildBody` 的 LayoutBuilder、`AppBreakpoints.compact`、padding 与 side panel show/hide 逻辑原样保留。

4. `ChatScreen` 仍负责 AppShellScaffold、dialogs、focus/scroll、page edit state；不要把 `_editingMessageId` 写进 application Provider。

- [ ] **Step 6: 运行 workspace/composer 回归。**

```powershell
flutter test test/features/chat/application/chat_workspace_view_state_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-workspace-state.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-workspace-state.log
flutter test test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-workspace-widget.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-workspace-widget.log
```

Expected: 两条 `EXIT=0`。

- [ ] **Step 7: 格式化并提交。**

```bash
dart format lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_workspace_bindings.dart lib/features/chat/presentation/widgets/chat_workspace.dart lib/features/chat/presentation/widgets/chat_messages_panel.dart lib/features/chat/presentation/widgets/chat_composer_card.dart lib/features/chat/presentation/widgets/composer_data.dart lib/features/chat/presentation/widgets/widgets.dart test/features/chat/application/chat_workspace_view_state_test.dart test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_basics_cases.dart test/features/chat/chat_screen/chat_screen_branching_cases.dart test/features/chat/chat_screen/chat_screen_favorites_cases.dart test/features/chat/chat_screen/chat_screen_streaming_cases.dart test/features/chat/chat_screen/chat_screen_test_helpers.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git add lib/features/chat/application/chat_workspace_view_state.dart \
        lib/features/chat/presentation/chat_screen.dart \
        lib/features/chat/presentation/widgets/chat_workspace_bindings.dart \
        lib/features/chat/presentation/widgets/chat_workspace.dart \
        lib/features/chat/presentation/widgets/chat_messages_panel.dart \
        lib/features/chat/presentation/widgets/chat_composer_card.dart \
        lib/features/chat/presentation/widgets/composer_data.dart \
        lib/features/chat/presentation/widgets/widgets.dart \
        test/features/chat/application/chat_workspace_view_state_test.dart \
        test/features/chat/chat_screen_test.dart \
        test/features/chat/chat_screen/chat_screen_basics_cases.dart \
        test/features/chat/chat_screen/chat_screen_branching_cases.dart \
        test/features/chat/chat_screen/chat_screen_favorites_cases.dart \
        test/features/chat/chat_screen/chat_screen_streaming_cases.dart \
        test/features/chat/chat_screen/chat_screen_test_helpers.dart \
        test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git commit -m "refactor(chat): 收敛工作区视图绑定"
```

---

## Task 3: 把 composer 提交与编辑事务移到明确 command

**Files:**
- Add: `lib/features/chat/application/chat_composer_command.dart`
- Add: `test/features/chat/application/chat_composer_command_test.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `lib/features/chat/application/composer_draft_controller.dart`（如需补充 `ChatDirectSubmitIntent` 用的只读取值，不加）
- Modify: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`
- Modify: branching/basics cases only where behavior is covered

**Interfaces produced (later tasks rely on these):**
- `class ChatComposerSubmitIntent` — `conversationId`, `body`, `templatePrompt`, `variableValues`, `selectedModel`, `selectedPresetPrompt`, `reasoningEnabled`, `reasoningEffort`, `editingMessageId`.
- `sealed class ChatComposerDispatchResult`; `class ChatComposerRejected(reason)`; `enum ChatComposerRejectReason { empty, noModel, busy, staleConversation }`; `class ChatComposerAccepted({completion, wasEdit})`.
- `class ChatComposerCommand` — `dispatch(intent)`, `selectProvider(providerId)`, `selectModel(modelId)`, `selectPreset(presetPromptId)`, `selectTemplate(conversationId, templatePromptId)`, `setReasoningEnabled(bool)`, `setReasoningEffort(ReasoningEffort)`, `setAutoRetryEnabled(bool)`, `createConversationAndResetDraft()`.
- `final chatComposerCommandProvider = Provider<ChatComposerCommand>`.
- `class ChatDirectSubmitIntent`（或等价明确类型）供 fixed-sequence `sendStep` 复用 dispatch 引擎。

- [ ] **Step 1: 实现 `chat_composer_command.dart`。**

新建文件。这是现有 command 的薄编排层，不是新 session/generation controller。`dispatch` 同步校验并返回 accepted（含已启动的 completion Future），不清 controller、不持有 generation handle：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import 'package:oh_my_llm/features/settings/domain/models/preset_prompt.dart';
import 'package:oh_my_llm/features/settings/domain/models/template_prompt.dart';
import 'package:oh_my_llm/features/settings/application/chat_defaults_controller.dart';
import '../domain/models/chat_conversation.dart';
import 'chat_sessions_controller.dart';
import 'composer_draft_controller.dart';
import 'templated_user_message_builder.dart';

/// 用户点发送/提交编辑时携带的不可变输入。
class ChatComposerSubmitIntent {
  const ChatComposerSubmitIntent({
    required this.conversationId,
    required this.body,
    this.templatePrompt,
    this.variableValues = const {},
    required this.selectedModel,
    this.selectedPresetPrompt,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    this.editingMessageId,
  });

  final String conversationId;
  final String body;
  final TemplatePrompt? templatePrompt;
  final Map<String, String> variableValues;
  final LlmModelConfig? selectedModel;
  final PresetPrompt? selectedPresetPrompt;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  /// 非 null 表示编辑既有 user message。
  final String? editingMessageId;
}

/// dispatch 的同步结果：拒绝或已启动。
sealed class ChatComposerDispatchResult {
  const ChatComposerDispatchResult();
}

enum ChatComposerRejectReason { empty, noModel, busy, staleConversation }

class ChatComposerRejected extends ChatComposerDispatchResult {
  const ChatComposerRejected(this.reason);
  final ChatComposerRejectReason reason;
}

class ChatComposerAccepted extends ChatComposerDispatchResult {
  const ChatComposerAccepted({
    required this.completion,
    required this.wasEdit,
  });

  /// 已启动的 generation Future；dispatch 在它能完成前同步返回。
  final Future<void> completion;
  final bool wasEdit;
}

/// fixed-sequence sendStep 的直接提交输入（无模板/segments 元数据）。
class ChatDirectSubmitIntent {
  const ChatDirectSubmitIntent({
    required this.conversationId,
    required this.content,
    required this.selectedModel,
    this.selectedPresetPrompt,
    required this.reasoningEnabled,
    required this.reasoningEffort,
  });

  final String conversationId;
  final String content;
  final LlmModelConfig? selectedModel;
  final PresetPrompt? selectedPresetPrompt;
  final bool reasoningEnabled;
  final ReasoningEffort reasoningEffort;
}

/// composer 的薄编排层：把 Screen 原先两三行的编排收拢，
/// 统一校验、模板拼接、draft 提交语义与 Phase 9 facade 调用。
class ChatComposerCommand {
  ChatComposerCommand(this._ref);
  final Ref _ref;

  /// 校验并启动发送/编辑。accepted 返回已启动 completion，不等待其完成。
  ChatComposerDispatchResult dispatch(ChatComposerSubmitIntent intent) {
    final conversation = _ref.read(activeChatConversationProvider);
    if (conversation.id != intent.conversationId) {
      return const ChatComposerRejected(
        ChatComposerRejectReason.staleConversation,
      );
    }
    if (_ref.read(isChatBusyProvider)) {
      return const ChatComposerRejected(ChatComposerRejectReason.busy);
    }
    if (intent.selectedModel == null) {
      return const ChatComposerRejected(ChatComposerRejectReason.noModel);
    }

    // 只调用一次模板拼接；Screen/command 不得分别解析造成不一致。
    final templated = buildTemplatedUserMessage(
      body: intent.body,
      templatePrompt: intent.templatePrompt,
      variableValues: intent.variableValues,
    );
    if (templated.content.trim().isEmpty) {
      return const ChatComposerRejected(ChatComposerRejectReason.empty);
    }

    final editingMessageId = intent.editingMessageId;
    final wasEdit = editingMessageId != null;
    final Future<void> completion;
    if (wasEdit) {
      completion = _ref.read(chatSessionsProvider.notifier).editMessage(
        messageId: editingMessageId,
        nextContent: templated.content,
        userMessageSegments: templated.userMessageSegments,
        templatePromptId: intent.templatePrompt?.id,
        templateVariableValues: intent.variableValues,
      );
    } else {
      completion = _ref.read(chatSessionsProvider.notifier).sendMessage(
        content: templated.content,
        userMessageSegments: templated.userMessageSegments,
        modelConfig: intent.selectedModel!,
        presetPrompt: intent.selectedPresetPrompt,
        reasoningEnabled: intent.reasoningEnabled,
        reasoningEffort: intent.reasoningEffort,
        templatePromptId: intent.templatePrompt?.id,
        templateVariableValues: intent.variableValues,
      );
    }

    // accepted 后立即把目标 draft 更新为「body 空、保留本次 template/variables」。
    _ref.read(composerDraftProvider.notifier).clearBody(intent.conversationId);
    return ChatComposerAccepted(completion: completion, wasEdit: wasEdit);
  }

  /// fixed-sequence sendStep：直接发送步骤文本，不消费普通 composer draft。
  Future<void> dispatchDirect(ChatDirectSubmitIntent intent) async {
    final conversation = _ref.read(activeChatConversationProvider);
    if (conversation.id != intent.conversationId) return;
    if (_ref.read(isChatBusyProvider)) return;
    final model = intent.selectedModel;
    if (model == null) return;
    final trimmedContent = intent.content.trim();
    if (trimmedContent.isEmpty) return;
    await _ref.read(chatSessionsProvider.notifier).sendMessage(
      content: trimmedContent,
      modelConfig: model,
      presetPrompt: intent.selectedPresetPrompt,
      reasoningEnabled: intent.reasoningEnabled,
      reasoningEffort: intent.reasoningEffort,
    );
  }

  // ── composer toolbar 方法 ────────────────────────────────────────────────

  /// 选择模型：更新当前会话并记住为默认。
  void selectModel(String modelId) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(selectedModelId: modelId);
    _ref.read(chatDefaultsProvider.notifier).rememberModelId(modelId);
  }

  /// 选择 provider：选该 provider 第一个有效模型；无模型时 no-op。
  void selectProvider(String providerId) {
    final providers = _ref.read(llmProviderConfigsProvider);
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    final targetModelId = provider?.models.firstOrNull?.id;
    if (targetModelId == null) return;
    selectModel(targetModelId);
  }

  /// 选择预设 Prompt：只更新 conversation，不擅自新增 remember-default 行为。
  void selectPreset(String presetPromptId) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(
          selectedPresetPromptId: presetPromptId ?? noPresetPromptSelectedId,
        );
  }

  /// 选择模板：只更新目标 conversation 的内存 draft。
  void selectTemplate(String conversationId, String? templatePromptId) {
    _ref
        .read(composerDraftProvider.notifier)
        .selectTemplate(conversationId, templatePromptId);
  }

  void setReasoningEnabled(bool value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(reasoningEnabled: value);
  }

  void setReasoningEffort(ReasoningEffort value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(reasoningEffort: value);
  }

  void setAutoRetryEnabled(bool value) {
    _ref
        .read(chatSessionsProvider.notifier)
        .updateActiveConversationPreferences(autoRetryEnabled: value);
  }

  /// 调用现有 create command，读取调用后的 active ID，只清该 active draft。
  /// 无消息导致 controller 未新建会话时，仍清当前 active（空输入区）draft。
  Future<void> createConversationAndResetDraft() async {
    await _ref.read(chatSessionsProvider.notifier).createConversation();
    final activeId = _ref.read(activeConversationIdProvider);
    _ref.read(composerDraftProvider.notifier).clearDraft(activeId);
  }
}

/// composer 命令的 provider。
final chatComposerCommandProvider = Provider<ChatComposerCommand>((ref) {
  return ChatComposerCommand(ref);
});
```

> 注意：命令内 `RewardEffort`/`llmProviderConfigsProvider`/`llmModelConfigsProvider` 需顶部 import（上面缺 `llm_provider_configs_controller.dart` 与 `llm_model_configs_controller.dart`，实施时补）。`dispatch` 里 `selectedModel!` 在 `null` 已提前 reject 后安全；若想避免 `!`，在校验处用局部变量。`selectPreset` 的 `presetPromptId` 参数类型应为 `String?`（`noPresetPromptSelectedId` 是 `const String`），若调用方传 nullable，签名改为 `selectPreset(String? presetPromptId)`。

- [ ] **Step 2: 写 `chat_composer_command_test.dart`。**

command 单测需要一个可读 `chatSessionsProvider`/`composerDraftProvider`/`chatDefaultsProvider`/`isChatBusyProvider` 的 `ProviderContainer`，并 override `chatConversationRepositoryProvider` 与 `chatCompletionClientProvider`（用 `FakeChatCompletionClient`）。用 `pumpTestApp` 的 overrides 模式构造 container，或复用 `test_harness`。核心断言：

```dart
test('normal accepted 返回 completion，draft body 清空、template/variables 保留', () async {
  // 用 ProviderContainer + overrides 初始化一个 active conversation。
  // intent: body='你好', templatePrompt=null, selectedModel=gpt41, reasoningEnabled=false。
  final command = container.read(chatComposerCommandProvider);
  final result = command.dispatch(intent);
  expect(result, isA<ChatComposerAccepted>());
  final accepted = result as ChatComposerAccepted;
  expect(accepted.wasEdit, isFalse);
  // draft body 已清空，selection/variables 保留。
  expect(container.read(composerDraftProvider.notifier).draftFor('conv-a').body, '');
  // completion 完成后产生一次 user 路径一次 client request。
  await accepted.completion;
  expect(fakeClient.requestHistory, hasLength(1));
});

test('empty/no model/busy/stale 返回 typed rejected，draft 不变', () {
  // 分别构造空 body、null model、busy、staleConversationId 的 intent，
  // 断言返回对应 ChatComposerRejectedReason，且 requestHistory 为空、draft 未变。
});

test('edit accepted 调 editMessage 不调 sendMessage，draft 提交后按规则', () {
  // editingMessageId 非 null：断言走 editMessage 分支（新分支产生），
  // 不额外产生 user 路径；draft body 清空保留 template/variables。
});

test('selectProvider 无模型 no-op，有模型选 first；selectPreset 不写 template/default', () {
  // 断言 updateActiveConversationPreferences 的 selectedPresetPromptId 被写，
  // 且 composerTemplateSelectionProvider 不变、chatDefaultsProvider 不变。
});

test('createConversationAndResetDraft 清 active draft', () async {
  // 非空会话：createConversation 新建会话并清空 active draft。
  // 空会话（无消息）：不新建第二个 conversation，但清空当前 active draft。
});
```

> 说明：command 单测需要真实 `ChatSessionsController` 依赖（repository/client），构造成本高。**推荐**：用 `test_helpers/test_harness.dart` 的 `pumpTestApp` 或直接 `ProviderContainer` + `appCompositionOverrides` + repository/client fake 初始化一个含单会话的 container，再调 command。若隔离成本过高，退而求其次：把 dispatch 的「校验 + 拼接 + 提交」拆成可注入的纯函数并对纯函数单测，command 只留薄分发；实施时以能稳定断言 reject/accept 与 draft 提交为准，不强行 mock Riverpod。

- [ ] **Step 3: 实现本地 editing draft（Task 1 的兼容 wrapper 升级为隔离）。**

在 `_ChatScreenState`：

1. 删除 `_ComposerSnapshot`（bodyText/templatePromptId/templateVariableValues/isComposerCollapsed 的旧结构），改为页面私有 `_EditSnapshot`（`ComposerDraft draft` + `bool preEditCollapsed`），或直接用两个字段：`ComposerDraft? _preEditDraft;` + `bool _preEditCollapsed = false;`。**绝不把 collapsed 字段加进会话级 `ComposerDraft`**。
2. 新增 `ComposerDraft? _editingDraft;`。`_editingMessageId != null` 是唯一路径开关。
3. 重写进入编辑 `_enterEditMode`：

```dart
void _enterEditMode(ChatMessage message) {
  final conversation = ref.read(activeChatConversationProvider);
  final currentDraft = ref.read(composerDraftProvider.notifier).draftFor(conversation.id);
  setState(() {
    _preEditDraft = currentDraft;
    _preEditCollapsed = ref.read(composerCollapsedProvider);
    _editingMessageId = message.id;
    _editingDraft = _buildEditingDraft(message, currentDraft);
  });
  _applyDraftToControllers(_editingDraft ?? ComposerDraft.empty);
  _messageFocusNode.requestFocus();
}
```

`_buildEditingDraft` 从目标 user message 的 segments/template 构造 `ComposerDraft`：

```dart
ComposerDraft _buildEditingDraft(ChatMessage message, ComposerDraft currentDraft) {
  final segments = message.userMessageSegments;
  final bodyText = segments.isNotEmpty
      ? segments.where((s) => s.kind == UserMessageSegmentKind.body).map((s) => s.text).join()
      : message.content;
  final templateVariables = <String, Map<String, String>>{};
  final templateId = message.templatePromptId;
  if (templateId != null && message.templateVariableValues.isNotEmpty) {
    templateVariables[templateId] = Map.unmodifiable(message.templateVariableValues);
  }
  return ComposerDraft(
    body: bodyText,
    selectedTemplatePromptId: templateId,
    templateVariableValuesByTemplateId: templateVariables,
  );
}
```

4. 所有 body/template/variable change 走同一个 page handler：normal 时写 `ComposerDraftController`，editing 时 `setState` 更新 `_editingDraft`；禁止 listener 同时写两边。

```dart
void _onBodyChanged() {
  if (_isApplyingComposerDraft) return;
  if (_editingMessageId != null) {
    setState(() {
      _editingDraft = (_editingDraft ?? ComposerDraft.empty)
          .copyWith(body: _messageController.text);
    });
    return;
  }
  final conversationId = _activeConversationIdOrNull();
  if (conversationId == null) return;
  ref.read(composerDraftProvider.notifier).setBody(conversationId, _messageController.text);
}
```

5. 取消编辑 `_cancelEditMode`：丢弃 local editing state，把 `_preEditDraft` 投影回 controllers；normal draft 从未被覆盖，故不执行恢复写回。collapsed 用 `_preEditCollapsed` 恢复：

```dart
void _cancelEditMode() {
  final preEditDraft = _preEditDraft;
  setState(() {
    _editingMessageId = null;
    _editingDraft = null;
    _preEditDraft = null;
  });
  if (preEditDraft != null) {
    _applyDraftToControllers(preEditDraft);
  }
  ref
      .read(composerCollapsedProvider.notifier)
      .setCollapsed(_preEditCollapsed);
  _preEditCollapsed = false;
}
```

6. 会话切换 / 页面销毁时丢弃编辑事务。会话切换监听回调里在投影新会话 draft 前清空 `_editingMessageId`/`_editingDraft`/`_preEditDraft`：

```dart
ref.listenManual<String>(activeConversationIdProvider, (prev, next) {
  if (next == null) return;
  // 切换会话即丢弃编辑事务，旧会话 session draft 保持原值。
  setState(() {
    _editingMessageId = null;
    _editingDraft = null;
    _preEditDraft = null;
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final currentId = ref.read(activeConversationIdProvider);
    if (currentId != next) return;
    _applyDraftToControllers(ref.read(composerDraftProvider.notifier).draftFor(next));
  });
}, fireImmediately: true);
```

7. 发送点击 `onSendPressed` 构造 intent，调用 command；只有 accepted 才清 UI controller、退出编辑并 await completion；rejected 原样保留：

```dart
Future<void> _handleSendPressed(ChatWorkspaceComposerState composer) async {
  final conversation = ref.read(activeChatConversationProvider);
  final editingDraft = _editingMessageId != null ? (_editingDraft ?? ComposerDraft.empty) : null;
  final intent = ChatComposerSubmitIntent(
    conversationId: conversation.id,
    body: editingDraft?.body ?? _messageController.text,
    templatePrompt: editingDraft != null
        ? resolveSelectedTemplatePrompt(composer.templatePrompts, editingDraft.selectedTemplatePromptId)
        : composer.selectedTemplatePrompt,
    variableValues: editingDraft != null
        ? _resolveTemplatePromptValues(editingDraft)
        : _resolveTemplatePromptValues(composer.selectedTemplatePrompt),
    selectedModel: composer.selectedModel,
    selectedPresetPrompt: _resolveSelectedPresetPrompt(ref.read(presetPromptsProvider), conversation),
    reasoningEnabled: composer.reasoningEnabled,
    reasoningEffort: composer.reasoningEffort,
    editingMessageId: _editingMessageId,
  );
  final result = ref.read(chatComposerCommandProvider).dispatch(intent);
  if (result is ChatComposerAccepted) {
    _messageController.clear();
    if (result.wasEdit) {
      setState(() { _editingMessageId = null; _editingDraft = null; _preEditDraft = null; });
    }
    await result.completion;
  }
  // rejected：输入内容与 edit banner 保留，不假装发送成功。
}
```

8. fixed sequence `fillComposer` 走 normal body change handler；`sendStep` 用 `dispatchDirect`，content 为步骤文本、segments/template 为空，model/preset/reasoning 来自当前 workspace 快照。保留当前行为：若普通正文草稿 trim 后恰好等于步骤 content 才清该正文；否则步骤直接发送时原普通草稿完整保留。

```dart
case FixedPromptSequenceRunnerAction.sendStep:
  final composer = _lastComposerState; // 或从 read-model 取
  if (_messageController.text.trim() == result.content.trim()) {
    _messageController.clear();
  }
  await ref.read(chatComposerCommandProvider).dispatchDirect(
    ChatDirectSubmitIntent(
      conversationId: ref.read(activeConversationIdProvider),
      content: result.content,
      selectedModel: composer.selectedModel,
      selectedPresetPrompt: /* 当前 preset */ null,
      reasoningEnabled: composer.reasoningEnabled,
      reasoningEffort: composer.reasoningEffort,
    ),
  );
```

> 说明：`_resolveSelectedPresetPrompt` 现只读 conversation 字段（Task 1 已改）。`_resolveTemplatePromptValues` 演变为从 `ComposerDraft` 取值（body 用 controller 或 draft.body，模板变量用 draft 的 map，trim 后空则用 template default）。此 helper 在 Task 4 删除时一并清理。

- [ ] **Step 4: 迁移 composer toolbar callbacks。**

`onProviderSelected`/`onModelSelected`/`onTemplatePromptSelected`/preset panel/reasoning/effort/auto-retry/create conversation 改调用 `ChatComposerCommand` 的命名方法：

```dart
// 在 bindings 构造处：
onProviderSelected: (id) => ref.read(chatComposerCommandProvider).selectProvider(id),
onModelSelected: (id) => ref.read(chatComposerCommandProvider).selectModel(id),
onTemplatePromptSelected: (id) {
  final conversationId = ref.read(activeConversationIdProvider);
  ref.read(chatComposerCommandProvider).selectTemplate(conversationId, id);
  _syncTemplateVariableControllers(
    resolveSelectedTemplatePrompt(readModel.composer.templatePrompts, id),
    draft: ref.read(composerDraftProvider.notifier).draftFor(conversationId),
  );
},
onReasoningEnabledChanged: supportsReasoning ? (v) => cmd.setReasoningEnabled(v) : null,
onReasoningEffortChanged: supportsReasoning ? (v) => cmd.setReasoningEffort(v) : null,
onAutoRetryEnabledChanged: (v) => cmd.setAutoRetryEnabled(v),
```

`_createConversationAndScroll` 改为调用 `chatComposerCommandProvider.createConversationAndResetDraft()`，其后仍清空 controller 并滚动到底部。Screen 可在命令后处理 focus/scroll/controller，但不能再直接组合两个业务 Provider 写入。

- [ ] **Step 5: 运行定向回归。**

```powershell
flutter test test/features/chat/application/chat_composer_command_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-composer-command.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-composer-command.log
flutter test test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-composer-widget.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-composer-widget.log
flutter test test/features/chat/application/chat_sessions_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-sessions-regression.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-sessions-regression.log
```

Expected: 三条 `EXIT=0`。

- [ ] **Step 6: 格式化并提交。**

```bash
dart format lib/features/chat/application/chat_composer_command.dart lib/features/chat/application/composer_draft_controller.dart lib/features/chat/presentation/chat_screen.dart test/features/chat/application/chat_composer_command_test.dart test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_basics_cases.dart test/features/chat/chat_screen/chat_screen_branching_cases.dart test/features/chat/chat_screen/chat_screen_test_helpers.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git add lib/features/chat/application/chat_composer_command.dart \
        lib/features/chat/application/composer_draft_controller.dart \
        lib/features/chat/presentation/chat_screen.dart \
        test/features/chat/application/chat_composer_command_test.dart \
        test/features/chat/chat_screen_test.dart \
        test/features/chat/chat_screen/chat_screen_basics_cases.dart \
        test/features/chat/chat_screen/chat_screen_branching_cases.dart \
        test/features/chat/chat_screen/chat_screen_test_helpers.dart \
        test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git commit -m "refactor(chat): 收敛输入与编辑命令"
```

---

## Task 4: 迁移 favorites、stop/retry 与撤销 intent，完成 Screen 编排收缩

**Files:**
- Add: `lib/features/chat/application/chat_favorite_intent_command.dart`
- Add: `test/features/chat/application/chat_favorite_intent_command_test.dart`
- Modify: `lib/features/chat/application/chat_favorites_facade.dart`（仅 `ChatFavoriteDraft.copyWithCollectionId`）
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_workspace_bindings.dart`（如需要）
- Modify: favorites/streaming/branching widget cases and existing Chat/Favorites integration only as needed
- `lib/app/composition/cross_feature_bindings.dart` only for additive signature compile adaptation

**Interfaces produced:**
- `sealed class ChatFavoriteIntentResult`; `class ChatFavoriteRemoved(removedEntry)`; `class ChatFavoriteNeedsCollection({draftWithoutCollection, collectionOptions})`.
- `class ChatFavoriteIntentCommand` — `beginToggle({conversation, assistantMessage})`, `addToCollection(draft, collectionId)`, `restore(entry)`, `createCollection(name)`.
- `final chatFavoriteIntentCommandProvider = Provider<ChatFavoriteIntentCommand>`（依赖 `chatFavoritesFacadeProvider`）。
- `ChatFavoriteDraft.copyWithCollectionId(String? collectionId)`（additive）。

- [ ] **Step 1: 给 `ChatFavoriteDraft` 补 `copyWithCollectionId`。**

在 `chat_favorites_facade.dart` 的 `ChatFavoriteDraft` 内新增追加方法（additive，不改既有字段与 provider binding）：

```dart
/// 复制并替换 collectionId（'' 已在调用方归一为 null 前透传）。
ChatFavoriteDraft copyWithCollectionId(String? collectionId) {
  return ChatFavoriteDraft(
    userMessageContent: userMessageContent,
    assistantContent: assistantContent,
    assistantReasoningContent: assistantReasoningContent,
    assistantModelDisplayName: assistantModelDisplayName,
    collectionId: collectionId,
    sourceAssistantMessageId: sourceAssistantMessageId,
    sourceConversationId: sourceConversationId,
    sourceConversationTitle: sourceConversationTitle,
  );
}
```

- [ ] **Step 2: 实现 `chat_favorite_intent_command.dart`。**

新建文件，只依赖 Chat domain + `ChatFavoritesFacade`，不 import `features/favorites/**`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';
import 'chat_favorites_facade.dart';

/// favorite toggle 的同步结果。
sealed class ChatFavoriteIntentResult {
  const ChatFavoriteIntentResult();
}

/// 已存在收藏：已调用 remove，可 restore。
class ChatFavoriteRemoved extends ChatFavoriteIntentResult {
  const ChatFavoriteRemoved(this.removedEntry);
  final ChatFavoriteEntry removedEntry;
}

/// 无收藏：返回待新增 draft 与 collection 选项，尚未 mutation。
class ChatFavoriteNeedsCollection extends ChatFavoriteIntentResult {
  const ChatFavoriteNeedsCollection({
    required this.draftWithoutCollection,
    required this.collectionOptions,
  });
  final ChatFavoriteDraft draftWithoutCollection;
  final List<ChatFavoriteCollectionOption> collectionOptions;
}

/// 收藏 intent 的薄编排：准备/移除/恢复/新增，都经 [ChatFavoritesFacade]。
class ChatFavoriteIntentCommand {
  ChatFavoriteIntentCommand(this._facade);
  final ChatFavoritesFacade _facade;

  ChatFavoriteIntentResult beginToggle({
    required ChatConversation conversation,
    required ChatMessage assistantMessage,
  }) {
    final snapshot = _facade.snapshot;
    final existing = snapshot.findByAssistantContent(assistantMessage.content);
    if (existing != null) {
      _facade.remove(existing.id);
      return ChatFavoriteRemoved(existing);
    }

    final draft = ChatFavoriteDraft(
      userMessageContent: _resolveUserContent(conversation, assistantMessage),
      assistantContent: assistantMessage.content,
      assistantReasoningContent: assistantMessage.reasoningContent,
      assistantModelDisplayName: assistantMessage.resolvedAssistantModelDisplayName,
      collectionId: null,
      sourceAssistantMessageId: assistantMessage.id,
      sourceConversationId: conversation.id,
      sourceConversationTitle: conversation.resolvedTitle,
    );
    return ChatFavoriteNeedsCollection(
      draftWithoutCollection: draft,
      collectionOptions: snapshot.collections,
    );
  }

  void addToCollection(ChatFavoriteDraft draft, String selectedCollectionId) {
    // '' 表示未分类 -> null。
    final normalized = selectedCollectionId.isEmpty ? null : selectedCollectionId;
    _facade.add(draft.copyWithCollectionId(normalized));
  }

  void restore(ChatFavoriteEntry entry) => _facade.add(entry.draft);

  String createCollection(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '收藏夹名称不能为空');
    }
    return _facade.createCollection(trimmed);
  }

  /// 在 assistant 之前反向找最近 user；前缀非空但无 user 回退前缀第一条；
  /// assistant 位于索引 0 或不存在时为 null。既有产品行为，本 Phase 不重新定义。
  String _resolveUserContent(
    ChatConversation conversation,
    ChatMessage assistantMessage,
  ) {
    final messages = conversation.messages;
    final assistantIndex = messages.indexWhere(
      (m) => m.id == assistantMessage.id,
    );
    if (assistantIndex <= 0) return '';
    final prefix = messages.sublist(0, assistantIndex);
    final userMessage = prefix.lastWhere(
      (m) => m.role == ChatMessageRole.user,
      orElse: () => prefix.first,
    );
    return userMessage.content;
  }
}

/// 由普通 Provider 从 [chatFavoritesFacadeProvider] 创建，不新增 app concrete bridge。
final chatFavoriteIntentCommandProvider = Provider<ChatFavoriteIntentCommand>((ref) {
  return ChatFavoriteIntentCommand(ref.watch(chatFavoritesFacadeProvider));
});
```

> 注意：`createCollection` 的空名 guard 用 `throw ArgumentError` 会让 widget 层崩溃；更稳妥是返回可空/失败信号。但 Phase 2.6 第 5 条要求「空名称的 UI guard 保留在 dialog，command 也不能因空值创建 collection」。建议：`createCollection` 返回 `String?`，空 trimmed 返回 null（表示未创建），widget 只委托、不因空值调用。实施时以不崩溃、不产生空收藏夹为准，二选一（返回 null 更安全）。

- [ ] **Step 3: 写 `chat_favorite_intent_command_test.dart`。**

command 单测用一个 fake `ChatFavoritesFacade`（`implements ChatFavoritesFacade`，记录 add/remove/create 调用），不 import Favorites feature：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_favorite_intent_command.dart';
import 'package:oh_my_llm/features/chat/application/chat_favorites_facade.dart';

class _RecordingFacade implements ChatFavoritesFacade {
  _RecordingFacade(this._snapshot);
  ChatFavoritesSnapshot _snapshot;
  final added = <ChatFavoriteDraft>[];
  final removedIds = <String>[];
  final createdNames = <String>[];

  @override
  ChatFavoritesSnapshot get snapshot => _snapshot;

  @override
  void add(ChatFavoriteDraft draft) => added.add(draft);

  @override
  String createCollection(String name) {
    createdNames.add(name);
    return 'new-col';
  }

  @override
  void remove(String favoriteId) => removedIds.add(favoriteId);
}

void main() {
  test('无现有收藏时返回 needs-collection 且未调用 add', () {
    // assistant 前有 user：draft.userMessageContent 取最近 user。
    // 断言 draft 字段完整（assistant content/reasoning/model、assistant ID、
    // conversation ID/title），且 facade.added 为空。
  });

  test('参数化锁定 user metadata 三分支 fallback', () {
    // 前缀有 user 取最近 user；前缀非空但无 user 回退前缀第一条；
    // assistant 为首条/不存在时为空。
  });

  test('已存在收藏时 remove 一次并返回完整 entry；restore 用原 draft 恢复', () {
    // beginToggle 返回 removed，facade.removedIds 含该 id；
    // restore(entry) 调 add 一次且 draft 字段不变。
  });

  test('addToCollection 的 "" 转 null、正常 ID 原样', () {
    // addToCollection(draft, '') -> facade.added 的 collectionId 为 null；
    // addToCollection(draft, 'col-1') -> collectionId 为 'col-1'。
  });

  test('createCollection 委托一次；空 trimmed name 不产生空收藏夹', () {
    // createCollection('  新夹  ') -> createdNames == ['新夹']；
    // 空名返回 null/不创建。
  });
}
```

- [ ] **Step 4: 迁移 Screen 的 dialog/notification orchestration。**

1. Screen 的 `_showAddToFavoritesDialog` 改为只 pattern-match typed result：

```dart
Future<void> _showAddToFavoritesDialog(
  BuildContext context,
  ChatMessage assistantMessage,
  ChatConversation conversation,
) async {
  final command = ref.read(chatFavoriteIntentCommandProvider);
  final result = command.beginToggle(
    conversation: conversation,
    assistantMessage: assistantMessage,
  );
  if (!context.mounted) return;

  switch (result) {
    case ChatFavoriteRemoved(:final removedEntry):
      ref.read(notificationBubblesProvider.notifier).show(
        message: '已取消收藏',
        action: NotificationBubbleAction(
          label: '撤销',
          onPressed: () => command.restore(removedEntry),
        ),
      );
    case ChatFavoriteNeedsCollection(
      :final draftWithoutCollection,
      :final collectionOptions,
    ):
      final selectedCollectionId = await showDialog<String>(
        context: context,
        builder: (context) => AddToFavoritesDialog(
          collections: collectionOptions,
          onCreateCollection: command.createCollection,
        ),
      );
      if (!mounted || selectedCollectionId == null) return;
      command.addToCollection(draftWithoutCollection, selectedCollectionId);
      if (!mounted) return;
      ref
          .read(notificationBubblesProvider.notifier)
          .show(message: '已收藏', type: NotificationBubbleType.success);
  }
}
```

删除 Screen 中「查找上一条 user message」「构造 `ChatFavoriteDraft`」「区分 remove/add」的代码。`_resolveUserContent` 的 fallback 算法已移入 command（Step 2）。

2. `AddToFavoritesDialog` 继续只接收不可变 collection options 与 `onCreateCollection`，不得 watch Favorites Provider；`onCreateCollection` 类型从 `String createCollection(String)` 兼容 `String?`（若 Step 2 选返回 null）。

3. `onFavoritePressed` 绑定到 `_showAddToFavoritesDialog`（与现状一致，仅内部实现变了）。

- [ ] **Step 5: 将 generation/message intent 只绑定到 Phase 9 facade。**

1. `onRetryLatestAssistant`、确认后的 `onStopStreaming`、message version、request exclusion、delete 继续调用 `chatSessionsProvider.notifier` 公开 command，但统一在 `ChatWorkspaceMessageBindings`/`ComposerBindings` 构造处出现一次：

```dart
final workspaceBindings = ChatWorkspaceBindings(
  messages: ChatWorkspaceMessageBindings(
    onEditMessage: (message) => _enterEditMode(message),
    onRetryLatestAssistant: () => ref.read(chatSessionsProvider.notifier).retryLatestAssistant(),
    onDeleteMessage: (message) => _showDeleteMessageDialog(context, message),
    onToggleRequestExclusion: (message) => ref.read(chatSessionsProvider.notifier).setMessagesExcluded(
      messageIds: [message.id],
      excluded: !conversation.isMessageExcluded(message.id),
    ),
    onSelectMessageVersion: (parentId, messageId) => ref.read(chatSessionsProvider.notifier).selectMessageVersion(parentId: parentId, messageId: messageId),
    onFavoritePressed: (message) => _showAddToFavoritesDialog(context, message, conversation),
  ),
  scroll: /* 同 Task 2 */,
  composer: /* 同 Task 2/3 */,
);
```

2. Screen 保留 stop/delete confirmation dialogs；确认是 presentation concern。网络/持久化错误仍为 inline message。
3. 不新增 `isStopping`/subscription/retry counter/generation ID/并行 provider；不改 Phase 9 lifecycle/state tests。
4. favorite undo 只恢复 favorite，不和消息 generation 的「retry」混为一个 generic undo command。

- [ ] **Step 6: 删除 Screen 中已失效的 resolver/handler/参数。**

用 `rg` 逐个确认后删除：本地 model/preset/template resolver（`_resolveSelectedModel`/`_resolveSelectedProviderId`/`_resolveSelectedTemplatePrompt` 若已迁到 view_state 则删）、重复 template values resolver（`_resolveTemplatePromptValues` 的旧实现）、`_sendMessageContent`、favorite draft builder、旧 `_buildWorkspace` 及不再使用的 cross-feature imports。保留真正属于 Screen 的 dialog、scroll/focus/edit UI handlers。

```powershell
rg -n "_sendMessageContent|buildTemplatedUserMessage|ChatFavoriteDraft\(|_resolveTemplatePromptValues" lib/features/chat/presentation/chat_screen.dart
```

- [ ] **Step 7: 运行 intent 与集成回归。**

```powershell
flutter test test/features/chat/application/chat_favorite_intent_command_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-favorite-command.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-favorite-command.log
flutter test test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-screen-intents.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-screen-intents.log
flutter test test/integration/chat_favorites_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase10-chat-favorites-integration.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase10-chat-favorites-integration.log
```

若仓库实际 integration 文件名不同，先 `rg --files test/integration | rg "chat.*favorite|favorite.*chat"`，运行现有文件；不得因为命令示例路径不同复制一套测试。

- [ ] **Step 8: 格式化并提交。**

```bash
dart format lib/features/chat/application/chat_favorite_intent_command.dart lib/features/chat/application/chat_favorites_facade.dart lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_workspace_bindings.dart lib/features/chat/presentation/widgets/dialogs/add_to_favorites_dialog.dart lib/app/composition/cross_feature_bindings.dart test/features/chat/application/chat_favorite_intent_command_test.dart test/features/chat/chat_screen/chat_screen_favorites_cases.dart test/features/chat/chat_screen/chat_screen_streaming_cases.dart test/features/chat/chat_screen/chat_screen_branching_cases.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart test/integration/chat_favorites_integration_test.dart
git add lib/features/chat/application/chat_favorite_intent_command.dart \
        lib/features/chat/application/chat_favorites_facade.dart \
        lib/features/chat/presentation/chat_screen.dart \
        lib/features/chat/presentation/widgets/chat_workspace_bindings.dart \
        lib/features/chat/presentation/widgets/dialogs/add_to_favorites_dialog.dart \
        lib/app/composition/cross_feature_bindings.dart \
        test/features/chat/application/chat_favorite_intent_command_test.dart \
        test/features/chat/chat_screen/chat_screen_favorites_cases.dart \
        test/features/chat/chat_screen/chat_screen_streaming_cases.dart \
        test/features/chat/chat_screen/chat_screen_branching_cases.dart \
        test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart \
        test/integration/chat_favorites_integration_test.dart
git commit -m "refactor(chat): 统一工作区业务意图"
```

只 stage 实际存在且确有 diff 的路径；若 composition/dialog/integration 无改动，从命令移除，不能为了匹配清单制造空改动。

---

## Task 5: 范围审计、格式门禁与全量验证

**Files:** 只允许修复 Task 1–4 引入的直接回归；不得借最终门禁开始后续 Phase。

- [ ] **Step 1: 检查参数、双 owner 和废弃 contract 已真正消失。**

```powershell
rg -n "_selectedPresetPromptId|_presetPromptNeedsInit|chatTemplatePromptSelectionProvider|_draftConversationId|_restoredDraftForConversationId|_sendMessageContent" lib/features/chat
rg -n "ComposerData|ComposerCallbacks|composer_data.dart" lib test
rg -n "ChatWorkspace\(" lib test
rg -n "templateId::|readTemplateVariable\(|setTemplateVariable\(" lib/features/chat test/features/chat
rg -n "TextEditingController|FocusNode|ItemScrollController|BuildContext|Widget" lib/features/chat/application/chat_workspace_view_state.dart lib/features/chat/application/composer_draft_controller.dart
rg -n "features/favorites" lib/features/chat/application lib/features/chat/presentation
```

预期：
- 前两条旧 owner/contract 搜索零结果（文档引用不在此路径）。
- `ChatWorkspace(` production call site 只有一个，构造只传 `state`/`bindings`。
- template variable API 每次都有 conversation ID；不得保留全局 key helper。
- application state 无 Flutter UI controller/widget 类型。
- Chat feature 不 import Favorites concrete feature；只使用自身 facade。

- [ ] **Step 2: 检查 Screen responsibility 而非只看行数。**

手工 review `chat_screen.dart`，逐项确认：
- build 不再解析 model/preset/template/favorites metadata；只 watch read-model、sidebar/history shell state 并组合 bindings。
- `_buildBody` 不再有 20+ 参数，`_buildWorkspace` 已删除。
- Screen 未持有与 conversation/provider 等价的 preset/template/body 事实值；本地只剩 controllers、edit transaction、fixed-sequence cursor、scroll/focus。
- showDialog/notification/focus/scroll 仍在 presentation，没有被错误下沉 application。
- 不设「必须降到 N 行」的机械目标；若责任已清晰，不为行数把同一大类拆成无意义 extension/mixin。

- [ ] **Step 3: 执行本 Phase Dart 格式化与暂存后检查。**

```powershell
$dartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($dartFiles) { dart format --output=none --set-exit-if-changed $dartFiles }
```

非零退出不得提交；修正后重新 stage/检查。不要格式化整个 `lib/` 或用户无关 Dart 改动。

- [ ] **Step 4: 运行 analyze。**

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase10.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase10.log
```

要求 `EXIT=0`、`No issues found!`。

- [ ] **Step 5: 按仓库强制格式运行全量测试。**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

要求 `EXIT=0` 和末尾 `All tests passed!`。失败时只从 `fltest.log` 查：

```powershell
Select-String -Pattern " -[1-9]" -Path fltest.log
Select-String -Pattern "失败测试名" -Path fltest.log -Context 0,30
```

修复后先重跑失败文件，再重跑 analyze 和全量测试。禁止直接不重定向运行全量 `flutter test`，禁止用 `tee`。

- [ ] **Step 6: 执行严格反范围审计。**

```powershell
rg -n "ChatGenerationCoordinator|ChatGenerationPhase|StreamSubscription|Completer" lib/features/chat/presentation lib/features/chat/application/chat_composer_command.dart lib/features/chat/application/chat_workspace_view_state.dart
rg -n "GoRoute|StatefulShellRoute|ShellRoute|AppDestination" lib/features/chat/application lib/features/chat/presentation/widgets/chat_workspace* lib/features/chat/presentation/chat_screen.dart
rg -n "AppBreakpoints|compactComposerBreakpoint" lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_*
rg -n "chat_completion_client|chat_conversation_repository|openai_compatible" lib/features/chat/application/chat_composer_command.dart lib/features/chat/application/chat_workspace_view_state.dart
rg -n "CREATE TABLE|ALTER TABLE|user_version|reasoning_content|finish_reason" lib/features/chat/application lib/features/chat/presentation
git diff --check
git status --short
```

审计解释：
- presentation 可能因类型/doc 提到 coordinator 名称而命中；任何实际 lifecycle import/字段均越界。
- route 搜索不得出现本 Phase 新增改动；ChatScreen 原有 destination/shell import 可存在，不改全局导航。
- breakpoint 常量可以保留原样，但 diff 不得统一/重命名阈值。
- command/read-model 不得绕过 Phase 9 facade import data client/repository（当前 `ChatSessionsController` 自身旧 imports 属 Phase 11，不在本 Phase 处理）。
- 不得有 schema/migration/SQL 改动。
- status 中无关未跟踪 Phase 9 文档仍保持未触碰/未暂存。

> 注意：`chat_workspace_view_state.dart` 的 `chatWorkspaceReadModelProvider` 会 watch `chatSessionsController.dart` 的 providers（`activeChatConversationProvider` 等），这是合法派生，不是 lifecycle 越界；`rg` 命中的是 import 语句而非本 Phase 新增的 lifecycle 字段。若 `chatWorkspace*` 文件出现 `StreamSubscription`/`Completer`/`ChatGenerationCoordinator` 的实际字段，才越界。

- [ ] **Step 7: 仅在必要时提交最小门禁修复。**

只有 Step 1–6 发现本 Phase 直接回归才创建：

```bash
git commit -m "fix(chat): 修复工作区所有权回归"
```

`git add` 必须是导致回归的最小精确文件集；没有修复不创建空提交。

---

## 提交序列总览

| 节点 | Commit message | 可独立回滚的价值 |
|---|---|---|
| 1 | `refactor(chat): 明确输入草稿状态所有权` | composer input 成为 per-conversation 内存 state，preset/template 双 owner 消失 |
| 2 | `refactor(chat): 收敛工作区视图绑定` | workspace 获得不可变 state + UI bindings，20+ 参数链消失 |
| 3 | `refactor(chat): 收敛输入与编辑命令` | send/edit/template toolbar 编排离开 Screen，编辑事务不再污染普通 draft |
| 4 | `refactor(chat): 统一工作区业务意图` | favorites/undo metadata 和 generation/message callbacks 经既有稳定 command/facade 绑定 |
| 5（仅必要） | `fix(chat): 修复工作区所有权回归` | 只含最终门禁发现的最小回归修复 |

每个 commit 都触发仓库 post-commit version bump；不要手工改 `pubspec.yaml`。提交必须在 Bash 使用上表第一行 conventional message。

## 验收映射

| 验收项 | 证据 |
|---|---|
| 状态 owner 可清晰说明 | Ownership 矩阵；Task 1 controller/widget tests；Screen 手工责任审计 |
| 删除本地/Provider 双写 | preset local mirror 与全局 template selection Provider 删除；edit input 不再写普通 draft |
| 页面销毁不丢会话/持久态 | 同 ProviderScope 重挂恢复 composer session；conversation/SharedPreferences 既有持久测试 |
| 页面销毁不错误保留瞬态 | edit mode/fixed runner/scroll/focus 不进 Provider；edit dispose case |
| Workspace/body 不再 20+ 参数 | `ChatWorkspace(state, bindings)`；`_buildWorkspace` 删除；参数 audit |
| view-state 不隐藏 UI controller | application grep + contract type review；controllers 只在 presentation bindings |
| composer 渐进迁移 | Task 1 state → Task 2 contract → Task 3 command，每步可运行/独立提交 |
| favorites/send/stop/undo 走 command | composer/favorite command tests；Phase 7 facade 和 Phase 9 sessions facade 保持唯一 mutation/lifecycle 边界 |
| 核心 Chat 规则不变 | 既有 branching/streaming/request/checkpoint tests + 全量 `EXIT=0` |
| 可独立回滚 | 四个行为完整提交；无 schema/route/generation state machine 混入 |

## 严格 Out of Scope / 停止条件

以下任一改动出现时，执行者必须停止并把它从本 Phase diff 拆除：

1. 修改 `ChatGenerationCoordinator`、generation phases/outcomes、retry scheduler、SSE parser、300ms flush、stop 持久化或 Phase 9 tests 的产品语义。
2. 修改消息树 parent/branch/select/retry-latest 规则，Prompt 五步顺序，Reasoning/Content 分离，标题/搜索，inline error/empty reply 或 finish reason。
3. 搬迁 `ChatCompletionClient`/repository ports、修 application→data imports 或增加 architecture gate（属 Phase 11）。
4. 引入 StatefulShellRoute、页面 keep-alive、route extra/ID 恢复或跨顶层导航状态（属 Phase 12）。
5. 统一 560/600/640/680/720/840 等 breakpoint、补全 viewport matrix（属 Phase 13）。
6. 全仓替换 `pumpAndSettle`、internal Key、timing tests（属 Phase 15）；只修本 Phase 新增/直接触及测试。
7. 修改 SQLite schema/migration/user_version、SharedPreferences versioned codec、background writer 或 persistence Future 语义。
8. 让 Chat import Favorites concrete controllers/repositories，或让 app composition 吸收 composer 内部状态。
9. 把 `TextEditingController`、FocusNode、scroll controller、BuildContext、Widget、callback 存入 Riverpod state/Equatable/SQLite/SharedPreferences。
10. 为减少 `ChatScreen` 行数一次重写全部 dialogs/sidebar/checkpoints/scroll，或创建另一个共享可变 God controller。

**完成定义：** 只有当 Task 1–4 的定向测试、`flutter analyze`、暂存格式检查和强制重定向的全量测试全部通过，旧 selection/data-clump contract 零引用，ownership/参数/依赖审计满足要求，且 diff 不含以上越界项时，本 Phase 才算完成。