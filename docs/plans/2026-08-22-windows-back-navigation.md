# Windows 鼠标侧键返回导航实施计划

**Goal:** 在不改变 Android 返回、现有 GoRouter 栈和页面本地 `PopScope` 契约的前提下，让 Windows 窗口内的鼠标后退侧键与 `LogicalKeyboardKey.browserBack` 进入同一条应用返回链。

**Architecture:** 现有 `BackButtonDispatcher -> Navigator.maybePop() -> PopScope` 已经是返回行为的深 module。本次只在 `MaterialApp.router` 根部增加一个 Windows 输入 adapter，把 `kBackMouseButton` 和 `browserBack` 翻译成一次 dispatcher 请求；不创建新的返回状态机，不把页面本地状态搬进中央 controller，也不把 Windows 输入伪装成 Android predictive back。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` / go_router 17.4.0 / Riverpod 3 / Flutter pointer、focus 与 keyboard APIs / `flutter_test`。

**Branch:** `feat/desktop-back-navigation`

**Planning baseline:** `cfbb5299d8293196d1df9d37d11d115470c4ee51`。本计划编写阶段仅完成只读代码审计，没有实现、测试、Windows 运行或真实鼠标验证。

## 1. 固定契约

### 1.1 输入契约

- 仅 Windows 启用；不为 Linux、macOS 或 Web 建立假想 desktop adapter。
- 标准鼠标后退侧键：`PointerDownEvent.buttons & kBackMouseButton != 0` 时请求一次返回。
- 被驱动映射成浏览器后退键的设备：首次 `KeyDownEvent` 且 `logicalKey == LogicalKeyboardKey.browserBack` 时请求一次返回。
- 忽略 `KeyRepeatEvent` 与 `KeyUpEvent`，避免长按连续穿透多层页面。
- 不支持 `Alt+Left`：Flutter Windows 文本编辑快捷键使用它移动光标，视频播放器也把 Left 解释为固定 seek。
- 不把 `Escape` 变成全局返回：Dialog、菜单、历史选择态与视频全屏继续拥有各自 Escape 语义。
- 不实现鼠标前进侧键；当前顶层导航使用 `go`，没有稳定的 forward stack。
- 不实现应用失焦后的全局鼠标 hook；只有指针事件到达 Flutter 窗口时生效。
- 不添加基于毫秒窗口的猜测性 debounce。若真实硬件证明一次点击同时产生 pointer back 与 browserBack，再以捕获日志设计窄去重；不得先吞掉用户有意的快速连退。

### 1.2 返回优先级

Windows adapter 必须调用 GoRouter 的 `BackButtonDispatcher` / `popRoute()`，不得直接调用 `router.pop()`、`context.pop()` 或 `context.go('/chat')`。这样固定复用以下顺序：

1. 最上层 Dialog、PopupMenu、BottomSheet 或 Drawer；
2. Dialog 内 busy `PopScope`；
3. 页面级 `PopScope`（视频页、App Shell）；
4. App Shell 本地目标（消息编辑、历史/收藏选择、Sync 媒体目录）；
5. GoRouter 子路由 pop；
6. 非 Chat 顶层页按现有策略回 `/chat`；
7. Chat 根返回 `false`，Windows adapter 消费输入但不关闭窗口。

### 1.3 已确认的特殊行为

- TextField 聚焦时，鼠标侧键与 `browserBack` 仍执行页面返回；`Alt+Left` 继续留给文本编辑。
- 普通 Dialog 先关闭 Dialog；busy Dialog 保持不动，不继续退底层页面。
- 未保存但未处于保存中的设置表单会像现有 Android Back 一样关闭并丢弃输入；本 PR 不新增全应用 dirty-form 确认。
- 视频窗口模式中的返回会等待平台会话恢复后关闭视频页。
- Windows 视频全屏时，鼠标侧键仍表示导航返回并关闭视频页；`Escape` 只退出全屏、留在视频页。
- Chat 根页面无动作；不得调用 `windowManager.close()`、`SystemNavigator.pop()` 或退出进程。
- Windows 没有 Android predictive back 的手势进度和系统预览。本次只共享最终返回语义，不模拟预测动画。

## 2. 明确非目标

- 不修改 `AppShellScaffold` 的现有返回策略。
- 不重构 Android manifest、Android embedding 或 predictive back。
- 不引入平台 controller 继承树，不新增通用 `AppBackDispatcher` pass-through interface。
- 不新增未保存表单确认、窗口关闭确认或前进历史。
- 不改视频键位、seek、音量、全屏或播放控制 contract。
- 不添加第三方鼠标插件、原生 Windows MethodChannel 或系统级 hook。
- 不因方便测试使用 `HardwareKeyboard.addHandler` 抢在 Focus 树之前消费事件。
- 不顺手修复其他导航、路由或可访问性问题。

## 3. 文件与 interface

### 3.1 新建

- `lib/app/platform/windows_navigation_input_adapter.dart`
  - 只翻译 Windows pointer/key 事件。
  - 接受 `Future<bool> Function()` 返回请求回调，adapter 不知道 GoRouter、页面或会话。
- `test/app/platform/windows_navigation_input_adapter_test.dart`
  - 锁定 pointer/key 翻译、事件阶段、TextField 与根部 no-op。
- `test/integration/windows_back_navigation_integration_test.dart`
  - 用真实 GoRouter/PopScope 组合验证 adapter 没有绕过返回层级。
- `docs/testing/windows-back-navigation-smoke.md`
  - 真实 Windows 鼠标验证清单和 `PASS/FAIL/PENDING` 记录。

### 3.2 修改

- `lib/app/app.dart`
  - 在 `MaterialApp.router.builder` 中仅为 `TargetPlatform.windows` 包装 adapter。
  - 调用 `ref.read(appRouterProvider).backButtonDispatcher.invokeCallback()`。
  - 保留 `NotificationBubbleStack` 和现有 child 组合顺序。
- `test/app/shell/app_shell_scaffold_test.dart`
  - 只补当前缺失的根/顶层/Drawer contract，不复制 adapter 单测。
- `test/features/media/presentation/video_player_page_test.dart`
  - 若现有测试未锁定 generic Back 与 Escape 差异，增加紧凑回归；不改 production player。

### 3.3 固定 interface 草图

`windows_navigation_input_adapter.dart` 的 public surface 保持窄：

```dart
typedef WindowsBackRequest = Future<bool> Function();

final class WindowsNavigationInputAdapter extends StatelessWidget {
  const WindowsNavigationInputAdapter({
    required this.onBackRequested,
    required this.child,
    super.key,
  });

  final WindowsBackRequest onBackRequested;
  final Widget child;
}
```

实现要求：

- `Listener.onPointerDown` 只在 back bit 置位时调用 `unawaited(onBackRequested())`。
- `Focus.onKeyEvent` 只处理首次 `KeyDownEvent + browserBack` 并返回 `KeyEventResult.handled`。
- 对其他 pointer/key 返回既有默认处理；不读取路由、不调用页面 callback。
- `onBackRequested()` 返回 `false` 时仍把 Windows 输入视为已消费，从而保证 Chat 根无动作。
- 生产 platform selection 留在 `app/` composition；adapter 文件内不读取 `Platform.isWindows`。

## 4. Task 1：用红灯测试定义 Windows 输入 adapter

**Files:**

- Create: `test/app/platform/windows_navigation_input_adapter_test.dart`
- Create after red: `lib/app/platform/windows_navigation_input_adapter.dart`

### 4.1 红灯测试

- [ ] 写 `PointerDownEvent` 后退侧键测试：
  - `tester.tapAt(..., buttons: kBackMouseButton)`；
  - callback 恰好调用一次；
  -普通 primary/secondary click 不调用。
- [ ] 写 keyboard 测试：
  - `browserBack` 首次 key down 调用一次并返回 handled；
  - repeat/up 不重复调用；
  - `browserForward`、Escape、Left 与 `Alt+Left` 不调用。
- [ ] 写 TextField 焦点测试：
  - 聚焦并设置 selection；
  - `browserBack` 仍冒泡到根 adapter；
  - `Alt+Left` 不触发返回，并保留 Flutter 文本编辑行为。
- [ ] 写 callback 返回 `false` 的测试：根 adapter 不抛错、不退出、不二次请求。
- [ ] 写 dispose 后没有额外 listener/subscription 的结构断言；实现不得注册全局 keyboard handler。

运行单文件红灯（工具级 timeout `60000`ms）：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/platform/windows_navigation_input_adapter_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/windows-back-task1-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/windows-back-task1-red.log
```

Expected: `EXIT!=0`，失败原因为 adapter/interface 尚不存在，而非测试基础设施错误。

### 4.2 最小实现与绿灯

- [ ] 新建 adapter，只实现 3.3 的 interface。
- [ ] 不添加 debounce、队列、路由类型或平台判断。
- [ ] 运行同一测试输出 `logs/windows-back-task1-green.log`，要求 `EXIT=0`。
- [ ] 对两个 Dart 文件执行 `dart format`。

### 4.3 Task 1 停止条件

- `Focus.onKeyEvent` 无法在 TextField 子树接收 `browserBack` 时，先建立最小复现；不得改用抢先全局 handler 绕过 Focus。
- Flutter test 无法构造 `kBackMouseButton` 时，核对 Flutter 3.44.6 API；不得为测试引入鼠标插件。
- 若 implementation 需要知道当前页面、全屏或选择态，说明 seam 放错，停止并回到 dispatcher 方案。

### 4.4 独立提交

计划批准并授权提交后：

```powershell
git add lib/app/platform/windows_navigation_input_adapter.dart test/app/platform/windows_navigation_input_adapter_test.dart
git diff --cached --check
git commit -m "feat(windows): 添加桌面返回输入适配器"
```

## 5. Task 2：接入应用根部并复用现有返回链

**Files:**

- Modify: `lib/app/app.dart`
- Create: `test/integration/windows_back_navigation_integration_test.dart`
- Modify only when coverage is missing: `test/app/shell/app_shell_scaffold_test.dart`

### 5.1 集成红灯

- [ ] 构造最小 GoRouter + `AppShellScaffold` 测试树，从根 adapter 注入真实 `router.backButtonDispatcher.invokeCallback`。
- [ ] 覆盖以下观察结果，每个测试只验证一个分支：
  - 普通 Dialog 只关闭 Dialog；
  - busy `PopScope(canPop: false)` 保持 Dialog，底层 route 不变；
  - Drawer 只关闭 Drawer；
  - App Shell 本地返回目标只清理本地状态；
  - pushed 子路由只 pop 一层；
  -非 Chat 顶层回 `/chat`；
  - Chat 根保持 `/chat` 且窗口/Widget 树仍存在。
- [ ] 通过 pointer back 与 browserBack 各走至少一个真实 router 场景；不要把所有用例复制两遍。

红灯命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/integration/windows_back_navigation_integration_test.dart test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/windows-back-task2-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/windows-back-task2-red.log
```

Expected: adapter 尚未由 `OhMyLlmApp` composition 接入时，至少根集成用例失败。

### 5.2 根部 composition

- [ ] 在 `OhMyLlmApp.build` 中保留 coordinator eager watch。
- [ ] 在现有 `MaterialApp.router.builder` 组合 `NotificationBubbleStack` 后，仅当 `defaultTargetPlatform == TargetPlatform.windows` 时包装 `WindowsNavigationInputAdapter`。
- [ ] callback 只调用 `ref.read(appRouterProvider).backButtonDispatcher.invokeCallback()`。
- [ ] 测试通过依赖注入/直接 adapter 构造，不修改全局平台状态。
- [ ] Android 与其他平台 builder 输出不新增 keyboard/pointer adapter。

### 5.3 绿灯与负向审计

运行同一组测试写 `logs/windows-back-task2-green.log`，要求 `EXIT=0`，随后执行：

```powershell
rg -n "HardwareKeyboard\.instance\.addHandler|Alt\+Left|browserForward|kForwardMouseButton|SystemNavigator\.pop|windowManager\.close" lib/app lib/features
rg -n "router\.pop\(|context\.pop\(|context\.go\('/chat'\)" lib/app/platform/windows_navigation_input_adapter.dart
```

Expected:

- 第一条不因本任务新增匹配；既有匹配要逐项说明。
- 第二条在新 adapter 中无匹配。

### 5.4 独立提交

```powershell
git add lib/app/app.dart test/integration/windows_back_navigation_integration_test.dart test/app/shell/app_shell_scaffold_test.dart
git diff --cached --check
git commit -m "feat(windows): 接入全局返回导航"
```

不存在实际修改的测试文件不得加入暂存或提交命令。

## 6. Task 3：锁定视频与现有页面的差异契约

**Files:**

- Modify only if missing: `test/features/media/presentation/video_player_page_test.dart`
- Reuse existing case files under History/Favorites/Sync/Chat；不为已覆盖行为重复造测试。

- [ ] 审计现有测试是否已证明：
  - History/收藏选择态 Back 先清选择；
  - Chat 编辑态 Back 先取消编辑；
  - Sync Media 目录 Back 先回目录/Tab；
  -视频窗口模式 generic Back 恢复平台状态后关闭；
  - Windows 全屏中 generic Back 关闭页面，而 Escape 只退出全屏。
- [ ] 只为缺失的“generic Back 与 Escape 不同”增加一个视频回归用例。
- [ ] 不修改 `desktop_video_interaction_controller.dart` 或播放 core。

目标测试命令（单文件工具级 timeout `60000`ms）：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/video_player_page_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/windows-back-video-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/windows-back-video-green.log
```

若现有测试已经完整覆盖且无需修改，本 Task 不创建空 commit。

## 7. Task 4：真实 Windows 鼠标 smoke 文档

**Files:**

- Create: `docs/testing/windows-back-navigation-smoke.md`

文档固定包含环境栏：Windows 版本、Flutter build、鼠标型号、驱动/厂商软件、侧键映射、HEAD、日期。

检查项：

1. 普通侧键在历史/收藏/设置/Sync 顶层回 Chat；
2. 详情、图片、视频子路由只退一层；
3. Dialog、菜单和 Drawer 先关闭自身；busy Dialog 不关闭；
4. History/收藏选择态先清选择；
5. Chat 根侧键无动作、不退出；
6. TextField 聚焦时侧键返回，`Alt+Left` 只移动光标；
7. 视频全屏侧键关闭视频页，Escape 只退出全屏；
8. 快速连续点击按物理点击次数逐层返回；
9. 检查一次点击是否产生双退。若出现，记录驱动映射与事件来源，保持 `FAIL`，不要用宽 debounce 临时掩盖；
10. browserBack 映射设备验证 key 路径（有对应硬件/驱动时）。

本 smoke 由用户在真实鼠标上执行。未执行项标为 `PENDING`；不得把 Widget 测试写成硬件通过。

文档提交可与 Task 2 集成提交合并，或在获得授权后独立使用：

```powershell
git commit -m "docs(windows): 添加鼠标返回验证清单"
```

## 8. 最终门禁

### 8.1 定向回归

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/app/platform/windows_navigation_input_adapter_test.dart test/integration/windows_back_navigation_integration_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/media/presentation/video_player_page_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/windows-back-targeted.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/windows-back-targeted.log
```

工具级 timeout：`60000`ms。若测试组合稳定超过单文件时限，按文件拆开运行，但每条仍需 60 秒硬超时与独立日志。

### 8.2 格式、架构与静态检查

```powershell
$DartFiles = git diff --name-only master...HEAD -- '*.dart'
if ($DartFiles) { dart format $DartFiles }
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/windows-back-boundaries.log; $GateExit = $LASTEXITCODE; Write-Host "EXIT=$GateExit"; Get-Content -Tail 120 logs/windows-back-boundaries.log
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/windows-back-analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/windows-back-analyze.log
```

### 8.3 全量测试

工具级 timeout 必须设为 `240000`ms：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

超时先运行 `./scripts/kill-stale-test-processes.ps1`，再诊断，不直接重跑。

### 8.4 Windows build 与范围审计

```powershell
flutter build windows --release 2>&1 | Out-File -Encoding utf8 logs/build-windows.log; $BuildExit = $LASTEXITCODE; Write-Host "EXIT=$BuildExit"; Get-Content -Tail 150 logs/build-windows.log
git diff --check master...HEAD
git diff --name-only master...HEAD
git status --short
```

Windows build 使用与仓库构建命令相称的工具级硬超时。最终 diff 只允许本计划列出的 app/platform、app composition、测试和 smoke 文档；不得包含 History/Favorites/Media production 行为改写。

## 9. 完成定义

只有以下条件全部满足才可宣称实现完成：

1. 鼠标 back 与 browserBack 自动测试均有 red/green 证据；
2. 所有输入都进入 dispatcher/PopScope 链，adapter 不认识具体 route；
3. `Alt+Left`、Escape、forward key/button 和 Chat 根退出均未新增；
4. Dialog、busy、Drawer、本地目标、子路由、顶层与根行为有可观察测试；
5. 视频 generic Back 与 Escape 差异被保留；
6. format、import boundary、analyze、定向测试、全量测试和 Windows release build 有真实 exit code；
7. 真实鼠标 smoke 明确记录 `PASS/FAIL/PENDING`，未执行不冒充通过；
8. diff 无无关文件、临时日志、调试代码、平台泛化或新依赖；
9. 未经授权不 push、不创建 PR。

## 10. 执行记录（2026-08-22）

Task 1–4 已在分支 `feat/desktop-back-navigation` 完成，门禁与真机验证结论：

- 红/绿证据：`logs/windows-back-task1-red.log`（编译失败=接口缺失）→ `windows-back-task1-green.log`（EXIT=0，12 例）；`windows-back-task2-red.log`（仅「Windows 宿主鼠标后退侧键把设置页退回对话」失败）→ `windows-back-task2-green.log`（EXIT=0，25 例）；`windows-back-video-green.log`（EXIT=0）。
- 与草图的偏差：Flutter 3.44 的 `BackButtonDispatcher.invokeCallback` 必传 defaultValue，实现统一为 `invokeCallback(Future.value(false))`；§8.1 的 `test/features/media/presentation/video_player_page_test.dart` 实际位于 `pages/` 子目录，定向门禁以 `pages/video_player_page_test.dart` 与 `pages/video_player_desktop_test.dart` 两个文件替代。
- §6 审计结论：History 选择态（`history_screen_actions_cases.dart`「系统返回先清除历史选择态再离开页面」）、Chat 编辑态（`chat_screen_workspace_ownership_cases.dart`「系统返回取消消息编辑并恢复草稿」）、Sync 媒体目录（`sync_workspace_screen_render_cases.dart` 三条）、busy Dialog（chat 检查点用例）已由既有测试覆盖；收藏选择态 generic Back 原缺直接用例，已补 `favorites_screen_selection_cases.dart`「系统返回先清除收藏选择态且留在收藏夹页」。
- 空焦点场景核查：Navigator 自带 `Focus(autofocus: true)`（flutter/widgets/navigator.dart），`MaterialApp.router` 下主焦点恒在 adapter 子树内，browserBack 键盘路径不会因「无任何节点持有焦点」而丢失，非缺陷。
- 真机 smoke：第 1–9 项 PASS（2026-08-22 用户真机验证，硬件型号待补填），第 10 项 PENDING（无 browserBack 映射设备），见 `docs/testing/windows-back-navigation-smoke.md`。
