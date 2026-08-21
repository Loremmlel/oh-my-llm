# Phase 13 响应式语义断点实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有零散的响应式断点（`compact=720`、裸 `840/760/900/600`、局部 `640/560`）收敛为按布局职责命名的唯一事实源 `AppBreakpoints`，并为 AppShell/Chat/Settings/Sync/Media 建立代表性 viewport 行为测试矩阵。默认不改断点数值、不重设计 UI、不改业务状态；只有新测试稳定暴露真实 overflow 时才允许对触发组件做最小约束修复。

**Architecture:** 新增 `AppBreakpoints` 唯一公共 API（6 个职责 token + 3 个纯宽度分类函数 + 1 个 context helper），迁移全部直接消费者；`AdaptiveMasterDetailLayout` 默认值改用 `contentMasterDetail`，保留可注入 breakpoint；新增共享 `ResponsiveViewportCase` 视口矩阵（`test/helpers/responsive_viewport_cases.dart`），各 feature 用参数化循环补行为测试。断点语义冻结为「`< breakpoint` 走 compact/single-pane/full-bubble，`>= breakpoint` 走 expanded/two-pane/proportional-bubble」，等号永远属于宽侧。

**Tech Stack:** Flutter ≥ 3.11.5 / Dart ≥ 3.x · flutter_test（`testWidgets` + 参数化循环）· 无新依赖。全程用 `package:oh_my_llm/...` 根路径 import（见项目 CLAUDE.md 第 6 节）。

**源文档:** `docs/第一轮审查/Phase 13 - Implement Plan.md`（含断点契约、逐文件改动、行为矩阵的权威定义）。本计划按第七节「分任务实施顺序」展开，任何与源文档冲突处，以源文档「零、执行结论」为准。

## Global Constraints

实现期间每个 Task 的 Requirements 都隐式包含本节，不逐一重复。

- **数值与比较方向不可变**：六个 token 值固定为 `shellNavigation=720`、`contentMasterDetail=840`、`dialogMasterDetail=760`、`formActions=680`、`formMasterDetail=900`、`messageBubble=600`。全部判定保持 `< breakpoint`；**禁止改成 `<=`**。精确 `600/680/720/760/840/900` 均属宽侧。
- **判定边界责任**：shell 用顶层可用宽度（`LayoutBuilder.constraints.maxWidth`）；composer/bubble/Settings 卡片判定父组件实际分配宽度（各自 `LayoutBuilder.constraints.maxWidth`）；Chat 内层与 shell 窗口级模式一致，只用 `AppBreakpoints.isCompactShell(context)`（内部 `MediaQuery.sizeOf`）。禁止 `MediaQuery.orientationOf`、`OrientationBuilder`、手机/平板/平台类型决定布局。
- **非断点数值不得替换**：`DetailDisplayDialog.width=640`、`SettingsFormDialogScaffold.width=720`、`FixedPromptSequenceRunnerDialog.width=680`、`FontWeight.w600` 保持原样；ProviderTile `640` 与 ProviderModelTile `560` 保留为类内局部阈值（独立命名，不合并为 form token）。
- **禁止新增旧 alias**：不得为 `compact`/`isCompact` 加兼容 alias；旧名必须删除，确保调用方无法再表达错误语义。
- **测试只测用户可见行为**：只用可见文案、tooltip、真实 tap、route 匹配、`tester.takeException()`。禁止 `getTopLeft`/`getRect`/`find.byKey`/`maxLines`/`expands`/像素距离/widget 尺寸比较/负向类型断言（`findsNothing` on widget 类型）/conditional early return。
- **每个参数化 iteration 必须执行到至少一个业务 `expect` 和一个 `tester.takeException()` 检查**；`takeException()` 得到异常时测试直接失败并输出原异常，不得只匹配/吞掉 RenderFlex 文案。
- **Setup 用 `pump()`**，不把 `pumpAndSettle` 当初始化惯例；仅 drawer/tab/dialog/route 等真实动画后用 `pumpAndSettle(const Duration(milliseconds: 250))`。
- **测试命令必须重定向**：`flutter test <...> --reporter compact 2>&1 | Out-File -Encoding utf8 <log>.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 <log>.log`。禁止裸跑 `flutter test`。全量输出统一落 `fltest.log`。
- **提交纪律**：commit 在 Bash 中执行（多个 `-m`，禁止 PowerShell here-string）；每个功能点单独 commit；版本号由 post-commit hook 自动 bump，不手工改 `pubspec.yaml`；提交前对改动 Dart 文件 `dart format`，暂存后跑 `dart format --output=none --set-exit-if-changed`。
- **注释规范**：简体中文，`//` 写「为什么」。注释与测试标题**不得出现**「Phase 13」「第一轮审查」「TD-29」等审查编号或临时计划术语（这是项目 CLAUDE.md 的硬性要求；共享 helper 文件同样适用）。

---

## 文件结构总览

**新增生产文件：无。**（Sync/Media production 不在预定修改列表；仅当第五节矩阵测试稳定复现 overflow 时，按 Task 5 的规则新增最小 fix。）

**修改生产文件（14 个，全部在 Task 1）：**
```
lib/core/constants/app_breakpoints.dart
lib/core/widgets/adaptive_master_detail_layout.dart
lib/app/shell/app_shell_scaffold.dart
lib/features/chat/presentation/chat_screen.dart
lib/features/chat/presentation/widgets/chat_workspace.dart
lib/features/chat/presentation/widgets/chat_messages_panel.dart
lib/features/chat/presentation/widgets/chat_composer_card.dart
lib/features/chat/presentation/widgets/chat_message_bubble.dart
lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart
lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart
lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart
lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart
lib/features/settings/presentation/widgets/list/provider_tile.dart
lib/features/settings/presentation/widgets/list/provider_model_tile.dart
```

**新增测试文件（7 个）：**
```
test/helpers/responsive_viewport_cases.dart
test/core/constants/app_breakpoints_test.dart
test/core/widgets/adaptive_master_detail_layout_test.dart
test/features/chat/chat_screen/chat_screen_responsive_cases.dart
test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart
test/features/settings/settings_screen/settings_screen_responsive_cases.dart
test/features/sync/sync_screen/sync_screen_responsive_cases.dart
```

**修改测试文件（6 个）：**
```
test/app/shell/app_shell_scaffold_test.dart
test/features/chat/chat_screen_test.dart
test/features/settings/settings_screen_test.dart
test/features/settings/settings_screen/settings_screen_test_helpers.dart
test/features/sync/sync_screen_test.dart
test/features/media/presentation/media_browser_navigation_test.dart
```

---

## 跨任务接口契约（Interfaces）

Task 1 产出、后续 Task 依赖的公共符号（类型与签名在计划内保持一致，不得在 Task 间改名）：

```dart
// lib/core/constants/app_breakpoints.dart（Task 1 最终形态）
final class AppBreakpoints {
  static const double shellNavigation;        // 720
  static const double contentMasterDetail;    // 840
  static const double dialogMasterDetail;     // 760
  static const double formActions;            // 680
  static const double formMasterDetail;       // 900
  static const double messageBubble;          // 600
  static bool useCompactShell(double availableWidth);
  static bool useCompactFormActions(double availableWidth);
  static bool useFullWidthMessageBubble(double availableWidth);
  static bool isCompactShell(BuildContext context);
}

// test/helpers/responsive_viewport_cases.dart（Task 2 产出）
enum ShellNavigationMode { bottomBar, rail }
final class ResponsiveViewportCase {
  final String name; final Size size; final ShellNavigationMode shellMode;
}
const requiredShellViewports;   // 7 个：phonePortrait/compactTablet/shellBelowBoundary/shellAtBoundary/shellAboveBoundary/desktop/wideDesktop
const androidLandscape;         // Size(844, 390)，独立于 shell 循环
```

关键观察（执行者写测试时直接引用）：
- 空会话标题 = `'未命名对话'`（`ChatConversation.resolvedTitle`，`lib/features/chat/domain/models/chat_conversation.dart:65`）。
- Chat 输入框 label = `'正文'`（`ComposerMessageField`）；发送 = `FilledButton` 内 `'发送'`；抽屉按钮 tooltip = `'打开侧边内容'`。
- activity bar tooltip = `ChatSidebarFunction.label`：`'历史会话'` / `'预设 Prompt'`（`lib/features/chat/application/chat_sidebar_controller.dart:11`）；侧栏面板标题 = `'历史会话面板'`（`conversation_history_panel.dart:37`）；紧凑面板 SegmentedButton 文案 = `'历史会话'` / `'预设 Prompt'`。
- composer compact 摘要以 `'更多设置'` 开头（`_compactSettingsSummary()`）；底部 sheet 内 toggle label = `'深度思考'` / `'自动重试'`；desktop 操作行按钮 = `'固定顺序提示词'` / `'上下文过滤'`（`messageFilterLabel(0)`）。
- Settings tab label：`['服务商','预设','提示词','网络','输出处理','其它']`（`settings_screen_test_helpers.dart` 的 `tabLabels` 与 `settings_screen.dart:130` 一致）；各 tab heading 见 Task 4。
- Sync 未连接提示 = `'请先在「连接」标签页中连接到服务端'`；标题 = `'局域网同步'`；tab = `'连接'`/`'同步'`/（Android）`'媒体'`；模式入口 = `'作为客户端'`/`'作为服务端'`。
- Media 路径栏根 chip = `'🏠'`；item 文案 = 文件名（如 `'猫.jpg'`、`'demo.mp4'`）或目录名。

---

## Task 0：重新建立可执行基线

**Files:** 无文件改动。

**Interfaces:** 无产出；建立后续所有 Task 可信的基线。

- [ ] **Step 1: 检查并保护现有改动**

Run: `git status --short`
Expected: 当前仅有 `?? "docs/第一轮审查/Phase 11 - Implement Plan.md"`（未跟踪的计划文档）等与本次无关的条目。记录它们，**不得** `git add .`、不得 restore/stage 任何无关文件。若出现本计划预期之外的工作区改动，先停下报告，不开始改代码。

- [ ] **Step 2: 确认工具链**

Run（PowerShell）:
```powershell
flutter --version
flutter pub get
```
Expected: 输出正常、无错误。若 `flutter` 命令长时间无输出，先跑 `./scripts/kill-stale-test-processes.ps1` 清理残留 dart/flutter_tester 进程（残留进程锁住 native assets dll 会卡住启动），再重试；工具链问题未解决前不进入下一步。

- [ ] **Step 3: 前置 Phase 定向回归**

Run（PowerShell，重定向必带）:
```powershell
flutter test test/features/settings/application/settings_entity_controller_test.dart test/features/settings/application/settings_import_executor_test.dart test/features/settings/application/settings_transfer_workflow_test.dart test/features/settings/application/model_catalog_workflow_test.dart test/features/settings/settings_screen_test.dart test/features/sync/application/sync_server_controller_test.dart test/features/sync/application/sync_client_controller_test.dart test/features/sync/sync_screen_test.dart test/features/chat/application/chat_workspace_view_state_test.dart test/features/chat/chat_screen_test.dart test/app/router/app_router_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase13-baseline.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase13-baseline.log
```
Expected: `EXIT=0`。

- [ ] **Step 4: 处理基线失败（若有）**

`EXIT!=0` 时从 `fltest-phase13-baseline.log` 定位既有失败：环境相关先报告；确属主干回归则单独定界并报告，**不得**把 baseline failure 混入后续 breakpoint commit。

---

## Task 1：建立语义断点 contract 并迁移消费者

**Files:**
- Create: `test/core/constants/app_breakpoints_test.dart`
- Create: `test/core/widgets/adaptive_master_detail_layout_test.dart`
- Modify: `lib/core/constants/app_breakpoints.dart`
- Modify: `lib/core/widgets/adaptive_master_detail_layout.dart`
- Modify: `lib/app/shell/app_shell_scaffold.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_workspace.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_messages_panel.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_composer_card.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_message_bubble.dart`
- Modify: `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart`
- Modify: `lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/list/provider_tile.dart`
- Modify: `lib/features/settings/presentation/widgets/list/provider_model_tile.dart`

**Interfaces:**
- Consumes: Task 0 基线（全绿）。
- Produces: `AppBreakpoints` 唯一公共 API（见上文契约）；`AdaptiveMasterDetailLayout` 默认 `breakpoint = AppBreakpoints.contentMasterDetail`（可注入不变）。Task 2–5 的测试全部引用这些符号。

### Step 1：写 contract 红灯测试

新建 `test/core/constants/app_breakpoints_test.dart`（完整内容）：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

void main() {
  group('useCompactShell', () {
    test('仅在 719 走紧凑分支，720 等号属宽侧', () {
      expect(AppBreakpoints.useCompactShell(719), isTrue);
      expect(AppBreakpoints.useCompactShell(720), isFalse);
      expect(AppBreakpoints.useCompactShell(721), isFalse);
    });
  });

  group('useCompactFormActions', () {
    test('仅在 679 走紧凑分支，680 等号属宽侧', () {
      expect(AppBreakpoints.useCompactFormActions(679), isTrue);
      expect(AppBreakpoints.useCompactFormActions(680), isFalse);
      expect(AppBreakpoints.useCompactFormActions(681), isFalse);
    });
  });

  group('useFullWidthMessageBubble', () {
    test('仅在 599 走近全宽分支，600 等号属宽侧', () {
      expect(AppBreakpoints.useFullWidthMessageBubble(599), isTrue);
      expect(AppBreakpoints.useFullWidthMessageBubble(600), isFalse);
      expect(AppBreakpoints.useFullWidthMessageBubble(601), isFalse);
    });
  });
}
```

新建 `test/core/widgets/adaptive_master_detail_layout_test.dart`（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';
import 'package:oh_my_llm/core/widgets/adaptive_master_detail_layout.dart';

/// 以指定父宽度挂载布局；宽分支同时渲染 master 与 detail，紧凑分支只渲染 compactChild。
Future<void> _pumpLayout(
  WidgetTester tester,
  double parentWidth, {
  double? breakpoint,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: parentWidth,
          child: AdaptiveMasterDetailLayout(
            breakpoint: breakpoint,
            compactChild: const Text('紧凑内容'),
            master: const Text('主栏'),
            detail: const Text('详情'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('默认断点：839 显示紧凑子项', (tester) async {
    await _pumpLayout(tester, 839);
    expect(find.text('紧凑内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认断点：840 等号进入双栏', (tester) async {
    await _pumpLayout(tester, 840);
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认断点：841 稳定双栏', (tester) async {
    await _pumpLayout(tester, 841);
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可注入断点：dialogMasterDetail 下 759 紧凑、760 双栏', (tester) async {
    await _pumpLayout(tester, 759, breakpoint: AppBreakpoints.dialogMasterDetail);
    expect(find.text('紧凑内容'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpLayout(tester, 760, breakpoint: AppBreakpoints.dialogMasterDetail);
    expect(find.text('主栏'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 运行确认红灯**

Run（PowerShell）:
```powershell
flutter test test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-contract.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-contract.log
```
Expected: `EXIT!=0`，编译失败（`useCompactShell`/`useFullWidthMessageBubble`/`contentMasterDetail` 等不存在）。红灯必须来自新 API 尚不存在，不得用 skip 或放宽 expect 伪造。

### Step 3：实现 `AppBreakpoints`

将 `lib/core/constants/app_breakpoints.dart` **整体替换**为（完整内容；doc comment 是强制要求）：

```dart
import 'package:flutter/widgets.dart';

/// 按布局职责定义的响应式断点。
///
/// 每个 token 只描述一种布局切换；判定统一为「小于断点走紧凑/单栏/近全宽分支，
/// 大于等于断点走宽侧/双栏/比例限宽分支」，等号永远属于宽侧。
/// 不要在调用处改写比较方向，也不要再引入 `compact`/`isCompact` 兼容别名。
final class AppBreakpoints {
  const AppBreakpoints._();

  /// 应用壳导航断点，接收窗口级宽度（顶层可用宽度）。
  ///
  /// 控制 [NavigationBar]+endDrawer 与 [NavigationRail]+常驻侧栏之间的切换：
  /// `width >= 720` 进入宽侧（rail + 常驻 Chat 侧栏），等号属宽侧。
  static const double shellNavigation = 720.0;

  /// 通用内容区主从布局默认双栏阈值，接收父组件分配宽度。
  ///
  /// 作为 [AdaptiveMasterDetailLayout] 的默认 `breakpoint` 使用，等号属宽侧
  /// （`width >= 840` 开始 master/detail 双栏）。调用方可注入自定义值。
  static const double contentMasterDetail = 840.0;

  /// 两个 Chat 主从选择对话框（检查点、消息过滤）的双栏阈值，接收父约束。
  ///
  /// `width >= 760` 开始 master/detail，等号属宽侧。
  static const double dialogMasterDetail = 760.0;

  /// Chat composer 操作行紧凑/完整阈值，接收 composer 父约束宽度。
  ///
  /// `width >= 680` 显示完整操作行（思考/重试/固定顺序/过滤），等号属宽侧。
  static const double formActions = 680.0;

  /// 两个 Settings 多面板表单（预设 Prompt、固定顺序提示词）的双栏阈值，
  /// 接收表单父约束宽度。`width >= 900` 开始 master/detail，等号属宽侧。
  static const double formMasterDetail = 900.0;

  /// 消息气泡近全宽/比例限宽阈值，接收气泡父约束宽度。
  ///
  /// `width >= 600` 开始按角色比例限宽，等号属宽侧。
  static const double messageBubble = 600.0;

  static bool useCompactShell(double availableWidth) =>
      availableWidth < shellNavigation;

  static bool useCompactFormActions(double availableWidth) =>
      availableWidth < formActions;

  static bool useFullWidthMessageBubble(double availableWidth) =>
      availableWidth < messageBubble;

  static bool isCompactShell(BuildContext context) =>
      useCompactShell(MediaQuery.sizeOf(context).width);
}
```

- [ ] **Step 4: 迁移 `AdaptiveMasterDetailLayout` 默认值**

在 `lib/core/widgets/adaptive_master_detail_layout.dart`：
1. import 前补 `import 'package:oh_my_llm/core/constants/app_breakpoints.dart';`（按第 1 行前插入）。
2. 构造参数 `this.breakpoint = 840,` 改为 `this.breakpoint = AppBreakpoints.contentMasterDetail,`。

- [ ] **Step 5: 迁移 `AppShellScaffold`**

在 `lib/app/shell/app_shell_scaffold.dart` 第 32 行：
```dart
// 之前
final isCompact = constraints.maxWidth < AppBreakpoints.compact;
// 之后
final isCompact = AppBreakpoints.useCompactShell(constraints.maxWidth);
```
导航结构、destination、endDrawer 行为一律不改。

- [ ] **Step 6: 迁移 `ChatScreen` shell 判定**

在 `lib/features/chat/presentation/chat_screen.dart` `_buildBody`（约 335–343 行）：
```dart
// 之前
// 使用 MediaQuery 获取窗口物理宽度，与 AppShellScaffold 的
// LayoutBuilder 判断保持一致，避免因 NavigationRail 占位导致
// 内层宽度缩水 69px 而产生判断偏差。
final showSidePanels =
    MediaQuery.of(context).size.width >= AppBreakpoints.compact;
// 之后
// 使用窗口级宽度与 AppShellScaffold 保持一致：父约束已被 NavigationRail
// 缩窄，不能拿内层 LayoutBuilder 宽度再判一次 shell。
final showSidePanels = !AppBreakpoints.isCompactShell(context);
```
`final isCompact = !showSidePanels;` 与下方 `Padding` 分支不变。

- [ ] **Step 7: 迁移 Chat workspace / messages panel 的 spacing**

- `lib/features/chat/presentation/widgets/chat_workspace.dart` 第 54 行：`AppBreakpoints.isCompact(context)` → `AppBreakpoints.isCompactShell(context)`。
- `lib/features/chat/presentation/widgets/chat_messages_panel.dart` 第 111 行：`AppBreakpoints.isCompact(context)` → `AppBreakpoints.isCompactShell(context)`。
- 这两个文件 import 已存在，无需新增。

- [ ] **Step 8: 迁移 `ChatComposerCard`**

在 `lib/features/chat/presentation/widgets/chat_composer_card.dart`：
1. 删除第 19 行 `static const compactComposerBreakpoint = 680.0;`。
2. 第 87–88 行改为：
```dart
// isCompactComposer 是输入区自身的 formActions（680）断点，决定操作行
// 紧凑/桌面布局；与 isCompactShell（720，影响 padding）含义不同，不可混用。
final isCompactComposer =
    AppBreakpoints.useCompactFormActions(constraints.maxWidth);
```
3. `_buildCollapsed` 中两处 `AppBreakpoints.isCompact(context)`（第 55、57 行）→ `AppBreakpoints.isCompactShell(context)`。
4. `_buildExpanded` 第 91 行 `AppBreakpoints.isCompact(context)` → `AppBreakpoints.isCompactShell(context)`。

- [ ] **Step 9: 迁移 `ChatMessageBubble`**

在 `lib/features/chat/presentation/widgets/chat_message_bubble.dart`：
1. 第 3 行前新增 `import 'package:oh_my_llm/core/constants/app_breakpoints.dart';`。
2. 第 165 行：
```dart
// 之前
final isNarrow = constraints.maxWidth < 600;
// 之后
final isNarrow = AppBreakpoints.useFullWidthMessageBubble(constraints.maxWidth);
```
`bubbleWidth` 公式与 900 max width 不变。

- [ ] **Step 10: 迁移两个 Chat dialog 的 master-detail 断点**

- `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart`：新增 `import 'package:oh_my_llm/core/constants/app_breakpoints.dart';`；`AdaptiveMasterDetailLayout(breakpoint: 760, ...)`（第 184 行）→ `breakpoint: AppBreakpoints.dialogMasterDetail`。
- `lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart`：新增同款 import；第 101 行 `breakpoint: 760` → `breakpoint: AppBreakpoints.dialogMasterDetail`。
- 两个 dialog 的 `content: SizedBox(width: 920, ...)` 是固定 dialog 宽度，保持原样。

- [ ] **Step 11: 迁移两个 Settings 表单的 master-detail 断点**

- `lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart`：
  1. 新增 `import 'package:oh_my_llm/core/constants/app_breakpoints.dart';`。
  2. 删除 build 内 `const masterDetailBreakpoint = 900.0;`（第 64 行）。
  3. `shouldScrollContent: (constraints) => constraints.maxWidth < masterDetailBreakpoint` → `constraints.maxWidth < AppBreakpoints.formMasterDetail`。
  4. `AdaptiveMasterDetailLayout(... breakpoint: masterDetailBreakpoint ...)` → `breakpoint: AppBreakpoints.formMasterDetail`。
  - 保留既有的 `key: ValueKey('preset-prompt-form-layout')` 等 test-key 与 `width: 1120`（固定 dialog 宽度，不替换）。
- `lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart`：同样处理（`const masterDetailBreakpoint = 900.0;` 在第 82 行），`width: 1080` 保持。

- [ ] **Step 12: 命名 ProviderTile / ProviderModelTile 局部阈值**

- `lib/features/settings/presentation/widgets/list/provider_tile.dart`：在 `_ProviderTileState` 类体内（`bool _modelsExpanded = false;` 附近）新增：
```dart
// 服务商卡片的长操作区（新增模型/编辑/删除）标签较长，需要在更窄的父约束下
// 先纵向堆叠；嵌套模型卡片（560）的按钮更短，不能复用同一阈值。
static const _compactActionsBreakpoint = 640.0;
```
  `constraints.maxWidth < 640`（第 95 行）→ `constraints.maxWidth < _compactActionsBreakpoint`。
- `lib/features/settings/presentation/widgets/list/provider_model_tile.dart`：在 `ProviderModelTile` 类体内新增：
```dart
// 嵌套模型卡片的操作区（编辑/删除）按钮更短且父 padding 不同，
// 与父服务商卡片的 640 保持独立，不得合并为同一个 form 断点。
static const _compactActionsBreakpoint = 560.0;
```
  `constraints.maxWidth < 560`（第 62 行）→ `constraints.maxWidth < _compactActionsBreakpoint`。

- [ ] **Step 13: 审计迁移无机械替换**

Run（PowerShell）:
```powershell
rg -n "AppBreakpoints\.(compact|isCompact)" lib test
rg -n "constraints\.maxWidth\s*<\s*(560|600|640|680|720|760|840|900)(\.0)?" lib/app lib/core lib/features/chat/presentation lib/features/settings/presentation
rg -n "breakpoint:\s*(760|840|900)(\.0)?" lib/core lib/features/chat/presentation lib/features/settings/presentation
```
Expected:
- 第一条 **无命中**。
- 后两条只允许已被明确判定为局部值/固定宽度的命中（如 `FixedPromptSequenceRunnerDialog` 的 `width: 680`、`DetailDisplayDialog` 的 `width: 640`、`SettingsFormDialogScaffold` 的 `width: 720`、bubble 900 max width）；每个命中人工分类，**不得批量 replace**。

- [ ] **Step 14: 定向验证消费者**

Run（PowerShell）:
```powershell
flutter test test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen_test.dart test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-contract-consumers.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-contract-consumers.log
```
Expected: `EXIT=0`。若 chat/settings 既有测试因迁移出现行为差异，从 log 定位并核实是不是断点语义被改错。

- [ ] **Step 15: 格式化并提交**

```powershell
git diff --name-only -- '*.dart'
dart format lib/core/constants/app_breakpoints.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_workspace.dart lib/features/chat/presentation/widgets/chat_messages_panel.dart lib/features/chat/presentation/widgets/chat_composer_card.dart lib/features/chat/presentation/widgets/chat_message_bubble.dart lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart lib/features/settings/presentation/widgets/list/provider_tile.dart lib/features/settings/presentation/widgets/list/provider_model_tile.dart test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart
```
```bash
git add lib/core/constants/app_breakpoints.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_workspace.dart lib/features/chat/presentation/widgets/chat_messages_panel.dart lib/features/chat/presentation/widgets/chat_composer_card.dart lib/features/chat/presentation/widgets/chat_message_bubble.dart lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart lib/features/settings/presentation/widgets/list/provider_tile.dart lib/features/settings/presentation/widgets/list/provider_model_tile.dart test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git diff --cached --check
```
```bash
git commit -m "refactor(ui): 收敛响应式语义断点" \
           -m "按布局职责建立 AppBreakpoints 唯一事实源（shell/content/dialog/form/bubble），
等号统一属宽侧；迁移全部直接消费者与两处局部卡片阈值命名。数值与分支行为不变。" \
           -m "新增断点边界契约测试与 AdaptiveMasterDetailLayout 默认/可注入断点行为测试。"
```
Expected: 提交成功；post-commit hook 自动 bump 版本并 amend 回本次提交（幂等，见项目 CLAUDE.md）。

---

## Task 2：建立共享 viewport 与 AppShell 边界矩阵

**Files:**
- Create: `test/helpers/responsive_viewport_cases.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `AppBreakpoints`（shell 判定已迁移）。
- Produces: `ResponsiveViewportCase` / `requiredShellViewports` / `androidLandscape`，Task 3–5 共享。

### Step 1：创建共享视口事实源

新建 `test/helpers/responsive_viewport_cases.dart`（完整内容；命名与注释必须 durable，不含任何审查编号）：

```dart
import 'package:flutter/widgets.dart';

/// 应用壳在当前视口下应呈现的导航模式。
enum ShellNavigationMode { bottomBar, rail }

/// 一个共享的响应式测试视口描述：宽度 + 壳层导航期望。
final class ResponsiveViewportCase {
  const ResponsiveViewportCase({
    required this.name,
    required this.size,
    required this.shellMode,
  });

  final String name;
  final Size size;
  final ShellNavigationMode shellMode;
}

/// 手机竖屏：常见移动端与最窄核心场景。
const phonePortrait = ResponsiveViewportCase(
  name: 'phonePortrait',
  size: Size(390, 844),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 紧凑平板：消息气泡代表值与 compact 页面。
const compactTablet = ResponsiveViewportCase(
  name: 'compactTablet',
  size: Size(600, 900),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 壳层断点前一像素：仍为紧凑。
const shellBelowBoundary = ResponsiveViewportCase(
  name: 'shellBelowBoundary',
  size: Size(719, 900),
  shellMode: ShellNavigationMode.bottomBar,
);

/// 壳层断点等号：恰好 720 进入宽侧（rail）。
const shellAtBoundary = ResponsiveViewportCase(
  name: 'shellAtBoundary',
  size: Size(720, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 壳层断点后一像素：稳定在宽侧。
const shellAboveBoundary = ResponsiveViewportCase(
  name: 'shellAboveBoundary',
  size: Size(721, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 平板/窄桌面。
const desktop = ResponsiveViewportCase(
  name: 'desktop',
  size: Size(1024, 768),
  shellMode: ShellNavigationMode.rail,
);

/// 常规桌面；高度 900，避免用 1200/1600 的高度掩盖滚动问题。
const wideDesktop = ResponsiveViewportCase(
  name: 'wideDesktop',
  size: Size(1440, 900),
  shellMode: ShellNavigationMode.rail,
);

/// 全部必需的七个壳层视口。
const requiredShellViewports = [
  phonePortrait,
  compactTablet,
  shellBelowBoundary,
  shellAtBoundary,
  shellAboveBoundary,
  desktop,
  wideDesktop,
];

/// Android 横屏低高度场景，供 Sync/Media 使用；不并入壳层循环。
const androidLandscape = Size(844, 390);
```

### Step 2：重写 AppShell 测试为参数化矩阵

将 `test/app/shell/app_shell_scaffold_test.dart` **整体替换**为（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oh_my_llm/app/navigation/app_destination.dart';
import 'package:oh_my_llm/app/shell/app_shell_scaffold.dart';

import '../../helpers/responsive_viewport_cases.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required AppDestination destination,
  required Size size,
  Widget? endDrawer,
  List<Widget> actions = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: destination.path,
    routes: [
      for (final dest in AppDestination.values)
        GoRoute(
          path: dest.path,
          builder: (context, state) => AppShellScaffold(
            currentDestination: dest,
            title: dest.label,
            body: Text('${dest.label}页面'),
            endDrawer: endDrawer,
            actions: actions,
          ),
        ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // 初次挂载只 pump；真实导航/抽屉动画之后再 settle。
  await tester.pump();
}

void main() {
  for (final viewport in requiredShellViewports) {
    testWidgets('${viewport.name}: 目的地导航可达', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
      );
      expect(tester.takeException(), isNull);

      const target = AppDestination.history;
      final navLabel = find.text(target.label);
      if (viewport.shellMode == ShellNavigationMode.bottomBar) {
        await tester.tap(
          find.descendant(of: find.byType(NavigationBar), matching: navLabel),
        );
      } else {
        await tester.tap(
          find.descendant(of: find.byType(NavigationRail), matching: navLabel),
        );
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('${target.label}页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in requiredShellViewports.where(
    (v) => v.shellMode == ShellNavigationMode.bottomBar,
  )) {
    testWidgets('${viewport.name}: 抽屉可打开且内容可达', (tester) async {
      await _pumpShell(
        tester,
        destination: AppDestination.chat,
        size: viewport.size,
        endDrawer: const Drawer(child: Text('侧边内容')),
      );

      await tester.tap(find.byTooltip('打开侧边内容'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('侧边内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
```

**注意：**
- `NavigationBar` / `NavigationRail` 类型仅作为 `find.descendant` 的 ancestor 定位真实可见导航（既有测试同款手法），不新增「另一导航 widget 不存在」的负向断言。
- 390/600/719 通过 `bottomBar` 循环自动覆盖 endDrawer；720/721/1024/1440 不显示抽屉按钮，其端抽屉入口本就不存在，无需断言。

### Step 3：定向运行

Run（PowerShell）:
```powershell
flutter test test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-shell.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-shell.log
```
Expected: `EXIT=0`，七个 navigation case + 三个 drawer case 全过。

### Step 4：格式化并提交

```powershell
dart format test/helpers/responsive_viewport_cases.dart test/app/shell/app_shell_scaffold_test.dart
```
```bash
git add test/helpers/responsive_viewport_cases.dart test/app/shell/app_shell_scaffold_test.dart
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git diff --cached --check
```
```bash
git commit -m "test(ui): 固化应用壳视口边界矩阵" \
           -m "共享 ResponsiveViewportCase 视口事实源；AppShell 在 390/600/719/720/721/1024/1440
下通过可见导航完成真实 destination 切换，compact 视口覆盖端抽屉可达性。"
```

---

## Task 3：补齐 Chat viewport matrix

**Files:**
- Create: `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`
- Create: `test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart`
- Modify: `test/features/chat/chat_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `requiredShellViewports`/`androidLandscape`（本 Task 用前者）；Task 1 的 composer/bubble 迁移。
- Produces: `registerChatScreenResponsiveTests()`（在 `chat_screen_test.dart` 注册）。

### Step 1：注册入口

修改 `test/features/chat/chat_screen_test.dart`，import 并注册：
```dart
import 'chat_screen/chat_screen_responsive_cases.dart';
// ...
void main() {
  registerChatScreenBasicsTests();
  registerChatScreenStreamingTests();
  registerChatScreenBranchingTests();
  registerChatScreenFavoritesTests();
  registerChatScreenWorkspaceOwnershipTests();
  registerChatScreenResponsiveTests();
}
```

### Step 2：创建 Chat responsive cases

新建 `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/persistence/app_database.dart';
import 'package:oh_my_llm/features/chat/domain/chat_message_parent.dart';

import '../../../helpers/fake_chat_completion_client.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/responsive_viewport_cases.dart';
import 'chat_screen_test_helpers.dart';

/// 含一对 user/assistant 消息的会话 JSON，供窄父约束下气泡内容可达验证。
/// 结构对齐 `history_screen_test_helpers.dart` 的 `_conversation`。
Map<String, dynamic> _seededConversation() => {
  'id': 'conversation-responsive',
  'title': '响应式会话',
  'messageNodes': [
    {
      'id': 'u-1',
      'role': 'user',
      'content': '这是一条较长的用户消息，用来验证窄父约束下气泡正文可达。',
      'parentId': rootConversationParentId,
      'createdAt': DateTime(2026, 5, 5, 10, 0).toIso8601String(),
    },
    {
      'id': 'a-1',
      'role': 'assistant',
      'content': '这是一条较长的助手回复，用来验证窄父约束下气泡正文完整可见。',
      'parentId': 'u-1',
      'createdAt': DateTime(2026, 5, 5, 10, 1).toIso8601String(),
    },
  ],
  'selectedChildByParentId': {rootConversationParentId: 'u-1', 'u-1': 'a-1'},
  'selectedModelId': null,
  'selectedPresetPromptId': null,
  'reasoningEnabled': false,
  'reasoningEffort': 'medium',
};

/// 点击抽屉遮罩关闭端抽屉（tap 屏幕左上角空白区）。
Future<void> _closeDrawer(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

void registerChatScreenResponsiveTests() {
  for (final viewport in requiredShellViewports) {
    testWidgets('${viewport.name}: 标题/正文/发送入口可达', (tester) async {
      final fakeClient = FakeChatCompletionClient();
      await pumpChatScreen(tester, fakeClient: fakeClient, size: viewport.size);

      expect(find.text('未命名对话'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in requiredShellViewports.where(
    (v) => v.shellMode == ShellNavigationMode.bottomBar,
  )) {
    testWidgets('${viewport.name}: 抽屉内历史/预设可达，关闭后正文可输入', (tester) async {
      final fakeClient = FakeChatCompletionClient();
      await pumpChatScreen(tester, fakeClient: fakeClient, size: viewport.size);

      await tester.tap(find.byTooltip('打开侧边内容'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('历史会话'), findsOneWidget);
      expect(find.text('预设 Prompt'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _closeDrawer(tester);
      expect(find.text('正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in requiredShellViewports.where(
    (v) => v.shellMode == ShellNavigationMode.rail,
  )) {
    testWidgets('${viewport.name}: activity bar 触发历史会话侧栏', (tester) async {
      final fakeClient = FakeChatCompletionClient();
      await pumpChatScreen(tester, fakeClient: fakeClient, size: viewport.size);

      // 初始侧栏即展开；先折叠再通过 activity bar 重新展开，证明图标可操作。
      await tester.tap(find.byTooltip('历史会话'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      await tester.tap(find.byTooltip('历史会话'));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('历史会话面板'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('600: compact composer 摘要与设置 sheet 可达', (tester) async {
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(600, 900),
    );

    expect(find.textContaining('更多设置'), findsOneWidget);
    await tester.tap(find.textContaining('更多设置'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.text('深度思考'), findsOneWidget);
    expect(find.text('自动重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1440: 完整操作区固定顺序与消息过滤可达', (tester) async {
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      size: const Size(1440, 900),
    );

    expect(find.text('固定顺序提示词'), findsOneWidget);
    expect(find.text('上下文过滤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('600: seed 消息双方正文可达且无 overflow', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final preferences = await TestFixtures.seedPreferences(
      database: db,
      models: [TestFixtures.gpt41()],
      prompts: [TestFixtures.codeAssistantPrompt()],
      conversations: [_seededConversation()],
    );
    final fakeClient = FakeChatCompletionClient();
    await pumpChatScreen(
      tester,
      fakeClient: fakeClient,
      preferences: preferences,
      database: db,
      size: const Size(600, 900),
    );

    expect(find.textContaining('这是一条较长的用户消息'), findsOneWidget);
    expect(find.textContaining('这是一条较长的助手回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

### Step 3：创建 composer focused test

新建 `test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart`（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/features/chat/application/chat_workspace_view_state.dart';
import 'package:oh_my_llm/features/chat/domain/models/chat_message.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/chat_composer_card.dart';
import 'package:oh_my_llm/features/chat/presentation/widgets/chat_workspace_bindings.dart';

ChatWorkspaceComposerState _composerState() => const ChatWorkspaceComposerState(
  modelProviders: [],
  modelConfigs: [],
  selectedProviderId: null,
  selectedModel: null,
  templatePrompts: [],
  selectedTemplatePrompt: null,
  fixedPromptSequences: [],
  isComposerCollapsed: false,
  reasoningEnabled: false,
  reasoningEffort: ReasoningEffort.low,
  supportsReasoning: false,
  autoRetryEnabled: false,
  isBusy: false,
  isStreaming: false,
  isAutoRetryWaiting: false,
  excludedMessageCount: 0,
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

/// 以指定父宽度挂载 composer，父约束只决定 formActions 分支。
Future<void> _pumpComposer(
  WidgetTester tester,
  double parentWidth, {
  required ChatWorkspaceComposerState state,
  required ChatWorkspaceComposerBindings bindings,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: parentWidth,
            child: ChatComposerCard(state: state, bindings: bindings),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [679.0, 680.0, 681.0]) {
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
        // 680/681：完整操作行。
        expect(find.text('固定顺序提示词'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
```

### Step 4：定向运行

Run（PowerShell）:
```powershell
flutter test test/features/chat/chat_screen_test.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-chat.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-chat.log
```
Expected: `EXIT=0`。

### Step 5：格式化并提交

```powershell
dart format test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_responsive_cases.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart
```
```bash
git add test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_responsive_cases.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git diff --cached --check
```
```bash
git commit -m "test(chat): 覆盖工作区响应式视口矩阵" \
           -m "七视口页面 smoke、compact drawer、rail activity bar 侧栏、composer 两分支
（679/680/681）与 seed 消息 bubble 内容可达，全部只断言可见文案与无 exception。"
```

---

## Task 4：补齐 Settings compact matrix

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`（`switchToTab` 增强）
- Create: `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`
- Modify: `test/features/settings/settings_screen_test.dart`（注册）

**Interfaces:**
- Consumes: Task 1 的 ProviderTile/ProviderModelTile 局部阈值；现有 `pumpSettingsScreen`/`setUpSettingsScreen`/`switchToTab`/`tabLabels`。
- Produces: `registerSettingsScreenResponsiveTests()`。

### Step 1：增强 `switchToTab` 可达性

修改 `test/features/settings/settings_screen/settings_screen_test_helpers.dart` 第 19–22 行：
```dart
/// 切换到指定标签页；先确保 tab 在滚动区域内可见再点击。
Future<void> switchToTab(WidgetTester tester, int index) async {
  final tabFinder = find.text(tabLabels[index]);
  await tester.ensureVisible(tabFinder);
  await tester.tap(tabFinder);
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}
```

### Step 2：确认既有桌面行为不变

Run（PowerShell）:
```powershell
flutter test test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-settings-helper.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-settings-helper.log
```
Expected: `EXIT=0`（`ensureVisible` 是纯增强，tab 已可见时立即返回）。

### Step 3：创建 Settings responsive cases

新建 `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_screen_test_helpers.dart';

/// 每个 tab 的关键 heading（内容区可滚动到达的文案）。
const _tabHeadingByIndex = <int, String>{
  0: '服务商设置',
  1: '预设 Prompt',
  2: '记忆总结提示词',
  3: '请求头定义',
  4: '输出正则处理',
  5: '自动重试',
};

/// 提示词 tab 除首个 section 外的补充 heading。
const _promptsTabAdditionalHeadings = ['模板提示词', '固定顺序提示词'];

void registerSettingsScreenResponsiveTests() {
  for (final width in [390.0, 600.0]) {
    testWidgets('${width.toInt()}px: 六 tab 关键 heading 可达', (tester) async {
      // 1500 高度视口下各 tab 内容区的关键 heading 均在首屏直接可见，
      // 无需滚动；若内容超高产生 overflow，takeException 会直接失败。
      await setUpSettingsScreen(
        tester,
        size: Size(width, 1500),
        useDefaultsSeed: true,
      );
      expect(tester.takeException(), isNull);

      for (var i = 0; i < tabLabels.length; i++) {
        await switchToTab(tester, i);
        final heading = _tabHeadingByIndex[i]!;
        expect(find.text(heading), findsWidgets);
        if (i == 2) {
          for (final additional in _promptsTabAdditionalHeadings) {
            expect(find.text(additional), findsWidgets);
          }
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('390px: 新增服务商表单内容可达', (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(390, 1500),
      useDefaultsSeed: true,
    );

    await tester.tap(find.text('新增服务商'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(providerNameField(), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 填入名称后取消关闭对话框，证明表单可交互且可达可退出；
    // 业务校验树由既有模型表单测试覆盖，此处不重复。
    await tester.enterText(providerNameField(), '测试服务商');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('600px: 新增预设 Prompt compact 表单内容可达', (tester) async {
    await setUpSettingsScreen(
      tester,
      size: const Size(600, 1500),
      useDefaultsSeed: true,
    );
    await switchToTab(tester, 1);

    await tester.tap(find.text('新增预设'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(presetPromptNameField(), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1024.0, 1440.0]) {
    testWidgets('${width.toInt()}px: 服务商页 smoke', (tester) async {
      await setUpSettingsScreen(
        tester,
        size: Size(width, 900),
        useDefaultsSeed: true,
      );

      expect(find.text('服务商设置'), findsOneWidget);
      expect(find.text('新增服务商'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
```

**说明：**
- `useDefaultsSeed: true` 会 seed `gpt41` + `claudeSonnet` 与一个预设，使服务商 tab 出现 `ProviderTile`（`640` 阈值）及其内嵌 `ProviderModelTile`（`560` 阈值）在 390/600 下走 compact 分支，自然覆盖两处局部阈值，无需坐标断言。
- `providerNameField()` / `presetPromptNameField()` 复用既有 finder 工厂；对话框保存/取消按钮文案来自 `SettingsFormDialogScaffold`（`'保存'`/`'取消'`）。

### Step 4：注册入口

修改 `test/features/settings/settings_screen_test.dart`：
```dart
import 'settings_screen/settings_screen_responsive_cases.dart';
// ...
void main() {
  registerSettingsScreenModelsAndPromptsTests();
  registerSettingsScreenFixedPromptSequencesTests();
  registerSettingsScreenTabNavigationTests();
  registerSettingsScreenResponsiveTests();
}
```

### Step 5：定向运行

Run（PowerShell）:
```powershell
flutter test test/features/settings/settings_screen_test.dart test/features/settings/presentation/model_config_form_dialog_test.dart test/features/settings/presentation/output_processing_tab_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-settings.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-settings.log
```
Expected: `EXIT=0`。若 390/600 下出现 overflow，先判定是否为 ProviderTile/ProviderModelTile 的局部阈值使用错误；**不得**为提高可测性直接拉高测试宽度。

### Step 6：格式化并提交

```powershell
dart format test/features/settings/settings_screen_test.dart test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart
```
```bash
git add test/features/settings/settings_screen_test.dart test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git diff --cached --check
```
```bash
git commit -m "test(settings): 补齐紧凑视口行为矩阵" \
           -m "390/600 下六 tab 关键 heading、新增服务商与预设表单内容、1024/1440 服务商
smoke；switchToTab 先 ensureVisible。全部只断言可见文案与无 exception。"
```

---

## Task 5：补齐 Sync/Media compact 与横屏矩阵

**Files:**
- Create: `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`
- Modify: `test/features/sync/sync_screen_test.dart`（注册）
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`（参数化 smoke + compact/landscape route）

**Interfaces:**
- Consumes: Task 2 的 `requiredShellViewports`/`androidLandscape`；既有 `pumpSyncScreen`/`SeededSyncClientController`/`connectedSyncState`/`RecordingMediaBrowserController`/`RecordingShufflePlaybackController`/`FakeMediaBrowserController`/`testServer`/`MediaBrowserState`/`FileItem`。
- Produces: `registerSyncScreenResponsiveTests()`。

### Step 1：创建 Sync responsive cases

新建 `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`（完整内容）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oh_my_llm/features/media/application/media_browser_controller.dart';
import 'package:oh_my_llm/features/media/presentation/media_browser_tab.dart';
import 'package:oh_my_llm/features/sync/application/sync_client_controller.dart';

import '../../../helpers/responsive_viewport_cases.dart';
import 'sync_screen_test_helpers.dart';

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void registerSyncScreenResponsiveTests() {
  for (final width in [390.0, 600.0]) {
    testWidgets('${width.toInt()}px: 同步页关键内容可达', (tester) async {
      final preferences = await _freshPrefs();
      await pumpSyncScreen(
        tester,
        preferences: preferences,
        size: Size(width, 1200),
      );

      expect(find.text('局域网同步'), findsOneWidget);
      expect(find.text('连接'), findsWidgets);
      expect(find.text('同步'), findsWidgets);
      expect(find.text('作为客户端'), findsOneWidget);
      expect(find.text('作为服务端'), findsOneWidget);

      await tester.tap(find.text('同步').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      expect(find.text('请先在「连接」标签页中连接到服务端'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in [shellBelowBoundary, shellAtBoundary, shellAboveBoundary]) {
    testWidgets('${viewport.name}: 同步页壳层边界', (tester) async {
      final preferences = await _freshPrefs();
      await pumpSyncScreen(tester, preferences: preferences, size: viewport.size);

      expect(find.text('局域网同步'), findsOneWidget);
      if (viewport.shellMode == ShellNavigationMode.bottomBar) {
        expect(find.byType(NavigationBar), findsOneWidget);
      } else {
        expect(find.byType(NavigationRail), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('844x390 Android 横屏: 媒体 tab 可达且离开后 reset', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final preferences = await _freshPrefs();
    await pumpSyncScreen(
      tester,
      preferences: preferences,
      size: androidLandscape,
      extraOverrides: [
        syncClientControllerProvider.overrideWith(
          () => SeededSyncClientController(connectedSyncState()),
        ),
        mediaBrowserControllerProvider.overrideWith(
          RecordingMediaBrowserController.new,
        ),
        shufflePlaybackControllerProvider.overrideWith(
          RecordingShufflePlaybackController.new,
        ),
      ],
    );

    await tester.tap(find.text('媒体'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.byType(MediaBrowserTab), findsOneWidget);
    expect(RecordingMediaBrowserController.lastState!.server, isNotNull);
    // 路径栏根 chip 在低高度横屏下仍可见，证明媒体内容区可达。
    expect(find.text('🏠'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 离开媒体 tab：session reset 契约保持。
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(RecordingMediaBrowserController.lastState, MediaBrowserState());
    expect(tester.takeException(), isNull);
  });
}
```

**说明：** Android override 只用于让产品既有的「媒体」tab 出现，不用于布局判定（`_hasMediaTab => defaultTargetPlatform == android` 属既有功能可用性判断，不在本 Phase 修改范围）。

### Step 2：注册入口

修改 `test/features/sync/sync_screen_test.dart`：
```dart
import 'sync_screen/sync_screen_responsive_cases.dart';
// ...
void main() {
  registerSyncScreenRenderTests();
  registerSyncScreenImportDialogTests();
  registerSyncScreenResponsiveTests();
}
```

### Step 3：扩展 Media 导航测试为参数化视口

修改 `test/features/media/presentation/media_browser_navigation_test.dart`：保留既有四个测试（默认 1440，route URI/back 契约），在 `main()` 末尾追加：

```dart
  const mediaSmokeViewports = [
    Size(390, 844),
    Size(600, 900),
    Size(844, 390),
    Size(1024, 768),
    Size(1440, 900),
  ];

  for (final viewportSize in mediaSmokeViewports) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 路径栏与目录/图片/视频可达',
      (tester) async {
        final prefs = await _testPrefs();
        final router = _mediaRouter();
        await pumpTestApp(
          tester,
          preferences: prefs,
          router: router,
          viewportSize: viewportSize,
          extraOverrides: [
            mediaBrowserControllerProvider.overrideWith(
              () => FakeMediaBrowserController(
                MediaBrowserState(
                  server: testServer,
                  items: [
                    _dir('/相册'),
                    _file('/相册/猫.jpg'),
                    _file('/视频/demo.mp4'),
                  ],
                ),
              ),
            ),
          ],
        );

        expect(find.text('🏠'), findsOneWidget);
        expect(find.text('相册'), findsOneWidget);
        expect(find.text('猫.jpg'), findsOneWidget);
        expect(find.text('demo.mp4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final viewportSize in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
      '${viewportSize.width}x${viewportSize.height}: 图片 route push/back 保持 URI 契约',
      (tester) async {
        final prefs = await _testPrefs();
        final router = _mediaRouter();
        await pumpTestApp(
          tester,
          preferences: prefs,
          router: router,
          viewportSize: viewportSize,
          extraOverrides: [
            mediaBrowserControllerProvider.overrideWith(
              () => FakeMediaBrowserController(
                MediaBrowserState(
                  server: testServer,
                  items: [_file('/相册/猫.jpg')],
                ),
              ),
            ),
          ],
        );

        await tester.tap(find.text('猫.jpg'));
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
        expect(
          router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
          '/sync/media/image',
        );

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle(const Duration(milliseconds: 250));
        expect(
          router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
          '/sync',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
```

**注意：** 只新增 viewport 覆盖；不断言列数、tile 尺寸或坐标，不修改生产 grid delegate；`_dir`/`_file` 沿用文件既有 helper。

### Step 4：定向运行

Run（PowerShell）:
```powershell
flutter test test/features/sync/sync_screen_test.dart test/features/media/presentation/media_browser_navigation_test.dart test/features/media/presentation/media_route_pages_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-sync-media.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-sync-media.log
```
Expected: `EXIT=0`。

### Step 5：处理可能的 production overflow（仅当稳定复现时）

若矩阵在 Sync/Media 中稳定复现 overflow，按源文档 4.4 的规则严格处理，**不做任何默认性 production 修改**：
1. 先把失败缩成单个 focused widget test；
2. 证明错误来自约束而非 fake/动画未完成；
3. 只在触发组件加 `Flexible`/`Expanded`/`Wrap` 或既有滚动容器中的一种最小修复；
4. 不新增平台/方向判断、不改媒体列数、不改 Tab/route/state；
5. 修复放入独立 `fix(sync)` 或 `fix(media)` commit，**先提交修复再提交矩阵测试**，不得把视觉重构夹入 test commit。

### Step 6：格式化并提交

```powershell
dart format test/features/sync/sync_screen_test.dart test/features/sync/sync_screen/sync_screen_responsive_cases.dart test/features/media/presentation/media_browser_navigation_test.dart
```
```bash
git add test/features/sync/sync_screen_test.dart test/features/sync/sync_screen/sync_screen_responsive_cases.dart test/features/media/presentation/media_browser_navigation_test.dart
dart format --output=none --set-exit-if-changed $(git diff --cached --name-only -- '*.dart')
git diff --cached --check
```
```bash
git commit -m "test(sync): 补齐同步与媒体视口矩阵" \
           -m "Sync 390/600 内容可达与 719/720/721 壳层边界；844x390 Android 横屏媒体
tab 可达与离开 reset；Media 浏览与图片 route push/back 在五个视口下保持可达与 URI 契约。"
```

---

## Task 6：最终审计、格式与全量门禁

**Files:** 无新增；全项目验证。

**Interfaces:** 依赖 Task 1–5 全部落地。

### Step 1：范围与反模式审计

Run（PowerShell）:
```powershell
rg -n "AppBreakpoints\.(compact|isCompact)" lib test
rg -n "OrientationBuilder|MediaQuery\.orientationOf|isTablet|isPhone" lib/app lib/core lib/features/chat/presentation lib/features/settings/presentation lib/features/sync/presentation lib/features/media/presentation
rg -n "getTopLeft|getRect|find\.byKey|maxLines|expands" test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen/chat_screen_responsive_cases.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart test/features/sync/sync_screen/sync_screen_responsive_cases.dart test/features/media/presentation/media_browser_navigation_test.dart
```
Expected:
- 第一条 **无命中**。
- 第二条必须没有新布局判定命中（现有功能可用性平台判断不在此 regex，如 Sync 的 `defaultTargetPlatform == android`）。
- 第三条在**新增** responsive 测试文件中必须无命中；若现有 media 旧测试命中，不得以它作为新响应式断言依据，本 Phase 不要求无关清理。

### Step 2：格式化与 staged 复检

Task 1–5 各自提交前已格式化；本步对 Phase 涉及的全部 27 个 Dart 文件做最终复核（`--set-exit-if-changed` 对已格式化文件返回 exit 0，漏格式化的返回非 0）：

Run（PowerShell）:
```powershell
git diff --name-only -- '*.dart'
dart format --output=none --set-exit-if-changed lib/core/constants/app_breakpoints.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart lib/features/chat/presentation/chat_screen.dart lib/features/chat/presentation/widgets/chat_workspace.dart lib/features/chat/presentation/widgets/chat_messages_panel.dart lib/features/chat/presentation/widgets/chat_composer_card.dart lib/features/chat/presentation/widgets/chat_message_bubble.dart lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart lib/features/settings/presentation/widgets/list/provider_tile.dart lib/features/settings/presentation/widgets/list/provider_model_tile.dart test/helpers/responsive_viewport_cases.dart test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen_test.dart test/features/chat/chat_screen/chat_screen_responsive_cases.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart test/features/settings/settings_screen_test.dart test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart test/features/sync/sync_screen_test.dart test/features/sync/sync_screen/sync_screen_responsive_cases.dart test/features/media/presentation/media_browser_navigation_test.dart
git diff --cached --check
```
Expected: 两条均 exit 0。若 `git diff --name-only` 显示任务已提交、工作区 clean，属正常（Task 1–5 已各自提交）。不得 `git add .`；不得把 `fltest*.log` 或无关用户改动加入提交。

### Step 3：架构与静态分析

Run（PowerShell）:
```powershell
dart run tool/architecture/import_boundary_checker.dart
flutter analyze
```
Expected: 两条都成功。`flutter analyze` 若超时**不能记为通过**，先处理工具链后重跑（这是源文档明确的红线：超时不是 green）。

### Step 4：强制格式全量测试

Run（PowerShell，强制重定向）:
```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```
Expected: `EXIT=0` 才完成。失败详情从 `fltest.log` 查询；**不得**直接裸跑全量测试。

---

## 完成定义（Definition of Done）

- [ ] `AppBreakpoints` 不再暴露 `compact`/`isCompact`；shell/content/dialog/form/bubble 六 token 的职责与等号行为有简体中文 doc。
- [ ] AppShellScaffold、Chat shell consumers、composer、bubble、AdaptiveMasterDetailLayout 默认值、两个 Chat dialog、两个 Settings form 全部使用正确 token；ProviderTile `640` 与 ProviderModelTile `560` 已类内命名且未统一。
- [ ] 固定 dialog widths（920/1120/1080 等）、`FontWeight` 与其它非断点数未被机械替换。
- [ ] `app_breakpoints_test.dart` 覆盖 599/600/601、679/680/681、719/720/721 三组等号边界；`adaptive_master_detail_layout_test.dart` 覆盖默认 839/840/841 与可注入 759/760。
- [ ] 共享 viewport matrix 包含 390、600、719、720、721、1024、1440；AppShell 全矩阵（7 navigation + 3 drawer）通过。
- [ ] Chat responsive cases 覆盖 compact drawer、rail activity bar 侧栏、composer 679/680/681 两分支、600 seed 消息 bubble 内容可达。
- [ ] Settings 在 390/600 下六 tab 关键 heading 可达、新增服务商与预设表单内容可达；1024/1440 服务商 smoke 通过。
- [ ] Sync 在 390/600 下可达、719/720/721 壳层边界通过、844×390 Android media case 通过（含离开 reset）。
- [ ] Media 浏览在 compact/landscape/desktop 下路径与条目可达，compact/landscape 图片 push/back 保持 Phase 12 URI 契约；列数未改变。
- [ ] 新测试无 `getTopLeft`/`getRect`/`find.byKey`/widget 私有属性/像素断言，无 conditional early return，每个 iteration 都有业务 expect + `takeException`。
- [ ] 新生产代码无 orientation/device-type 布局分支，无 presentation → data/persistence 新依赖。
- [ ] 本 Phase 全部 Dart 文件已格式化，staged format check 与 `git diff --cached --check` 通过。
- [ ] architecture import checker 与 `flutter analyze` 通过（analyze 超时不记为通过）。
- [ ] 全量测试按强制重定向命令运行并得到 `EXIT=0`。
- [ ] 每个 commit 只含对应任务文件与 hook 自动产生的版本变化，可独立回滚（序列见源文档第九节）。

## 停止条件（须停下并重新定界）

1. 需要移动现有断点数值才能让测试通过（本 Phase 只命名并冻结现有行为）。
2. 720/721 出现无法用现有 compact/expanded 分支解释的内容不可达，且修复需改变 Chat/AppShell 信息架构或新增导航模式。
3. Settings/Sync compact 失败根因在 controller/持久化/协议/路由状态而非 presentation constraints。
4. Media 响应式改进需要改变列数、tile 设计、缩略图协议或 playback UI。
5. 需要 orientation lock、平台布局分支或硬件类型识别。
6. 需要用 internal key、像素坐标或 widget 私有属性才能证明目标（应换可观察行为）。
7. baseline 定向测试在任何本 Phase 改动前已失败（先报告既有失败）。
