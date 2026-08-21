# 渐进式响应式设计系统与媒体网格 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可复用的响应式令牌与布局原语，将媒体浏览器从固定三列迁移为按父级空间和用户密度自适应的跨平台网格。

**Architecture:** Core 只提供固定视觉令牌、共享密度枚举和无业务含义的布局原语；Media application 独占设备本地密度偏好，Media presentation 将密度映射为 4:3 缩略图、统一行高和网格规格；app composition 只负责平台默认值及 shell actions 组装。任何布局决策都以父级约束为准，平台只决定无持久化值时的默认密度。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6）/ Dart `^3.11.5` · Riverpod 3 `NotifierProvider` · SharedPreferences · Material 3 · Flutter Widget Test

## Global Constraints

- 不新增依赖；继续使用 Flutter SDK、Riverpod 3 和现有 SharedPreferences provider。
- Windows 默认 `compact`，Android 默认 `standard`，其他平台安全回退 `standard`；平台判断只能留在 `app/composition/`。
- 持久化 key 固定为 `app.feature.media.grid_density`，合法值只允许 `compact`、`standard`、`comfortable`。
- 媒体密度不进入 Settings export/import、Sync 协议或媒体 domain 模型。
- 网格列数只读取 `LayoutBuilder` 的父约束；不得读取 `MediaQuery` 整窗宽度或设备类别。
- 列数算法固定使用 `0.5` 逻辑像素容差；有效 tile 宽度不得超过名义上限加该容差。
- 缩略图区域固定 4:3；每轮布局由上游 metrics 为所有 tile 提供同一个 `mainAxisExtent`。
- 窗口缩放允许正常 build，但必须保持 scroll/key/resource identity，不得重复解析仍可见项目的同一缩略图。
- 所有新增注释、doc comment 和测试名称使用简体中文；禁止 `part` / `part of`。
- 跨 `core/`、跨 feature 和 app 引用使用 `package:oh_my_llm/...`；同一 feature 内使用相对路径。
- 每个任务先写失败测试并保存 `logs/<任务>-red.log`，再保存对应 `logs/<任务>-green.log`；禁止直接输出完整测试流。
- 每次提交前格式化所有改动 Dart 文件，并对暂存 Dart 文件运行 `dart format --output=none --set-exit-if-changed`。
- commit message 的 conventional 前缀保留英文，subject/body 使用简体中文；不要手动修改 `pubspec.yaml`，由 post-commit hook 自动 bump。
- 不批量迁移 Chat、Settings、History、Favorites 或 Sync 的既有稳定布局。

---

## File Structure

### Core constants

- Create `lib/core/constants/app_layout_density.dart`：共享的 `AppLayoutDensity` 三值枚举。
- Create `lib/core/constants/app_layout_tokens.dart`：`AppSpacing`、`AppRadii`、`AppContentWidths`、`AppInteractionSizes`。
- Create `test/core/constants/app_layout_tokens_test.dart`：一次性锁定公开令牌值和密度枚举。

### Core adaptive grid

- Create `lib/core/widgets/adaptive_grid/adaptive_grid_geometry.dart`：纯列数/项目宽度计算，独占 0.5px 容差与输入校验。
- Create `lib/core/widgets/adaptive_grid/app_adaptive_grid.dart`：父约束驱动的惰性 `GridView.builder`。
- Create `test/core/widgets/adaptive_grid/adaptive_grid_geometry_test.dart`：整数、长小数、容差临界点和单调性测试。
- Create `test/core/widgets/adaptive_grid/app_adaptive_grid_test.dart`：父约束、惰性构建、运行时 resize 和子项状态保持测试。

### Core layout primitives and shell

- Create `lib/core/widgets/app_constrained_content.dart`：宽屏内容限宽原语。
- Create `lib/core/widgets/app_adaptive_actions.dart`：宽/紧凑 action 分支规格。
- Modify `lib/core/widgets/adaptive_master_detail_layout.dart`：补齐父约束与等号宽侧 doc contract，不改变行为。
- Modify `lib/app/shell/app_shell_scaffold.dart`：在已有顶层 `LayoutBuilder` 中解析 `AppAdaptiveActions`。
- Create `test/core/widgets/app_constrained_content_test.dart`：父约束与最大内容宽度测试。
- Create `test/core/widgets/app_adaptive_actions_test.dart`：719/720/721 分支测试。
- Modify `test/app/shell/app_shell_scaffold_test.dart`：固定 actions 与 adaptive actions 合并测试。

### Media density state

- Create `lib/features/media/application/media_grid_density_controller.dart`：默认 provider、持久化 writer 和 `Notifier`。
- Modify `lib/app/composition/cross_feature_bindings.dart`：按平台覆盖媒体默认密度。
- Create `test/features/media/application/media_grid_density_controller_test.dart`：默认值、编解码、持久化失败和 revive 测试。
- Create `test/app/composition/media_grid_density_default_test.dart`：Windows/Android composition 默认值测试。
- Modify `test/features/settings/application/transfer/settings_sync_facade_test.dart`：证明本地媒体密度不进入设置同步导出。

### Media layout specifications

- Create `lib/features/media/presentation/models/media_grid_layout_spec.dart`：三种密度的网格与 tile 产品规格。
- Create `lib/features/media/presentation/models/media_grid_tile_metrics.dart`：使用主题与 `TextScaler` 解析统一行高。
- Create `test/features/media/presentation/models/media_grid_layout_spec_test.dart`：三种规格的精确映射测试。
- Create `test/features/media/presentation/models/media_grid_tile_metrics_test.dart`：4:3、统一行高与文字缩放测试。

### Media grid and actions

- Modify `lib/features/media/presentation/widgets/media_grid_view.dart`：消费密度状态并使用 `AppAdaptiveGrid`。
- Modify `lib/features/media/presentation/widgets/media_file_tile.dart`：固定 thumbnail/metadata 区域、零 Card margin、完整名称 tooltip。
- Create `test/features/media/presentation/widgets/media_grid_view_test.dart`：网格 resize、密度变化、长文字和缩略图 identity 回归测试。
- Create `lib/features/media/presentation/widgets/media_grid_density_actions.dart`：展开 IconButtons 与紧凑 PopupMenu。
- Create `test/features/media/presentation/widgets/media_grid_density_actions_test.dart`：selected、tooltip、菜单与持久化交互测试。
- Modify `lib/app/composition/sync_workspace_screen.dart`：把媒体密度 actions 作为 `AppAdaptiveActions` 交给 shell。
- Modify `test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart`：Android 紧凑菜单与 Windows 展开按钮测试。
- Modify `test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart`：切换密度不重建媒体会话/目录测试。

### Documentation

- Modify `AGENTS.md`：写入空间优先、语义令牌、自适应网格与渐进迁移规则。
- Modify `README.md`：说明媒体浏览器支持自适应密度。
- Modify `docs/视频局域网广播-prd.md`：替换固定方形/单行旧规则为 4:3 自适应网格和三档密度。

---

### Task 1: 建立共享布局令牌与密度枚举

**Files:**
- Create: `lib/core/constants/app_layout_density.dart`
- Create: `lib/core/constants/app_layout_tokens.dart`
- Create: `test/core/constants/app_layout_tokens_test.dart`

**Interfaces:**
- Produces: `enum AppLayoutDensity { compact, standard, comfortable }`
- Produces: `AppSpacing.xxs/xs/sm/md/lg/xl`
- Produces: `AppRadii.sm/md/lg/xl`
- Produces: `AppContentWidths.readable/form/wide`
- Produces: `AppInteractionSizes.minimumHitTarget/compactVisualControl/standardVisualControl`

- [ ] **Step 1: 写失败测试锁定公开 token 值**

Create `test/core/constants/app_layout_tokens_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

void main() {
  test('共享布局令牌保持已批准的固定值', () {
    expect(
      [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ],
      [4, 8, 12, 16, 24, 32],
    );
    expect([AppRadii.sm, AppRadii.md, AppRadii.lg, AppRadii.xl], [8, 12, 18, 24]);
    expect(
      [AppContentWidths.readable, AppContentWidths.form, AppContentWidths.wide],
      [720, 900, 1200],
    );
    expect(
      [
        AppInteractionSizes.minimumHitTarget,
        AppInteractionSizes.compactVisualControl,
        AppInteractionSizes.standardVisualControl,
      ],
      [48, 32, 40],
    );
  });

  test('共享密度只暴露紧凑、标准、舒适三个等级', () {
    expect(AppLayoutDensity.values, [
      AppLayoutDensity.compact,
      AppLayoutDensity.standard,
      AppLayoutDensity.comfortable,
    ]);
  });
}
```

- [ ] **Step 2: 运行测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/constants/app_layout_tokens_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/responsive-tokens-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 80 logs/responsive-tokens-red.log
```

Expected: `EXIT≠0`，缺少 `app_layout_density.dart` / `app_layout_tokens.dart`。

- [ ] **Step 3: 实现最小常量类型**

Create `lib/core/constants/app_layout_density.dart`：

```dart
/// 跨 feature 可复用的布局密度语义；不对应全局状态。
enum AppLayoutDensity { compact, standard, comfortable }
```

Create `lib/core/constants/app_layout_tokens.dart`：

```dart
final class AppSpacing {
  const AppSpacing._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

final class AppRadii {
  const AppRadii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double xl = 24;
}

final class AppContentWidths {
  const AppContentWidths._();
  static const double readable = 720;
  static const double form = 900;
  static const double wide = 1200;
}

final class AppInteractionSizes {
  const AppInteractionSizes._();
  static const double minimumHitTarget = 48;
  static const double compactVisualControl = 32;
  static const double standardVisualControl = 40;
}
```

- [ ] **Step 4: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/core/constants/app_layout_density.dart lib/core/constants/app_layout_tokens.dart test/core/constants/app_layout_tokens_test.dart
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/constants/app_layout_tokens_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/responsive-tokens-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 80 logs/responsive-tokens-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 5: 暂存、复查格式并提交**

Run:

```powershell
git add lib/core/constants/app_layout_density.dart lib/core/constants/app_layout_tokens.dart test/core/constants/app_layout_tokens_test.dart
dart format --output=none --set-exit-if-changed lib/core/constants/app_layout_density.dart lib/core/constants/app_layout_tokens.dart test/core/constants/app_layout_tokens_test.dart
git commit -m "feat(core): 建立响应式布局令牌"
```

### Task 2: 实现纯网格算法与 AppAdaptiveGrid

**Files:**
- Create: `lib/core/widgets/adaptive_grid/adaptive_grid_geometry.dart`
- Create: `lib/core/widgets/adaptive_grid/app_adaptive_grid.dart`
- Create: `test/core/widgets/adaptive_grid/adaptive_grid_geometry_test.dart`
- Create: `test/core/widgets/adaptive_grid/app_adaptive_grid_test.dart`

**Interfaces:**
- Produces: `AdaptiveGridGeometry.resolve({availableWidth, horizontalPadding, maxCrossAxisExtent, crossAxisSpacing})`
- Produces: `AdaptiveGridGeometry.crossAxisCount/itemCrossAxisExtent`
- Produces: `AppAdaptiveGridMainAxisExtentBuilder`
- Produces: `AppAdaptiveGridItemBuilder`
- Produces: `AppAdaptiveGrid`

- [ ] **Step 1: 写列数算法失败测试**

Create `test/core/widgets/adaptive_grid/adaptive_grid_geometry_test.dart`，核心用例必须逐项出现：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:oh_my_llm/core/widgets/adaptive_grid/adaptive_grid_geometry.dart';

void main() {
  test('列数在 0.5px 容差内保持稳定，越过容差后增加', () {
    AdaptiveGridGeometry resolve(double width) => AdaptiveGridGeometry.resolve(
      availableWidth: width,
      horizontalPadding: 16,
      maxCrossAxisExtent: 160,
      crossAxisSpacing: 8,
    );

    expect(resolve(176).crossAxisCount, 1); // usable = 160
    expect(resolve(176.5).crossAxisCount, 1);
    expect(resolve(176.500001).crossAxisCount, 2);
    expect(resolve(344.5).crossAxisCount, 2);
    expect(resolve(344.500001).crossAxisCount, 3);
  });

  test('长小数宽度重复计算返回相同几何', () {
    final values = List.generate(
      20,
      (_) => AdaptiveGridGeometry.resolve(
        availableWidth: 411.42857142857144,
        horizontalPadding: 24,
        maxCrossAxisExtent: 220,
        crossAxisSpacing: 12,
      ),
    );
    expect(values.map((value) => value.crossAxisCount).toSet(), {2});
    expect(values.map((value) => value.itemCrossAxisExtent).toSet().length, 1);
  });

  test('宽度增长时列数不减少且项目宽度不超过上限加容差', () {
    var previousColumns = 1;
    for (double width = 0; width <= 1600; width += 0.25) {
      final geometry = AdaptiveGridGeometry.resolve(
        availableWidth: width,
        horizontalPadding: 16,
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 8,
      );
      expect(geometry.crossAxisCount, greaterThanOrEqualTo(previousColumns));
      expect(geometry.itemCrossAxisExtent, lessThanOrEqualTo(160.5));
      previousColumns = geometry.crossAxisCount;
    }
  });

  test('零宽安全退化为一列，无效规格触发断言', () {
    final zero = AdaptiveGridGeometry.resolve(
      availableWidth: 0,
      horizontalPadding: 16,
      maxCrossAxisExtent: 160,
      crossAxisSpacing: 8,
    );
    expect(zero.crossAxisCount, 1);
    expect(zero.itemCrossAxisExtent, 0);
    expect(
      () => AdaptiveGridGeometry.resolve(
        availableWidth: double.infinity,
        horizontalPadding: 0,
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 8,
      ),
      throwsAssertionError,
    );
  });
}
```

- [ ] **Step 2: 写 AppAdaptiveGrid 失败测试**

Create `test/core/widgets/adaptive_grid/app_adaptive_grid_test.dart`，使用 `SizedBox(width: ...)` 作为父约束，并让 item 内层 `LayoutBuilder` 记录获得的宽度。测试必须覆盖：

```dart
testWidgets('网格使用父宽度而不是整窗宽度', (tester) async {
  double? itemWidth;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 411.42857142857144,
          height: 500,
          child: AppAdaptiveGrid(
            itemCount: 30,
            maxCrossAxisExtent: 220,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            padding: const EdgeInsets.all(12),
            mainAxisExtentBuilder: (_, width) => width,
            itemBuilder: (context, index, width) {
              if (index == 0) itemWidth = width;
              return Text('项目$index', key: ValueKey(index));
            },
          ),
        ),
      ),
    ),
  ));
  expect(itemWidth, closeTo((411.42857142857144 - 24 - 12) / 2, 0.000001));
});
```

另写两个测试：`1000` 个 item 初帧的 builder 调用次数必须小于 `1000`；以稳定 `ValueKey` 挂载有计数状态的第一个 item，改变父宽度后计数文本仍为 `1`。

- [ ] **Step 3: 运行两个测试文件并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/widgets/adaptive_grid --reporter compact 2>&1 | Out-File -Encoding utf8 logs/adaptive-grid-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/adaptive-grid-red.log
```

Expected: `EXIT≠0`，缺少 `AdaptiveGridGeometry` 与 `AppAdaptiveGrid`。

- [ ] **Step 4: 实现纯几何类型**

Create `lib/core/widgets/adaptive_grid/adaptive_grid_geometry.dart`：

```dart
import 'dart:math' as math;

final class AdaptiveGridGeometry {
  const AdaptiveGridGeometry._({
    required this.crossAxisCount,
    required this.itemCrossAxisExtent,
  });

  static const double layoutTolerance = 0.5;

  final int crossAxisCount;
  final double itemCrossAxisExtent;

  factory AdaptiveGridGeometry.resolve({
    required double availableWidth,
    required double horizontalPadding,
    required double maxCrossAxisExtent,
    required double crossAxisSpacing,
  }) {
    assert(availableWidth.isFinite && availableWidth >= 0);
    assert(horizontalPadding.isFinite && horizontalPadding >= 0);
    assert(maxCrossAxisExtent.isFinite && maxCrossAxisExtent > 0);
    assert(crossAxisSpacing.isFinite && crossAxisSpacing >= 0);

    final usable = math.max(0.0, availableWidth - horizontalPadding);
    final rawCount =
        ((usable + crossAxisSpacing - layoutTolerance) /
                (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    final columns = math.max(1, rawCount);
    final itemWidth = math.max(
      0.0,
      (usable - crossAxisSpacing * (columns - 1)) / columns,
    );
    return AdaptiveGridGeometry._(
      crossAxisCount: columns,
      itemCrossAxisExtent: itemWidth,
    );
  }
}
```

- [ ] **Step 5: 实现惰性网格组件**

Create `lib/core/widgets/adaptive_grid/app_adaptive_grid.dart`，接口固定为：

```dart
import 'package:flutter/material.dart';

import 'adaptive_grid_geometry.dart';

typedef AppAdaptiveGridMainAxisExtentBuilder =
    double Function(BuildContext context, double itemCrossAxisExtent);
typedef AppAdaptiveGridItemBuilder =
    Widget Function(
      BuildContext context,
      int index,
      double itemCrossAxisExtent,
    );

class AppAdaptiveGrid extends StatelessWidget {
  const AppAdaptiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.maxCrossAxisExtent,
    required this.mainAxisExtentBuilder,
    this.padding = EdgeInsets.zero,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.controller,
    this.scrollViewKey,
    this.findChildIndexCallback,
    super.key,
  });

  final int itemCount;
  final AppAdaptiveGridItemBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final AppAdaptiveGridMainAxisExtentBuilder mainAxisExtentBuilder;
  final EdgeInsetsGeometry padding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final ScrollController? controller;
  final Key? scrollViewKey;
  final ChildIndexGetter? findChildIndexCallback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final geometry = AdaptiveGridGeometry.resolve(
          availableWidth: constraints.maxWidth,
          horizontalPadding: resolvedPadding.horizontal,
          maxCrossAxisExtent: maxCrossAxisExtent,
          crossAxisSpacing: crossAxisSpacing,
        );
        final mainAxisExtent = mainAxisExtentBuilder(
          context,
          geometry.itemCrossAxisExtent,
        );
        assert(mainAxisExtent.isFinite && mainAxisExtent >= 0);
        return GridView.builder(
          key: scrollViewKey,
          controller: controller,
          padding: resolvedPadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: geometry.crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: itemCount,
          findChildIndexCallback: findChildIndexCallback,
          itemBuilder: (context, index) => itemBuilder(
            context,
            index,
            geometry.itemCrossAxisExtent,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 6: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/core/widgets/adaptive_grid test/core/widgets/adaptive_grid
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/widgets/adaptive_grid --reporter compact 2>&1 | Out-File -Encoding utf8 logs/adaptive-grid-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/adaptive-grid-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 提交通用网格**

Run:

```powershell
git add lib/core/widgets/adaptive_grid test/core/widgets/adaptive_grid
dart format --output=none --set-exit-if-changed lib/core/widgets/adaptive_grid test/core/widgets/adaptive_grid
git commit -m "feat(core): 增加自适应网格原语"
```

### Task 3: 增加内容限宽与自适应 actions，并接入 AppShell

**Files:**
- Create: `lib/core/widgets/app_constrained_content.dart`
- Create: `lib/core/widgets/app_adaptive_actions.dart`
- Modify: `lib/core/widgets/adaptive_master_detail_layout.dart`
- Modify: `lib/app/shell/app_shell_scaffold.dart`
- Create: `test/core/widgets/app_constrained_content_test.dart`
- Create: `test/core/widgets/app_adaptive_actions_test.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`

**Interfaces:**
- Produces: `AppConstrainedContent({maxWidth, padding, alignment, child})`
- Produces: `AppAdaptiveActions({wideActions, compactActions, breakpoint})`
- Modifies: `AppShellScaffold.adaptiveActions`
- Preserves: existing `AppShellScaffold.actions`

- [ ] **Step 1: 写共享原语失败测试**

`test/core/widgets/app_constrained_content_test.dart` 使用 1400px 外层和内层 `LayoutBuilder`，断言 child 获得 `720` 最大宽度；使用 390px 外层与左右各 16 padding，断言 child 获得 `358`。

`test/core/widgets/app_adaptive_actions_test.dart`：

```dart
test('719 走紧凑分支，720 等号和 721 走宽侧', () {
  const actions = AppAdaptiveActions(
    compactActions: [Text('紧凑动作')],
    wideActions: [Text('宽侧动作')],
  );
  expect(actions.resolve(719).single, isA<Text>());
  expect((actions.resolve(719).single as Text).data, '紧凑动作');
  expect((actions.resolve(720).single as Text).data, '宽侧动作');
  expect((actions.resolve(721).single as Text).data, '宽侧动作');
});
```

- [ ] **Step 2: 扩充 AppShell 失败测试**

修改 `_shellRouter` / `_pumpShell` 接受 `AppAdaptiveActions? adaptiveActions`，新增测试：

```dart
testWidgets('壳层保留固定动作，并按 720 断点选择响应式动作', (tester) async {
  const adaptive = AppAdaptiveActions(
    compactActions: [Text('紧凑动作')],
    wideActions: [Text('宽侧动作')],
  );
  await _pumpShell(
    tester,
    destination: AppDestination.chat,
    size: shellBelowBoundary.size,
    actions: const [Text('固定动作')],
    adaptiveActions: adaptive,
  );
  expect(find.text('固定动作'), findsOneWidget);
  expect(find.text('紧凑动作'), findsOneWidget);
  expect(find.text('宽侧动作'), findsNothing);
});
```

再以 `shellAtBoundary.size` 重挂，断言固定动作仍存在、只显示宽侧动作。

- [ ] **Step 3: 运行失败测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/responsive-primitives-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/responsive-primitives-red.log
```

Expected: `EXIT≠0`，缺少两个新原语与 shell 参数。

- [ ] **Step 4: 实现 AppConstrainedContent 与 AppAdaptiveActions**

Create `lib/core/widgets/app_constrained_content.dart`：

```dart
import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_layout_tokens.dart';

class AppConstrainedContent extends StatelessWidget {
  const AppConstrainedContent({
    required this.child,
    this.maxWidth = AppContentWidths.readable,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
```

Create `lib/core/widgets/app_adaptive_actions.dart`：

```dart
import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_breakpoints.dart';

final class AppAdaptiveActions {
  const AppAdaptiveActions({
    required this.wideActions,
    required this.compactActions,
    this.breakpoint = AppBreakpoints.shellNavigation,
  });

  final List<Widget> wideActions;
  final List<Widget> compactActions;
  final double breakpoint;

  List<Widget> resolve(double availableWidth) =>
      availableWidth < breakpoint ? compactActions : wideActions;
}
```

- [ ] **Step 5: 修改 AppShellScaffold 合并 actions**

为构造器和字段加入：

```dart
this.adaptiveActions,
final AppAdaptiveActions? adaptiveActions;
```

在已有顶层 `LayoutBuilder` 内把 AppBar actions 改为固定顺序：固定 actions、解析后的 adaptive actions、紧凑 drawer 按钮。

```dart
actions: [
  ...?actions,
  ...?adaptiveActions?.resolve(constraints.maxWidth),
  if (isCompact && endDrawer != null) _buildDrawerButton(),
],
```

保持现有 drawer 行为；可以提取私有 `_buildDrawerButton()`，但不得改变 tooltip 与 `Scaffold.of(context).openEndDrawer`。

- [ ] **Step 6: 对齐 AdaptiveMasterDetailLayout 注释并跑 green**

仅补 doc：该组件读取父约束，`width < breakpoint` 为紧凑、等号属于宽侧；不改默认值和 widget tree。

Run:

```powershell
dart format lib/core/widgets/app_constrained_content.dart lib/core/widgets/app_adaptive_actions.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/app/shell/app_shell_scaffold_test.dart
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/responsive-primitives-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/responsive-primitives-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 提交共享布局原语**

Run:

```powershell
git add lib/core/widgets/app_constrained_content.dart lib/core/widgets/app_adaptive_actions.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/app/shell/app_shell_scaffold_test.dart
dart format --output=none --set-exit-if-changed lib/core/widgets/app_constrained_content.dart lib/core/widgets/app_adaptive_actions.dart lib/core/widgets/adaptive_master_detail_layout.dart lib/app/shell/app_shell_scaffold.dart test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/app/shell/app_shell_scaffold_test.dart
git commit -m "feat(core): 增加共享响应式布局原语"
```

### Task 4: 持久化媒体密度并绑定平台默认值

**Files:**
- Create: `lib/features/media/application/media_grid_density_controller.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Create: `test/features/media/application/media_grid_density_controller_test.dart`
- Create: `test/app/composition/media_grid_density_default_test.dart`
- Modify: `test/features/settings/application/transfer/settings_sync_facade_test.dart`

**Interfaces:**
- Produces: `mediaGridDensityStorageKey`
- Produces: `mediaGridDensityDefaultProvider`
- Produces: `mediaGridDensityWriterProvider`
- Produces: `mediaGridDensityProvider`
- Produces: `MediaGridDensityController.select(AppLayoutDensity)`

- [ ] **Step 1: 写 controller 失败测试**

Create `test/features/media/application/media_grid_density_controller_test.dart`，用 helper 创建带 `sharedPreferencesProvider`、`mediaGridDensityDefaultProvider` override 的 `ProviderContainer`。参数化覆盖：

```dart
for (final testCase in [
  ('compact', AppLayoutDensity.compact),
  ('standard', AppLayoutDensity.standard),
  ('comfortable', AppLayoutDensity.comfortable),
]) {
  test('持久化值 ${testCase.$1} 恢复为对应密度', () async {
    SharedPreferences.setMockInitialValues({
      mediaGridDensityStorageKey: testCase.$1,
    });
    final container = await boot(defaultDensity: AppLayoutDensity.standard);
    expect(container.read(mediaGridDensityProvider), testCase.$2);
  });
}
```

还必须覆盖：无值使用注入默认值；未知字符串回退默认值；`select(comfortable)` 立即更新 state 并写入 key；销毁后用同一 SharedPreferences revive 得到 `comfortable`；override writer 抛异常时 `select` Future 正常完成且 state 仍为新值。

- [ ] **Step 2: 写 composition 与导出边界失败测试**

Create `test/app/composition/media_grid_density_default_test.dart`：在 Windows 和 Android `debugDefaultTargetPlatformOverride` 下分别创建 `ProviderContainer(overrides: [sharedPreferencesProvider..., ...appCompositionOverrides(...)])`，读取 `mediaGridDensityProvider` 并断言紧凑/标准；每个 test body 结束前显式把 override 设回 `null`。

Modify `settings_sync_facade_test.dart`，新增：

```dart
test('设备本地媒体密度不进入设置同步导出', () async {
  await preferences.setString(mediaGridDensityStorageKey, 'comfortable');
  final data = facade.exportSelected(
    const SettingsSyncSelection(other: true),
  );
  final json = data.toJsonString();
  expect(json, isNot(contains(mediaGridDensityStorageKey)));
  expect(json, isNot(contains('grid_density')));
});
```

- [ ] **Step 3: 运行失败测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/application/media_grid_density_controller_test.dart test/app/composition/media_grid_density_default_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-density-state-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/media-density-state-red.log
```

Expected: `EXIT≠0`，缺少媒体密度 providers。

- [ ] **Step 4: 实现密度 controller**

Create `lib/features/media/application/media_grid_density_controller.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';
import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';

const String mediaGridDensityStorageKey = 'app.feature.media.grid_density';

typedef MediaGridDensityWriter = Future<bool> Function(
  AppLayoutDensity density,
);

final mediaGridDensityDefaultProvider = Provider<AppLayoutDensity>(
  (ref) => AppLayoutDensity.standard,
);

final mediaGridDensityWriterProvider = Provider<MediaGridDensityWriter>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return (density) => preferences.setString(
    mediaGridDensityStorageKey,
    density.name,
  );
});

final mediaGridDensityProvider =
    NotifierProvider<MediaGridDensityController, AppLayoutDensity>(
      MediaGridDensityController.new,
    );

class MediaGridDensityController extends Notifier<AppLayoutDensity> {
  @override
  AppLayoutDensity build() {
    final fallback = ref.watch(mediaGridDensityDefaultProvider);
    final raw = ref
        .watch(sharedPreferencesProvider)
        .getString(mediaGridDensityStorageKey);
    return switch (raw) {
      'compact' => AppLayoutDensity.compact,
      'standard' => AppLayoutDensity.standard,
      'comfortable' => AppLayoutDensity.comfortable,
      _ => fallback,
    };
  }

  Future<void> select(AppLayoutDensity density) async {
    state = density;
    try {
      await ref.read(mediaGridDensityWriterProvider)(density);
    } catch (_) {
      // 密度是非关键本地偏好；内存选择继续生效，写入失败不阻塞浏览。
    }
  }
}
```

- [ ] **Step 5: 在 app composition 绑定平台默认值**

在 `cross_feature_bindings.dart` 导入 Flutter foundation、`AppLayoutDensity` 和 controller。把下面 override 放入 `appCompositionOverrides()` 返回列表：

```dart
mediaGridDensityDefaultProvider.overrideWithValue(
  defaultTargetPlatform == TargetPlatform.windows
      ? AppLayoutDensity.compact
      : AppLayoutDensity.standard,
),
```

不得在 media application/presentation 新增 `defaultTargetPlatform` 或 `Platform` import。

- [ ] **Step 6: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/features/media/application/media_grid_density_controller.dart lib/app/composition/cross_feature_bindings.dart test/features/media/application/media_grid_density_controller_test.dart test/app/composition/media_grid_density_default_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/application/media_grid_density_controller_test.dart test/app/composition/media_grid_density_default_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-density-state-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/media-density-state-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 提交媒体密度状态**

Run:

```powershell
git add lib/features/media/application/media_grid_density_controller.dart lib/app/composition/cross_feature_bindings.dart test/features/media/application/media_grid_density_controller_test.dart test/app/composition/media_grid_density_default_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart
dart format --output=none --set-exit-if-changed lib/features/media/application/media_grid_density_controller.dart lib/app/composition/cross_feature_bindings.dart test/features/media/application/media_grid_density_controller_test.dart test/app/composition/media_grid_density_default_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart
git commit -m "feat(media): 持久化媒体网格密度偏好"
```

### Task 5: 定义媒体网格规格与统一行高

**Files:**
- Create: `lib/features/media/presentation/models/media_grid_layout_spec.dart`
- Create: `lib/features/media/presentation/models/media_grid_tile_metrics.dart`
- Create: `test/features/media/presentation/models/media_grid_layout_spec_test.dart`
- Create: `test/features/media/presentation/models/media_grid_tile_metrics_test.dart`

**Interfaces:**
- Produces: `MediaGridLayoutSpec.forDensity(AppLayoutDensity)`
- Produces: `MediaGridLayoutSpec.maxCrossAxisExtent/spacing/padding/tilePadding/thumbnailAspectRatio/maxTitleLines`
- Produces: `MediaGridTileMetrics.resolve({context, spec, itemWidth})`
- Produces: `MediaGridTileMetrics.thumbnailHeight/titleHeight/sizeHeight/mainAxisExtent`

- [ ] **Step 1: 写密度规格失败测试**

Create `media_grid_layout_spec_test.dart`，参数化断言：

```dart
final cases = [
  (AppLayoutDensity.compact, 160.0, 8.0, 8.0, 1),
  (AppLayoutDensity.standard, 220.0, 12.0, 12.0, 2),
  (AppLayoutDensity.comfortable, 360.0, 16.0, 16.0, 2),
];
for (final testCase in cases) {
  test('${testCase.$1.name} 映射为批准的媒体网格规格', () {
    final spec = MediaGridLayoutSpec.forDensity(testCase.$1);
    expect(spec.maxCrossAxisExtent, testCase.$2);
    expect(spec.spacing, testCase.$3);
    expect(spec.padding, EdgeInsets.all(testCase.$3));
    expect(spec.tilePadding, testCase.$4);
    expect(spec.thumbnailAspectRatio, 4 / 3);
    expect(spec.maxTitleLines, testCase.$5);
  });
}
```

- [ ] **Step 2: 写统一行高与 TextScaler 失败测试**

Create `media_grid_tile_metrics_test.dart`，通过 `Builder` 捕获 context，分别在 `TextScaler.noScaling` 与 `TextScaler.linear(2)` 下调用 resolver。断言：

```dart
expect(metrics.thumbnailHeight, closeTo(metrics.contentWidth / (4 / 3), 0.001));
expect(
  metrics.mainAxisExtent,
  closeTo(
    spec.tilePadding * 2 +
        metrics.thumbnailHeight +
        MediaGridTileMetrics.thumbnailMetadataGap +
        metrics.titleHeight +
        MediaGridTileMetrics.metadataLineGap +
        metrics.sizeHeight,
    0.001,
  ),
);
expect(scaledMetrics.mainAxisExtent, greaterThan(metrics.mainAxisExtent));
```

再对同一 context/spec/itemWidth 连续 resolve 三次，断言 `mainAxisExtent` 完全相同；`itemWidth == 0` 必须安全解析为零宽缩略图，传负数和无限值必须触发 assertion。

- [ ] **Step 3: 运行失败测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/models --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-grid-metrics-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/media-grid-metrics-red.log
```

Expected: `EXIT≠0`，缺少两个 presentation model。

- [ ] **Step 4: 实现 MediaGridLayoutSpec**

Create `media_grid_layout_spec.dart`：

```dart
import 'package:flutter/widgets.dart';

import 'package:oh_my_llm/core/constants/app_layout_density.dart';

final class MediaGridLayoutSpec {
  const MediaGridLayoutSpec({
    required this.maxCrossAxisExtent,
    required this.spacing,
    required this.padding,
    required this.tilePadding,
    required this.thumbnailAspectRatio,
    required this.maxTitleLines,
  });

  final double maxCrossAxisExtent;
  final double spacing;
  final EdgeInsets padding;
  final double tilePadding;
  final double thumbnailAspectRatio;
  final int maxTitleLines;

  static MediaGridLayoutSpec forDensity(AppLayoutDensity density) =>
      switch (density) {
        AppLayoutDensity.compact => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 160,
          spacing: 8,
          padding: EdgeInsets.all(8),
          tilePadding: 8,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 1,
        ),
        AppLayoutDensity.standard => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 220,
          spacing: 12,
          padding: EdgeInsets.all(12),
          tilePadding: 12,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 2,
        ),
        AppLayoutDensity.comfortable => const MediaGridLayoutSpec(
          maxCrossAxisExtent: 360,
          spacing: 16,
          padding: EdgeInsets.all(16),
          tilePadding: 16,
          thumbnailAspectRatio: 4 / 3,
          maxTitleLines: 2,
        ),
      };
}
```

- [ ] **Step 5: 实现 MediaGridTileMetrics**

Create `media_grid_tile_metrics.dart`，使用 `AppSpacing.xs` 作为 thumbnail/metadata gap、`AppSpacing.xxs` 作为两行 metadata gap。标题 style 使用 `bodySmall`，大小 style 使用 `labelSmall`；都必须传入当前 `TextScaler`。

```dart
final class MediaGridTileMetrics {
  const MediaGridTileMetrics({
    required this.contentWidth,
    required this.thumbnailHeight,
    required this.titleHeight,
    required this.sizeHeight,
    required this.mainAxisExtent,
  });

  static const double thumbnailMetadataGap = AppSpacing.xs;
  static const double metadataLineGap = AppSpacing.xxs;

  final double contentWidth;
  final double thumbnailHeight;
  final double titleHeight;
  final double sizeHeight;
  final double mainAxisExtent;

  static MediaGridTileMetrics resolve({
    required BuildContext context,
    required MediaGridLayoutSpec spec,
    required double itemWidth,
  }) {
    assert(itemWidth.isFinite && itemWidth >= 0);
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final titleStyle = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final sizeStyle = theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11);
    final titleLineHeight = _lineHeight(titleStyle, textScaler, direction);
    final sizeLineHeight = _lineHeight(sizeStyle, textScaler, direction);
    final contentWidth = math.max(0.0, itemWidth - spec.tilePadding * 2);
    final thumbnailHeight = contentWidth / spec.thumbnailAspectRatio;
    final titleHeight = titleLineHeight * spec.maxTitleLines;
    final mainAxisExtent =
        spec.tilePadding * 2 +
        thumbnailHeight +
        thumbnailMetadataGap +
        titleHeight +
        metadataLineGap +
        sizeLineHeight;
    return MediaGridTileMetrics(
      contentWidth: contentWidth,
      thumbnailHeight: thumbnailHeight,
      titleHeight: titleHeight,
      sizeHeight: sizeLineHeight,
      mainAxisExtent: mainAxisExtent,
    );
  }

  static double _lineHeight(
    TextStyle style,
    TextScaler textScaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: direction,
      textScaler: textScaler,
    );
    try {
      return painter.preferredLineHeight;
    } finally {
      painter.dispose();
    }
  }
}
```

文件顶部补 `dart:math as math`、Material、tokens 与相对 spec import。

- [ ] **Step 6: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/features/media/presentation/models test/features/media/presentation/models
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/models --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-grid-metrics-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 100 logs/media-grid-metrics-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 提交媒体规格**

Run:

```powershell
git add lib/features/media/presentation/models test/features/media/presentation/models
dart format --output=none --set-exit-if-changed lib/features/media/presentation/models test/features/media/presentation/models
git commit -m "feat(media): 定义媒体网格布局规格"
```

### Task 6: 将媒体浏览器迁移到自适应网格

**Files:**
- Modify: `lib/features/media/presentation/widgets/media_grid_view.dart`
- Modify: `lib/features/media/presentation/widgets/media_file_tile.dart`
- Create: `test/features/media/presentation/widgets/media_grid_view_test.dart`
- Modify: `test/features/media/presentation/media_browser_navigation_test.dart`

**Interfaces:**
- Consumes: `mediaGridDensityProvider`
- Consumes: `MediaGridLayoutSpec.forDensity`
- Consumes: `MediaGridTileMetrics.resolve`
- Consumes: `AppAdaptiveGrid`
- Preserves: `MediaGridView` public constructor and loading/error/empty behavior

- [ ] **Step 1: 写固定三列缺陷与资源 identity 的回归测试**

Create `media_grid_view_test.dart`，使用 `pumpTestApp`、`PreActivatedMediaLibrarySessionController` 和 `FakeMediaLibrary`。种子图片必须有 `hasThumbnail: true`，让 `resolveThumbnailCalls` 可观察。

覆盖四个场景：

1. 390×844、960×640、1440×900 均渲染目录/图片/视频且无异常；
2. `TextScaler.linear(2)` 下长文件名、目录和带大小文件无异常，长名称 tooltip 可找到；
3. 初帧等待缩略图 Future 完成后，把 `tester.view.physicalSize` 从 960×640 改为 1440×900 并 `pump()`，`resolveThumbnailCalls` 仍只有一个相同 request；
4. 先滚动到列表中部，再通过 controller 从 compact 切到 comfortable，当前目录状态不变，原本位于中部的命名锚点仍可达，且同一可见缩略图没有新增解析调用。

关键断言示例：

```dart
expect(library.resolveThumbnailCalls, [request]);
tester.view.physicalSize = const Size(1440, 900);
await tester.pump();
expect(library.resolveThumbnailCalls, [request]);
expect(find.byTooltip('这是一个用于验证放大文字和省略号的很长文件名.jpg'), findsOneWidget);
```

- [ ] **Step 2: 加强现有媒体视口 smoke 的可观察断言**

在 `media_browser_navigation_test.dart` 的三视口循环中保留路径栏、目录、图片、视频可达断言，并新增 `find.byType(MediaGridView)` 与 `tester.takeException()`；不得新增 `getTopLeft/getRect/getSize` 像素断言。

- [ ] **Step 3: 运行失败测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-adaptive-grid-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/media-adaptive-grid-red.log
```

Expected: `EXIT≠0`，新测试暴露固定三列/缺失 metrics 或重复资源解析契约。

- [ ] **Step 4: 把 MediaGridView 改为 ConsumerWidget**

保留 loading/error/empty 三个分支；有内容时：

```dart
final density = ref.watch(mediaGridDensityProvider);
final spec = MediaGridLayoutSpec.forDensity(density);
return AppAdaptiveGrid(
  scrollViewKey: const PageStorageKey<String>('media-grid'),
  itemCount: items.length,
  maxCrossAxisExtent: spec.maxCrossAxisExtent,
  crossAxisSpacing: spec.spacing,
  mainAxisSpacing: spec.spacing,
  padding: spec.padding,
  mainAxisExtentBuilder: (context, itemWidth) =>
      MediaGridTileMetrics.resolve(
        context: context,
        spec: spec,
        itemWidth: itemWidth,
      ).mainAxisExtent,
  findChildIndexCallback: (key) {
    if (key is! ValueKey<String>) return null;
    final index = items.indexWhere((item) => item.relativePath == key.value);
    return index < 0 ? null : index;
  },
  itemBuilder: (context, index, itemWidth) {
    final item = items[index];
    final metrics = MediaGridTileMetrics.resolve(
      context: context,
      spec: spec,
      itemWidth: itemWidth,
    );
    return MediaFileTile(
      key: ValueKey<String>(item.relativePath),
      item: item,
      layoutSpec: spec,
      metrics: metrics,
      onTap: () => onItemTap(item),
    );
  },
);
```

错误/空状态间距可以把已触及的 `8` 替换为 `AppSpacing.xs`；不得顺带迁移其他页面。

- [ ] **Step 5: 让 MediaFileTile 消费固定 metrics**

构造器新增：

```dart
required this.layoutSpec,
required this.metrics,
final MediaGridLayoutSpec layoutSpec;
final MediaGridTileMetrics metrics;
```

Card 必须 `margin: EdgeInsets.zero`。内部 Column 不再用 `Expanded`，改为：

```dart
Padding(
  padding: EdgeInsets.all(layoutSpec.tilePadding),
  child: Column(
    children: [
      SizedBox(
        width: double.infinity,
        height: metrics.thumbnailHeight,
        child: _buildThumbnail(context, ref, theme),
      ),
      const SizedBox(height: MediaGridTileMetrics.thumbnailMetadataGap),
      SizedBox(
        height: metrics.titleHeight,
        child: Tooltip(
          message: item.name,
          child: Text(
            item.name,
            maxLines: layoutSpec.maxTitleLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
      const SizedBox(height: MediaGridTileMetrics.metadataLineGap),
      SizedBox(
        height: metrics.sizeHeight,
        child: item.formattedSize.isEmpty
            ? const SizedBox.shrink()
            : Text(
                item.formattedSize,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    ],
  ),
)
```

保持现有 `MediaThumbnailRequest` 字段、错误回退图标与 `MediaImageResourceView`；不得清除 provider/image cache。

- [ ] **Step 6: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/features/media/presentation/widgets/media_grid_view.dart lib/features/media/presentation/widgets/media_file_tile.dart test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/media_browser_navigation_test.dart
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-adaptive-grid-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/media-adaptive-grid-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 运行全部媒体 presentation 定向回归**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-presentation-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 120 logs/media-presentation-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 8: 提交媒体网格迁移**

Run:

```powershell
git add lib/features/media/presentation/widgets/media_grid_view.dart lib/features/media/presentation/widgets/media_file_tile.dart test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/media_browser_navigation_test.dart
dart format --output=none --set-exit-if-changed lib/features/media/presentation/widgets/media_grid_view.dart lib/features/media/presentation/widgets/media_file_tile.dart test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/media_browser_navigation_test.dart
git commit -m "fix(media): 让媒体网格适配可用空间"
```

### Task 7: 增加媒体密度 actions 并完成 app composition

**Files:**
- Create: `lib/features/media/presentation/widgets/media_grid_density_actions.dart`
- Create: `test/features/media/presentation/widgets/media_grid_density_actions_test.dart`
- Modify: `lib/app/composition/sync_workspace_screen.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart`

**Interfaces:**
- Produces: `MediaGridDensityActions.expanded()`
- Produces: `MediaGridDensityActions.menu()`
- Consumes: `AppAdaptiveActions`
- Preserves: existing `ShuffleAppBarActions` and media session lifecycle

- [ ] **Step 1: 写 actions 失败测试**

Create `media_grid_density_actions_test.dart`，在 ProviderScope 中注入 SharedPreferences 并分别挂载两个 named constructor：

- expanded 显示 tooltip `紧凑密度`、`标准密度`、`舒适密度`；当前密度 IconButton 的 Semantics 具有 selected；
- 点击 `舒适密度` 后 provider 与 SharedPreferences 都变为 comfortable；
- menu 只显示 tooltip `显示密度`，点击后出现三个 `CheckedPopupMenuItem`；选择 `标准` 后 provider 与持久化值更新；
- 用 Tab/Enter 驱动 expanded 的按钮一次，证明键盘等价操作可达；不额外包重复 Semantics。

核心交互：

```dart
await tester.tap(find.byTooltip('舒适密度'));
await tester.pump();
expect(container.read(mediaGridDensityProvider), AppLayoutDensity.comfortable);
expect(
  preferences.getString(mediaGridDensityStorageKey),
  'comfortable',
);
```

- [ ] **Step 2: 写 SyncWorkspace 组合失败测试**

在 responsive cases 增加：

- 390×844 Android 活动媒体会话只显示 `显示密度` 菜单，不显示三个展开 tooltip；
- 960×640 Windows 活动媒体会话显示三个展开 tooltip，不显示 `显示密度` 菜单。

在 render cases 使用 `RecordingMediaBrowserController`：进入媒体 Tab 后种子路径 `/相册`，记录 `factory.openedSources.length`、`initCount` 与 currentPath；点击另一个密度后断言三者分别仍为 `1`、`1`、`/相册`。

- [ ] **Step 3: 运行失败测试并保存 red 证据**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/widgets/media_grid_density_actions_test.dart test/app/composition/sync_workspace_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-density-actions-red.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/media-density-actions-red.log
```

Expected: `EXIT≠0`，缺少 actions 与 shell composition。

- [ ] **Step 4: 实现展开和菜单两种 actions**

Create `media_grid_density_actions.dart`：

```dart
enum _MediaGridDensityActionsMode { expanded, menu }

class MediaGridDensityActions extends ConsumerWidget {
  const MediaGridDensityActions.expanded({super.key})
      : _mode = _MediaGridDensityActionsMode.expanded;
  const MediaGridDensityActions.menu({super.key})
      : _mode = _MediaGridDensityActionsMode.menu;

  final _MediaGridDensityActionsMode _mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(mediaGridDensityProvider);
    final controller = ref.read(mediaGridDensityProvider.notifier);
    return switch (_mode) {
      _MediaGridDensityActionsMode.expanded => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.density_small, '紧凑密度', AppLayoutDensity.compact, density, controller),
          _button(Icons.density_medium, '标准密度', AppLayoutDensity.standard, density, controller),
          _button(Icons.density_large, '舒适密度', AppLayoutDensity.comfortable, density, controller),
        ],
      ),
      _MediaGridDensityActionsMode.menu => PopupMenuButton<AppLayoutDensity>(
        tooltip: '显示密度',
        icon: const Icon(Icons.view_module_rounded),
        initialValue: density,
        onSelected: controller.select,
        itemBuilder: (context) => [
          for (final value in AppLayoutDensity.values)
            CheckedPopupMenuItem(
              value: value,
              checked: value == density,
              child: Text(_label(value)),
            ),
        ],
      ),
    };
  }
}
```

私有 `_button` 返回带 `isSelected`、`selectedIcon`、tooltip 和 `onPressed: () => controller.select(value)` 的 Material 3 `IconButton`；`_label` 穷举返回 `紧凑`、`标准`、`舒适`。所有 switch 必须穷举，不写 default。

- [ ] **Step 5: 在 SyncWorkspaceScreen 组装 adaptive actions**

保持现有固定 shuffle action：

```dart
actions: mediaSession is MediaLibrarySessionActive && mediaBrowser != null
    ? [ShuffleAppBarActions(currentDirectoryPath: mediaBrowser.currentPath)]
    : null,
adaptiveActions:
    mediaSession is MediaLibrarySessionActive && mediaBrowser != null
    ? const AppAdaptiveActions(
        wideActions: [MediaGridDensityActions.expanded()],
        compactActions: [MediaGridDensityActions.menu()],
      )
    : null,
```

`SyncWorkspaceScreen` 不直接 watch 密度 provider；actions widget 自己消费。不得改变 `_initMediaSession`、离开 Tab reset 顺序或返回键逻辑。

- [ ] **Step 6: 格式化并运行 green 测试**

Run:

```powershell
dart format lib/features/media/presentation/widgets/media_grid_density_actions.dart lib/app/composition/sync_workspace_screen.dart test/features/media/presentation/widgets/media_grid_density_actions_test.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/media/presentation/widgets/media_grid_density_actions_test.dart test/app/composition/sync_workspace_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/media-density-actions-green.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 140 logs/media-density-actions-green.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 提交密度 actions 与组合**

Run:

```powershell
git add lib/features/media/presentation/widgets/media_grid_density_actions.dart lib/app/composition/sync_workspace_screen.dart test/features/media/presentation/widgets/media_grid_density_actions_test.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart
dart format --output=none --set-exit-if-changed lib/features/media/presentation/widgets/media_grid_density_actions.dart lib/app/composition/sync_workspace_screen.dart test/features/media/presentation/widgets/media_grid_density_actions_test.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart
git commit -m "feat(media): 增加媒体网格密度切换"
```

### Task 8: 更新规范并完成全量验证

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/视频局域网广播-prd.md`
- Verify: all files changed by Tasks 1–7

**Interfaces:**
- Consumes: all previous tasks
- Produces: documented contributor constraints and final verification evidence

- [ ] **Step 1: 更新 AGENTS.md 响应式规则**

在“导航、响应式与可访问性”补充以下精确规则：

```markdown
- 响应式组件优先使用 `LayoutBuilder` 获取父级实际宽度；除 app shell 等窗口级职责外，不用整窗宽度决策，也不按 Windows/Android/手机/平板标签切换布局。
- 连续网格使用 `AppAdaptiveGrid` 与 feature-owned 规格约束项目最大宽度；不要用固定列数模拟设备适配。固定列数只有在列数本身是稳定业务契约时才能保留并解释。
- 共享间距、圆角、内容限宽与命中区域使用 `AppSpacing` / `AppRadii` / `AppContentWidths` / `AppInteractionSizes`；局部业务几何可保留，不为追求零数字机械迁移。
- 密度偏好由各 feature 独立拥有；平台只可在 app composition 提供无持久化值时的默认密度，不建立全局密度开关。
```

- [ ] **Step 2: 更新 README 与媒体 PRD**

README 的响应式能力改为“桌面/移动导航 + 父约束驱动的内容与媒体网格”；媒体浏览器段落补“紧凑/标准/舒适三档设备本地密度，Windows 默认紧凑、Android 默认标准”。

PRD 4.4 替换为：

```markdown
采用按父级可用宽度计算列数的自适应 GridView。

规则：

* 缩略图区域固定 4:3，不采用瀑布流或交错布局
* 支持紧凑、标准、舒适三档密度
* Windows 默认紧凑，Android 默认标准；用户选择保存在当前设备
* 紧凑密度文件名单行省略，标准与舒适密度最多两行省略
* 系统文字放大时整行统一增高，单个项目不能独立撑高网格行
```

- [ ] **Step 3: 格式化全部改动 Dart 文件**

Run:

```powershell
$DartFiles = git diff --name-only HEAD~7..HEAD -- '*.dart'
if ($DartFiles) { dart format $DartFiles }
```

Tasks 1–7 严格各产生一个提交，因此该范围只覆盖本计划的 Dart 改动；若执行期间插入了额外提交，先用 `git log --oneline` 定位 Task 1 的父提交，再替换范围起点，不得扩大到用户的既有改动。

- [ ] **Step 4: 运行架构门禁**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/responsive-import-boundaries.log; $CheckExit = $LASTEXITCODE; Write-Host "EXIT=$CheckExit"; Get-Content -Tail 120 logs/responsive-import-boundaries.log
```

Expected: `EXIT=0`，零 violation、零 stale allowance。

- [ ] **Step 5: 运行 flutter analyze**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/responsive-analyze.log; $AnalyzeExit = $LASTEXITCODE; Write-Host "EXIT=$AnalyzeExit"; Get-Content -Tail 150 logs/responsive-analyze.log
```

Expected: `EXIT=0`。若依赖解析阶段异常停滞，改用 `flutter analyze --no-pub` 写回同一日志；不得忽略真实 lint/error。

- [ ] **Step 6: 运行聚焦响应式与媒体套件**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/core/constants/app_layout_tokens_test.dart test/core/widgets/adaptive_grid test/core/widgets/app_constrained_content_test.dart test/core/widgets/app_adaptive_actions_test.dart test/app/shell/app_shell_scaffold_test.dart test/app/composition/media_grid_density_default_test.dart test/app/composition/sync_workspace_screen_test.dart test/features/media test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/responsive-media-focused.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/responsive-media-focused.log
```

Expected: `EXIT=0`。

- [ ] **Step 7: 运行全量测试**

Run:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

Expected: `EXIT=0`。若启动阶段无用例输出，先运行 `./scripts/kill-stale-test-processes.ps1`，再重跑同一命令。

- [ ] **Step 8: 检查禁止项与格式**

Run:

```powershell
rg -n "defaultTargetPlatform|Platform\.is" lib/features/media/application lib/features/media/presentation
rg -n "crossAxisCount:\s*3|SliverGridDelegateWithFixedCrossAxisCount" lib/features/media/presentation/widgets/media_grid_view.dart
rg -n "getTopLeft|getRect" test/core/widgets/adaptive_grid test/features/media/presentation/widgets/media_grid_view_test.dart test/features/media/presentation/widgets/media_grid_density_actions_test.dart
$StagedDart = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($StagedDart) { dart format --output=none --set-exit-if-changed $StagedDart }
```

Expected: 前三条无命中；格式检查退出 `0`。共享 `AppAdaptiveGrid` 内部允许使用 `SliverGridDelegateWithFixedCrossAxisCount`，媒体 feature 不允许。

- [ ] **Step 9: 执行或明确记录手工 smoke 状态**

Windows profile mode：960px 与 1440px 打开同一目录、实时拖窗、切换三档密度、键盘操作、重启恢复偏好；观察无临界闪烁、无持续严重卡顿、无重复缩略图解析。

Android：390×844 与 844×390 打开同一目录、菜单切换密度、系统字体放大、重启恢复偏好。

如果当前环境不能运行真实 Windows/Android UI，在交付说明逐项标记 `pending`，不得把 Widget 测试描述为手工视觉验收。

- [ ] **Step 10: 暂存文档、复查 worktree 并提交**

Run:

```powershell
git add AGENTS.md README.md docs/视频局域网广播-prd.md
git diff --cached --check
git status --short
git commit -m "docs: 记录响应式布局与媒体密度规范"
```

- [ ] **Step 11: 最终状态审计**

Run:

```powershell
git status --short
git log -8 --oneline
```

Expected: worktree 干净；日志中包含 Tasks 1–8 的独立提交；最终报告列出 red/green 日志、门禁结果和手工 smoke 完成/pending 状态。

---

## Final Acceptance Mapping

| 设计验收项 | 实施任务与证据 |
|---|---|
| 媒体不再固定三列 | Task 2 geometry + Task 6 MediaGridView 回归 |
| 宽窗增加列数且卡片不无限变大 | Task 2 容差/单调性测试 + Task 6 三视口测试 |
| 极窄宽度一列无溢出 | Task 2 零宽/窄宽测试 |
| Windows/Android 默认密度 | Task 4 composition 测试 |
| 三档切换与本地持久化 | Task 4 controller + Task 7 actions 测试 |
| 偏好不跨设备同步 | Task 4 SettingsSyncFacade JSON 断言 |
| 切换不重建会话/目录 | Task 7 SyncWorkspace render case |
| 共享网格只读父约束 | Task 2 nested-width widget test |
| tile 不读平台/持久化 | Task 6 构造参数边界 + Task 8 rg 门禁 |
| selected/tooltip/键盘/Semantics | Task 7 actions widget tests |
| 统一行高与 TextScaler | Task 5 metrics tests + Task 6 放大文字测试 |
| resize 不重复解析缩略图 | Task 6 FakeMediaLibrary 调用历史测试 |
| 架构、analyze、全量测试通过 | Task 8 logs |
| Windows/Android 视觉 smoke | Task 8 手工记录或明确 pending |
