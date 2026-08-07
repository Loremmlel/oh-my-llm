# Phase 13 - 响应式语义断点 Implementation Plan

> 对应文档：`docs/第一轮审查/Phase 13 - 响应式语义断点.md`
>
> 对应技术债：TD-29（仅核对了 `architecure-review.md` 中命中 TD-29 的第 289、459 行，未读取整份审查文档）
>
> 代码基线：`dd7ce0d`（2026-08-07，审查时 worktree clean）
>
> 前置 Phase：Phase 5、7、10、12

本计划只处理响应式布局契约与行为测试：为现有断点建立稳定语义、让直接消费者使用同一事实源、建立代表性 viewport 矩阵。默认实施结果**不改变断点数值、不重新设计 UI、不改变业务状态**。如果新测试暴露真实 overflow，只允许对触发 overflow 的 presentation 组件做最小约束修复；不得借机重做页面结构。

---

## 零、执行结论（实现时不得自行改写）

### 0.1 本 Phase 的七个确定决策

1. **全局断点按布局职责命名，不使用一个含义模糊的 `compact`。**
   - shell navigation：`720.0`；控制 `NavigationBar` 与 `NavigationRail`，以及 Chat 是否显示与 shell 同步的常驻侧栏。
   - content master-detail：`840.0`；作为通用 `AdaptiveMasterDetailLayout` 的默认单栏/双栏阈值。
   - dialog master-detail：`760.0`；供两个 Chat 主从选择对话框复用。
   - form actions：`680.0`；控制 Chat composer 的紧凑操作行/完整操作行。
   - form master-detail：`900.0`；供两个 Settings 多面板表单复用。
   - message bubble：`600.0`；控制消息气泡在窄父约束下近全宽、宽父约束下按比例限宽。

2. **所有断点保持当前比较方向。**
   - `availableWidth < breakpoint` 使用 compact/single-pane/full-width-bubble 分支。
   - `availableWidth >= breakpoint` 使用 expanded/two-pane/proportional-bubble 分支。
   - 因此精确 `600`、`680`、`720`、`760`、`840`、`900` 都属于宽侧分支；不得在迁移常量时改成 `<=`。

3. **选择 `LayoutBuilder` 还是 `MediaQuery.sizeOf` 取决于被判定的责任边界。**
   - `AppShellScaffold` 判定自己获得的全部可用宽度，使用 `LayoutBuilder.constraints.maxWidth`。
   - `AdaptiveMasterDetailLayout`、composer、bubble、Settings 卡片判定父组件实际分配宽度，使用各自 `LayoutBuilder.constraints.maxWidth`。
   - Chat 内层需要与顶层 shell 的窗口级模式完全一致；其父约束已被 `NavigationRail` 缩窄，不能拿内层 `constraints.maxWidth` 再判一次 shell，因此使用 `MediaQuery.sizeOf(context).width`，但必须通过 `AppBreakpoints.isCompactShell(context)` 统一调用。
   - 禁止使用 `MediaQuery.orientationOf`、`OrientationBuilder`、手机/平板硬件类型或平台类型决定布局。现有 Windows/Android 功能可用性判断不属于布局判断，不在本 Phase 修改。

4. **560/640 保留为组件局部语义，不塞进全局 token。**
   - `ProviderTile` 的 `640.0` 是服务商卡片长操作区的换行阈值。
   - `ProviderModelTile` 的 `560.0` 是嵌套模型卡片短操作区的换行阈值。
   - 两者接收的是不同层级、不同 padding、不同按钮长度的父约束，不得合并为同一个 `form` 断点。
   - 两个裸数分别改为类内 `static const _compactActionsBreakpoint`，并用简体中文注释解释为什么不同。

5. **相同数值但不是断点的尺寸不得替换。**
   - `DetailDisplayDialog.width = 640` 是首选 dialog 宽度，不是 ProviderTile 断点。
   - `SettingsFormDialogScaffold.width = 720` 是首选表单宽度，不是 shell 断点。
   - `FixedPromptSequenceRunnerDialog` 的 `width: 680` 是 dialog 宽度，不是 composer action 断点。
   - `FontWeight.w600` 与 viewport 无关。
   - 这些值保持原样；禁止全仓机械替换 `600/640/680/720`。

6. **viewport 测试验证用户可见行为与内容可达性。**
   - 必须覆盖宽度 `390、600、719、720、721、1024、1440`。
   - Settings 与 Sync 至少在 `390`、`600` 两个 compact viewport 跑页面行为；额外覆盖 `844×390` Android 横屏。
   - shell 测试通过可见导航组件完成一次真实 destination 切换；页面测试通过标题、标签、按钮、输入框文案、drawer 内容和正常交互证明内容可达。
   - 每次关键 pump 后检查没有 Flutter framework exception；RenderFlex overflow、unbounded constraint 会使测试失败。

7. **禁止把测试写成布局实现快照。**
   - 不新增 `getTopLeft`、`getRect`、像素距离或 widget 尺寸比较。
   - 不新增 `find.byKey`；不得复用现有 test key 来证明响应式模式。
   - 不断言 `maxLines`、`expands`、`crossAxisCount` 等 widget 私有/实现属性。
   - 不用 `findsNothing` 断言某个 widget 类型；需要区分模式时，只正向断言该模式的可见导航或可操作文案。
   - case 使用参数化循环，不能复制七份相同测试。

### 0.2 明确不采用的替代方案

| 方案 | 不采用原因 |
|---|---|
| 把所有断点统一成 720 | shell、父内容、表单操作区、bubble 接收的空间与职责不同，会制造新的布局夹缝。 |
| 把 560/640 都改为全局 form token | 两个嵌套卡片的按钮长度和父约束不同，当前差异是有意设计。 |
| 根据 Android/Windows、手机/平板或横竖屏选布局 | 可调整窗口、分屏、折叠屏下不可靠；应只看可用空间。 |
| 为通过 compact 测试提高测试视口高度 | 会隐藏低高度 overflow；必须让可滚动内容自行可达。 |
| 把固定 3 列 Media grid 改成自适应列数 | TD-29 没有要求改变媒体信息密度；这是视觉/产品行为变化。当前 Phase 只验证各 viewport 可达且无 overflow。 |
| 为每个数字创建全局常量 | 固定 dialog 宽度、padding、字体权重不是 breakpoint；会污染契约。 |
| 用 golden/pixel test 冻结布局 | 本 Phase 要冻结语义行为，不冻结像素。 |
| 顺手处理 Semantics、focus、快捷键 | 属于 Phase 14；本 Phase 只保证现有输入方式下内容可达。 |

---

## 一、前置 Phase 实现审查

### 1.1 Phase 5：Settings 工作流与持久化契约

| Phase 5 要求 | 当前证据 | 判定 |
|---|---|---|
| 导入不再接受 `dynamic ref` | `settings_import_executor.dart` 定义 `SettingsImportTargets`，executor 只依赖类型化 targets；Riverpod adapter 使用 `Ref`。 | 已满足 |
| mutation Future 等到真实 commit | `SettingsEntityController.upsert/upsertAll/deleteById` 返回 `_commit`；`_commit` 先 await repository，再发布 state。 | 已满足 |
| SettingsScreen 不直接访问 persistence/data | `settings_screen.dart` 只组合 application/domain/presentation；tab preference、transfer、catalog 均为 application workflow。 | 已满足 |
| 小设置持久化契约统一 | `SettingsKeyValueStore`、版本化 JSON store 与对应 controller/application tests 已存在。 | 已满足 |
| compact 测试可复用稳定 workflow | `pumpSettingsScreen` 可注入 viewport，页面行为不需要 presentation 直接装配 data client。 | 可作为本 Phase 基础 |

提交证据包括 `fb4ad5e`、`af6b92c`、`ffb4553`、`f675960`、`e147824`、`95e6770`、`57a83d9`。Phase 13 不修改这些 workflow、存储格式或错误语义，只在现有 `SettingsScreen` 和 presentation widgets 上增加布局契约与测试。

### 1.2 Phase 7：跨 Feature 组合边界

| Phase 7 要求 | 当前证据 | 判定 |
|---|---|---|
| Sync + Media 组合归 app | `lib/app/composition/sync_workspace_screen.dart` 拥有 Tab、Media session init/reset 与 AppShell。 | 已满足 |
| Sync 依赖显式 ports/facade | `SettingsSyncFacade`、client/server transport、media route factory 等 ports 已存在；app composition 绑定 concrete。 | 已满足 |
| media presentation 不穿透 data | `MediaBrowserTab` 依赖 application/domain/presentation，并通过 GoRouter 发起媒体导航。 | 已满足 |
| Chat/Favorites intent 有稳定 command | `ChatFavoriteIntentCommand`、facade 与 app binding 已存在。 | 已满足 |
| 页面可独立测试 | Sync screen case decomposition 与 media navigation tests 已存在，helper 接受 viewport。 | 可作为本 Phase 基础 |

Phase 13 必须继续把 Sync+Media 当作 app 组合页面测试，不能把 viewport 逻辑下沉到 Sync controller、media data 或 HTTP route。

### 1.3 Phase 10：Chat workspace 状态所有权

| Phase 10 要求 | 当前证据 | 判定 |
|---|---|---|
| workspace 状态收敛 | `ChatWorkspaceViewState.compose` 已存在，`ChatWorkspace` 只接收 `state` 与 `bindings`。 | 已满足 |
| callbacks/resource 分组 | `ChatWorkspaceBindings` 已按 messages/composer/scroll 分组。 | 已满足 |
| 页面 owner 清晰 | ChatScreen 本地持有纯页面 controllers/editing draft；会话草稿、模板选择等由 Provider owner。 | 已满足 |
| 页面卸载/重挂有行为测试 | `chat_screen_workspace_ownership_cases.dart` 覆盖草稿恢复与编辑瞬态丢弃。 | 已满足 |
| 响应式调整不需重开业务重构 | `_buildBody` 已只接收 7 个稳定参数，composer 可独立获得父约束。 | 可作为本 Phase 基础 |

提交证据包括 `4060947`、`381b379`、`0500a65`、`66bf178`、`5513a48`、`eac3559` 及后续修复。Phase 13 只能修改宽度判定与 presentation tests，不得把 view-state 拆回二十多个参数，也不得改 composer draft/command 生命周期。

### 1.4 Phase 12：可恢复导航契约

| Phase 12 要求 | 当前证据 | 判定 |
|---|---|---|
| 收藏详情使用 ID route | `/favorites/:favoriteId` 已由 `app_router.dart` 解析并传给 `FavoriteDetailScreen`。 | 已满足 |
| 收藏详情有恢复状态 | `FavoriteDetailScreen` 接受 nullable ID 并包含 recovery page。 | 已满足 |
| 媒体使用 GoRouter 子路由 | `/sync/media/image`、`/sync/media/video` 已在 `/sync` 下定义。 | 已满足 |
| MediaBrowser 不再创建平行 MaterialPageRoute | `MediaBrowserTab` 使用 `context.pushNamed`，URL 只携带相对路径。 | 已满足 |
| 路由行为有 tests | `app_router_test.dart`、`media_browser_navigation_test.dart`、`media_route_pages_test.dart` 已存在。 | 已满足 |

提交证据：`01f9b13`、`cdf300e`、`5e0e62e`。Phase 13 的 viewport tests 必须继续用生产 GoRouter/AppShell 组合；不得为了测试方便退回自建 MaterialPageRoute 或不可恢复 extra。

### 1.5 前置依赖总判定与当前验证状态

- 四个前置 Phase 的**结构与测试装具已经落地，没有发现阻塞 Phase 13 的缺口**。
- 当前响应式债务仍存在：`AppBreakpoints` 只有含糊的 `compact = 720`；840/680/600/640/560 等直接判定仍分散；Chat 用同一个 shell helper 表达 padding 等语义；Settings/Sync 的系统化 compact matrix 不存在。
- 审查期间 `flutter analyze` 在 180 秒内未返回诊断并被执行环境超时终止；这不是 green 结果，也没有观察到具体 lint。执行者必须先完成 Task 0 基线验证；不得把本次超时写成“分析通过”。
- 审查未修改代码，生成计划前后 worktree 均为 clean。

---

## 二、当前响应式实现问题清单

| 位置 | 当前行为 | 问题 | 本 Phase 处理 |
|---|---|---|---|
| `app_breakpoints.dart` | 只有 `compact = 720` 与 `isCompact(context)`。 | 名称无法说明这是 shell；容易被内容/form 误用。 | 建立明确 token 与纯宽度判定 helper，删除含糊旧名。 |
| `app_shell_scaffold.dart` | `constraints.maxWidth < AppBreakpoints.compact`。 | 数值已集中，但语义不清、边界无 719/720/721 tests。 | 使用 shell helper，参数化 boundary tests。 |
| `chat_screen.dart` | `MediaQuery.of(context).size.width >= AppBreakpoints.compact`。 | API 订阅范围大；比较方向单独书写；注释把窗口宽度称为物理宽度。 | 统一为 `AppBreakpoints.isCompactShell(context)`，更新注释，不改分支。 |
| Chat workspace/messages/composer padding | 多处 `AppBreakpoints.isCompact(context)`。 | 实际表达 shell compact，却使用泛化名。 | 全部迁移为 `isCompactShell`。 |
| `chat_composer_card.dart` | 类内 `compactComposerBreakpoint = 680`。 | 有局部命名，但 form action 语义未进入统一契约。 | 改用 `formActions` token。 |
| `chat_message_bubble.dart` | 直接 `< 600`。 | bubble 断点是裸数；无边界契约。 | 改用 bubble helper/token。 |
| `adaptive_master_detail_layout.dart` | 默认 `breakpoint = 840`。 | 通用 content 阈值是裸默认值。 | 默认值改用 content token；保留可注入 breakpoint。 |
| 两个 Chat master-detail dialogs | 分别直接传 `760`。 | 同义重复值。 | 使用同一个 dialog master-detail token。 |
| 两个 Settings master-detail forms | 各自在 build 内声明 `900.0`。 | 同义重复，生命周期内反复声明。 | 使用同一个 form master-detail token。 |
| `ProviderTile` | 直接 `< 640`。 | 局部阈值无名字。 | 类内命名为 `_compactActionsBreakpoint`。 |
| `ProviderModelTile` | 直接 `< 560`。 | 局部阈值无名字。 | 类内命名为 `_compactActionsBreakpoint`，不与父卡片统一。 |
| AppShell tests | 只有 600、1440。 | 不覆盖 720 等号语义、390、窄桌面。 | 使用共享矩阵覆盖全部必需 widths。 |
| Chat tests | 默认 1440×1600，零散 390/430/900。 | 没有统一 viewport contract。 | 新增 responsive case 文件和 composer focused test。 |
| Settings tests | 默认 1440×1500，零散 430。 | compact 不是系统矩阵；tab helper 未先 ensure visible。 | 390/600 compact 行为矩阵；增强 tab helper 可达性。 |
| Sync tests | 默认 1440×1200。 | 没有 compact/低高度 Android 横屏覆盖。 | 390/600 compact + 844×390 Android landscape。 |
| Media tests | 路由行为完整，但默认超宽。 | 未证明网格、路径栏和 route tap 在 compact/landscape 可达。 | 在现有 navigation test 参数化 viewport smoke；不改列数。 |

---

## 三、最终断点契约

### 3.1 `AppBreakpoints` 的唯一公共 API

`lib/core/constants/app_breakpoints.dart` 最终应等价于以下结构；命名和比较方向不得自行变化：

```dart
import 'package:flutter/widgets.dart';

/// 按布局职责定义的响应式断点。
final class AppBreakpoints {
  const AppBreakpoints._();

  static const double shellNavigation = 720.0;
  static const double contentMasterDetail = 840.0;
  static const double dialogMasterDetail = 760.0;
  static const double formActions = 680.0;
  static const double formMasterDetail = 900.0;
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

实现时为每个 token 写简体中文 doc comment，必须说明：它接收的是窗口宽度还是父约束、控制哪一种布局切换、等号属于哪侧。不要增加 `compact`/`isCompact` 兼容 alias；alias 会继续允许调用方表达错误语义。

`contentMasterDetail`、`dialogMasterDetail`、`formMasterDetail` 作为 `AdaptiveMasterDetailLayout.breakpoint` 参数使用，比较仍由通用 widget 统一执行。它们不需要重复增加三个仅包装 `<` 的 helper。

### 3.2 数值与等号行为表

| token | compact/single 条件 | 等号行为 | 直接消费者 |
|---|---|---|---|
| `messageBubble = 600` | `< 600` 近全宽 bubble | `600` 开始比例限宽 | `ChatMessageBubble` |
| `formActions = 680` | `< 680` compact composer row | `680` 开始 desktop settings row | `ChatComposerCard` |
| `shellNavigation = 720` | `< 720` bottom nav/endDrawer/no常驻 Chat panel | `720` 开始 rail/常驻 Chat panel | `AppShellScaffold`、`ChatScreen`、shell spacing consumers |
| `dialogMasterDetail = 760` | `< 760` Chat dialog compact child | `760` 开始 master/detail | checkpoint/filter dialogs |
| `contentMasterDetail = 840` | `< 840` 通用 single pane | `840` 开始默认 master/detail | `AdaptiveMasterDetailLayout` 默认值 |
| `formMasterDetail = 900` | `< 900` Settings form compact child + scroll | `900` 开始 master/detail | preset/sequence form dialogs |
| Provider local `640` | `< 640` 服务商信息与 actions 纵向 | `640` 开始横向 header/actions | `ProviderTile` only |
| Model local `560` | `< 560` 模型信息与 actions 纵向 | `560` 开始横向 header/actions | `ProviderModelTile` only |

### 3.3 viewport 尺寸事实源

新增 `test/helpers/responsive_viewport_cases.dart`，只放可长期复用的测试尺寸和 shell 期望，不出现 `Phase 13`、审查编号或临时计划术语。

```dart
enum ShellNavigationMode { bottomBar, rail }

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
```

共享常量必须包含：

| name | Size | shell mode | 目的 |
|---|---:|---|---|
| `phonePortrait` | `390×844` | bottomBar | 常见移动端与最窄核心场景 |
| `compactTablet` | `600×900` | bottomBar | bubble 代表值与 compact 页面 |
| `shellBelowBoundary` | `719×900` | bottomBar | 720 前一像素 |
| `shellAtBoundary` | `720×900` | rail | 等号属于宽侧 |
| `shellAboveBoundary` | `721×900` | rail | 720 后一像素 |
| `desktop` | `1024×768` | rail | 平板/窄桌面 |
| `wideDesktop` | `1440×900` | rail | 常规桌面，不再使用 1200/1600 高度掩盖滚动问题 |

另定义 `androidLandscape = Size(844, 390)`，供 Sync/Media 低高度场景使用；不并入 shell 边界循环，避免每个普通页面重复跑额外 case。

---

## 四、生产代码逐文件改动

### 4.1 Core 与 App shell

| 文件 | 精确修改 |
|---|---|
| `lib/core/constants/app_breakpoints.dart` | 用第三节 API 替换旧 `compact/isCompact`；补职责和等号 doc。 |
| `lib/core/widgets/adaptive_master_detail_layout.dart` | import `app_breakpoints.dart`；默认 `breakpoint` 改为 `AppBreakpoints.contentMasterDetail`；仍允许调用方传自定义值。 |
| `lib/app/shell/app_shell_scaffold.dart` | `constraints.maxWidth < AppBreakpoints.compact` 改为 `AppBreakpoints.useCompactShell(constraints.maxWidth)`；导航结构、destination、drawer 行为不改。 |

### 4.2 Chat presentation

| 文件 | 精确修改 |
|---|---|
| `lib/features/chat/presentation/chat_screen.dart` | 用 `!AppBreakpoints.isCompactShell(context)` 判定常驻侧栏；`MediaQuery.of(...).size.width` 不再直接出现；注释改称“窗口级宽度”，保留与 shell 同步的理由。 |
| `lib/features/chat/presentation/widgets/chat_workspace.dart` | spacing 使用 `isCompactShell`。 |
| `lib/features/chat/presentation/widgets/chat_messages_panel.dart` | list padding 使用 `isCompactShell`。 |
| `lib/features/chat/presentation/widgets/chat_composer_card.dart` | 删除 `compactComposerBreakpoint`；用 `useCompactFormActions(constraints.maxWidth)`；shell padding helper 改名。 |
| `lib/features/chat/presentation/widgets/chat_message_bubble.dart` | `< 600` 改为 `useFullWidthMessageBubble(constraints.maxWidth)`；保留原 bubbleWidth 公式和 900 max width。 |
| `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart` | `breakpoint: 760` 改为 `AppBreakpoints.dialogMasterDetail`。 |
| `lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart` | 同上。 |

不得修改 Chat domain/application、message tree、streaming、inline error、composer command 或 workspace state。

### 4.3 Settings presentation

| 文件 | 精确修改 |
|---|---|
| `lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart` | 删除 build 内 `masterDetailBreakpoint = 900.0`；`shouldScrollContent` 与 `AdaptiveMasterDetailLayout.breakpoint` 都引用 `AppBreakpoints.formMasterDetail`。 |
| `lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart` | 同上。 |
| `lib/features/settings/presentation/widgets/list/provider_tile.dart` | 在 widget/state 类的稳定作用域增加 `static const _compactActionsBreakpoint = 640.0`；LayoutBuilder 使用它；注释说明长操作标签需要更早堆叠。 |
| `lib/features/settings/presentation/widgets/list/provider_model_tile.dart` | 增加同名类内常量 `560.0`；注释说明嵌套模型 actions 更短且父 padding 不同。 |

不得修改 Settings controller、workflow、repository、导入导出格式或错误提示方式。现存 Settings SnackBar 不属于 Chat inline-error 规则，本 Phase 不清理。

### 4.4 Sync 与 Media production

默认**不修改** Sync/Media production 文件：当前 `SyncConnectionTab`/`SyncOperationTab` 已用 `ListView`，`MediaPathBar` 可横向滚动，`MediaGridView` 使用 builder，且没有报告列出的 conditional breakpoint。它们进入 File Scope 的原因是必须被 viewport matrix 验证，而不是预先改变布局。

如果新增矩阵在这些文件中稳定复现 overflow：

1. 先把失败缩成单个 focused widget test；
2. 证明错误来自约束而不是 fake/动画未完成；
3. 只在触发组件增加 `Flexible`、`Expanded`、`Wrap` 或既有滚动容器中的一种最小修复；
4. 不新增平台/方向判断，不改变媒体列数，不改变 Tab/route/state；
5. 将修复放入独立 `fix(sync)` 或 `fix(media)` commit，不夹入 token 重命名 commit。

---

## 五、测试设计

### 5.1 Breakpoint contract 与通用 master-detail

新增 `test/core/constants/app_breakpoints_test.dart`：

- 参数化 `719/720/721`，验证 `useCompactShell` 仅在 719 为 true；
- 参数化 `679/680/681`，验证 `useCompactFormActions` 仅在 679 为 true；
- 参数化 `599/600/601`，验证 `useFullWidthMessageBubble` 仅在 599 为 true；
- 不直接断言常量字段等于某值后就结束；必须调用公开分类函数，证明边界语义。

新增 `test/core/widgets/adaptive_master_detail_layout_test.dart`：

- 用默认 breakpoint 和不同父宽度挂载 widget；
- `839` 正向断言调用方提供的 `compactChild` 可见；
- `840`、`841` 正向断言 master/detail 的可见文案均可见；
- 不比较 Row/Column 类型，不比较坐标或尺寸；
- 另用 `breakpoint: AppBreakpoints.dialogMasterDetail` 做一个 759/760 的可见分支 case，证明可注入 breakpoint 仍有效。

### 5.2 AppShell viewport matrix

修改 `test/app/shell/app_shell_scaffold_test.dart`：

1. import 共享 viewport cases；
2. `_pumpShell` 继续只做 setup，不在 setup 使用 `pumpAndSettle`；初次挂载用 `pump`，真实 navigation 动画后才 `pumpAndSettle`；
3. 对七个 required viewport 循环：
   - bottomBar case 从可见 `NavigationBar` 目的地点击“历史”或“收藏”；
   - rail case 从可见 `NavigationRail` 目的地点击同一目标；
   - 最终都断言目标页面文案出现；
   - `expect(tester.takeException(), isNull)`；
4. 对 390、600、719 循环验证 endDrawer：通过 tooltip“打开侧边内容”点击并看到“侧边内容”；
5. 不增加“另一个导航 widget 不存在”的负向类型断言。

### 5.3 Chat responsive cases

新增 `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`，在 `chat_screen_test.dart` import 并调用 `registerChatScreenResponsiveTests()`。

页面矩阵：

- 七个 required viewport 均使用 `pumpChatScreen`，只 seed 默认模型/Prompt；
- 所有 case 正向断言标题、`正文` 输入标签和发送入口可达，并检查无 exception；
- 390、600、719：点击“打开侧边内容”，正向断言“历史会话”“预设 Prompt”，关闭 drawer 后正文仍可输入；
- 720、721、1024、1440：通过 activity bar 的可见 tooltip“历史会话”触发侧栏，正向断言“历史会话面板”；
- 600：正向断言 compact composer 可见文案以“更多设置”开头，并点击打开设置 sheet，看到思考/重试设置；
- 1440：正向断言完整操作区的“固定顺序提示词”和消息过滤入口可操作；
- 600 宽 seed 一组 user/assistant 消息，断言双方正文完整可见且无 overflow；不测 bubble 像素宽度。

另新增 `test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart`：

- 用最小 `ChatWorkspaceComposerState`、可释放的 `TextEditingController/FocusNode`、no-op bindings 直接挂载 `ChatComposerCard`；
- 外层 `SizedBox` 分别给 679、680、681 的父宽度；
- 679 只正向断言“更多设置”摘要可见；680/681 正向断言“固定顺序提示词”可见；
- 测试只使用可见文案，不查 `ComposerCompactActionRow`/`ComposerDesktopSettingsRow` 类型，不查 test key。

### 5.4 Settings compact matrix

新增 `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`，在入口注册。

先修改 `switchToTab` helper：

- 查找 tab 文案；
- `await tester.ensureVisible(tabFinder)`；
- tap 后只因 Tab 动画使用 `pumpAndSettle`；
- 不引入 key。

测试场景：

1. 对 390、600 循环，挂载默认 provider/model seed；依次切换六个 tab，并分别正向断言：
   - 服务商：`服务商设置`、`新增服务商`；
   - 预设：`预设 Prompt`；
   - 提示词：`记忆总结提示词`、`模板提示词`、`固定顺序提示词`；
   - 网络：`请求头定义`；
   - 输出处理：`输出正则处理`；
   - 其它：`自动重试`；
   - 每次切换后无 exception。
2. 390 宽打开“新增服务商”，使用表单 label 填入最小合法值、滚动到“保存”并取消/保存一个由现有测试已覆盖的最小路径，证明 dialog 内容可达；不重复测试业务校验树。
3. 600 宽打开“新增预设 Prompt”，正向断言 compact form 的列表/详情关键文案和保存/取消入口可达；不通过内部 pane key 判断单栏。
4. 1024、1440 只做一次服务商页 smoke 与无 exception，避免把所有六 tab 在桌面重复七遍。

### 5.5 Sync 与 Media matrix

新增 `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`，在入口注册：

- 390、600：标题“局域网同步”、连接/同步 tabs、客户端/服务端模式入口可见；切换同步 tab 后“请先在「连接」标签页中连接到服务端”可见；列表可滚动且无 exception。
- 719/720/721：只做 shell boundary + 当前 tab 关键内容 smoke，避免重复 Sync 业务测试。
- 844×390 Android：设置 `debugDefaultTargetPlatformOverride = TargetPlatform.android` 并在 tearDown 恢复；注入 connected client 和 recording media controller；进入“媒体”，正向断言路径/空目录或 seeded 文件内容可见且无 exception；离开 media 后既有 reset contract 仍通过。
- 不通过平台判断布局；Android override 只用于让产品已有的 media tab 出现。

扩展 `test/features/media/presentation/media_browser_navigation_test.dart`：

- 增加参数化 smoke：390×844、600×900、844×390、1024×768、1440×900；
- seed 一个目录、一个图片、一个视频；正向断言路径栏和三个 item 文案可达；
- 在 390 与 844×390 各执行一次图片或视频 route push/back，证明 compact/低高度不影响 Phase 12 route contract；
- 不断言列数、tile 尺寸或坐标，不修改 production grid delegate。

### 5.6 测试异常与 setup 规则

- `pumpTestApp`/feature helper 已在 setup 内执行 `pump`；新测试不得再用 `pumpAndSettle` 作为初始化惯例。
- 只有 drawer、tab、dialog、route 等真实动画后使用 `pumpAndSettle(const Duration(milliseconds: 250))`。
- 每个参数化 iteration 必须执行到至少一个业务 `expect` 和一个 `tester.takeException()` 检查；禁止 conditional early return。
- 如果 `takeException()` 得到异常，测试应直接失败并输出原异常；不得只匹配/吞掉 RenderFlex 文案。

---

## 六、文件改动清单

### 6.1 修改生产文件

- `lib/core/constants/app_breakpoints.dart`
- `lib/core/widgets/adaptive_master_detail_layout.dart`
- `lib/app/shell/app_shell_scaffold.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `lib/features/chat/presentation/widgets/chat_workspace.dart`
- `lib/features/chat/presentation/widgets/chat_messages_panel.dart`
- `lib/features/chat/presentation/widgets/chat_composer_card.dart`
- `lib/features/chat/presentation/widgets/chat_message_bubble.dart`
- `lib/features/chat/presentation/widgets/dialogs/conversation_checkpoints_dialog.dart`
- `lib/features/chat/presentation/widgets/dialogs/message_request_filter_dialog.dart`
- `lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart`
- `lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart`
- `lib/features/settings/presentation/widgets/list/provider_tile.dart`
- `lib/features/settings/presentation/widgets/list/provider_model_tile.dart`

Sync/Media production 文件不在预定修改列表；只有第五节所述测试稳定失败时才允许新增最小 fix 文件，并单独提交。

### 6.2 新增测试文件

- `test/helpers/responsive_viewport_cases.dart`
- `test/core/constants/app_breakpoints_test.dart`
- `test/core/widgets/adaptive_master_detail_layout_test.dart`
- `test/features/chat/chat_screen/chat_screen_responsive_cases.dart`
- `test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart`
- `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`
- `test/features/sync/sync_screen/sync_screen_responsive_cases.dart`

### 6.3 修改测试文件

- `test/app/shell/app_shell_scaffold_test.dart`
- `test/features/chat/chat_screen_test.dart`
- `test/features/settings/settings_screen_test.dart`
- `test/features/settings/settings_screen/settings_screen_test_helpers.dart`
- `test/features/sync/sync_screen_test.dart`
- `test/features/media/presentation/media_browser_navigation_test.dart`

如果执行者发现某个清单文件无需修改，应保持未修改；不得为“对齐清单”制造无意义 diff。

---

## 七、分任务实施顺序

### Task 0：重新建立可执行基线

1. `git status --short`，记录并保护所有用户现有改动；不得 restore/stage 无关文件。
2. 运行 `flutter --version` 与 `flutter pub get`；若 Flutter 命令继续长期无输出，先排查工具链/残留进程，不开始改代码。
3. 运行前置 Phase 定向回归：

```powershell
flutter test test/features/settings/application/settings_entity_controller_test.dart test/features/settings/application/settings_import_executor_test.dart test/features/settings/application/settings_transfer_workflow_test.dart test/features/settings/application/model_catalog_workflow_test.dart test/features/settings/settings_screen_test.dart test/features/sync/application/sync_server_controller_test.dart test/features/sync/application/sync_client_controller_test.dart test/features/sync/sync_screen_test.dart test/features/chat/application/chat_workspace_view_state_test.dart test/features/chat/chat_screen_test.dart test/app/router/app_router_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase13-baseline.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase13-baseline.log
```

4. `EXIT!=0` 时从 log 定位既有失败；不得把 baseline failure 混入 breakpoint commit。若失败与环境相关，先报告；若是主干真实回归，单独定界。

### Task 1：建立语义断点 contract 并迁移消费者

#### Step 1：先写 contract 红灯测试

新增 breakpoint 与 adaptive layout tests。红灯必须来自新 API/默认 token 尚不存在，不能通过临时 skip 或放宽 expect 伪造。

```powershell
flutter test test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-contract.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-contract.log
```

#### Step 2：实现 `AppBreakpoints`

按第三节精确 API 修改常量；运行 contract tests 到 `EXIT=0`。

#### Step 3：逐类迁移，禁止机械替换

按顺序迁移：AppShell → Chat shell consumers → composer/bubble → adaptive/default dialogs/forms → Settings local thresholds。每完成一组执行 `rg` 确认没有误改固定宽度。

```powershell
rg -n "AppBreakpoints\.(compact|isCompact)" lib test
rg -n "constraints\.maxWidth\s*<\s*(560|600|640|680|720|760|840|900)(\.0)?" lib/app lib/core lib/features/chat/presentation lib/features/settings/presentation
rg -n "breakpoint:\s*(760|840|900)(\.0)?" lib/core lib/features/chat/presentation lib/features/settings/presentation
```

第一条最终必须无命中。后两条只允许无关或已被明确判定为局部值的命中；每个命中都要人工分类，不能批量 replace。

#### Step 4：定向验证与提交

```powershell
flutter test test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen_test.dart test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-contract-consumers.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-contract-consumers.log
```

格式化所有本任务 Dart 文件，暂存后再执行 staged Dart format check。提交：

```bash
git commit -m "refactor(ui): 收敛响应式语义断点"
```

### Task 2：建立共享 viewport 与 AppShell 边界矩阵

1. 新增 durable viewport helper；名称/注释不得含审查阶段编号。
2. 参数化 AppShell test，先确认 719/720/721 的当前行为。
3. drawer 与 destination navigation 均通过可见内容交互。
4. 定向测试：

```powershell
flutter test test/app/shell/app_shell_scaffold_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-shell.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-shell.log
```

5. 提交：`test(ui): 固化应用壳视口边界矩阵`。

### Task 3：补齐 Chat viewport matrix

1. 新增 case file 并注册；先跑现有 `chat_screen_test.dart` 确保 registration 有效。
2. 添加七宽度页面 smoke/interaction。
3. 添加 679/680/681 composer focused test。
4. 600 宽 seed 消息验证 bubble 内容可达，不做几何断言。
5. 定向测试：

```powershell
flutter test test/features/chat/chat_screen_test.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-chat.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-chat.log
```

6. 提交：`test(chat): 覆盖工作区响应式视口矩阵`。

### Task 4：补齐 Settings compact matrix

1. 先增强 `switchToTab` 的 `ensureVisible`，运行现有 settings screen tests，确认桌面行为不变。
2. 新增 390/600 六 tab matrix、compact dialog reachability、1024/1440 smoke。
3. 若出现 overflow，先判断是否为 `ProviderTile`/`ProviderModelTile` 的 local threshold 使用错误；不得直接提高测试宽度。
4. 定向测试：

```powershell
flutter test test/features/settings/settings_screen_test.dart test/features/settings/presentation/model_config_form_dialog_test.dart test/features/settings/presentation/output_processing_tab_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-settings.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-settings.log
```

5. 提交：`test(settings): 补齐紧凑视口行为矩阵`。

### Task 5：补齐 Sync/Media compact 与横屏矩阵

1. 新增 Sync responsive cases，注册入口。
2. 添加 390/600、719/720/721 和 844×390 Android cases。
3. 扩展 media navigation viewport smoke，保留 Phase 12 route URI/back assertions。
4. 定向测试：

```powershell
flutter test test/features/sync/sync_screen_test.dart test/features/media/presentation/media_browser_navigation_test.dart test/features/media/presentation/media_route_pages_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-responsive-sync-media.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-responsive-sync-media.log
```

5. 全绿且无 production fix 时提交：`test(sync): 补齐同步与媒体视口矩阵`。
6. 若需要 production fix，按第四节规则先单独修复并提交，再提交矩阵测试；不能把不可见的视觉重构夹入 test commit。

### Task 6：最终审计、格式与全量门禁

#### Step 1：范围与反模式审计

```powershell
rg -n "AppBreakpoints\.(compact|isCompact)" lib test
rg -n "OrientationBuilder|MediaQuery\.orientationOf|isTablet|isPhone" lib/app lib/core lib/features/chat/presentation lib/features/settings/presentation lib/features/sync/presentation lib/features/media/presentation
rg -n "getTopLeft|getRect|find\.byKey|maxLines|expands" test/core/constants/app_breakpoints_test.dart test/core/widgets/adaptive_master_detail_layout_test.dart test/app/shell/app_shell_scaffold_test.dart test/features/chat/chat_screen/chat_screen_responsive_cases.dart test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart test/features/sync/sync_screen/sync_screen_responsive_cases.dart test/features/media/presentation/media_browser_navigation_test.dart
```

- 第一条必须无命中。
- 第二条必须没有新布局判定命中；现有功能可用性平台判断不在此 regex。
- 第三条在新增 responsive tests 中必须无命中。若现有 media test 的旧代码命中，不能用它作为新响应式断言；本 Phase 不要求无关清理。

#### Step 2：格式化与 staged 复检

```powershell
git diff --name-only -- '*.dart'
dart format <本 Phase 改动的全部 Dart 文件>
git add <当前独立任务的显式文件列表>
dart format --output=none --set-exit-if-changed <已暂存的 Dart 文件列表>
git diff --cached --check
```

不得使用 `git add .`，不得把 `fltest*.log` 或无关用户改动加入提交。

#### Step 3：架构与静态分析

```powershell
dart run tool/architecture/import_boundary_checker.dart
flutter analyze
```

两条都必须成功；analyze 超时不能记为通过，应先处理工具链后重跑。

#### Step 4：强制格式全量测试

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

只有 `EXIT=0` 才完成。失败详情从 `fltest.log` 查询，不得直接重跑无重定向全量测试。

---

## 八、行为测试矩阵

### 8.1 AppShell

| viewport | 预期导航 | endDrawer | 关键行为 |
|---:|---|---|---|
| 390×844 | bottom bar | 可打开 | destination tap 可达 |
| 600×900 | bottom bar | 可打开 | destination tap 可达 |
| 719×900 | bottom bar | 可打开 | 720 前一像素仍 compact |
| 720×900 | rail | 不以 drawer 作为入口 | 等号进入宽侧，destination tap 可达 |
| 721×900 | rail | 同上 | boundary 后稳定 |
| 1024×768 | rail | 同上 | 窄桌面 |
| 1440×900 | rail | 同上 | 宽桌面 |

### 8.2 Chat

| 场景 | 输入 | 可观察结果 |
|---|---|---|
| compact shell | 390/600/719 | drawer 可打开；历史/预设可达；正文可输入 |
| exact shell boundary | 720 | activity bar/常驻 panel 可操作；正文仍可达；无 overflow |
| wide shell | 721/1024/1440 | 常驻 workspace 与 navigation 正常 |
| compact form actions | parent 679 | “更多设置”摘要与 sheet 可操作 |
| expanded form actions | parent 680/681 | 完整设置操作文案可见 |
| bubble representative | 600 页面宽 + seeded messages | user/assistant 内容可见，无 overflow |
| wide composer | 1440 | 固定顺序/过滤入口可操作 |

### 8.3 Settings

| 场景 | viewport | 可观察结果 |
|---|---:|---|
| 六 tab 导航 | 390/600 | 每个 tab 关键 heading 可达，无 overflow |
| provider form | 390 | 字段、保存/取消可滚动到达 |
| preset form | 600 | compact master/detail 内容均可达 |
| desktop smoke | 1024/1440 | provider 内容与 actions 可达 |
| nested provider/model cards | compact + desktop seed | 信息/actions 均可达；不测坐标 |

### 8.4 Sync/Media

| 场景 | viewport | 可观察结果 |
|---|---:|---|
| Sync compact | 390/600 | tabs、模式、未连接提示可达，无 overflow |
| shell boundary | 719/720/721 | 当前 tab 内容与对应 shell nav 均可用 |
| Android landscape | 844×390 | media tab 可进入/离开，内容可达，session reset 保持 |
| Media browser | 390/600/844×390/1024/1440 | path + dir/image/video 文案可达，无 overflow |
| Media routed page | compact/landscape tap | push/back 与 URI contract 保持 |

---

## 九、提交序列与回滚

| 顺序 | Commit | 独立价值 | 回滚影响 |
|---|---|---|---|
| 1 | `refactor(ui): 收敛响应式语义断点` | 单一 token 事实源与无歧义命名；数值/行为不变。 | 回退只恢复旧名字/裸数。 |
| 2 | `test(ui): 固化应用壳视口边界矩阵` | 719/720/721 与代表性 viewport 成为 shell contract。 | 不影响 feature tests。 |
| 3 | `test(chat): 覆盖工作区响应式视口矩阵` | Chat drawer/panel/form/bubble 在各尺寸有行为保护。 | 不影响 Settings/Sync。 |
| 4 | `test(settings): 补齐紧凑视口行为矩阵` | Settings compact tabs/forms/cards 有覆盖。 | 不影响 Sync/Media。 |
| 5 | `test(sync): 补齐同步与媒体视口矩阵` | Sync compact 与 Android landscape/Media route 有覆盖。 | 不影响其他 feature。 |
| 额外（仅测试稳定失败） | `fix(sync): ...` / `fix(media): ...` | 最小 overflow 修复。 | 独立回滚，不回退 token contract。 |

每次 commit 会触发 post-commit version bump；不要手工预改 `pubspec.yaml`。提交使用 Bash；多段消息用多个 `-m`，不得使用 PowerShell here-string。

回滚原则：

- token refactor 与各 feature matrix 可分别回滚；
- 不得为了回滚测试恢复魔法数后再保留测试对新 contract 的假依赖；
- 若某 viewport 暴露真实 overflow，不能通过删除该 case、提高高度或改成 `skip` 回滚问题；应整体回滚对应生产 fix 或重新定界。

---

## 十、风险、停止条件与严格 Out of Scope

### 10.1 主要风险与控制

| 风险 | 控制 |
|---|---|
| 机械替换误改 dialog 宽度/FontWeight | 只迁移明确比较表达式与 breakpoint 参数；逐命中人工分类。 |
| 720 等号行为意外改变 | 纯 contract test + AppShell 719/720/721 behavior test。 |
| inner LayoutBuilder 错把剩余宽度当窗口宽度 | shell 用窗口/顶层约束；组件内部用父约束；在 doc 中写清。 |
| 560/640 被错误合并 | 保留类内常量与原因注释；Settings compact/desktop seed 验证可达。 |
| 测试依赖坐标而脆弱 | 只用可见文字、tooltip、实际 tap、route 与无 exception。 |
| 过多矩阵拖慢全量测试 | shell 跑完整七宽度；feature 按职责复用子集；所有重复结构用循环。 |
| 低高度动画导致 settle 慢 | setup 用 pump；只在真实动画后 settle；不加入微秒级延迟。 |
| Media grid 视觉被顺手重做 | 明确固定列数不在 scope，只测 reachability。 |
| 新常量名过于抽象 | 名称包含 layout responsibility，不使用 `small/medium/large` 或单一 `compact`。 |

### 10.2 必须停止并请求重新定界的情况

1. 需要移动现有断点数值才能让测试通过；本 Phase 默认只命名并冻结现有行为，移动阈值属于产品行为变化。
2. 720/721 出现无法用现有 compact/expanded 分支解释的内容不可达，且修复需要改变 Chat/AppShell 信息架构或增加新的 drawer/navigation 模式。
3. Settings/Sync compact failure 的根因位于 controller、持久化、协议或路由状态，而不是 presentation constraints。
4. Media responsive 改进需要改变列数、tile 设计、缩略图协议或 playback UI。
5. 需要新增 orientation lock、平台布局分支或硬件类型识别。
6. 需要使用 internal key、像素坐标或 widget 私有属性才能证明目标；应重新选择可观察行为，而不是放宽测试规范。
7. baseline 定向 tests 在任何 Phase 13 改动前已经失败；先报告既有失败，不把无关修复夹入本 Phase。

### 10.3 严格 Out of Scope

- 不修改 Chat Controller、generation、消息树、Prompt 顺序、reasoning/content、streaming 节流或 inline error；
- 不修改 Settings workflow、repository、SharedPreferences/SQLite、导入导出或 model catalog；
- 不修改 Sync protocol、pairing、crypto、transport、media HTTP handlers 或资源生命周期；
- 不修改 Favorites/History 业务或 Phase 12 route matrix；
- 不迁移 StatefulShellRoute，不增加 destination；
- 不重新设计主题、间距体系、字体、卡片、导航信息架构或 Media grid 列数；
- 不处理 Semantics、focus traversal、键盘快捷键；属于 Phase 14；
- 不做 device/release smoke；属于 Phase 16；
- 不清理与响应式矩阵无关的存量测试反模式、test key 或 SnackBar。

---

## 十一、完成定义（Definition of Done）

- [ ] `AppBreakpoints` 不再暴露含糊的 `compact/isCompact`；shell/content/dialog/form/bubble 语义和等号行为有 doc。
- [ ] `AppShellScaffold`、Chat shell consumers、composer、bubble、通用 master-detail 和重复 dialog/form breakpoints 均使用正确 token。
- [ ] ProviderTile 640 与 ProviderModelTile 560 已命名为局部阈值且未被错误统一。
- [ ] 固定 dialog widths、FontWeight 与其他非 breakpoint 数值未被机械替换。
- [ ] breakpoint public classification tests 覆盖 599/600/601、679/680/681、719/720/721。
- [ ] AdaptiveMasterDetailLayout 默认 839/840/841 分支有稳定可见行为测试。
- [ ] 共享 viewport matrix 包含 390、600、719、720、721、1024、1440；AppShell 全矩阵通过。
- [ ] Chat responsive cases 覆盖 compact drawer、exact shell boundary、wide workspace、composer 两分支和 seeded bubble 内容可达。
- [ ] Settings 在 390/600 下六个 tab 与代表性 form 可达；1024/1440 smoke 通过。
- [ ] Sync 在 390/600 下可达；719/720/721 shell boundary 通过；844×390 Android media case 通过。
- [ ] Media browser 在 compact、landscape、desktop 下内容与 Phase 12 push/back contract 可达；列数未改变。
- [ ] 新测试没有 `getTopLeft`、`getRect`、内部 key、widget 私有属性或像素断言，没有 conditional early return。
- [ ] 新生产代码没有 orientation/device-type layout branch，没有 presentation → data/persistence 新依赖。
- [ ] 本 Phase 所有 Dart 文件已格式化，暂存后 format check 与 `git diff --cached --check` 通过。
- [ ] architecture import checker 与 `flutter analyze` 通过。
- [ ] 全量测试按强制重定向命令运行并得到 `EXIT=0`。
- [ ] 每个 commit 只包含对应任务文件和 hook 自动产生的版本变化，可独立回滚。
