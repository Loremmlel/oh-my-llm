# 存量测试韧性治理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 `test/` 中全部 `find.byKey`、散落 `pumpAndSettle`、`Future.delayed` 与时间余量，用可观察完成信号（Provider 状态、受控流、仓储 ACK、fake gate、WidgetTester 虚拟时钟）重写所有等待，并以架构门禁阻止回流。

**Architecture:** 测试等待分五类信号收敛：① 同步状态变更后单帧 `pump()`；② Provider 状态用共享 `waitForProviderState`（Riverpod `listen`，非轮询）；③ SSE 流用 `ControlledChatCompletionStream.listened` 控制输入时序；④ 后台写入用仓储 `save()`/`flush()` ACK 与 fake gate；⑤ 有限动画用 5 个按场景命名的动画 helper（唯一允许 `pumpAndSettle` 的位置）。唯一生产源码改动是 `SseLogBuffer.flush()` 等待调用前已在途的自动落盘 Future。

**Tech Stack:** Flutter ≥ 3.11.5 / Dart ≥ 3.x · `flutter_riverpod: ^3.4.2`（`ProviderContainer.listen` 含 `fireImmediately` / `onError`）· Flutter 公开手势常量（`kDoubleTapMinTime` / `kDoubleTapTimeout` / `kLongPressTimeout`）· 产品公开 debounce 常量（`HistoryScreen.searchDebounce` = 300ms、`TemplatePromptFormDialog.variableReconcileDebounce` = 220ms）。

## Global Constraints

以下约束对所有任务生效，逐条严格执行：

- 不修改任何产品动画、搜索防抖、模板变量防抖、流式刷新、后台保存防抖或自动重试时长。
- 不引入全局 Clock、Scheduler 或通用 Debouncer 服务；不为 `ChatGenerationRun`、History 搜索或模板变量协调新增生产时钟抽象。
- 不机械地把 `pumpAndSettle` 替换为 `pump(const Duration(...))`；不把等待隐藏到另一个固定时长。
- 不删除生产代码中具有列表身份、状态保留或焦点保持用途的 Key；只取消测试对内部 Key 的依赖。
- 不修改 `.github/workflows/ci.yml`，不修改 `dart_test.yaml` 的并发、timeout 或 UDP tag；本阶段只把 UDP 3 处真实延时登记为门禁例外。
- 不治理 UDP 网络资源隔离本身，不为 UDP 用例新增 fake transport。
- 新 helper 必须是窄职责 API；禁止提供 `waitForEverything` / `settleEverything` / `sleepUntilStable` 一类无法表达等待对象的接口。
- 每个成功等待都必须由可观察事件完成；`.timeout(...)` 仅防止挂死，错误消息必须说明等待的状态。
- 每次提交前：对改动 Dart 文件执行 `dart format`；暂存后 `dart format --output=none --set-exit-if-changed <暂存列表>` 非零退出不得提交；跑 `flutter analyze`。
- 测试输出一律重定向到日志文件（`flutter test path --reporter compact 2>&1 | Out-File -Encoding utf8 <log>`，检查 `$LASTEXITCODE`），禁止直接打印完整测试流。
- 所有新增注释使用简体中文，只说明"为什么"；源码与测试注释、测试用例标题不得出现审查轮次、TD 或 Phase 编号。
- 不手工编辑 `pubspec.yaml` 版本号；提交 hook 自行 bump。
- 每个提交独立可回滚；多个任务不得合并成一个"大治理"提交。

---

## 共享契约（所有任务引用）

### 契约 A：等待决策表

每一处存量等待必须先归类，再选择唯一对应方案：

| 等待对象 | 允许的方式 | 禁止的方式 |
|---|---|---|
| 同步 Provider/Repository 变更后的 UI 帧 | `tester.pump()` 一次 | `pumpAndSettle`、任意固定毫秒 |
| Provider 应用状态 | `waitForProviderState(...)`，再 `tester.pump()` | polling + `Future.delayed` |
| SSE/受控流开始监听 | `ControlledChatCompletionStream.listened` | `Future.delayed(1ms)` |
| SSE 增量已进入状态 | Provider predicate 或 fake host projection | chunk delay、微任务循环 |
| 后台 SQLite 保存 | `await save()` / `await flush()` / fake gate | 100ms 经验等待 |
| I/O 自动 flush | 公开 `flush()`/`drain()` Future | 写入后 sleep 50ms |
| Route/Dialog/Menu/Tab/Scroll 动画 | 对应命名的 finite-animation helper | 业务文件直接 `pumpAndSettle` |
| 产品 Timer | `tester.pump(公开时长常量或明确契约值)` | `常量 + 50ms`、真实 sleep |
| 负向事件 | 用后续正向事件夹住观察窗口，或等待流/操作终态后断言计数 | 只等待一段时间然后断言"没发生" |
| UDP 资源释放/无数据窗口 | 保留现有非零 delay，登记例外 | 扩大到其他文件 |

### 契约 B：Finder 契约

| 当前 Key 用途 | 替代 Finder |
|---|---|
| composer `chat-message-composer` | 在 ChatScreen 范围内定位带 `正文` label 的 `TextField` |
| anchor rail 容器 | 定位 `第 N 条用户消息：<preview>` 的 semantics；需要 hover 时对第一条语义节点操作 |
| 消息 ID Key | 先按完整可见用户消息文本找到对应消息气泡，再在该气泡内定位 `编辑消息` tooltip/button |
| `template-variable-title` | 在模板变量区域定位 label 为 `title` 的 `TextField` |
| 设置表单字段 Key | 在具体 dialog/widget 类型下，以可见 label 定位 `TextFormField`/`TextField` |
| 模型拉取按钮 Key | `find.widgetWithText(FilledButton, '拉取模型')`；加载态按 `正在拉取...` |
| 模型选择 checkbox Key | 以远端模型名找到所属 row，再找 row 内 `Checkbox` 角色 |

设置 helper 使用稳定可见标签：服务商 → `服务商名称`/`API URL`/`API Key`；模型 → `显示名称`/`API 模型名称`/`支持深度思考`；预设 Prompt → `预设 Prompt 名称`/`标题`/`Prompt 内容`；固定序列 → `序列名称`/`步骤标题`/`步骤内容`；模板 → `标题`/`模板提示词`（动态变量用变量名或 `变量名（数字）`）；记忆 Prompt → `名称`/`记忆总结提示词`。

`标题`、`名称` 等重复标签必须先按 dialog/widget 类型限定祖先范围；禁止直接使用不限定范围的 `find.text('标题').first` 掩盖歧义。

### 契约 C：手势与动画常量

- 双击间隔：`kDoubleTapMinTime`（40ms）；单击胜出双击竞技场：`kDoubleTapTimeout`（300ms）；长按：`kLongPressTimeout`（500ms）。
- 产品 Timer：中央提示消失精确 `pump(const Duration(seconds: 1))`；控制栏自动隐藏精确 `pump(const Duration(seconds: 3))`，随后用动画 helper 等待淡出。
- History 搜索：`pump(HistoryScreen.searchDebounce)`；模板变量：`pump(TemplatePromptFormDialog.variableReconcileDebounce)`。
- 最终不允许 `tester.pump(const Duration(milliseconds: <魔法数字>))`；`find.byKey`、`Future.delayed`、`chunkDelay` 全仓归零。

---

### Task 0: 建立可比较基线（不提交）

**Files:** 无（仅记录）
**Interfaces:** 无

- [ ] **Step 1: 确认工作区干净**

```powershell
git status --short
git rev-parse --short HEAD
```

预期：`git status --short` 无输出；HEAD 记入基线记录（预期 `7ddad8e`）。

- [ ] **Step 2: 重跑存量统计**

```powershell
rg -n "pumpAndSettle" test --glob "*.dart"
rg -n "find\.byKey" test --glob "*.dart"
rg --pcre2 -n "Future(?:<[^>]+>)?\.delayed|chunkDelay|searchDebounce|variableReconcileDebounce" test --glob "*.dart"
```

预期：`pumpAndSettle` 376 处（34 文件）、`find.byKey` 39 处（5 文件）、`Future.delayed` 58 处（含 13 处 `Duration.zero`）、`chunkDelay` 1 处、debounce 加余量 6 处。若数字与预期不符，先核实差异再继续，不得跳过。

- [ ] **Step 3: 连续 3 次 CI 同构基线测试**

```powershell
$phase15Baseline = @()
1..3 | ForEach-Object {
  $phase15Run = $_
  $phase15Log = "phase15-baseline-$phase15Run.log"
  $phase15Watch = [System.Diagnostics.Stopwatch]::StartNew()
  flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 |
    Out-File -Encoding utf8 $phase15Log
  $phase15Exit = $LASTEXITCODE
  $phase15Watch.Stop()
  Get-Content -Tail 20 $phase15Log
  if ($phase15Exit -ne 0) {
    throw "baseline run $phase15Run failed: EXIT=$phase15Exit"
  }
  $phase15Baseline += [pscustomobject]@{
    Run = $phase15Run
    Seconds = $phase15Watch.Elapsed.TotalSeconds
    Log = $phase15Log
  }
}
$phase15Baseline | Sort-Object Seconds | Format-Table
```

预期：三次 `EXIT=0`；记录三次耗时（参考值约 84 秒，以本次实测为准，取中位数作 7.3 节比较基准）。若基线自身失败，先确认是否与当前提交无关，本阶段不得顺手修其他问题。

- [ ] **Step 4: 验收记录**

将 HEAD、三次耗时、三次退出码、Step 2 的计数写入 `phase15-baseline.md`（本目录）。该文件不提交（或提交为 `docs:`，二选一，不得混入后续 commit）。

---

### Task 1: 建立共享等待原语并清理 setup settle

**Files:**
- Create: `test/helpers/async_test_signals.dart`
- Create: `test/helpers/async_test_signals_test.dart`
- Create: `test/helpers/widget_test_animation.dart`
- Create: `test/helpers/widget_test_animation_test.dart`
- Modify: `test/helpers/test_harness.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_test_helpers.dart`（只加薄 helper，不动既有 finder）
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`（tab/dialog helper 转调动画 helper）
- Modify: `test/features/sync/sync_screen/sync_screen_test_helpers.dart`
- Modify: `test/widget_test.dart`
- Modify: `test/integration/bootstrap_integration_test.dart`

**Interfaces:**
- Produces: `waitForProviderState<StateT>({container, provider, matches, description, timeout})`；`settleRouteTransition` / `settleOverlayTransition` / `settleTabTransition` / `settleScrollMotion` / `settleAnimatedWidgetTransition`（均接收 `WidgetTester`）；`waitForState(matches, {description})`（chat controller 薄封装）。
- Consumes: 现有 `pumpTestApp`（`test/helpers/test_harness.dart`）首帧契约。

- [ ] **Step 1: 写 `waitForProviderState` 的失败测试**

`test/helpers/async_test_signals_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'async_test_signals.dart';

final counterProvider = StateProvider<int>((ref) => 0);

void main() {
  group('waitForProviderState', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('注册前已满足时立即命中', () async {
      final state = await waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) => s == 0,
        description: '初始计数 0',
      );
      expect(state, 0);
    });

    test('注册后状态变化时命中', () async {
      final future = waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) => s >= 1,
        description: '计数自增到 1',
      );
      container.read(counterProvider.notifier).state = 1;
      expect(await future, 1);
    });

    test('Provider 错误转发给调用方', () async {
      final failing = Provider<int>((ref) => throw StateError('boom'));
      await expectLater(
        waitForProviderState<int>(
          container: container,
          provider: failing,
          matches: (_) => false,
          description: '永不匹配',
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
      );
    });

    test('超时错误携带等待描述', () async {
      await expectLater(
        waitForProviderState<int>(
          container: container,
          provider: counterProvider,
          matches: (_) => false,
          description: '等待永不发生的状态',
          timeout: Duration.zero,
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            contains('等待永不发生的状态'),
          ),
        ),
      );
    });

    test('完成后不再监听', () async {
      var matchCalls = 0;
      await waitForProviderState<int>(
        container: container,
        provider: counterProvider,
        matches: (s) {
          matchCalls++;
          return s == 0;
        },
        description: '初始状态',
      );
      container.read(counterProvider.notifier).state = 1;
      container.read(counterProvider.notifier).state = 2;
      await Future<void>.value();
      expect(matchCalls, 1);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/helpers/async_test_signals_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t1.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 30 t1.log
```

预期：EXIT≠0，报 `async_test_signals.dart` 不存在。

- [ ] **Step 3: 实现 `waitForProviderState`**

`test/helpers/async_test_signals.dart`：

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 等待 [provider] 的状态满足 [matches] 后返回该状态。
///
/// 基于 [ProviderContainer.listen] 而非轮询；[fireImmediately] 保证注册监听前
/// 状态已满足时也能立即命中，避免漏事件。[description] 用于失败保护：超时
/// 抛出的错误必须能看出在等什么，而不是笼统的超时。
Future<StateT> waitForProviderState<StateT>({
  required ProviderContainer container,
  required ProviderListenable<StateT> provider,
  required bool Function(StateT state) matches,
  required String description,
  Duration timeout = const Duration(seconds: 5),
}) {
  final completer = Completer<StateT>();
  final subscription = container.listen<StateT>(
    provider,
    (previous, next) {
      if (!completer.isCompleted && matches(next)) {
        completer.complete(next);
      }
    },
    fireImmediately: true,
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  return completer.future
      .timeout(
        timeout,
        onTimeout: () => throw TimeoutException(description, timeout),
      )
      .whenComplete(subscription.close);
}
```

注意：listener 内不引用 `subscription`（`fireImmediately` 的首次回调发生在 `listen` 返回之前）；关闭放在 `whenComplete`。

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/helpers/async_test_signals_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t1.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 30 t1.log
```

预期：EXIT=0，5 个用例全过。

- [ ] **Step 5: 写五个动画 helper 的最小测试**

`test/helpers/widget_test_animation_test.dart`（只覆盖私有实现一次，不为五个薄包装复制同构测试）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_animation.dart';

void main() {
  testWidgets('有限动画完成后 helper 返回', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOpacity(
          opacity: 1.0,
          duration: Duration(milliseconds: 120),
          child: Text('内容'),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimatedOpacity(
          opacity: 0.0,
          duration: Duration(milliseconds: 120),
          child: Text('内容'),
        ),
      ),
    );
    await settleAnimatedWidgetTransition(tester);
    final widget =
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(widget.opacity, 0.0);
  });

  testWidgets('无限动画触发超时保护', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 500),
    )..repeat();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, child) => const Text('内容'),
        ),
      ),
    );
    await expectLater(
      settleAnimatedWidgetTransition(tester),
      throwsA(isA<FlutterError>()),
    );
  });
}
```

- [ ] **Step 6: 运行测试确认失败**

```powershell
flutter test test/helpers/widget_test_animation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t1.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 30 t1.log
```

预期：EXIT≠0，报 `widget_test_animation.dart` 不存在。

- [ ] **Step 7: 实现五个动画 helper**

`test/helpers/widget_test_animation.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

/// 等待一次有限的 Route/GoRouter 导航动画（push/pop/redirect）结束。
Future<void> settleRouteTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 Dialog、Menu、BottomSheet、Drawer 的开合动画结束。
Future<void> settleOverlayTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 TabController / TabBarView 的切换动画结束。
Future<void> settleTabTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 PageView、ballistic scroll、scroll-to-bottom 的滚动动画结束。
Future<void> settleScrollMotion(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 等待 AnimatedCrossFade、AnimatedSize、rail 展开收起等有限组件动画结束。
Future<void> settleAnimatedWidgetTransition(WidgetTester tester) =>
    _settleFiniteAnimation(tester);

/// 全仓唯一直接调用 pumpAndSettle 的位置。
///
/// 50ms 步进比默认 250ms 更快推进有限动画；2 秒超时是"有限动画没有结束"的
/// 失败保护，不代表测试需要等满 2 秒。不导入生产动画时长，不提供通用
/// settle API——等待对象必须由调用方命名。
Future<void> _settleFiniteAnimation(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}
```

- [ ] **Step 8: 运行测试确认通过**

同 Step 6 命令。预期：EXIT=0。

- [ ] **Step 9: 收紧 `test_harness.dart` 契约文档**

在 `pumpTestApp` 的 doc 注释末尾追加：

```dart
/// 返回时只保证首帧和同步依赖完成，不承诺动画或异步业务完成；
/// 需要等待动画/业务状态时由调用方按场景使用专门等待 helper。
```

不改变任何行为代码（文件内唯一 pump 已是 `await tester.pump();`）。

- [ ] **Step 10: 清理 setup settle**

- `test/widget_test.dart`：把 setup 处的 `pumpAndSettle` 改为单次 `pump()`。
- `test/integration/bootstrap_integration_test.dart`：把 3 处 setup `pumpAndSettle` 改为 `pump()`（bootstrap 已 await 的资源不需要动画等待）。

- [ ] **Step 11: 三个 feature helper 转调**

- `chat_screen_test_helpers.dart`：为后续任务新增薄 helper（本任务只加不删）：

```dart
/// 等待生成状态满足条件（转调共享 helper，不复制 listener 逻辑）。
Future<void> waitForChatGeneration(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(ChatSessionsState state) matches, {
  required String description,
}) async {
  await waitForProviderState(
    container: container,
    provider: chatSessionsProvider,
    matches: matches,
    description: description,
  );
  await tester.pump();
}
```

（按实际文件已有的 container 获取方式调整；`chatSessionsProvider` 与 `ChatSessionsState` 从 `package:oh_my_llm/features/chat/application/chat_sessions_controller.dart` import。）若原 helper 中的 tab/dialog 等待直接调用 `pumpAndSettle`，改为转调 `settleTabTransition` / `settleOverlayTransition`。
- `settings_screen_test_helpers.dart`：tab helper 用 `settleTabTransition`，dialog helper 用 `settleOverlayTransition`。
- `sync_screen_test_helpers.dart`：import dialog helper 用 `settleOverlayTransition`；普通 Provider 刷新只 `pump()`。

- [ ] **Step 12: 验收运行**

```powershell
flutter test test/helpers/async_test_signals_test.dart test/helpers/widget_test_animation_test.dart test/widget_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t1.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 50 t1.log
flutter test test/features/chat/chat_screen/chat_screen_test.dart test/features/settings/settings_screen_test.dart test/features/sync/sync_screen/sync_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t1b.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 50 t1b.log
flutter analyze
```

预期：全部 EXIT=0，analyze 0 issue。

- [ ] **Step 13: 提交**

```bash
git add test/helpers/async_test_signals.dart test/helpers/async_test_signals_test.dart test/helpers/widget_test_animation.dart test/helpers/widget_test_animation_test.dart test/helpers/test_harness.dart test/features/chat/chat_screen/chat_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/sync/sync_screen/sync_screen_test_helpers.dart test/widget_test.dart test/integration/bootstrap_integration_test.dart
git commit -m "test: 收紧共享测试等待工具"
```

---

### Task 2: 先消除 5 秒播放器等待

**Files:**
- Modify: `test/features/media/helpers/fake_video_player_controller.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`（只统一 fake 初始化/失败完成方式，不改无关 a11y 契约）

**Interfaces:**
- Produces: `FakeVideoPlayerController.initializeError`（可设置 `Object?`）、`initializeCallCount`（`int`）、`Future<void> waitForInitializeCount(int expected)`。
- Consumes: 页面测试既有 `controllerFactory: (uri) => fakeController` 注入路径（`video_player_page_test.dart:29` 等）。

- [ ] **Step 1: 增强 fake，支持确定性初始化失败**

`test/features/media/helpers/fake_video_player_controller.dart`，在类内新增：

```dart
import 'dart:async';

  // ── 初始化控制（确定性失败与时序） ──
  /// 设置后 [initialize] 递增计数后确定性抛出该错误。
  Object? initializeError;
  int initializeCallCount = 0;
  final List<Completer<void>> _initializeWaiters = [];

  /// 等待第 [expected] 次 [initialize] 完成（含失败）。已满足时立即完成，
  /// 未满足时按调用次数完成，避免复用首次已完成的 Completer。
  Future<void> waitForInitializeCount(int expected) {
    if (initializeCallCount >= expected) return Future<void>.value();
    final completer = Completer<void>();
    _initializeWaiters.add(completer);
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        '等待第 $expected 次视频初始化',
        const Duration(seconds: 5),
      ),
    );
  }
```

`initialize()` 改为：

```dart
  @override
  Future<void> initialize() async {
    initializeCallCount++;
    for (final waiter in List.of(_initializeWaiters)) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _initializeWaiters.clear();
    if (initializeError != null) {
      fakeIsInitialized = false;
      _updateValue();
      throw initializeError!;
    }
    fakeIsInitialized = true;
    _updateValue();
  }
```

- [ ] **Step 2: 写失败测试（先跑旧版确认失败原因成立）**

在 `video_player_page_test.dart` 的错误用例（现 4 处 5 秒 settle）处，先写一个确定性失败用例并运行，确认能稳定复现错误页：

```dart
testWidgets('初始化失败展示内联错误与重试入口', (tester) async {
  final fakeController = FakeVideoPlayerController()
    ..initializeError = StateError('初始化失败');
  await tester.pumpWidget(
    buildVideoPlayerPage(controllerFactory: (uri) => fakeController),
  );
  await fakeController.waitForInitializeCount(1);
  await tester.pump();
  expect(find.byIcon(Icons.error_outline), findsOneWidget);
});
```

（`buildVideoPlayerPage` 按文件内实际入口名调整；先用 `tester.pump()` 首帧，观察用例失败原因再继续。）

- [ ] **Step 3: 重试路径按次数等待**

在既有"重试后再次失败"用例中：

```dart
  // 首次失败
  await fakeController.waitForInitializeCount(1);
  await tester.pump();
  expect(find.byIcon(Icons.error_outline), findsOneWidget);

  // 点击重试 → 第二次初始化
  await tester.tap(find.text('重试'));
  await fakeController.waitForInitializeCount(2);
  await tester.pump();
  expect(fakeController.initializeCallCount, 2);
  expect(find.byIcon(Icons.error_outline), findsOneWidget);
```

- [ ] **Step 4: 删除 4 处 5 秒 settle 与真实网络路径**

- 删除 `video_player_page_test.dart` 中 4 处 `tester.pumpAndSettle(const Duration(seconds: 5))`，错误用例全部改用 Step 2/3 的"初始化信号 + 单帧"。
- 删除真实 `VideoPlayerController.networkUrl` 无效端口 URL 与依赖网络超时的用例路径（错误页统一经 `controllerFactory` 注入 fake）。
- `_pumpInit` helper：删除"初始化完成"100ms，改为初始化信号 + 单帧：

```dart
Future<void> _pumpInit(
  WidgetTester tester,
  FakeVideoPlayerController fakeController,
) async {
  await tester.pumpWidget(
    buildVideoPlayerPage(controllerFactory: (uri) => fakeController),
  );
  await fakeController.waitForInitializeCount(1);
  await tester.pump();
}
```

- `video_player_accessibility_test.dart`：`_pumpVideo` 同样改信号 + 单帧；私有失败 subclass 删除，统一使用可配置 `FakeVideoPlayerController(initializeError: ...)`，避免两套失败时序。
- 不改变产品 retry、控制栏和手势时长；手势魔法时长的全面迁移留在任务 12。

- [ ] **Step 5: 验收运行**

```powershell
1..10 | ForEach-Object {
  flutter test test/features/media/presentation/video_player_page_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t2-$_.log
  if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 t2-$_.log; throw "round $_ failed" }
}
flutter test test/features/media/presentation/video_player_accessibility_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t2b.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 40 t2b.log
rg -n "pumpAndSettle\(const Duration\(seconds: 5\)|seconds: 5\)" test/features/media/presentation/video_player_page_test.dart
```

预期：连续 10 次全过；5 秒 settle 无输出。

- [ ] **Step 6: 提交**

```bash
git add test/features/media/helpers/fake_video_player_controller.dart test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart
git commit -m "test(media): 移除播放器错误用例的真实网络等待"
```

---

### Task 3: 修正 SSE 日志已有在途写入的完成语义（唯一生产改动）

**Files:**
- Modify: `lib/core/logging/sse_log_buffer.dart`
- Modify: `test/core/logging/sse_log_buffer_test.dart`

**Interfaces:**
- Consumes: `AppLogStore.appendLines(List<String>)`（返回串行化 `_operation` Future，`app_log_store.dart:41`）。
- Produces: `SseLogBuffer.flush()` 行为契约：即使当前 buffer 为空，也等待调用前已在途的 append Future；`drain()` 语义不变。

- [ ] **Step 1: 写失败测试（TDD 先行）**

在 `test/core/logging/sse_log_buffer_test.dart` 增加：

```dart
import 'dart:io';

  group('flush 在途写入完成语义', () {
    late Directory tempDir;
    late AppLogStore store;
    late SseLogBuffer buffer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sse-log-flush-test');
      store = await AppLogStore.open(directoryPath: tempDir.path);
    });

    tearDown(() async {
      await buffer.drain();
      await tempDir.delete(recursive: true);
    });

    test('达到阈值后的立即 flush 等待已在途的自动写入', () async {
      buffer = SseLogBuffer(
        store: store,
        batchSize: 2,
        flushInterval: const Duration(days: 1),
      );
      buffer.enqueue('第一行');
      buffer.enqueue('第二行'); // 达到阈值，自动 flush 已在途
      await buffer.flush(); // 空 buffer 但存在在途写入，必须等待其完成
      final content = await File('${tempDir.path}/network.log').readAsString();
      expect(content, contains('第一行'));
      expect(content, contains('第二行'));
    });

    test('无在途写入时 flush 幂等', () async {
      buffer = SseLogBuffer(store: store, batchSize: 64);
      buffer.enqueue('一行');
      await buffer.flush();
      await buffer.flush(); // 空 buffer、无在途写入，立即返回
      final content = await File('${tempDir.path}/network.log').readAsString();
      expect(content, contains('一行'));
    });
  });
```

同时删除该文件中原有的 50ms `Future.delayed` 等待（改为上述真实文件断言）。

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/core/logging/sse_log_buffer_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t3.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 40 t3.log
```

预期：EXIT≠0，"达到阈值后的立即 flush" 用例失败（当前 `flush()` 空 buffer 直接 return）。

- [ ] **Step 3: 实现 in-flight 等待**

`lib/core/logging/sse_log_buffer.dart`，新增字段与 `flush()` 改造：

```dart
  /// 已从内存 buffer 取走、但 append 尚未完成的写入 Future。
  /// 自动 flush 与手动 flush 共用，保证调用方可以等到"调用前已启动"的落盘。
  final Set<Future<void>> _inFlightWrites = {};
```

```dart
  Future<void> flush() async {
    if (_buffer.isEmpty && _droppedCount == 0 && _inFlightWrites.isEmpty) {
      return;
    }

    final lines = <String>[];
    if (_droppedCount > 0) {
      final now = DateTime.now().toIso8601String();
      lines.add('[$now] [sse-dropped] $_droppedCount lines dropped');
      _droppedCount = 0;
    }
    lines.addAll(_buffer);
    _buffer.clear();

    if (lines.isNotEmpty) {
      final write = store.appendLines(lines);
      _inFlightWrites.add(write);
      // 成功与失败两条路径都从集合移除；原始错误仍由 write 本身暴露
      write.then<void>(
        (_) => _inFlightWrites.remove(write),
        onError: (Object _, StackTrace __) => _inFlightWrites.remove(write),
      );
    }

    // 等待本次 flush 调用前已在途的写入快照；调用后新加入的写入
    // 不属于本次调用前的工作，不无限追赶
    final snapshot = List<Future<void>>.of(_inFlightWrites);
    if (snapshot.isNotEmpty) {
      await Future.wait(snapshot);
    }
  }
```

`drain()` 不变（继续经 `flush()` 保证缓冲内容与在途写入都完成）。不新增仅供测试使用的 getter，不更改 flush 阈值与计时。

- [ ] **Step 4: 运行测试确认通过 + 检查 drain 调用方**

```powershell
flutter test test/core/logging/sse_log_buffer_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t3.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 40 t3.log
rg -n "\.drain\(\)" lib test --glob "*.dart"
flutter analyze
```

预期：EXIT=0；`drain()` 调用方（如 `AppNetworkLogger`）未改动即通过。

- [ ] **Step 5: 提交**

```bash
git add lib/core/logging/sse_log_buffer.dart test/core/logging/sse_log_buffer_test.dart
git commit -m "fix(logging): 让日志 flush 等待在途写入"
```

---

### Task 4: 建立聊天受控流与生成生命周期等待

**Files:**
- Modify: `test/helpers/fake_chat_completion_client.dart`
- Modify: `test/features/chat/application/chat_generation_run_test.dart`
- Modify: `test/features/chat/application/chat_generation_coordinator_test.dart`
- Modify: `test/features/chat/application/chat_generation_race_contract_test.dart`

**Interfaces:**
- Produces: `ControlledChatCompletionStream`（`stream` / `listened` / `add` / `addError` / `close`）；`FakeChatCompletionClient.enqueueControlledStream()`；`enqueueChunks`/`enqueueDeltas` 删除 `chunkDelay` 参数；`_FakeHost.waitForProjection(bool Function(ChatGenerationProgress))`。
- Consumes: `ChatGenerationHost.projectProgress`（`chat_generation_contract.dart:102`）、`_FakeHost` 既有 `prepareGate`/`completeAttemptGate`/`prepareEntered`/`completeAttemptEntered`。

- [ ] **Step 1: 实现受控流**

`test/helpers/fake_chat_completion_client.dart` 新增：

```dart
/// 由测试手动驱动的受控流。
///
/// 持有单订阅 [StreamController]；[listened] 在流的 `onListen` 时完成，
/// 测试先启动 send/run，再 await [listened] 确认开始监听，之后才 [add]
/// chunk——不依赖任何真实延时。
class ControlledChatCompletionStream {
  final StreamController<ChatCompletionChunk> _controller =
      StreamController<ChatCompletionChunk>();
  final Completer<void> _listened = Completer<void>();

  ControlledChatCompletionStream() {
    _controller.onListen = _listened.complete;
  }

  Stream<ChatCompletionChunk> get stream => _controller.stream;

  /// 等待流被 [streamCompletion] 开始监听。
  Future<void> get listened => _listened.future;

  void add(ChatCompletionChunk chunk) => _controller.add(chunk);

  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  Future<void> close() => _controller.close();
}
```

`FakeChatCompletionClient` 内新增排队入口，并把 `enqueueChunks`/`enqueueDeltas` 的 `chunkDelay` 参数与 `_streamDeltas` 一起删除：

```dart
  /// 排队一条受控流并返回驱动句柄。
  ///
  /// 测试先启动 send/run，再 `await controlled.listened`，之后才发送 chunk。
  ControlledChatCompletionStream enqueueControlledStream() {
    final controlled = ControlledChatCompletionStream();
    _queuedStreams.add(controlled.stream);
    return controlled;
  }
```

```dart
  void enqueueChunks(List<String> chunks) {
    _queuedStreams.add(
      Stream<ChatCompletionChunk>.fromIterable(
        chunks.map((chunk) => ChatCompletionChunk(contentDelta: chunk)),
      ),
    );
  }

  void enqueueDeltas(List<ChatCompletionChunk> chunks) {
    _queuedStreams.add(Stream<ChatCompletionChunk>.fromIterable(chunks));
  }
```

- [ ] **Step 2: 迁移 `chunkDelay` 唯一消费者**

```powershell
rg -n "chunkDelay" test --glob "*.dart"
```

对该调用点：若它需要分步控制输入时序，改为 `enqueueControlledStream()` + `listened` + 逐步 `add`；若只是顺序发 chunk，改用 `enqueueChunks` 无参形式。

- [ ] **Step 3: 给 `_FakeHost` 增加投影 waiter**

`chat_generation_run_test.dart` 的 `_FakeHost`（约 384 行起）新增：

```dart
  final List<ChatGenerationProgress> projections = [];
  final List<(bool Function(ChatGenerationProgress), Completer<void>)>
      _projectionWaiters = [];

  /// 等待 progress 投影满足 predicate；已满足时立即完成，不轮询。
  Future<void> waitForProjection(bool Function(ChatGenerationProgress) predicate) {
    for (final projection in projections) {
      if (predicate(projection)) return Future<void>.value();
    }
    final completer = Completer<void>();
    _projectionWaiters.add((predicate, completer));
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        '等待生成投影满足条件',
        const Duration(seconds: 5),
      ),
    );
  }

  @override
  void projectProgress(ChatGenerationProgress progress) {
    projections.add(progress);
    for (final (predicate, completer) in List.of(_projectionWaiters)) {
      if (!completer.isCompleted && predicate(progress)) {
        completer.complete();
      }
    }
  }
```

- [ ] **Step 4: 删除本地延时函数并重写生成 run 用例**

`chat_generation_run_test.dart` 删除 `pump([int ms = 10])` 函数（约 31 行）。逐处替换：

| 原写法 | 新写法 |
|---|---|
| `await pump();`（等待 prepare/completeAttempt 推进） | `await host.completeAttemptEntered.future;` 或 `await host.waitForProjection(...)` |
| `await pump(50);`（等待流增量进入投影） | `await host.waitForProjection((p) => p.phase == ChatGenerationPhase.streaming)`（`ChatGenerationPhase` 枚举：idle/preparing/streaming/stopping/retryWaiting/finalizing/succeeded/emptyReply/failed/cancelled/persistenceFailed） |
| `await pump();`（prepare gate 释放后的微任务让路） | `await Future<void>.value();`（纯微任务让路，不是延时） |

代表性顺序改写（prepare gate 用例）：

```dart
// 迁移前
final host = _FakeHost(prepareGate: Completer<void>());
await host.prepareEntered.future;
host.prepareGate!.complete();
await pump();

// 迁移后
final host = _FakeHost(prepareGate: Completer<void>());
await host.prepareEntered.future;
host.prepareGate!.complete();
await host.waitForProjection((p) => p.phase == ChatGenerationPhase.preparing);
```

（completeAttempt gate、late callback 用例同理：等待 `completeAttemptEntered` / run Future / `waitForProjection` 的终态投影后再断言。`Future<void>.value()` 只在确无其他信号可等的微任务让路处使用，且不得出现在负向断言中。）

- [ ] **Step 5: 迁移 coordinator 与 race contract**

- `chat_generation_coordinator_test.dart`：3 处 `Duration.zero` 改为 host phase/progress wait 与受控流 `listened`。
- `chat_generation_race_contract_test.dart`：保留既有 `awaitReached`/`release` repository gate；其余零时长 flush 改为 Provider phase、stream listener 或保存 gate。
- 两个文件按"启动 run → await listened → add chunk → await projection/state → close → await run"顺序重写。

- [ ] **Step 6: 验收运行**

```powershell
foreach ($f in @("test/features/chat/application/chat_generation_run_test.dart", "test/features/chat/application/chat_generation_coordinator_test.dart", "test/features/chat/application/chat_generation_race_contract_test.dart")) {
  1..10 | ForEach-Object {
    flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t4-$(Split-Path $f -Leaf)-$_.log
    if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 "t4-$(Split-Path $f -Leaf)-$_.log"; throw "$f round $_ failed" }
  }
}
rg -n "Future\.delayed|chunkDelay" test/features/chat/application/chat_generation_run_test.dart test/features/chat/application/chat_generation_coordinator_test.dart test/features/chat/application/chat_generation_race_contract_test.dart test/helpers/fake_chat_completion_client.dart
```

预期：三个文件各连续 10 次全过；`rg` 无输出。

- [ ] **Step 7: 提交**

```bash
git add test/helpers/fake_chat_completion_client.dart test/features/chat/application/chat_generation_run_test.dart test/features/chat/application/chat_generation_coordinator_test.dart test/features/chat/application/chat_generation_race_contract_test.dart
git commit -m "test(chat): 用受控流验证生成生命周期"
```

---

### Task 5: 治理 ChatSessionsController 的停止、重试与持久化竞态

**Files:**
- Modify: `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_generation_cases.dart`
- Modify: `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_stop_cases.dart`
- Modify: `test/features/chat/application/chat_sessions_controller_persistence_test.dart`
- Modify: `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart`（薄封装，见任务 1 Step 11）

**Interfaces:**
- Consumes: `waitForProviderState`（任务 1）、`ControlledChatCompletionStream`（任务 4）、`ChatSessionsState` 公开字段（`generation.phase` / `isStreaming` / `isAutoRetryWaiting` / `streamingReply`）、stop case 的 `saveReached`/`stopSaveReached` gate、`ControllerTestHarness`（`container`/`fakeClient`/`sendMsg`）。
- Produces: `waitForState(bool Function(ChatSessionsState), {required String description})` 薄封装（在 `chat_sessions_controller_test_helpers.dart`）：

```dart
/// 等待会话状态满足条件。只转调共享 [waitForProviderState]，不复制
/// Riverpod listener 逻辑。
Future<ChatSessionsState> waitForState(
  bool Function(ChatSessionsState state) matches, {
  required String description,
}) {
  return waitForProviderState(
    container: container,
    provider: chatSessionsProvider,
    matches: matches,
    description: description,
  );
}
```

- [ ] **Step 1: 逐个用例写下所等待事件并归类**

对 `stop_cases.dart` 的 29 处等待（含 polling loop）与 `generation_cases.dart` 的 4 处 1ms，按契约 A 逐处标注类别，然后按下列映射替换：

| 等待目的 | 替换为 |
|---|---|
| 开始监听 | 受控流 `await controlled.listened` |
| partial chunk 已进入状态 | `await waitForState((s) => s.streamingReply?.content == '期望片段')` |
| 第二次请求已发出 | 第二条受控流预排队并 `await second.listened`（禁止轮询 `requestHistory.length`） |
| 自动重试等待 | `await waitForState((s) => s.isAutoRetryWaiting)` |
| 慢保存 | `saveReached -> stop -> stopSaveReached/release -> await save Future` 严格顺序 |
| late done/error | 保存 send Future，完成/关闭受控流，再 `await sendFuture`；之后断言状态未被旧 callback 覆盖 |
| dispose 收口 | run Future / stream close / gate 的终态，不用 10ms 收集错误 |

- [ ] **Step 2: 迁移 `stop_cases.dart`（最大块，逐用例提交内小步验证）**

删除 `50×10ms`、`50×100ms` 一类 polling loop。代表性片段：

```dart
// 迁移前（polling loop）
for (var i = 0; i < 50 && !isAutoRetryWaiting; i++) {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
expect(isAutoRetryWaiting, isTrue);

// 迁移后
await waitForState((s) => s.isAutoRetryWaiting, description: '进入自动重试等待');
```

```dart
// 迁移前（微任务轮询 partial content）
await Future<void>.delayed(Duration.zero);
await Future<void>.delayed(Duration.zero);

// 迁移后
await waitForState(
  (s) => s.streamingReply?.content == '期望片段',
  description: '流式内容达到期望片段',
);
```

- [ ] **Step 3: 迁移 `generation_cases.dart` 与 `persistence_test.dart`**

- generation 4 处 1ms：分别改 `listened` 与 `streamingReply.content`/`finishReason` predicate。
- persistence：chunk 后的 `Duration.zero` 改为等待 streaming content / 保存完成（`await save()` 或 Provider predicate）。

- [ ] **Step 4: 验收运行**

```powershell
foreach ($f in @("test/features/chat/application/chat_sessions_controller_test.dart", "test/features/chat/application/chat_sessions_controller/chat_sessions_controller_stop_cases.dart")) {
  1..20 | ForEach-Object {
    flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t5-$_.log
    if ($LASTEXITCODE -ne 0) { Get-Content -Tail 80 t5-$_.log; throw "$f round $_ failed" }
  }
}
rg -n "Future\.delayed|chunkDelay" test/features/chat/application/chat_sessions_controller test/features/chat/application/chat_sessions_controller_persistence_test.dart
flutter analyze
```

预期：controller 入口连续 20 次、单独 stop case 连续 20 次全过，无未处理异步错误；`rg` 无输出。

- [ ] **Step 5: 提交**

```bash
git add test/features/chat/application/chat_sessions_controller/ test/features/chat/application/chat_sessions_controller_persistence_test.dart
git commit -m "test(chat): 移除停止与重试竞态的时间轮询"
```

---

### Task 6: 治理聊天集成、后台保存和负向监听等待

**Files:**
- Modify: `test/integration/chat_lifecycle_integration_test.dart`
- Modify: `test/features/chat/data/background_chat_repository_lifecycle_test.dart`
- Modify: `test/features/chat/application/composer_draft_controller_test.dart`

**Interfaces:**
- Consumes: 受控流（任务 4）、`waitForProviderState`（任务 1）、`BackgroundChatConversationRepository.save()`/`flush()` ACK。
- Produces: 无新接口。

- [ ] **Step 1: 迁移集成测试的 5 处 5ms**

`chat_lifecycle_integration_test.dart`：`Future.delayed(const Duration(milliseconds: 5))` 逐处改：

| 等待目的 | 替换为 |
|---|---|
| 流开始监听 | `await controlled.listened` |
| 增量进入状态 | `await waitForProviderState(..., matches: (s) => s.generation.phase == ...)` |
| checkpoint busy guard 触发 | 明确等进入 generation active phase 后触发（`waitForState` active phase predicate），不靠延时 |

- [ ] **Step 2: 迁移后台仓储 100ms**

`background_chat_repository_lifecycle_test.dart`：第一次 `await save()` 已收到 ACK；直接发第二次保存并 `await` 其 Future，删除中间 100ms。验证两批保存没有被错误合并（各批次行数分别断言）。

- [ ] **Step 3: 迁移 composer draft 负向监听**

`composer_draft_controller_test.dart`：删除 5 次 `Duration.zero` 的 `_flushMicrotasks`。负向监听断言（"无关修改不触发回调"）改为：用"无关修改 → 下一次相关选择事件"夹住观察窗口，按通知计数断言无额外回调：

```dart
// 迁移前
notifier.selectSomething();          // 无关修改
await _flushMicrotasks();            // 等 N 个 microtask 后断言"没发生"
expect(notifications, hasLength(0));

// 迁移后：负向观察窗口用后续正向事件夹住
notifier.selectSomething();          // 无关修改
notifier.selectSomethingRelated();   // 下一次相关选择事件 = 窗口终点
expect(notifications, hasLength(1)); // 只收到相关选择回调，无关修改未触发
```

- [ ] **Step 4: 验收运行**

```powershell
foreach ($f in @("test/integration/chat_lifecycle_integration_test.dart", "test/features/chat/data/background_chat_repository_lifecycle_test.dart", "test/features/chat/application/composer_draft_controller_test.dart")) {
  1..10 | ForEach-Object {
    flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t6-$(Split-Path $f -Leaf)-$_.log
    if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 "t6-$(Split-Path $f -Leaf)-$_.log"; throw "$f round $_ failed" }
  }
}
rg -n "Future\.delayed" test/integration/chat_lifecycle_integration_test.dart test/features/chat/data/background_chat_repository_lifecycle_test.dart test/features/chat/application/composer_draft_controller_test.dart
```

预期：各连续 10 次全过；`rg` 无输出。

- [ ] **Step 5: 提交**

```bash
git add test/integration/chat_lifecycle_integration_test.dart test/features/chat/data/background_chat_repository_lifecycle_test.dart test/features/chat/application/composer_draft_controller_test.dart
git commit -m "test(chat): 以完成信号替代集成与持久化等待"
```

---

### Task 7: 治理同步状态等待，登记 UDP 例外

**Files:**
- Modify: `test/features/sync/application/sync_client_controller_test.dart`
- （不改 `test/features/sync/data/sync_udp_discovery_test.dart`）

**Interfaces:**
- Consumes: `waitForProviderState`（任务 1）、fake transport 的 add/close。
- Produces: 无新接口；`sync_udp_discovery_test.dart` 3 处非零 delay（200ms/1s/2s）作为门禁例外的登记依据（记录于任务 13）。

- [ ] **Step 1: 删除 `flushAsync` 与零时长 flush**

`sync_client_controller_test.dart`：删除 `flushAsync` helper 与所有 `Duration.zero` 的 microtask flush 调用。

- [ ] **Step 2: 以 Provider phase 等待连接状态**

在 fake transport add/close 事件前注册 phase predicate（`SyncPhase` 与 `syncClientControllerProvider` 从 `package:oh_my_llm/features/sync/application/sync_client_controller.dart` import）：

```dart
// 迁移前
fakeTransport.emitConnected();
await flushAsync();

// 迁移后
final connected = waitForProviderState(
  container: container,
  provider: syncClientControllerProvider,
  matches: (s) => s.phase == SyncPhase.connected,
  description: '同步连接建立',
);
fakeTransport.emitConnected();
await connected;
```

disconnected、error 同理各注册对应 predicate 再触发。

- [ ] **Step 3: 容器 dispose 前收口**

dispose 前关闭 fake transport 并等待 controller 终态，避免 dangling listener：

```dart
await fakeTransport.close(); // 或按 fake 实际 API
await waitForProviderState(
  container: container,
  provider: syncClientControllerProvider,
  matches: (s) => s.phase == SyncPhase.error || s.server == null,
  description: '同步连接关闭',
);
container.dispose();
```

- [ ] **Step 4: 记录 UDP 例外**

将 `sync_udp_discovery_test.dart` 3 处 delay 的用途（200ms 资源释放窗口、1s/2s 负向观测）与 `udp` tag 行为记入任务 13 的门禁注释依据；不改该文件。

- [ ] **Step 5: 验收运行**

```powershell
1..10 | ForEach-Object {
  flutter test test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t7-$_.log
  if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 t7-$_.log; throw "round $_ failed" }
}
rg -n "Future\.delayed|flushAsync" test/features/sync/application/sync_client_controller_test.dart
flutter analyze
```

预期：连续 10 次全过；`rg` 无输出。

- [ ] **Step 6: 提交**

```bash
git add test/features/sync/application/sync_client_controller_test.dart
git commit -m "test(sync): 以连接状态替代微任务等待"
```

---

### Task 8: 清除聊天测试内部 Key Finder

**Files:**
- Modify: `test/features/chat/chat_screen/chat_screen_test_helpers.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`
- Modify: `test/features/chat/widgets/message_anchor_rail_test.dart`

**Interfaces:**
- Consumes: 契约 B 的 Finder 映射。
- Produces: 无新接口。

- [ ] **Step 1: composer finder 改为可见 label**

`chat_screen_test_helpers.dart` 中 1 处 composer Key：

```dart
// 迁移前
final composer = find.byKey(const Key('chat-message-composer'));

// 迁移后：限定在 ChatScreen 范围内，按"正文"label 定位输入框
final composer = find.descendant(
  of: find.byType(ChatScreen),
  matching: find.widgetWithText(TextField, '正文'),
);
```

- [ ] **Step 2: 迁移 workspace ownership 的 7 个 Key**

- 模板变量字段：在模板变量区域以变量 label 定位（`find.widgetWithText(TextField, 'title')` 限定区域），断言使用实际用户可见文本。
- 消息 ID Key：以唯一可见用户消息正文找到所属消息气泡，再在气泡内定位 `编辑消息` tooltip：

```dart
// 迁移前
final editButton = find.byKey(Key('edit-${message.id}'));

// 迁移后
final bubble = find.widgetWithText(ChatMessageBubble, '唯一的用户消息正文');
await tester.tap(find.descendant(
  of: bubble,
  matching: find.byTooltip('编辑消息'),
));
```

- [ ] **Step 3: anchor rail 用语义定位**

`message_anchor_rail_test.dart`：删除 rail 容器 Key，以既有 semantics label（`第 N 条用户消息：<preview>`）定位；hover/tap 施加在语义节点，不再定位容器 Key：

```dart
// 迁移前
final rail = find.byKey(const Key('message-anchor-rail'));
await tester.hover(find.descendant(of: rail, matching: find.byType(MessageAnchorItem)));

// 迁移后
final firstAnchor = find.bySemanticsLabel('第 1 条用户消息：<preview>');
await tester.hover(firstAnchor);
```

（`ChatMessageBubble`/`MessageAnchorItem` 按文件内实际类型名调整；语义 label 格式按页面实际实现。）

- [ ] **Step 4: 确认生产 Key 未删**

`rg -n "KeyedSubtree|Key\(" lib/features/chat` 只确认生产 Key 存在，不修改生产代码。

- [ ] **Step 5: 验收运行**

```powershell
flutter test test/features/chat/chat_screen/chat_screen_test.dart test/features/chat/widgets/message_anchor_rail_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t8.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 60 t8.log
rg -n "find\.byKey" test/features/chat
flutter analyze
```

预期：EXIT=0；`rg` 无输出。

- [ ] **Step 6: 提交**

```bash
git add test/features/chat/chat_screen/chat_screen_test_helpers.dart test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart test/features/chat/widgets/message_anchor_rail_test.dart
git commit -m "test(chat): 改用可见行为定位聊天控件"
```

---

### Task 9: 清除 Settings 内部 Key Finder

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`
- Modify: `test/features/settings/presentation/model_config_form_dialog_test.dart`

**Interfaces:**
- Consumes: 契约 B 的设置标签表。
- Produces: 无新接口。

- [ ] **Step 1: 建立类型限定的字段 finder**

`settings_screen_test_helpers.dart` 中 17 个字段 Key 逐个改为"dialog 类型 + 可见 label"：

```dart
/// 在指定 dialog 内按可见 label 定位输入框。禁止全局"第 N 个 TextField"。
Finder fieldInDialog<T extends Widget>(String label, {bool wrapsText = false}) =>
    find.descendant(
      of: find.byType(T),
      matching: wrapsText
          ? find.widgetWithText(TextField, label)
          : find.widgetWithText(TextFormField, label),
    );
```

使用点示例：

```dart
// 迁移前
final urlField = find.byKey(const Key('provider-api-url'));

// 迁移后
final urlField = fieldInDialog<ProviderConfigDialog>('API URL');
```

各 dialog 类型对应的标签：服务商 dialog → `服务商名称`/`API URL`/`API Key`；模型 dialog → `显示名称`/`API 模型名称`/`支持深度思考`；预设 Prompt → `预设 Prompt 名称`/`标题`/`Prompt 内容`；固定序列 → `序列名称`/`步骤标题`/`步骤内容`；模板 → `标题`/`模板提示词`（动态变量用变量名）；记忆 Prompt → `名称`/`记忆总结提示词`。（dialog 类型名按文件内实际类名。）

- [ ] **Step 2: 迁移 13 个 dialog 测试使用点**

`model_config_form_dialog_test.dart`：

```dart
// 模型拉取按钮（迁移前：Key）
final fetchButton = find.byKey(const Key('fetch-models'));

// 迁移后：可见文本；加载态按"正在拉取..."
final fetchButton = find.widgetWithText(FilledButton, '拉取模型');
```

模型选择 checkbox：以远端模型名找到所属 row，再找 row 内 `Checkbox` 角色：

```dart
final row = find.widgetWithText(Row, 'gpt-4.1');
final checkbox = find.descendant(of: row, matching: find.byType(Checkbox));
```

- [ ] **Step 3: 模型拉取用 Completer 控制**

对模型加载过程使用测试 Completer：完成前断言 `正在拉取...`，完成后断言模型行；不用 settle 代替 Future：

```dart
final completer = Completer<List<RemoteModel>>();
// 注入提供 completer.future 的 fake 拉取函数
await tester.tap(fetchButton);
await tester.pump(); // 加载一帧
expect(find.text('正在拉取...'), findsOneWidget);
completer.complete([RemoteModel(id: 'gpt-4.1', name: 'gpt-4.1')]);
await tester.pump(); // 完成一帧
expect(find.text('gpt-4.1'), findsOneWidget);
```

- [ ] **Step 4: 验收运行**

```powershell
flutter test test/features/settings/settings_screen_test.dart test/features/settings/presentation/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t9.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 60 t9.log
rg -n "find\.byKey" test/features/settings
flutter analyze
```

预期：EXIT=0；`rg` 无输出。

- [ ] **Step 5: 提交**

```bash
git add test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/presentation/model_config_form_dialog_test.dart
git commit -m "test(settings): 改用标签与角色定位表单控件"
```

---

### Task 10: 迁移聊天 Widget 的直接 settle

**Files:**
- Modify: `test/features/chat/chat_screen/chat_screen_basics_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_branching_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_favorites_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_streaming_cases.dart`
- Modify: `test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart`
- Modify: `test/features/chat/widgets/message_anchor_rail_test.dart`

**Interfaces:**
- Consumes: 任务 1-8 的所有 helper 与信号（动画 helper / `waitForProviderState` / 受控流 / 可见 finder）。
- Produces: 无新接口。

- [ ] **Step 1: 逐文件分类标记**

对每个文件的每处 `pumpAndSettle` 标注七类之一：single frame、provider state、controlled stream、route、overlay、scroll、animated widget。禁止全局字符串替换。生成/保存类必须走完成信号；只有后四类可以调用动画 helper。

- [ ] **Step 2: 迁移每个文件（小步验证）**

每个 case 文件完成后立即跑对应 chat screen 入口，避免 100+ 修改后才定位问题。代表性替换：

```dart
// 生成完成（basics/favorites/branching/workspace）
// 迁移前
await tester.pumpAndSettle();

// 迁移后：等待生成终态后单帧
await waitForChatGeneration(
  tester,
  container,
  (s) => s.generation.phase == ChatGenerationPhase.succeeded,
  description: '生成完成',
);
```

```dart
// dialog / menu / drawer / sheet
// 迁移前
await tester.pumpAndSettle();

// 迁移后
await settleOverlayTransition(tester);
```

```dart
// composer 展开收起 / rail 动画 / reasoning 展开
// 迁移前
await tester.pumpAndSettle();

// 迁移后
await settleAnimatedWidgetTransition(tester);
```

```dart
// scroll-to-bottom
// 迁移前
await tester.pumpAndSettle();

// 迁移后
await settleScrollMotion(tester);
```

```dart
// 纯同步状态变更（树选择、Repository 结果、focus/selection）
// 迁移前
await tester.pumpAndSettle();

// 迁移后
await tester.pump();
```

- [ ] **Step 3: streaming 用例改用受控流**

`chat_screen_streaming_cases.dart`：`enqueueControlledStream()` 逐步 add chunk，每步等待状态 predicate 后 pump 单帧；reasoning 展开用 animated-widget；复制等同步动作只 pump。

- [ ] **Step 4: 验收运行**

```powershell
foreach ($f in @("test/features/chat/chat_screen/chat_screen_test.dart", "test/features/chat/widgets/message_anchor_rail_test.dart")) {
  flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t10-$(Split-Path $f -Leaf).log
  Write-Host "$f EXIT=$LASTEXITCODE"; Get-Content -Tail 50 "t10-$(Split-Path $f -Leaf).log"
}
foreach ($f in @("test/features/chat/chat_screen/chat_screen_streaming_cases.dart", "test/features/chat/chat_screen/chat_screen_branching_cases.dart", "test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart")) {
  1..10 | ForEach-Object {
    flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t10b-$_.log
    if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 t10b-$_.log; throw "$f round $_ failed" }
  }
}
rg -n "pumpAndSettle" test/features/chat
flutter analyze
```

预期：入口全过，三个高风险文件各连续 10 次全过；`rg` 无输出。

- [ ] **Step 5: 提交**

```bash
git add test/features/chat/chat_screen/ test/features/chat/widgets/message_anchor_rail_test.dart
git commit -m "test(chat): 按可观察状态收敛 Widget 等待"
```

---

### Task 11: 迁移 Settings、History 与 Favorites 的直接 settle

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`
- Modify: `test/features/settings/presentation/import_confirm_dialog_test.dart`
- Modify: `test/features/settings/presentation/output_processing_tab_test.dart`
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_actions_cases.dart`
- Modify: `test/features/history/history_screen/history_screen_pagination_bar_cases.dart`
- Modify: `test/features/favorites/manage_collections_dialog_cases.dart`
- Modify: `test/features/favorites/favorites_screen_detail_cases.dart`
- Modify: `test/features/favorites/favorites_screen_basics_cases.dart`

**Interfaces:**
- Consumes: 动画 helper、`waitForProviderState`、`HistoryScreen.searchDebounce`（300ms）、`TemplatePromptFormDialog.variableReconcileDebounce`（220ms）。
- Produces: 无新接口。

- [ ] **Step 1: Settings 先迁共享 helper 再迁各 case**

- tab 切换：`settleTabTransition`；dialog/menu：`settleOverlayTransition`；CRUD Future 完成后单帧 `pump()`。
- 模型拉取/异步保存由测试 Completer 控制（同任务 9 Step 3），不用 settle 等网络。
- 模板变量 Timer 精确推进：

```dart
// 迁移前
await tester.pump(const Duration(milliseconds: 270)); // variableReconcileDebounce + 50ms
await tester.pumpAndSettle();

// 迁移后：边界前观察未触发，再精确推进公开常量
await tester.pump(); // 输入后单帧：未触发
expect(尚未触发断言, ...);
await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce);
await tester.pump();
expect(触发断言, ...);
```

- [ ] **Step 2: History 搜索精确推进 debounce**

`history_screen_search_cases.dart`：每次输入后先断言旧结果仍在（边界前），再 `pump(HistoryScreen.searchDebounce)`，下一帧断言新结果；删除 4 处 `+50ms` 与随后 settle。

- [ ] **Step 3: History actions / pagination / Favorites**

- 删除/重命名确认：`settleOverlayTransition`；action 完成后单帧。
- 页码切换是同步状态则只 `pump()`；只有真实滚动才用 `settleScrollMotion`。
- Favorites：导航用 `settleRouteTransition`；dialog 用 `settleOverlayTransition`；Repository/Provider 状态用单帧。

- [ ] **Step 4: 验收运行（含 debounce 边界用例重复验证）**

```powershell
foreach ($f in @("test/features/settings/settings_screen_test.dart", "test/features/history/history_screen/history_screen_test.dart", "test/features/favorites/favorites_screen_test.dart")) {
  flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t11-$(Split-Path $f -Leaf).log
  Write-Host "$f EXIT=$LASTEXITCODE"; Get-Content -Tail 50 "t11-$(Split-Path $f -Leaf).log"
}
foreach ($f in @("test/features/history/history_screen/history_screen_search_cases.dart")) {
  1..20 | ForEach-Object {
    flutter test $f --reporter compact 2>&1 | Out-File -Encoding utf8 t11b-$_.log
    if ($LASTEXITCODE -ne 0) { Get-Content -Tail 60 t11b-$_.log; throw "round $_ failed" }
  }
}
rg -n "pumpAndSettle|searchDebounce\s*\+|variableReconcileDebounce\s*\+" test/features/settings test/features/history test/features/favorites
flutter analyze
```

预期：三个 feature 全过，搜索 debounce 用例连续 20 次全过；`rg` 无输出。

- [ ] **Step 5: 提交**

```bash
git add test/features/settings test/features/history test/features/favorites
git commit -m "test: 收敛设置历史与收藏界面的等待"
```

---

### Task 12: 迁移 Core Widget、App、Media、Sync 和基础集成的直接 settle/魔法时长

**Files:**
- Modify: `test/core/widgets/notification_bubble_accessibility_test.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`
- Modify: `test/features/media/presentation/image_viewer_page_test.dart`
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`
- Modify: `test/features/media/presentation/shuffle_appbar_actions_test.dart`
- Modify: `test/features/media/presentation/media_route_pages_test.dart`
- Modify: `test/features/media/presentation/video_player_page_test.dart`（手势与产品 Timer 部分）
- Modify: `test/features/media/presentation/video_player_accessibility_test.dart`
- Modify: `test/features/sync/presentation/widgets/interface_selector_test.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_render_cases.dart`
- Modify: `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`
- Modify: `test/widget_test.dart`、`test/integration/bootstrap_integration_test.dart`（残余 setup settle 清理）

**Interfaces:**
- Consumes: 契约 C 的手势/动画常量；任务 2 的 `waitForInitializeCount`；动画 helper。
- Produces: 无新接口。

- [ ] **Step 1: Notification bubble**

`notification_bubble_accessibility_test.dart`：入场/清理 300ms 用 `settleAnimatedWidgetTransition`；dismiss 后语义立即退出只 `pump()` 一帧，删除 50ms 魔法值。

- [ ] **Step 2: App 路由与壳层**

`app_router_test.dart`：GoRouter navigation/redirect 用 `settleRouteTransition`；静态页 setup 单帧。
`app_shell_scaffold_test.dart`：drawer 用 `settleOverlayTransition`，页面切换用 `settleRouteTransition`；普通 selection 单帧。

- [ ] **Step 3: ImageViewer**

`image_viewer_page_test.dart`：PageView drag/ballistic 用 `settleScrollMotion`；双击两次 tap 间隔用 `kDoubleTapMinTime`：

```dart
// 迁移前
await tester.tap(image);
await tester.pump(const Duration(milliseconds: 150)); // 双击间隔魔法值
await tester.tap(image);

// 迁移后
await tester.tap(image);
await tester.pump(kDoubleTapMinTime);
await tester.tap(image);
```

缩放结束用 `settleAnimatedWidgetTransition`；删除 250ms 魔法值。

- [ ] **Step 4: Media 导航双击竞技场**

`media_browser_navigation_test.dart`、`shuffle_appbar_actions_test.dart`：等待单击胜出双击手势竞技场时精确推进 `kDoubleTapTimeout`，随后 `settleRouteTransition`；删除 400ms：

```dart
// 迁移前
await tester.tap(item);
await tester.pump(const Duration(milliseconds: 400));
await settleRouteTransition(tester); // 或原有 settle

// 迁移后
await tester.tap(item);
await tester.pump(kDoubleTapTimeout);
await settleRouteTransition(tester);
```

- [ ] **Step 5: Media route fake 初始化**

`media_route_pages_test.dart`：fake 初始化由 `waitForInitializeCount` + 单帧表达，删除 100ms；Navigator/GoRouter 用 `settleRouteTransition`。

- [ ] **Step 6: Video 手势与产品 Timer**

`video_player_page_test.dart` / `video_player_accessibility_test.dart`：

```dart
// 双击间隔
await tester.tap(video);
await tester.pump(kDoubleTapMinTime);
await tester.tap(video);

// 单击解析（等待胜出双击竞技场）
await tester.tap(video);
await tester.pump(kDoubleTapTimeout);

// 长按
final gesture = await tester.startGesture(center);
await tester.pump(kLongPressTimeout);
```

```dart
// 中央 seek/speed hint 消失：精确 1 秒契约
await tester.pump(const Duration(seconds: 1));
// 控制栏自动隐藏：精确 3 秒契约边界，再等待淡出动画
await tester.pump(const Duration(seconds: 3));
await settleAnimatedWidgetTransition(tester);
```

删除 4 秒/500/600ms 余量与 fake method 完成后的 100ms（改单帧）。`video_player_accessibility_test.dart` 的长按/单击同样使用手势常量。

- [ ] **Step 7: Sync 与基础集成**

- `interface_selector_test.dart`：接口选择和持久化是同步/await 后状态，只 `pump()`。
- `sync_screen_import_dialog_cases.dart`：dialog 用 `settleOverlayTransition`；导入状态等 Provider predicate。
- `sync_screen_render_cases.dart` / `sync_screen_responsive_cases.dart`：tab 用 `settleTabTransition`；连接状态等 Provider；布局单帧。
- `test/widget_test.dart` / `bootstrap_integration_test.dart`：清理残余 setup settle。

- [ ] **Step 8: 全仓审计**

```powershell
rg -n "pumpAndSettle" test --glob "*.dart"
rg -n "tester\.pump\(const Duration\(milliseconds: [0-9]+\)\)" test --glob "*.dart"
```

预期：第一条只有 `test/helpers/widget_test_animation.dart` 1 处；第二条无输出（秒级产品 Timer 契约值允许，魔法毫秒不允许）。

- [ ] **Step 9: 验收运行**

```powershell
flutter test test/core/widgets/notification_bubble_accessibility_test.dart test/app/router/app_router_test.dart test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t12.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 50 t12.log
flutter test test/features/media --reporter compact 2>&1 | Out-File -Encoding utf8 t12b.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 50 t12b.log
flutter test test/features/sync test/widget_test.dart test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t12c.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 50 t12c.log
flutter analyze
```

预期：全部 EXIT=0。

- [ ] **Step 10: 提交**

```bash
git add test/core/widgets test/app test/features/media test/features/sync test/widget_test.dart test/integration/bootstrap_integration_test.dart
git commit -m "test: 收敛导航媒体与同步界面的等待"
```

---

### Task 13: 增加持续门禁并完成审计

**Files:**
- Create: `test/architecture/test_resilience_policy_test.dart`

**Interfaces:**
- Consumes: 整个 `test/` 树（路径统一 `/`）。
- Produces: `_maskCommentsAndStrings(String)` 词法扫描器；精确 allowlist 校验（"路径 → 精确数量 + 原因"，少于允许数量也失败）。

- [ ] **Step 1: 实现门禁（TDD：先写扫描器单测骨架，再实现）**

`test/architecture/test_resilience_policy_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 保持测试树免受脆弱等待与内部 Finder 回流。
///
/// 扫描器先用词法状态机把注释与字符串内容替换为空白（保留换行），
/// 再对剩余代码计数，避免 URL、转义引号或多行字符串破坏匹配。
/// 待查 token 用字符串片段拼接，形成门禁自身的第二层自匹配保护。
void main() {
  group('扫描器', () {
    test('注释与字符串内容不计数', () {
      const source = '''
// 'find.by' + 'Key' 在行注释里
/* "pumpAndSettle" 在块注释里 */
final s = 'Future' + '.delayed(Duration.zero)';
find.by' + 'Key(const Key('x'));
''';
      final masked = _maskCommentsAndStrings(source);
      expect(_countOf(masked, _findByKeyPattern), 1);
      expect(_countOf(masked, _futureDelayedPattern), 1);
      expect(_countOf(masked, _pumpAndSettlePattern), 0);
    });

    test('泛型与非泛型延时都计数，多行 pump 可识别', () {
      const source = '''
Future.delayed(Duration.zero);
Future<void>.delayed(const Duration(seconds: 1));
tester
    .pump(
      const Duration(milliseconds: 300),
    );
''';
      final masked = _maskCommentsAndStrings(source);
      expect(_countOf(masked, _futureDelayedPattern), 2);
      expect(_countOf(masked, _literalMsPumpPattern), 1);
    });
  });

  group('仓库门禁', () {
    test('整个 test 树满足韧性契约', () async {
      final rawSettleCounts = <String, int>{};
      final delayedCounts = <String, int>{};
      final otherViolations = <String>[];

      await for (final entity in Directory('test').list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final masked = _maskCommentsAndStrings(await entity.readAsString());

        final settleCount = _countOf(masked, _pumpAndSettlePattern);
        if (settleCount > 0) rawSettleCounts[path] = settleCount;
        final delayedCount = _countOf(masked, _futureDelayedPattern);
        if (delayedCount > 0) delayedCounts[path] = delayedCount;

        if (_countOf(masked, _findByKeyPattern) > 0) {
          otherViolations.add('$path: find.byKey');
        }
        if (_countOf(masked, _chunkDelayPattern) > 0) {
          otherViolations.add('$path: chunkDelay');
        }
        if (_countOf(masked, _debounceMarginPattern) > 0) {
          otherViolations.add('$path: debounce 加余量');
        }
        if (_countOf(masked, _literalMsPumpPattern) > 0) {
          otherViolations.add('$path: 魔法毫秒 pump');
        }
      }

      _verifyExactAllow(rawSettleCounts, _pumpAndSettleAllow, 'pumpAndSettle');
      _verifyExactAllow(delayedCounts, _futureDelayedAllow, 'Future.delayed');
      expect(otherViolations, isEmpty,
          reason: '违规项:\n${otherViolations.join('\n')}');
    });
  });
}

/// 允许直接 pumpAndSettle 的唯一位置，精确 1 处。
const _pumpAndSettleAllow = {
  'test/helpers/widget_test_animation.dart': 1,
};

/// 允许真实延时的唯一位置（外部 socket 资源释放与负向观测，
/// 已有 udp tag 且 CI 排除），精确 3 处。
const _futureDelayedAllow = {
  'test/features/sync/data/sync_udp_discovery_test.dart': 3,
};

// 待查 token 均以片段拼接，避免门禁自身被匹配
final _findByKeyPattern = RegExp(r'find\.by' + 'Key');
final _pumpAndSettlePattern = RegExp('pump' + 'AndSettle');
final _futureDelayedPattern = RegExp(r'Future(?:<[^>]+>)?\.' + 'delayed');
final _chunkDelayPattern = RegExp('chunk' + 'Delay');
final _debounceMarginPattern =
    RegExp('search' + 'Debounce' r'\s*\+|variable' + 'Reconcile' r'Debounce\s*\+');
final _literalMsPumpPattern = RegExp(
  r'tester\s*\.\s*pump\s*\(\s*(?:const\s+)?Duration\s*\(\s*milliseconds\s*:\s*\d+',
  multiLine: true,
);

/// 精确 allowlist 校验：少于允许数量也失败，防止陈旧豁免永远保留。
void _verifyExactAllow(
  Map<String, int> actual,
  Map<String, int> allow,
  String token,
) {
  final excess = actual.entries
      .where((e) => allow[e.key] != e.value)
      .map((e) => '${e.key}: ${e.value} 处 $token（允许 ${allow[e.key] ?? 0}）')
      .join('\n');
  expect(excess, isEmpty, reason: '超出或缺失的豁免:\n$excess');
  final missing = allow.keys.where((k) => !actual.containsKey(k)).toList();
  expect(missing, isEmpty, reason: '豁免路径未出现（陈旧豁免）:\n$missing');
}

int _countOf(String masked, RegExp pattern) =>
    pattern.allMatches(masked).length;

/// 把注释与字符串内容替换为空白，保留换行与其余字符。
String _maskCommentsAndStrings(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    final isSlash = char == '/';
    if (isSlash && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        buffer.write(' ');
        i++;
      }
    } else if (isSlash && i + 1 < source.length && source[i + 1] == '*') {
      buffer.write('  ');
      i += 2;
      while (i + 1 < source.length && !(source[i] == '*' && source[i + 1] == '/')) {
        buffer.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i + 1 < source.length) {
        buffer.write('  ');
        i += 2;
      }
    } else if (char == "'" || char == '"') {
      final quote = char;
      buffer.write(' ');
      i++;
      var triple = false;
      if (i + 1 < source.length && source[i] == quote && source[i + 1] == quote) {
        triple = true;
        buffer.write('  ');
        i += 2;
      }
      while (i < source.length) {
        if (source[i] == r'\' && i + 1 < source.length) {
          buffer.write('  ');
          i += 2;
        } else if (source[i] == quote) {
          if (triple) {
            if (i + 2 < source.length &&
                source[i + 1] == quote &&
                source[i + 2] == quote) {
              buffer.write('   ');
              i += 3;
              break;
            }
            buffer.write(' ');
            i++;
          } else {
            buffer.write(' ');
            i++;
            break;
          }
        } else {
          buffer.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
    } else {
      buffer.write(char);
      i++;
    }
  }
  return buffer.toString();
}
```

- [ ] **Step 2: 门禁自身反例测试**

在 `group('扫描器')` 内增加（确保新增违规与陈旧豁免都会失败）：

```dart
    test('反例：新增违规会被拒绝', () {
      // 构造"额外 find.byKey / 额外 raw settle / 额外 1ms delay"的模拟扫描
      const violatingSource = '''
find.by' + 'Key(const Key('x'));
tester.pump' + 'AndSettle();
Future<void>.delayed(const Duration(milliseconds: 1));
''';
      final masked = _maskCommentsAndStrings(violatingSource);
      expect(_countOf(masked, _findByKeyPattern), 1);
      expect(_countOf(masked, _pumpAndSettlePattern), 1);
      expect(_countOf(masked, _futureDelayedPattern), 1);
    });

    test('反例：陈旧豁免会被拒绝', () {
      const staleSource = '''
tester.pump' + 'AndSettle();
''';
      final masked = _maskCommentsAndStrings(staleSource);
      final counts = {'fake/path.dart': _countOf(masked, _pumpAndSettlePattern)};
      // 允许列表只登记 widget_test_animation.dart：fake/path.dart 出现即越界
      expect(_pumpAndSettleAllow.containsKey('fake/path.dart'), isFalse);
      _verifyExactAllow(counts, _pumpAndSettleAllow, 'pumpAndSettle');
    });
```

第二个反例通过 `_verifyExactAllow` 的"超出部分"分支失败，验证陈旧/新增豁免都会触发失败。

- [ ] **Step 3: 运行门禁并完成最终静态审计**

```powershell
flutter test test/architecture/test_resilience_policy_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 t13.log
Write-Host "EXIT=$LASTEXITCODE"; Get-Content -Tail 60 t13.log
```

若门禁失败，逐项修复（任何 `find.byKey`/raw settle/延时/余量残留在对应文件，回到对应任务迁移），直到：

```powershell
rg -n "find\.byKey" test --glob "*.dart"
rg -n "pumpAndSettle" test --glob "*.dart"
rg --pcre2 -n "Future(?:<[^>]+>)?\.delayed|chunkDelay" test --glob "*.dart"
rg -n "searchDebounce\s*\+|variableReconcileDebounce\s*\+|Duration\([^)]*\)\s*\+" test --glob "*.dart"
rg -U --pcre2 -n "tester\s*\.\s*pump\s*\(\s*(?:const\s+)?Duration\s*\(\s*milliseconds" test --glob "*.dart"
```

预期：第一条无输出；第二条只有 `widget_test_animation.dart` 1 处；第三条只有 UDP 文件 3 处、无 `Duration.zero`；第四、五条无输出。

- [ ] **Step 4: 全量验证（7.2-7.6 节）**

按"七、测试与验证策略"执行：高风险集合连续 10 次 → CI 同构连续 3 次（中位数不劣于任务 0 基线）→ 本地完整测试（含 UDP，`fltest.log`）→ `flutter analyze` → `git diff --check` → `git status --short` 只含预期文件。

- [ ] **Step 5: 提交**

```bash
git add test/architecture/test_resilience_policy_test.dart
git commit -m "test: 防止脆弱等待与内部 Finder 回流"
```

---

## 七、测试与验证策略（最终阶段全量执行）

### 7.1 高风险重复测试（最终至少连续 10 次）

```powershell
$phase15HighRisk = @(
  'test/features/chat/application/chat_generation_run_test.dart',
  'test/features/chat/application/chat_generation_race_contract_test.dart',
  'test/features/chat/application/chat_sessions_controller_test.dart',
  'test/integration/chat_lifecycle_integration_test.dart',
  'test/features/media/presentation/video_player_page_test.dart',
  'test/features/settings/settings_screen_test.dart',
  'test/core/logging/sse_log_buffer_test.dart',
  'test/features/sync/application/sync_client_controller_test.dart',
  'test/architecture/test_resilience_policy_test.dart'
)
1..10 | ForEach-Object {
  $phase15Round = $_
  foreach ($phase15Target in $phase15HighRisk) {
    $phase15Name = [System.IO.Path]::GetFileNameWithoutExtension($phase15Target)
    $phase15Log = "phase15-repeat-$phase15Round-$phase15Name.log"
    flutter test $phase15Target --reporter compact 2>&1 |
      Out-File -Encoding utf8 $phase15Log
    $phase15Exit = $LASTEXITCODE
    if ($phase15Exit -ne 0) {
      Get-Content -Tail 150 $phase15Log
      throw "round $phase15Round failed: $phase15Target, EXIT=$phase15Exit"
    }
  }
}
```

任一次失败即视为不稳定，禁止通过扩大 timeout 或增加延时解决。

### 7.2 CI 同构测试（连续 3 次，与任务 0 基线比较）

```powershell
flutter test --exclude-tags=udp --coverage --reporter compact 2>&1 | Out-File -Encoding utf8 phase15-ci.log
$phase15CiExit = $LASTEXITCODE
Write-Host "EXIT=$phase15CiExit"
Get-Content -Tail 150 phase15-ci.log
```

三次都必须 `EXIT=0`；不得出现偶发 retry 才通过；中位时间不得劣于基线。若有显著变慢，先用测试日志定位等待对象，不能提高全局 timeout。

### 7.3 本地完整测试（含 UDP）

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
$phase15FullExit = $LASTEXITCODE
Write-Host "EXIT=$phase15FullExit"
Get-Content -Tail 150 fltest.log
```

只有 `EXIT=0` 才算通过。若 UDP 因本机网络权限失败，记录为环境结果并另行确认 CI 同构集合，但不得静默宣称"全量通过"，也不得修改 UDP 隔离策略。

### 7.4 最终代码质量检查

- `flutter analyze` 0 issue；`git diff --check` 无空白错误。
- `git status --short` 只包含本阶段预期文件；所有提交消息第一行符合 Conventional Commits。
- 无测试专用生产 API、无产品时长改动、无 `.github`/`dart_test.yaml` 改动（唯一生产改动为 `sse_log_buffer.dart` 的完成语义）。

---

## 失败诊断规则

实施者遇到失败时按以下顺序处理，禁止第一反应增加等待时长：

1. **状态永不满足**：检查 waiter 是否在触发事件前注册、predicate 是否使用正确 phase、流是否已经 `listened`。
2. **受控流 add 时报未监听**：先 `await controlled.listened`，不要插入 1ms。
3. **Widget 只差一帧**：Future/Provider 已明确完成时只 `tester.pump()`；route/overlay 动画用对应 helper。
4. **无限 animation 导致 timeout**：确认该屏幕是否存在持续 spinner；业务测试不应 settle 全树，应等待目标状态后 pump 单帧。不能提高 2 秒 helper timeout。
5. **Finder 找到多个**：增加用户可感知的祖先范围或语义，而不是 `.first`、索引或重新加 Key。
6. **Finder 找不到 label**：先确认当前 UI 实际可见文本；若控件缺少必要可访问语义，可在不改变业务的前提下补 Semantics，但必须同时增加语义行为测试。不能添加仅供测试的隐形文字。
7. **日志 flush 测试挂起**：检查 in-flight Future 是否在所有成功/失败路径移除，以及 `flush()` 是否等待快照。
8. **重复测试偶发失败**：保存失败轮日志，定位未收口 Future/stream/subscription；不能用重跑掩盖。
9. **UDP 失败**：只记录环境和 tag 行为，不把 UDP 改造扩入本阶段。

---

## 独立提交清单

| 顺序 | Commit message | 主要内容 |
|---:|---|---|
| 1 | `test: 收紧共享测试等待工具` | Provider waiter、有限动画 helper、setup 契约 |
| 2 | `test(media): 移除播放器错误用例的真实网络等待` | fake 初始化失败、删除 5 秒 settle |
| 3 | `fix(logging): 让日志 flush 等待在途写入` | 最小生产完成语义与测试 |
| 4 | `test(chat): 用受控流验证生成生命周期` | controlled stream、run/coordinator/race |
| 5 | `test(chat): 移除停止与重试竞态的时间轮询` | controller stop/retry/persistence |
| 6 | `test(chat): 以完成信号替代集成与持久化等待` | integration、background ACK、composer |
| 7 | `test(sync): 以连接状态替代微任务等待` | sync controller，UDP 不改 |
| 8 | `test(chat): 改用可见行为定位聊天控件` | chat Key finder 清零 |
| 9 | `test(settings): 改用标签与角色定位表单控件` | settings Key finder 清零 |
| 10 | `test(chat): 按可观察状态收敛 Widget 等待` | chat Widget settle 迁移 |
| 11 | `test: 收敛设置历史与收藏界面的等待` | settings/history/favorites |
| 12 | `test: 收敛导航媒体与同步界面的等待` | app/media/sync/bootstrap |
| 13 | `test: 防止脆弱等待与内部 Finder 回流` | policy gate、最终审计 |

每个提交独立可回滚。第 3 个提交是唯一包含生产源码的提交；若实施中发现还需要修改其他 production application/core 文件，必须先证明现有状态、ACK、gate 和虚拟时钟无法表达完成，并重新核对范围，不能直接扩张。

---

## Definition of Done

以下项目必须全部满足：

- [ ] 共享 setup helper 只负责首帧，不含全局 settle。
- [ ] 4 处 5 秒 settle 全部删除，视频错误测试不访问真实网络。
- [ ] 34 个原直接 settle 文件均已逐处分类；业务测试不直接调用 `pumpAndSettle`。
- [ ] raw `pumpAndSettle` 全仓只在 animation helper 中精确 1 处。
- [ ] `find.byKey` 在 `test/` 中为 0。
- [ ] `chunkDelay` 为 0。
- [ ] UDP 外 `Future.delayed` 为 0；UDP 精确保留 3 处并由门禁登记。
- [ ] History 和模板变量测试不含 `+50ms` 或其他边界余量。
- [ ] 聊天停止、重试、late callback、dispose、慢保存测试全部由受控流/状态/gate 收口。
- [ ] 后台聊天保存测试等待 ACK，不含固定等待。
- [ ] `SseLogBuffer.flush()` 等待调用前已经在途的 append，并覆盖成功/失败测试。
- [ ] Sync controller 测试等待公开 phase，不做 microtask flush。
- [ ] 所有保留虚拟时间等待都对应明确的产品动画、手势窗口或 Timer。
- [ ] 韧性架构门禁能拒绝新增直接 settle、Key finder、真实 delay 和余量。
- [ ] `dart_test.yaml`、CI workflow 和产品业务时长未改变。
- [ ] 所有改动 Dart 文件已格式化，暂存后格式检查通过。
- [ ] `flutter analyze` 通过。
- [ ] 高风险集合连续 10 次通过。
- [ ] CI 同构全量连续 3 次通过，时间中位数不劣于实施前同机基线。
- [ ] 包含 UDP 的本地完整测试 `EXIT=0`；若环境阻塞，已如实记录而非隐藏。
- [ ] 最终工作区只含预期改动，提交粒度与提交清单一致。
