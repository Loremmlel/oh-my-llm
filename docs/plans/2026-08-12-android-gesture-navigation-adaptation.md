# Android 手势与返回导航适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 系统返回手势遵循固定起点、临时 UI 优先、详情路由可预测返回的导航契约，同时消除播放器、右侧抽屉与系统边缘手势的已知冲突，并保证 Windows 键鼠行为不退化。

**Architecture:** 顶层导航继续使用现有平铺 `GoRoute`，由 `AppShellScaffold` 成为每个顶层页面唯一的返回策略入口：页面本地临时状态优先消费 Back，非聊天顶层页回到固定起点 `/chat`，聊天根页把 Back 交给系统退出。详情、图片和视频仍由 GoRouter 子路由自然 pop；媒体 Tab 的目录返回从离屏 `MediaBrowserTab` 上移到当前可见的 `SyncWorkspaceScreen`。播放器手势层与控制层改为兄弟关系，并只在 `systemGestureInsets` 之外接收横向拖动。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6；本次审计环境 3.44.8）· Dart `^3.11.5` · go_router 17.4.0 · Riverpod 3 · Android API 33+ predictive back · `flutter_test`

## Global Constraints

- 不引入新的路由、手势或 AndroidX 依赖；不新增原生 MethodChannel 来接管 Back。
- 不使用 `WillPopScope`、`Navigator.willPop`、`onBackPressed` 或 `KeyEvent.KEYCODE_BACK` 拦截返回；需要拦截时只使用提前可知的 `PopScope.canPop` 状态。
- 不使用 `View.setSystemGestureExclusionRects()` 抢占系统边缘；系统 Back 优先于抽屉打开、视频 seek 和图片翻页。
- 不迁移 `ShellRoute` / `StatefulShellRoute`，不把媒体目录写进 URL，不改变现有收藏与媒体可恢复路由契约。
- 非聊天顶层页 Back 回 `/chat`；聊天根页 Back 退出应用。详情页 Back/Up 继续 pop 到父页。
- 临时 UI 的 Back 优先级固定为：系统弹层/抽屉 → 页面本地状态（历史选择、消息编辑、媒体目录/Tab）→ 子路由 → 非聊天顶层回 `/chat` → 聊天根页退出。
- 异步保存、导入、总结已开始后，Back 与 barrier 点击都不得销毁其对话框；操作完成或失败后恢复正常退出能力。
- 全屏图片/视频继续支持键盘与显式关闭按钮；Android 边缘手势不应触发图片翻页、视频 seek 或右侧抽屉。
- 注释使用简体中文并解释“为什么”；代码与测试名称不得写临时审查/阶段编号。
- 所有 Dart 改动提交前执行 `dart format`；全量测试必须按仓库规定重定向到日志文件。

---

## 1. 官方基线与仓库审计

### 1.1 官方文档结论

1. Flutter predictive back 要求返回是否允许在手势开始前已知；`WillPopScope` 一类“收到 Back 后再决定”的 API 不兼容。`PopScope.canPop` 负责提前声明，`onPopInvokedWithResult` 只观察已经处理或被阻止的结果：
   - [Flutter Android predictive back migration](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)
   - [Flutter PopScope API](https://api.flutter.dev/flutter/widgets/PopScope-class.html)
2. Flutter 3.38 起 Android 默认页面转场已经是 `PredictiveBackPageTransitionsBuilder`；本项目使用 Flutter 3.44，不需要在 `ThemeData` 重复配置：
   - [Flutter default Android page transition](https://docs.flutter.dev/release/breaking-changes/default-android-page-transition)
3. Flutter 的平台接入文档仍要求在 Android manifest 启用 `android:enableOnBackInvokedCallback="true"`，以接入系统 predictive back：
   - [Flutter: Add the predictive-back gesture](https://docs.flutter.dev/platform-integration/android/predictive-back)
4. Android 的返回栈必须有固定 start destination；它既是 launcher 首次进入的页面，也是 Back 退出应用前最后一页。Up 与 Back 在应用任务内行为一致，但 Up 不退出应用：
   - [Android principles of navigation](https://developer.android.com/guide/navigation/principles)
5. Android 10+ 的左右边缘属于系统 Back。官方要求处理冲突，并避免把拖动目标放在系统手势 inset 中；排除区只应在确有必要时窄范围使用：
   - [Android gesture navigation compatibility](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav)
   - [Flutter `MediaQueryData.systemGestureInsets`](https://api.flutter.dev/flutter/widgets/MediaQueryData/systemGestureInsets.html)
6. Android predictive back 的回调应由可观察 UI 状态启用/禁用，每个回调只承担一个职责；默认系统动画应尽量保留：
   - [Android predictive back implementation guide](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)
7. Android 设计指南把全屏图片/视频视为全屏 modal，显式导航 affordance 应使用 close，而不是把应用内 Up 与 modal dismiss 混为一谈：
   - [Android: Translate designs to Android](https://developer.android.com/design/ui/mobile/guides/foundations/translate-designs)

### 1.2 做得较好的现状

- `pubspec.yaml` 使用 `go_router: ^17.4.0`；收藏详情和媒体图片/视频都已是 GoRouter child route，没有 feature 内 `MaterialPageRoute` 平行栈。
- 全仓没有 `WillPopScope`、`Navigator.willPop`、原生 `onBackPressed` 或 `KEYCODE_BACK`。
- Flutter 3.44 已默认提供 Android predictive page transition；`AppTheme` 没有覆盖成旧的 `ZoomPageTransitionsBuilder`。
- 图片查看器在缩放状态下禁用 `PageView`，未缩放时禁用 `InteractiveViewer.panEnabled`，已处理两套 Flutter 手势识别器之间的竞技场冲突。
- 弹窗、PopupMenu、BottomSheet 和 Drawer 都使用 Flutter route/Material 组件，系统 Back 原则上可以先关闭最上层弹层。
- 视频播放器已有 Escape、方向键、空格键和焦点语义，Windows 键盘路径可以继续复用。

### 1.3 已确认问题与优先级

| 优先级 | 位置 | 证据 | 用户影响 | 计划任务 |
|---|---|---|---|---|
| P0 | `android/app/src/main/AndroidManifest.xml` | `<application>` 缺少 `enableOnBackInvokedCallback` | Android 预测性返回的系统 opt-in 不完整 | Task 1 |
| P0 | `AppShellScaffold` 顶层切换 | 五个顶层入口使用 `context.go`，非 `/chat` 根页没有上一层栈 | 从历史/收藏/设置/同步按 Back 会直接离开应用，不符合固定 start destination | Task 2 |
| P0 | `MediaBrowserTab` | 离屏 Tab 自身持有 `PopScope(canPop: false)`，且收到 Back 后才异步 `goBack()` | 访问过媒体 Tab 后，离屏 PopScope 仍可能阻断 `/sync` 的正常 Back；预测性动画长期被禁用 | Task 3 |
| P1 | `HistoryScreen` / `ChatScreen` | 选择态与消息编辑态没有 Back 契约 | Back 不能优先取消选择/编辑，可能丢失瞬态操作上下文 | Task 2 |
| P1 | `VideoPlayerPage` | 全页祖先 `GestureDetector` 同时声明 tap/double-tap/long-press/horizontal-drag | 控制按钮 tap 被双击识别器延迟；现有测试必须推进 `kDoubleTapTimeout` 才能点返回/重试 | Task 4 |
| P1 | 视频与底部 Slider | 全屏横拖从左右边缘也能开始，未读取 `systemGestureInsets`；没有 `onHorizontalDragCancel` | 与左右边缘 Back 竞争；手势被系统取消时可能遗留隐藏控件/seek 预览状态 | Task 4 |
| P1 | 紧凑布局 `endDrawer` | `Scaffold.endDrawerEnableOpenDragGesture` 默认在 mobile 为 true | 从右边缘向内滑既可能打开侧栏，也可能触发系统 Back | Task 5 |
| P1 | 保存/导入/总结弹窗 | 按钮在 busy 时禁用，但 Dialog route 仍可被 Back/barrier pop | 异步操作仍在执行时 UI 被销毁，结果无明确落点 | Task 6 |
| P2 | 全屏图片/视频显式按钮与测试 | 使用 `arrow_back`；测试主要点按钮，没有真实 system Back 覆盖 | modal 语义不清；预测性返回回归缺少自动化与真机证据 | Task 7 |

### 1.4 明确不采用的方案

- **本次不迁移 `StatefulShellRoute.indexedStack`。** 它可以让每个顶层入口保留独立历史并为顶层切换提供真实可预览栈，但会同时改变 URL 组合、页面保活和媒体会话生命周期，超出手势适配的最小范围。若未来需要“非聊天顶层 → 聊天”的完整 predictive preview，再单独设计 shell migration。
- **本次不设置 system gesture exclusion rect。** 抽屉与视频 seek 都有显式按钮/中央拖动替代路径，没有理由牺牲系统 Back。
- **本次不自行实现 predictive back progress 动画。** Flutter 3.44 已为正常 route pop 提供默认实现；页面内选择态、编辑态和媒体目录属于自定义瞬态返回，只要求确定性与状态正确。

---

## 2. 文件结构

### 新建

- `test/android/android_manifest_contract_test.dart`：锁定 predictive back manifest opt-in。

### 修改

- `android/app/src/main/AndroidManifest.xml`：启用 Android predictive back callback。
- `lib/app/shell/app_shell_scaffold.dart`：集中顶层与页面本地 Back 优先级；禁用 endDrawer 边缘打开。
- `lib/features/history/presentation/history_screen.dart`：把选择态声明为页面本地 Back target。
- `lib/features/chat/presentation/chat_screen.dart`：把消息编辑态声明为页面本地 Back target。
- `lib/app/composition/sync_workspace_screen.dart`：只在当前媒体 Tab 声明本地 Back target；处理目录 → 媒体根 → 连接 Tab。
- `lib/features/media/presentation/media_browser_tab.dart`：移除离屏 `PopScope`，保留显式“返回连接”动作。
- `lib/features/media/presentation/pages/video_player_page.dart`：把播放表面手势与控制层拆成兄弟层；尊重 system gesture inset；接入 drag cancel。
- `lib/features/media/presentation/pages/video_player_gesture.dart`：将横拖提交与取消分开收口。
- `lib/features/media/presentation/pages/image_viewer_page.dart`：全屏 modal 使用 close affordance。
- `lib/features/media/presentation/widgets/video_player_controls.dart`：视频 modal 使用 close affordance。
- `lib/features/settings/presentation/widgets/settings_form_dialog_scaffold.dart`：busy 时阻止 route pop。
- `lib/features/settings/presentation/widgets/import_confirm_dialog.dart`：导入中阻止 route pop。
- `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`：导入中阻止 route pop。
- `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart`：创建检查点时阻止 route pop。
- `test/app/shell/app_shell_scaffold_test.dart`：顶层 Back、Drawer Back 与边缘 drag 契约。
- `test/features/history/history_screen/history_screen_actions_cases.dart`：Back 取消选择。
- `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`：Back 取消消息编辑。
- `test/features/sync/sync_screen/sync_screen_test_helpers.dart`：提供可观测媒体目录 Back fake。
- `test/features/sync/sync_screen/sync_screen_render_cases.dart`：媒体 Tab 返回优先级与离屏回归。
- `test/features/media/presentation/video_player_page_test.dart`：控制按钮无双击延迟、边缘避让与 drag cancel。
- `test/features/media/presentation/video_player_accessibility_test.dart`：close 语义与键盘回归。
- `test/features/media/presentation/image_viewer_page_test.dart`：close 与 system Back。
- `test/features/media/presentation/media_browser_navigation_test.dart`：图片/视频 system Back 回媒体列表。
- `test/features/settings/presentation/model_provider_form_dialog_test.dart`：保存中不能 Back/barrier dismiss。
- `test/features/settings/presentation/import_confirm_dialog_test.dart`：导入中不能 Back dismiss。
- `test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart`：同步导入中不能 Back dismiss。
- `test/features/chat/chat_screen/chat_screen_basics_cases.dart`：创建检查点时不能 Back dismiss。

---

### Task 1: 启用 Android predictive back 平台契约

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `test/android/android_manifest_contract_test.dart`

**Interfaces:**
- Consumes: Flutter Android embedding v2 和现有单 Activity manifest。
- Produces: application-level `android:enableOnBackInvokedCallback="true"`；不新增 Kotlin callback。

- [ ] **Step 1: 写 manifest 红灯测试**

创建 `test/android/android_manifest_contract_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android application enables predictive back callbacks', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:enableOnBackInvokedCallback="true"'),
    );
  });
}
```

- [ ] **Step 2: 运行测试确认红灯**

```powershell
flutter test test/android/android_manifest_contract_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task1-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task1-red.log
```

Expected: `EXIT≠0`，缺少 `android:enableOnBackInvokedCallback="true"`。

- [ ] **Step 3: 在 application 节点启用 callback**

把 `AndroidManifest.xml` 的 application 起始标签改为：

```xml
<application
    android:label="oh_my_llm"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:enableOnBackInvokedCallback="true"
    android:usesCleartextTraffic="true">
```

不要修改 `MainActivity.kt`，不要额外注册 `OnBackInvokedCallback`。

- [ ] **Step 4: 运行测试确认绿灯并检查旧 API**

```powershell
flutter test test/android/android_manifest_contract_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task1-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task1-green.log
rg -n "WillPopScope|Navigator\.willPop|onBackPressed|KEYCODE_BACK" lib android
```

Expected: `EXIT=0`；`rg` 无命中。

- [ ] **Step 5: 提交平台 opt-in**

```powershell
git add android/app/src/main/AndroidManifest.xml test/android/android_manifest_contract_test.dart
git diff --cached --check
git commit -m "fix(android): enable predictive back callbacks"
```

---

### Task 2: 建立唯一的 App Shell 返回层级

**Files:**
- Modify: `lib/app/shell/app_shell_scaffold.dart`
- Modify: `lib/features/history/presentation/history_screen.dart`
- Modify: `lib/features/chat/presentation/chat_screen.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`
- Modify: `test/features/history/history_screen/history_screen_actions_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`

**Interfaces:**
- Consumes: `AppDestination.chat` 固定 start destination；History `_selectionMode/_clearSelection`；Chat `_editingMessageId/_cancelEditMode`。
- Produces:
  - `AppShellScaffold({bool hasLocalBackTarget = false, VoidCallback? onLocalBack})`
  - 返回顺序：local target → 非 chat 顶层 `context.go('/chat')` → chat 根交系统退出。

- [ ] **Step 1: 写 App Shell 顶层 Back 红灯测试**

在 `test/app/shell/app_shell_scaffold_test.dart` 增加由 GoRouter 承载的用例：

```dart
testWidgets('system Back returns non-chat top-level destination to chat', (
  tester,
) async {
  final router = _shellRouter(initialLocation: AppDestination.settings.path);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));

  expect(find.text('设置页面'), findsOneWidget);
  await tester.binding.handlePopRoute();
  await settleRouteTransition(tester);

  expect(router.routeInformationProvider.value.uri.path, '/chat');
  expect(find.text('聊天页面'), findsOneWidget);
});
```

同时增加：

- `history/favorites/settings/sync` 四个非起点均回 `/chat`；
- `/chat` 没有 local target 时不被 AppShell 改写为其他路由；
- `hasLocalBackTarget: true` 时只调用一次 `onLocalBack`，URI 不变。

- [ ] **Step 2: 写历史选择态 Back 红灯测试**

在 `history_screen_actions_cases.dart` 复用现有 long-press 场景：

```dart
testWidgets('system Back clears history selection before leaving screen', (
  tester,
) async {
  await setUpHistoryScreen(tester);
  await tester.longPress(find.text('Flutter 路线图'));
  await tester.pump();

  expect(find.byTooltip('取消选择'), findsOneWidget);
  await tester.binding.handlePopRoute();
  await tester.pump();

  expect(find.byTooltip('取消选择'), findsNothing);
  expect(find.text('聊天落点'), findsNothing);
  expect(find.text('Flutter 路线图'), findsOneWidget);
});
```

- [ ] **Step 3: 写聊天编辑态 Back 红灯测试**

在 `chat_screen_workspace_ownership_cases.dart` 的“编辑取消恢复草稿”附近新增：进入编辑、修改正文后调用 `tester.binding.handlePopRoute()`；断言 `取消编辑` 消失、普通会话草稿恢复、ChatScreen 仍可见。不要用页面卸载间接证明。

- [ ] **Step 4: 运行红灯测试**

```powershell
$Files = @(
  'test/app/shell/app_shell_scaffold_test.dart',
  'test/features/history/history_screen_test.dart',
  'test/features/chat/chat_screen_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task2-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task2-red.log
```

Expected: `EXIT≠0`；顶层 Back 退出/不回 chat，选择或编辑态没有被优先清除。

- [ ] **Step 5: 给 AppShellScaffold 增加唯一返回策略入口**

构造函数新增：

```dart
const AppShellScaffold({
  required this.currentDestination,
  required this.title,
  required this.body,
  this.actions,
  this.endDrawer,
  this.hasLocalBackTarget = false,
  this.onLocalBack,
  super.key,
}) : assert(!hasLocalBackTarget || onLocalBack != null);

final bool hasLocalBackTarget;
final VoidCallback? onLocalBack;
```

用一个 `PopScope<void>` 包住现有 `LayoutBuilder`：

```dart
final canPop =
    currentDestination == AppDestination.chat && !hasLocalBackTarget;

return PopScope<void>(
  canPop: canPop,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    if (hasLocalBackTarget) {
      onLocalBack!.call();
      return;
    }
    if (currentDestination != AppDestination.chat) {
      context.go(AppDestination.chat.path);
    }
  },
  child: _buildShellLayout(context),
);
```

把当前 `build` 中完整的 `LayoutBuilder` 表达式原样提取为 `Widget _buildShellLayout(BuildContext context)`，其内部布局不变。`canPop` 只依赖 build 时的同步 UI 状态；不要在回调里查询异步条件后再决定是否允许 route pop。

- [ ] **Step 6: 接入 History 与 Chat 的 local target**

`HistoryScreen` 的 `AppShellScaffold` 增加：

```dart
hasLocalBackTarget: _selectionMode,
onLocalBack: _clearSelection,
```

`ChatScreen` 的 `AppShellScaffold` 增加：

```dart
hasLocalBackTarget: _editingMessageId != null,
onLocalBack: _cancelEditMode,
```

普通 composer draft 不拦 Back；仅显式消息编辑事务属于 local target。

- [ ] **Step 7: 运行绿灯测试**

```powershell
dart format lib/app/shell/app_shell_scaffold.dart lib/features/history/presentation/history_screen.dart lib/features/chat/presentation/chat_screen.dart test/app/shell/app_shell_scaffold_test.dart test/features/history/history_screen/history_screen_actions_cases.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
flutter test test/app/shell/app_shell_scaffold_test.dart test/features/history/history_screen_test.dart test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task2-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task2-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 8: 提交返回层级**

```powershell
git add lib/app/shell/app_shell_scaffold.dart lib/features/history/presentation/history_screen.dart lib/features/chat/presentation/chat_screen.dart test/app/shell/app_shell_scaffold_test.dart test/features/history/history_screen test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
git diff --cached --check
git commit -m "fix(navigation): prioritize local state before app exit"
```

---

### Task 3: 把媒体目录 Back 所有权移到可见 Sync workspace

**Files:**
- Modify: `lib/app/composition/sync_workspace_screen.dart`
- Modify: `lib/features/media/presentation/media_browser_tab.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_test_helpers.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Verify: `test/features/media/presentation/media_browser_navigation_test.dart`

**Interfaces:**
- Consumes: `MediaBrowserState.canGoBack`、`MediaBrowserController.goBack()`、`TabController.index`。
- Produces: 只有 `SyncWorkspaceScreen` 当前 index 为 2 时向 `AppShellScaffold` 声明 local Back target；`MediaBrowserTab` 不再注册 route-level PopScope。

- [ ] **Step 1: 扩充可观测 fake 并写红灯测试**

给 `RecordingMediaBrowserController` 增加同步种子与调用记录：

```dart
int goBackCount = 0;

void seedPathForTest({
  required String currentPath,
  required List<String> pathHistory,
}) {
  state = state.copyWith(
    currentPath: currentPath,
    pathHistory: pathHistory,
  );
}

@override
Future<bool> goBack() async {
  goBackCount++;
  if (state.pathHistory.isEmpty) return false;
  final history = [...state.pathHistory];
  final previous = history.removeLast();
  state = state.copyWith(currentPath: previous, pathHistory: history);
  return true;
}
```

在 Sync screen cases 增加三个用例：

1. 当前媒体 Tab 且 `/相册/旅行` 有历史时，system Back 只回 `/相册`，Tab 仍是“媒体”；
2. 当前媒体根目录时，system Back 切到“连接”，仍留在 `/sync`；
3. 访问媒体后主动切回“连接”，下一次 system Back 不再调用 `goBack()`，而是由 AppShell 回 `/chat`。

- [ ] **Step 2: 运行红灯测试**

```powershell
flutter test test/features/sync/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task3-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task3-red.log
```

Expected: `EXIT≠0`；当前 PopScope 位于 `MediaBrowserTab`，无法可靠区分可见/离屏 Tab。

- [ ] **Step 3: 从 MediaBrowserTab 删除 PopScope**

`MediaBrowserTab.build` 直接返回 session switch：

```dart
return switch (session) {
  MediaLibrarySessionOpening() => const Center(
    child: CircularProgressIndicator(),
  ),
  MediaLibrarySessionFailed(:final failure) => AppEmptyState(
    icon: Icons.link_off_rounded,
    title: failure.message,
    description: '请返回同步页重新打开媒体浏览器。',
    action: FilledButton(
      onPressed: widget.onExitMediaBrowser,
      child: const Text('返回连接'),
    ),
  ),
  MediaLibrarySessionInactive() => const AppEmptyState(
    icon: Icons.perm_media,
    title: '媒体会话不可用',
    description: '请返回同步页重新打开媒体浏览器。',
  ),
  MediaLibrarySessionActive() => _buildBrowser(
    context,
    state,
    controller,
  ),
};
```

保留 `onExitMediaBrowser`，它仍供错误/失效状态的显式“返回连接”按钮调用。不要在 presentation leaf 内读取 TabController。

- [ ] **Step 4: 在 SyncWorkspaceScreen 同步声明 local target**

增加：

```dart
void _handleMediaBack() {
  if (!_hasMediaTab || _tabController.index != 2) return;
  final state = ref.read(mediaBrowserControllerProvider);
  if (!state.canGoBack) {
    _tabController.animateTo(0);
    return;
  }
  unawaited(ref.read(mediaBrowserControllerProvider.notifier).goBack());
}
```

`AppShellScaffold` 增加：

```dart
hasLocalBackTarget: isMediaTab,
onLocalBack: _handleMediaBack,
```

为此在 `sync_workspace_screen.dart` 引入 `dart:async` 的 `unawaited`。这里先同步读 `canGoBack` 决定“目录返回还是切 Tab”；异步目录加载失败时保持媒体 Tab 并显示现有 inline error，不把失败误判成“已经到根目录”。

- [ ] **Step 5: 运行 Sync 与媒体回归**

```powershell
dart format lib/app/composition/sync_workspace_screen.dart lib/features/media/presentation/media_browser_tab.dart test/features/sync/sync_screen
flutter test test/features/sync/sync_screen_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task3-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task3-green.log
```

Expected: `EXIT=0`；`rg -n "PopScope" lib/features/media/presentation/media_browser_tab.dart` 无命中。

- [ ] **Step 6: 提交媒体 Back 所有权修复**

```powershell
git add lib/app/composition/sync_workspace_screen.dart lib/features/media/presentation/media_browser_tab.dart test/features/sync/sync_screen
git diff --cached --check
git commit -m "fix(media): scope directory back handling to active tab"
```

---

### Task 4: 隔离播放器控制与全屏手势，尊重系统边缘

**Files:**
- Modify: `lib/features/media/presentation/pages/video_player_page.dart`
- Modify: `lib/features/media/presentation/pages/video_player_gesture.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`

**Interfaces:**
- Consumes: `MediaQuery.systemGestureInsetsOf(context)`、现有 `VideoPlayerGestureController`。
- Produces:
  - 控制按钮不再是 double-tap recognizer 的后代；
  - `handleHorizontalDragCancel()` 回滚预览且不 seek；
  - 简单横拖只在左右 system gesture inset 之外开始。

- [ ] **Step 1: 写控制按钮无延迟红灯测试**

修改现有“返回按钮”与“重试”测试：删除为父级双击识别器服务的 `pump(kDoubleTapTimeout)`，点击后只 `pump()` 一帧并等待真实初始化/路由信号。修复前应失败，证明按钮确实被父手势层延迟。

新增倍速菜单或音量按钮用例：一次 tap 后一帧内 overlay 出现，证明 top controls 也不再受 double-tap countdown 影响。

- [ ] **Step 2: 写边缘避让与 cancel 红灯测试**

为测试宿主注入：

```dart
const MediaQueryData(
  size: Size(400, 800),
  systemGestureInsets: EdgeInsets.only(left: 24, right: 24),
)
```

新增：

- 从 `x=5` 开始横拖超过 slop，`seekToCalls` 仍为空；
- 从 `x=200` 开始横拖仍能 seek；
- 中央横拖开始后调用 `gesture.cancel()`，不调用 seek，`isHorizontalDragging` 复位，控制栏恢复到手势前状态，seek hint 消失。

- [ ] **Step 3: 运行红灯测试**

```powershell
flutter test test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task4-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task4-red.log
```

Expected: `EXIT≠0`；按钮仍延迟、边缘拖动仍被识别、controller 没有 cancel 入口。

- [ ] **Step 4: 把播放手势层改为控制栏的兄弟层**

`VideoPlayerPage` 的外层不再用 `GestureDetector(child: Stack(...))`。改为：

```dart
return Scaffold(
  backgroundColor: Colors.black,
  body: FocusTraversalGroup(
    policy: OrderedTraversalPolicy(),
    child: Stack(
      children: [
        Positioned.fill(child: _buildPlaybackInteractionLayer(s)),
        IgnorePointer(
          child: Center(
            child: VideoCenterHint(
              visible:
                  s.isInitialized &&
                  !s.hasError &&
                  (!s.isPlaying || s.centerHint != CenterHintType.none),
              hintType: s.centerHint,
              seekPosition: s.seekPreviewPosition,
              showPauseIcon:
                  s.isInitialized && !s.hasError && !s.isPlaying,
            ),
          ),
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: _buildTopControls(s),
        ),
        FocusTraversalOrder(
          order: const NumericFocusOrder(3),
          child: _buildBottomControls(s),
        ),
      ],
    ),
  ),
);
```

新增播放交互层：

```dart
Widget _buildPlaybackInteractionLayer(VideoPlayerUiState s) {
  final playbackSurface = FocusTraversalOrder(
    order: const NumericFocusOrder(1),
    child: _buildPlaybackSurface(s),
  );
  if (!s.isInitialized || s.hasError) return playbackSurface;

  final insets = MediaQuery.systemGestureInsetsOf(context);
  return Stack(
    fit: StackFit.expand,
    children: [
      playbackSurface,
      Positioned(
        left: insets.left,
        right: insets.right,
        top: 0,
        bottom: 0,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.translucent,
          onTap: _gesture.handleTap,
          onDoubleTapDown: _gesture.handleDoubleTapDown,
          onDoubleTap: _gesture.handleDoubleTap,
          onLongPressStart: _gesture.handleLongPressStart,
          onLongPressEnd: _gesture.handleLongPressEnd,
          onLongPressCancel: _gesture.handleLongPressCancel,
          onHorizontalDragStart: _gesture.handleHorizontalDragStart,
          onHorizontalDragUpdate: _gesture.handleHorizontalDragUpdate,
          onHorizontalDragEnd: _gesture.handleHorizontalDragEnd,
          onHorizontalDragCancel: _gesture.handleHorizontalDragCancel,
        ),
      ),
    ],
  );
}
```

错误/加载状态没有全屏 gesture overlay，因此“重试”可立即点击。控制栏位于 overlay 之后，hit test 优先命中控制栏；它们不再是 double-tap recognizer 的后代。

- [ ] **Step 5: 实现横拖取消的单一收口**

在 `VideoPlayerGestureController` 中提取：

```dart
void handleHorizontalDragEnd(DragEndDetails details) {
  _finishHorizontalDrag(commit: true);
}

void handleHorizontalDragCancel() {
  _finishHorizontalDrag(commit: false);
}

void _finishHorizontalDrag({required bool commit}) {
  if (!_mounted || !state.isHorizontalDragging) return;
  state.isHorizontalDragging = false;
  if (commit) {
    state.controller?.seekTo(state.seekPreviewPosition);
  }
  hideCenterHint();
  endGesture();
}
```

cancel 路径不得 seek；`endGesture()` 必须恢复 `controlsVisibleBeforeGesture`。

- [ ] **Step 6: 给底部 Slider 增加 system gesture inset padding**

在 `_buildBottomControls` 的 `SafeArea` 内、`VideoBottomBar` 外加左右 padding：

```dart
final gestureInsets = MediaQuery.systemGestureInsetsOf(context);

Padding(
  padding: EdgeInsets.only(
    left: gestureInsets.left,
    right: gestureInsets.right,
  ),
  child: VideoBottomBar(
    isPlaying: s.isPlaying,
    hasEnded: s.hasEnded,
    currentPosition: s.currentPosition,
    totalDuration: s.totalDuration,
    bufferedPercent: s.bufferedPercent,
    isDragging: s.isDragging,
    dragPosition: Duration(milliseconds: s.dragPositionMs.round()),
    onPlayPause: _gesture.togglePlayPause,
    onSeekStart: _gesture.onSeekStart,
    onSeekUpdate: _gesture.onSeekUpdate,
    onSeekEnd: _gesture.onSeekEnd,
  ),
)
```

只避让拖动目标，视频画面和渐变仍可 edge-to-edge。

- [ ] **Step 7: 运行绿灯测试与现有媒体 suite**

```powershell
dart format lib/features/media/presentation/pages/video_player_page.dart lib/features/media/presentation/pages/video_player_gesture.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart
flutter test test/features/media --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task4-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task4-green.log
```

Expected: `EXIT=0`；返回/重试测试不再为按钮 tap 推进 `kDoubleTapTimeout`。双击功能自身的测试仍可按识别器契约推进 timeout。

- [ ] **Step 8: 提交播放器手势隔离**

```powershell
git add lib/features/media/presentation/pages/video_player_page.dart lib/features/media/presentation/pages/video_player_gesture.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart
git diff --cached --check
git commit -m "fix(media): isolate player gestures from system edges"
```

---

### Task 5: 禁止右侧抽屉抢占 Android Back 边缘

**Files:**
- Modify: `lib/app/shell/app_shell_scaffold.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`
- Verify: `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`

**Interfaces:**
- Consumes: 现有“打开侧边内容”IconButton 与 `Scaffold.endDrawer`。
- Produces: `endDrawerEnableOpenDragGesture: false`；已打开 drawer 仍可由 system Back 或 scrim 关闭。

- [ ] **Step 1: 写抽屉边缘红灯测试**

对紧凑 viewport 增加：

```dart
final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
expect(scaffold.isEndDrawerOpen, isFalse);

await tester.dragFrom(
  Offset(viewport.size.width - 1, viewport.size.height / 2),
  const Offset(-240, 0),
);
await settleOverlayTransition(tester);

expect(scaffold.isEndDrawerOpen, isFalse);
```

再保留并补强图标打开用例；打开后调用 `tester.binding.handlePopRoute()`，断言 `isEndDrawerOpen == false` 且仍在 chat。

- [ ] **Step 2: 运行红灯**

```powershell
flutter test test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task5-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task5-red.log
```

Expected: 右边缘 drag 打开 endDrawer，测试失败。

- [ ] **Step 3: 禁用 mobile endDrawer edge drag**

在 `AppShellScaffold` 的 `Scaffold` 增加：

```dart
endDrawerEnableOpenDragGesture: false,
```

不要禁用 barrier dismiss，不修改显式 IconButton。

- [ ] **Step 4: 运行绿灯与 chat responsive 回归**

```powershell
dart format lib/app/shell/app_shell_scaffold.dart test/app/shell/app_shell_scaffold_test.dart
flutter test test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task5-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task5-green.log
```

Expected: `EXIT=0`；图标打开、Back 关闭、边缘不打开三条契约同时成立。

- [ ] **Step 5: 提交抽屉边缘修复**

```powershell
git add lib/app/shell/app_shell_scaffold.dart test/app/shell/app_shell_scaffold_test.dart
git diff --cached --check
git commit -m "fix(navigation): reserve screen edges for system back"
```

---

### Task 6: busy 弹窗使用提前可知的 PopScope 状态

**Files:**
- Modify: `lib/features/settings/presentation/widgets/settings_form_dialog_scaffold.dart`
- Modify: `lib/features/settings/presentation/widgets/import_confirm_dialog.dart`
- Modify: `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`
- Modify: `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart`
- Modify: `test/features/settings/presentation/model_provider_form_dialog_test.dart`
- Modify: `test/features/settings/presentation/import_confirm_dialog_test.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_basics_cases.dart`

**Interfaces:**
- Consumes: `isSaving`、`_isImporting`、`_isCreating`。
- Produces: busy 为 true 时 `PopScope.canPop == false`；false 时 Dialog route 正常由 Back 取消。

- [ ] **Step 1: 写 Settings form busy 红灯测试**

用 `Completer<void>` 控制 `onSubmit`：点击保存并确认“保存中...”，调用 system Back 与 barrier tap，断言 dialog 仍存在；complete 后 dialog 自动关闭。

```dart
await tester.tap(find.widgetWithText(FilledButton, '保存'));
await submitStarted.future;
await tester.pump();

await tester.binding.handlePopRoute();
await tester.pump();
expect(find.byType(ModelProviderFormDialog), findsOneWidget);

await tester.tapAt(Offset.zero);
await tester.pump();
expect(find.byType(ModelProviderFormDialog), findsOneWidget);
```

- [ ] **Step 2: 写导入与检查点 busy 红灯测试**

分别用现有 provider fake/Completer 让 `_isImporting` 或 `_isCreating` 保持 true；system Back 后断言 dialog、进度文案和操作状态仍存在。操作失败恢复 false 后，再按 Back 应关闭。

- [ ] **Step 3: 运行红灯测试**

```powershell
$Files = @(
  'test/features/settings/presentation/model_provider_form_dialog_test.dart',
  'test/features/settings/presentation/import_confirm_dialog_test.dart',
  'test/features/sync/sync_screen_test.dart',
  'test/features/chat/chat_screen_test.dart'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task6-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task6-red.log
```

Expected: `EXIT≠0`；busy dialog 可被 Back/barrier pop。

- [ ] **Step 4: 用 PopScope 包裹异步弹窗**

共享 settings scaffold 把现有 `AlertDialog` 表达式提取为 `_buildAlertDialog(context)`，然后让 `build` 返回：

```dart
return PopScope<void>(
  canPop: !isSaving,
  child: _buildAlertDialog(context),
);
```

另外三个 stateful dialog 也把当前 `AlertDialog` 表达式原样提取到各自的 `_buildAlertDialog(context)`，然后分别使用：

```dart
return PopScope<void>(
  canPop: !_isImporting,
  child: _buildAlertDialog(context),
);
```

检查点 dialog 使用其独立 busy 字段：

```dart
return PopScope<void>(
  canPop: !_isCreating,
  child: _buildAlertDialog(context),
);
```

不要在 `onPopInvokedWithResult` 里弹二次确认；busy 期间就是不可 pop，失败后状态恢复即可取消。

- [ ] **Step 5: 运行绿灯与弹窗回归**

```powershell
dart format lib/features/settings/presentation/widgets/settings_form_dialog_scaffold.dart lib/features/settings/presentation/widgets/import_confirm_dialog.dart lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart test/features/settings/presentation/model_provider_form_dialog_test.dart test/features/settings/presentation/import_confirm_dialog_test.dart test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart test/features/chat/chat_screen/chat_screen_basics_cases.dart
flutter test test/features/settings/presentation test/features/sync/sync_screen_test.dart test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task6-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task6-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 6: 提交 busy 弹窗返回契约**

```powershell
git add lib/features/settings/presentation/widgets/settings_form_dialog_scaffold.dart lib/features/settings/presentation/widgets/import_confirm_dialog.dart lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart test/features/settings/presentation/model_provider_form_dialog_test.dart test/features/settings/presentation/import_confirm_dialog_test.dart test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart test/features/chat/chat_screen/chat_screen_basics_cases.dart
git diff --cached --check
git commit -m "fix(ui): keep busy dialogs mounted during back attempts"
```

---

### Task 7: 统一全屏媒体 dismiss affordance 与 system Back 测试

**Files:**
- Modify: `lib/features/media/presentation/pages/image_viewer_page.dart`
- Modify: `lib/features/media/presentation/widgets/video_player_controls.dart`
- Modify: `test/features/media/presentation/image_viewer_page_test.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`

**Interfaces:**
- Consumes: GoRouter child route 和现有 `Navigator.pop` callback。
- Produces: `关闭图片` / `关闭视频` 明确 modal 语义；系统 Back 与按钮 dismiss 到同一父路由。

- [ ] **Step 1: 写语义与 system Back 红灯测试**

新增或改写：

- ImageViewer 顶部按钮 tooltip 为“关闭图片”，icon 为 `Icons.close`；
- VideoTopBar tooltip 为“关闭视频”，icon 为 `Icons.close`；
- 从 `/sync` push 图片/视频后调用 `tester.binding.handlePopRoute()`，router 回 `/sync`，资源按现有生命周期释放；
- 图片第一页从左边缘执行 system Back 时关闭 viewer，而不是切页；Widget test 只验证 route pop，真实 progress/cancel 留给 Android smoke。

- [ ] **Step 2: 运行红灯**

```powershell
flutter test test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task7-red.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task7-red.log
```

- [ ] **Step 3: 替换显式 modal affordance**

图片：

```dart
IconButton(
  icon: const Icon(Icons.close, color: Colors.white),
  tooltip: '关闭图片',
  onPressed: () => Navigator.pop(context),
)
```

视频：

```dart
IconButton(
  icon: const Icon(Icons.close, color: Colors.white),
  tooltip: '关闭视频',
  onPressed: onBack,
)
```

`MediaRouteRecoveryPage` 与 `FavoriteDetailScreen` 仍是普通 child destination，保留 AppBar 自动 Up，不改成 close。

- [ ] **Step 4: 运行绿灯媒体 suite**

```powershell
dart format lib/features/media/presentation/pages/image_viewer_page.dart lib/features/media/presentation/widgets/video_player_controls.dart test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart test/features/media/presentation/media_browser_navigation_test.dart
flutter test test/features/media --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-task7-green.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-task7-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 5: 提交媒体 dismiss 语义**

```powershell
git add lib/features/media/presentation/pages/image_viewer_page.dart lib/features/media/presentation/widgets/video_player_controls.dart test/features/media/presentation/image_viewer_page_test.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart test/features/media/presentation/media_browser_navigation_test.dart
git diff --cached --check
git commit -m "fix(media): align fullscreen dismiss with Android navigation"
```

---

### Task 8: 完整验证与 Android 手势 smoke

**Files:**
- Verify only: all files above
- Verify only: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: Tasks 1-7 的自动化契约。
- Produces: 静态分析、架构门禁、全量测试、Android build 与 API 级真机证据。

- [ ] **Step 1: 格式与静态门禁**

```powershell
$DartFiles = git diff --name-only --diff-filter=ACMR -- '*.dart'
if ($DartFiles) {
  dart format $DartFiles
  dart format --output=none --set-exit-if-changed $DartFiles
}
dart run tool/check_import_boundaries.dart
flutter analyze
```

Expected: 全部退出码 `0`。

- [ ] **Step 2: 定向测试**

```powershell
$Files = @(
  'test/android/android_manifest_contract_test.dart',
  'test/app/shell/app_shell_scaffold_test.dart',
  'test/features/history/history_screen_test.dart',
  'test/features/chat/chat_screen_test.dart',
  'test/features/sync/sync_screen_test.dart',
  'test/features/media',
  'test/features/settings/presentation'
)
flutter test $Files --reporter compact 2>&1 | Out-File -Encoding utf8 gesture-targeted.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 gesture-targeted.log
```

Expected: `EXIT=0`。

- [ ] **Step 3: 全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
$E = $LASTEXITCODE
Write-Host "EXIT=$E"
Get-Content -Tail 150 fltest.log
```

若测试在启动前卡住，运行 `./scripts/kill-stale-test-processes.ps1` 后重试一次。Expected: `EXIT=0`。

- [ ] **Step 4: Android release build**

```powershell
flutter build apk --release
```

Expected: `EXIT=0`，manifest merge 没有移除 predictive back attribute。

- [ ] **Step 5: API 35/36 手势导航 smoke**

设备启用 gesture navigation。Android 15+ 不需要开发者选项；若用 Android 13/14，再启用 “Predictive back animations”。逐项记录：

1. `/chat` 空闲根页：从左右边缘缓慢滑动，能看到 launcher 预览；松手退出，取消手势留在 chat。
2. `/settings`、`/history`、`/favorites`、`/sync` 根页：一次 Back 回 `/chat`，第二次 Back 退出。
3. 收藏详情：慢滑能预览收藏列表；取消不 pop，完成后回列表。
4. 图片/视频 child route：慢滑能预览媒体列表；显式 close 与 system Back 结果一致。
5. History 选择态：第一次 Back 只清除选择；第二次回 chat。
6. Chat 消息编辑态：第一次 Back 取消编辑并恢复原 draft；第二次按根页规则退出。
7. Sync 媒体子目录：Back 逐级回目录；根目录 Back 切“连接”；下一次回 chat。
8. 访问媒体后切到“连接/同步”：Back 不再触发隐藏媒体目录返回。
9. 紧凑 Chat：左右边缘不会打开 endDrawer；工具栏按钮可打开；打开后 Back 先关 drawer。
10. 视频：左右边缘 Back 不 seek；中央横拖仍 seek；取消系统 Back 后播放器没有残留 seek hint 或隐藏控制栏。
11. 视频返回、重试、倍速、音量按钮没有可感知的双击等待。
12. 保存/导入/检查点总结进行中：Back 与 barrier 点击不关闭 dialog；结束或失败后可关闭。

- [ ] **Step 6: 三键导航与 Windows 回归 smoke**

Android 切到 three-button navigation，重复 1-8 的离散 Back 行为。Windows 执行：

1. 视频 Escape 关闭、方向键 seek、空格播放/暂停；
2. Top/Bottom controls 可立即通过鼠标点击；
3. 非 chat 顶层页面的系统/窗口 Back 路径若可用则回 chat；
4. NavigationRail 和紧凑 drawer 显式按钮行为不变。

- [ ] **Step 7: 最终审计**

```powershell
rg -n "WillPopScope|Navigator\.willPop|onBackPressed|KEYCODE_BACK|setSystemGestureExclusionRects" lib android
rg -n "PopScope" lib
rg -n "endDrawerEnableOpenDragGesture" lib/app/shell/app_shell_scaffold.dart
rg -n "systemGestureInsets" lib/features/media/presentation
git diff --check
git status --short
```

Expected:

- 第一条无命中；
- `PopScope` 只出现在 AppShell 与明确 busy dialog，不在离屏 `MediaBrowserTab`；
- drawer edge drag 明确为 false；
- system gesture inset 只用于手势/Slider 命中区域，不缩小媒体画面；
- 工作区只含计划内改动。

- [ ] **Step 8: 记录最终证据并提交剩余测试调整**

若前面每个 task 已独立提交，此步只提交验证中发现的聚焦测试修正；不得混入新功能。

```powershell
$StagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($StagedDartFiles) {
  dart format --output=none --set-exit-if-changed $StagedDartFiles
}
git diff --cached --check
git commit -m "test(navigation): cover Android back gesture contracts"
```

如果没有剩余 diff，不创建空提交。

---

## 3. 验收标准

1. Manifest 明确启用 predictive back；Flutter 主题继续使用 3.44 默认 transition。
2. `/chat` 是唯一应用 start destination：非 chat 顶层 Back 先回 chat，chat 根 Back 才退出。
3. History selection 与 Chat edit 在 route navigation 前被 Back 清除。
4. 只有当前媒体 Tab 能拦截 Back；离屏媒体 widget 不影响 `/sync` 返回。
5. 媒体目录按历史逐级返回；根目录回连接 Tab；加载失败不误切 Tab。
6. 收藏详情、图片、视频的正常 route pop 支持 Android predictive preview/cancel/commit。
7. endDrawer 不能从系统边缘打开，但显式按钮、barrier 和 Back 关闭行为正常。
8. 视频全屏手势不再包裹控制按钮；返回、重试、菜单等点击无需等待 double-tap timeout。
9. 视频横拖与进度 Slider 避让 system gesture inset；drag cancel 不提交 seek 且恢复 UI。
10. busy dialog 在操作期间不能由 Back 或 barrier 销毁，完成/失败后恢复可关闭。
11. 图片/视频显式按钮使用 modal close 语义；普通详情与恢复页仍使用 Up。
12. import boundary、analyze、定向测试、全量测试、Android release build 全部通过。
13. API 35/36 手势导航、三键导航与 Windows 键鼠 smoke 均有记录。

## 4. 已知限制与后续触发条件

- 非 chat 顶层页回 chat 仍是受 `PopScope` 拦截后的程序化 `go`，不会获得完整的 route-to-route predictive preview。只有当产品明确要求顶层入口独立 back stack 与预览时，才启动 `StatefulShellRoute` 专项设计。
- 页面内 History selection、Chat edit、媒体目录/Tab 是瞬态 UI，不映射为 route，因此不会展示前一 route preview；本计划只保证第一次 Back 的目标确定、无数据丢失且状态可测试。
- 图片 PageView 仍铺满视觉区域，但 Android 系统边缘 Back 优先；不添加 exclusion rect。若真实设备证明某 OEM 把边缘事件错误送给 PageView，先记录设备/API/导航模式与可复现视频，再决定是否只缩小 PageView 的手势命中区。
- `SystemUiMode.immersiveSticky` 的媒体全屏行为保留；Android 15+ edge-to-edge 是平台默认。本计划不改 system bar 样式，只验证返回手势区域不被应用拖动目标抢占。
