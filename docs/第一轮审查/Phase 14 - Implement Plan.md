# Phase 14 - 关键交互可访问性 Implementation Plan

> 对应文档：`docs/第一轮审查/Phase 14 - 关键交互可访问性.md`
>
> 对应技术债：TD-30（Phase 文档上下文完整且无不可消解矛盾，本计划未回查 Architecture Review Report）
>
> 代码基线：`80b9105`（2026-08-07）
>
> 前置 Phase：Phase 10、12、13

本计划只为关键自绘交互建立可验证的 Semantics、焦点、键盘和动态状态反馈契约。实现后不得改变视频播放、通知队列、消息定位、目录导航、Chat 开关或推理面板的业务结果；不得启用全量 localization，不做全应用 a11y 审计，不把 Phase 16 的设备 smoke 或 Phase 15 的存量测试治理提前并入本 Phase。

---

## 零、执行结论（实现时不得自行改写）

### 0.1 本 Phase 的十个确定决策

1. **采用显式 Semantics 作为外部契约，不依赖图标、颜色、文本拼接或 Flutter 的偶然自动推断。**
   - 自绘操作必须声明可理解的 `label`、role/action 和适用的 `enabled`、`selected`、`toggled`、`expanded`、`liveRegion` 状态。
   - 可见图标、重复状态文本和装饰进度必须从语义树排除，避免同一信息播报两次。
   - 子操作仍需独立可达时使用 `explicitChildNodes` 或仅排除装饰子树，不得用一个 `excludeSemantics: true` 把操作按钮一起吞掉。

2. **视频页面的键盘快捷键只在“播放表面自身拥有主焦点”时生效。**
   - `Enter`：显示/隐藏控制栏，对应播放表面的语义激活动作。
   - `Space`：播放、暂停或播放结束后重播。
   - `ArrowLeft` / `ArrowRight`：相对快退/快进 15 秒，沿用现有 clamp、中心提示和控制栏恢复逻辑。
   - `Escape`：返回上一页，沿用现有 `onBackPressed`。
   - 当返回按钮、倍速菜单、音量按钮、播放按钮、进度 Slider、弹窗或菜单项拥有焦点时，播放表面必须返回 `KeyEventResult.ignored`，不能截获 Space、方向键或 Escape 的平台默认行为。

3. **视频控制栏隐藏时必须同时退出指针、焦点和语义树。**
   - 保留现有 `AnimatedOpacity` 视觉动画和三秒自动隐藏规则。
   - 在现有 `IgnorePointer` 外补 `ExcludeFocus` 与 `ExcludeSemantics`，隐藏控制不得继续被 Tab 或屏幕阅读器访问。
   - 控制栏内存在键盘焦点时暂停自动隐藏计时；焦点离开后恢复原计时。
   - 如果用户用指针在某个控制仍聚焦时手动隐藏控制栏，下一帧把焦点恢复到播放表面，禁止留下不可见焦点。

4. **视频动态播报只覆盖离散结果，不直播高频进度。**
   - 快进、快退、临时三倍速使用单一 live region；文案分别为“已快进 15 秒”“已快退 15 秒”“临时三倍速播放”。
   - 水平拖动的 seek 预览可提供当前目标位置语义，但不标记 live region。
   - 播放位置、缓冲百分比和播放器 listener 的每帧更新不得成为 live region；否则会持续打断用户。
   - 暂停中央图标不单独播报，播放表面状态和播放按钮已经表达同一事实。

5. **通知气泡使用状态型 live region，不调用命令式 `SemanticsService.announce`。**
   - 每条入场通知只产生一个状态节点：`信息通知：<message>`、`成功通知：<message>`、`警告通知：<message>` 或 `错误通知：<message>`。
   - 可选 action 和“关闭通知”仍是该状态节点下的独立按钮；通知图标和可见 message 文本不再生成重复语义。
   - 出场动画副本整体 `IgnorePointer` + `ExcludeFocus` + `ExcludeSemantics`，避免 dismiss 时再次播报或留下可点击/可聚焦的 dead action。
   - 通知出现不得抢焦点；action 与关闭按钮按视觉顺序参与 Tab。不得改变最多三条、队列顺序、自动消失时长或 action 执行后关闭的现有规则。

6. **消息锚点的语义不依赖展开预览是否可见。**
   - 每项固定使用 `label: 第 N 条用户消息：<preview>`；预览为空时只使用“第 N 条用户消息”。
   - 使用 `value: N / 总数`、`button: true`、`selected: isActive` 和显式 tap action。
   - 当前高亮变化不是 live region，避免滚动消息列表时连续播报。
   - 键盘焦点进入锚点条时自动展开，焦点在条内移动或父级更新 active ID 时保持展开，焦点完全离开后折叠；鼠标 hover、长按和点击定位行为不变。

7. **盘点后只额外纳入三个满足“关键路径 + 自绘/状态语义缺口 + 可局部修复”条件的控件。**
   - `MediaPathBar`：当前 `_PathChip` 是裸 `GestureDetector`，目录回退是媒体浏览核心路径，但完全不能 Tab/键盘激活；纳入。
   - `ComposerPillToggle`：深度思考与自动重试仅靠颜色表达开关状态，必须暴露 `toggled` 与 disabled；纳入。
   - `ReasoningPanel`：展开/收起是 Chat/Favorites 中读取推理内容的关键状态操作，必须暴露 `expanded`；纳入。
   - 除这三项外，不再扩展生产文件范围。

8. **不修改全局 Theme 或 app 级 Shortcuts。**
   - 焦点可见性在上述自绘控件局部实现：播放表面使用明确边框，InkWell/按钮使用局部 focus overlay。
   - 不在 `AppTheme` 注入全局 `focusColor`，不在 `MaterialApp` 注册全局快捷键，避免影响普通 Material 控件和文本输入。

9. **测试只验证用户可观察的语义、焦点和行为。**
   - 使用 `tester.ensureSemantics()`、`find.semantics.byLabel(...)`、`containsSemantics(...)` 和 `tester.semantics.tap(...)`/increase/decrease 验证语义契约。
   - 使用 Tab、Shift+Tab、Enter、Space、Escape、方向键和公开回调/播放器 fake 记录验证键盘行为。
   - 不新增 `find.byKey`、`find.byType(InkWell)`、`getRect`、`getTopLeft`、像素坐标、私有 FocusNode/debugLabel 或整棵 semantics dump 快照断言。
   - 既有测试中的存量实现细节断言留给 Phase 15；本 Phase 不借机全量改写。

10. **compact 与 desktop 使用 Phase 13 已落地的共享 viewport 事实源。**
    - 复用 `test/helpers/responsive_viewport_cases.dart` 的 `phonePortrait.size`（390×844）和 `wideDesktop.size`（1440×900）。
    - 不新增另一套 a11y viewport 常量，不重新讨论断点，不修改 Phase 13 的布局数值。

### 0.2 明确不采用的替代方案

| 方案 | 不采用原因 |
|---|---|
| 给所有 Material 按钮再包一层 Semantics | 会产生重复 label/action；普通 `IconButton`、`TextButton`、`Slider` 只补缺失 tooltip/formatter，不重复声明已有 role。 |
| 用 `SemanticsService.announce` 播报每条通知和每次视频状态更新 | 命令式播报易与 live region、平台控件播报重复，且高频位置更新会造成噪声。 |
| 在 `MaterialApp` 注册 Space/方向键全局快捷键 | 会抢占 Chat 输入、Slider、PopupMenu 和对话框的键盘行为。 |
| 控制栏透明时只保留 `IgnorePointer` | 透明控件仍可能留在焦点/语义树，造成不可见焦点和幽灵播报。 |
| 通知出现后自动把焦点移到通知 | 会打断正在输入或操作的用户；动态状态应用 live region，焦点保持原处。 |
| 通知获得焦点时暂停/重算 provider 自动消失计时 | 会改变通知生命周期业务规则；本 Phase 只保证不抢焦点、按钮可达、退出副本立即失去交互，以及移除后可继续遍历。 |
| 为视频所有手势设计大量新快捷键 | 只提供与现有核心操作直接等价且不冲突的五个按键；不新增音量、倍速、全屏等产品行为。 |
| 把图片浏览器双击缩放、所有 InkWell、所有图标按钮一并治理 | 超出报告点名和“关键路径最小盘点”边界；辅助缩放与普通 Material 控件不在本 Phase。 |
| 新增 ARB、`flutter_localizations`、`intl` 或翻译现有中文 | Phase 明确未触发全量 l10n；本次语义文案沿用当前中文产品语言。 |
| 用 golden/截图证明焦点环 | 本 Phase 冻结可达行为与语义，不冻结像素；焦点操作结果、语义 focused 状态和回调足以形成稳定契约。 |

---

## 一、前置依赖与当前基线

### 1.1 前置 Phase 核对

| 前置 Phase | 当前证据 | 对 Phase 14 的约束 |
|---|---|---|
| Phase 10：Chat workspace 状态所有权 | `ChatWorkspaceViewState`、`ChatWorkspaceBindings` 和页面级 FocusNode 所有权已经稳定；锚点 rail 由 `ChatMessagesPanel` 组合。 | 只修改 presentation 控件语义与局部焦点，不把焦点/展开状态搬进 controller/provider。 |
| Phase 12：可恢复导航契约 | Favorites 与 Media 已使用生产 GoRouter/route page；视频、图片返回路径已被路由测试保护。 | 视频 `Escape` 和返回按钮只能调用现有 back callback；不得新增平行 route 或改变 URL。 |
| Phase 13：响应式语义断点 | `AppBreakpoints` 已按职责拆分，`responsive_viewport_cases.dart` 已包含 390×844 和 1440×900。 | 本 Phase 只复用 viewport；不得改断点、布局分支或 Media grid。 |

前置依赖没有发现阻塞缺口。当前 `HEAD` 为 `80b9105`，Phase 13 的生产修改和 viewport tests 已完成。

### 1.2 当前点名控件的事实

| 位置 | 当前行为 | 可访问性缺口 | 本 Phase 处理 |
|---|---|---|---|
| `video_player_page.dart` | 页面级 `GestureDetector` 处理 tap/double-tap/long-press/drag；无 Focus/键盘入口。 | 播放表面没有 role、状态、快捷键或可见焦点。 | 增加局部 Focus、按键映射、播放表面 Semantics 和焦点恢复。 |
| `video_player_gesture.dart` | 相对 seek 逻辑嵌在双击左右半屏分支。 | 键盘无法复用同一 clamp/提示路径。 | 提取单一 `seekRelative`，双击和方向键共同调用。 |
| `video_player_controls.dart` | 图标按钮无 tooltip；Slider 只暴露归一化值；缓冲与时间文本可能重复。 | 操作名称、播放状态和实际时间不清晰。 | 增加动态 tooltip/label、进度语义 formatter、装饰语义排除和离散 live status。 |
| `notification_bubble*.dart` | 视觉图标 + message + action + 无 tooltip 的 close；AnimatedList 入/出场。 | 无通知类型/liveRegion，视觉 message 可能与父语义重复，退出副本可能重复出现。 | 单一状态节点、独立子 action/close、退出排除语义、不抢焦点。 |
| `message_anchor_rail.dart` | 已有 `button`、`selected` 和序号 label；hover/长按展开。 | label 不含预览/总数，键盘焦点不会展开，父更新无条件折叠。 | 强化语义，焦点进入展开/离开折叠，保持原定位业务。 |

### 1.3 同类自绘交互盘点与边界判定

| 候选 | 判定 | 理由 |
|---|---|---|
| `lib/features/media/presentation/widgets/media_path_bar.dart` | **纳入** | `_PathChip` 是裸 `GestureDetector`；根目录与各级目录是媒体浏览核心导航，没有等价键盘路径。 |
| `lib/features/chat/presentation/widgets/composer_pill_toggle.dart` | **纳入** | 发送工作流中的深度思考/自动重试状态只靠颜色，InkWell 虽可点击但没有显式 toggled/disabled 契约。 |
| `lib/features/chat/presentation/widgets/reasoning_panel.dart` | **纳入** | Chat 与 Favorites 的推理内容入口有明确展开状态，当前只显示“展开/收起”文本，没有 expanded flag。 |
| `image_viewer_page.dart` 的双击缩放 | 排除 | 图片仍可查看、翻页和返回；缩放是辅助增强。为其定义中心缩放、加减键或屏幕阅读器动作需要额外产品决策，不是点名债务的最小修复。 |
| Favorites/History/Media file/list tiles 的 InkWell | 排除 | 均为普通 Material 交互且有可见文本；未发现自绘状态或键盘完全不可达。 |
| `number_variable_field.dart` | 排除 | 增减 InkWell 之外已有可编辑字段作为等价输入路径；不是本 Phase 点名关键控件。 |
| Chat 编辑取消 icon InkWell | 排除 | 已有 Tooltip“取消编辑”，且 InkWell 具备标准键盘激活；无隐藏状态。 |
| `AppTheme` | 排除 | 全局主题修改会波及全应用；局部控件可完成清晰焦点反馈。 |

执行者不得因为后续搜索到更多 `GestureDetector`/`InkWell` 而自行扩大清单。若新发现的控件不满足“核心路径完全不可达”或“关键状态无法表达”，记录为后续候选，不在本 Phase 实现。

### 1.4 当前测试基线

- `test/features/media/presentation/video_player_page_test.dart`：676 行，覆盖现有手势、控制栏、错误/重试、资源释放和格式化，但没有 semantics/focus/keyboard 断言。
- `test/features/chat/widgets/message_anchor_rail_test.dart`：346 行，覆盖 hover、长按、点击和父重建；现有断言大量依赖 `InkWell`/test key，属于存量测试，不在本 Phase 重写。
- 通知气泡目前没有 widget/semantics 测试；只有 Sync application test 读取 provider 数据。
- `MediaPathBar`、`ComposerPillToggle` 没有独立 widget test；`ReasoningPanel` 只有 Chat streaming case 的可见文字交互。
- 全仓当前没有 `SemanticsTester`/`ensureSemantics` 或语义 matcher 的既有范例，因此本 Phase 新测试需建立可复用的写法，但不新增抽象过度的全局 test helper。
- 计划编写期间已按强制重定向格式运行视频与锚点两个现有测试文件，共 52 个测试，结果 `EXIT=0`。
- 计划编写前 worktree 已有一个用户的未跟踪文件：`docs/第一轮审查/Phase 11 - Implement Plan.md`。实施时必须保留，禁止暂存、覆盖或清理。

---

## 二、最终 Semantics 契约

### 2.1 通用节点规则

1. 操作节点必须只有一个可理解 label 和一个 tap/adjust action；装饰 Icon/Text 用 `ExcludeSemantics`，不能让 label 被拼成“图标 + 文本 + 自定义 label”。
2. `enabled: false` 时不得保留 tap action，也不得参与普通 Tab traversal。
3. `selected`、`toggled`、`expanded` 是状态 flag，不把“已选择/已开启/已展开”硬编码到 label；平台负责按语言习惯播报 flag。
4. 非动态容器不得滥用 `liveRegion`。active anchor、播放进度、buffer、toggle 和 expanded 变化由当前焦点控件自身播报，不是全局公告。
5. 每个 live region 的 label 必须完整自足，不能依赖相邻可见文本补全。
6. 不添加 `namesRoute`、header、link 等与控件角色不符的 flag。

### 2.2 视频播放表面与状态

只有 `isInitialized && !hasError` 时，播放表面是可激活节点：

| 字段 | 精确契约 |
|---|---|
| `label` | `视频播放器：<fileName>` |
| `value`（播放中） | `正在播放，播放控件已显示` 或 `正在播放，播放控件已隐藏` |
| `value`（暂停） | `已暂停，播放控件已显示`；暂停时现有逻辑会保持控制栏可见 |
| `value`（结束） | `播放已结束，播放控件已显示` |
| `hint` | 控件可见时为 `激活以隐藏播放控件；空格键播放或暂停，左右方向键快退或快进 15 秒`；隐藏时把“隐藏”改为“显示” |
| role/action | `button: true`、`enabled: true`、显式 `onTap: handleTap` |
| focus | 可 Tab 聚焦；聚焦时播放区域边缘显示主题 primary 色的清晰焦点边框 |

加载和错误状态不伪装成可操作播放表面：

- 加载态提供单一 `label: 正在加载视频` 的进度语义，不设 live region。
- 错误态提供 `liveRegion: true`、`label: <现有 errorMessage>` 的状态节点；可见 error icon/text 排除重复语义。
- “重试”继续使用现有 `ElevatedButton` 自动语义，不另包重复 button Semantics。

### 2.3 视频控制栏

| 控件 | label/tooltip | 状态与 action |
|---|---|---|
| 返回 | `返回` | 普通 button，调用现有 `onBack`。 |
| 倍速菜单 | `播放速度，当前 <speed> 倍` | 普通 popup button；现有 0.25/0.5/0.75/1.0/1.5/2.0 选项和选中勾不变。 |
| 音量 | `音量，当前 <0..100>%` | 普通 button；打开现有音量 dialog。 |
| 播放按钮 | 播放中 `暂停`；暂停 `播放`；结束 `重新播放` | 调用现有 `togglePlayPause`。 |
| 进度 Slider | `label: 播放进度`；value 为 `<displayPosition> / <totalDuration>` | 有 duration 时保持 Slider 的 increase/decrease/tap；无 duration 时 `enabled: false`，没有 increase/decrease。 |
| 可见时间文本 | 排除语义 | 信息已由 Slider value 表达。 |
| buffer LinearProgressIndicator | 排除语义 | 高频装饰状态，不单独播报。 |

进度 Slider 的 `semanticFormatterCallback` 必须把回调收到的归一化值换算为实际 Duration，并复用 `formatVideoDuration`。拖动期间使用 drag position；不得把屏幕阅读器 increase/decrease 改成另一套 seek 算法。

### 2.4 视频中心提示

| `CenterHintType` | semantic label | liveRegion |
|---|---|---|
| `fastForward` | `已快进 15 秒` | true |
| `rewind` | `已快退 15 秒` | true |
| `speed` | `临时三倍速播放` | true |
| `seek` | `预览位置 <mm:ss 或 h:mm:ss>` | false |
| `none` 且显示暂停图标 | 无独立语义 | false |

中央提示可见内容必须放在 `ExcludeSemantics` 下，由外层单一 Semantics 节点表达；提示退出不播报“消失”或“恢复”。

### 2.5 通知气泡

在 `NotificationBubbleType` 上增加只读中文语义名称 getter，不改变 icon、color 或 duration：

| type | 语义名称 |
|---|---|
| `info` | `信息通知` |
| `success` | `成功通知` |
| `warning` | `警告通知` |
| `error` | `错误通知` |

每个入场 item 的结构必须等价于：

```text
Semantics(container: true, explicitChildNodes: true, liveRegion: true,
          label: "<类型>：<message>")
  ├─ 装饰 icon + 可见 message（ExcludeSemantics）
  ├─ 可选 action TextButton（独立语义，label 沿用 action.label）
  └─ close IconButton（独立语义，tooltip/label = "关闭通知"）
```

额外约束：

- 无 action 时只保留状态节点 + close；有 action 时遍历顺序是 action 后 close，和 Row 的视觉顺序一致。
- `showCloseButton == false` 的退出副本不是 disabled 通知，而是整个副本立即退出 pointer、focus 与 semantics；视觉淡出仍正常播放。
- `NotificationBubbleStack` 不创建 FocusNode、不 requestFocus；底层当前焦点在通知插入后必须保持。
- 不修改 `NotificationBubbleNotifier` 的 timer、最大三条和丢弃最旧项算法。

### 2.6 消息锚点

每个锚点 item 的语义字段：

| 字段 | 契约 |
|---|---|
| `label` | preview 非空：`第 N 条用户消息：<extractPreviewText 结果>`；preview 为空：`第 N 条用户消息` |
| `value` | `N / <userMessages.length>` |
| role | `button: true` |
| state | `selected: message.id == activeMessageId` |
| action | 显式 tap 调用 `onSelectMessage(message.id)` |
| liveRegion | false |

语义 label 在紧凑态也包含 preview；可见 preview Text 只负责视觉，必须排除子语义，确保展开后仍只有一个锚点节点。

### 2.7 媒体路径、Composer pill 与推理面板

| 控件 | Semantics 契约 | 焦点/键盘契约 |
|---|---|---|
| 根目录 path chip | `label: 根目录`、`button: true`、`selected: currentPath 是 / 或空` | 替换裸 GestureDetector 为局部透明 Material + InkWell；Tab 可达，Enter/Space 调用 `/`。 |
| 普通 path chip | `label: 目录：<segment.name>`、`button: true`、`selected: segment.path == currentPath` | 按根到叶的 widget 顺序遍历；紧凑横向滚动时 focus 自动 showOnScreen。 |
| `ComposerPillToggle` | `label: widget.label`、`toggled: value`、`enabled: enabled && onChanged != null` | interactive 时 Enter/Space 调用一次 `onChanged(!value)`；disabled 时使用禁用视觉、无 tap action并跳过 traversal。 |
| `ReasoningPanel` header | `label: 深度思考`、`button: true`、`expanded: _expanded`、动态 hint `激活以展开/收起` | Enter/Space切换；切换后 header 保持焦点；展开的 Markdown 内容保留自身语义。 |

这三个控件都使用局部、主题派生的 focus overlay；不新增固定颜色或全局 theme token。`ComposerPillToggle` 必须用 `isInteractive = enabled && onChanged != null` 同时驱动禁用视觉、Semantics enabled/action 和 InkWell onTap，禁止出现视觉可用但实际是 no-op 的可聚焦 InkWell；现有合法调用（disabled 时 `enabled == false`）的颜色不变。

---

## 三、焦点与键盘状态机

### 3.1 视频页面焦点顺序

使用局部 `FocusTraversalGroup` + widget order，顺序固定为：

1. 播放表面；
2. 返回；
3. 倍速；
4. 音量；
5. 播放/暂停/重播；
6. 进度 Slider（仅有 duration 时）。

约束：

- 不给视频页面 `autofocus: true`，避免路由打开时无条件抢占屏幕阅读器/应用焦点；首次 Tab 才进入播放表面。
- 控制栏隐藏时步骤 2-6 完全退出 traversal，播放表面仍可聚焦并用 Enter 重新显示。
- PopupMenu 或音量 dialog 关闭后使用 Flutter 现有 route/menu focus restoration，不创建第二套 FocusScope。
- Key handler 只响应 `KeyDownEvent`，忽略 KeyUp 和 KeyRepeat，避免一次长按触发多次 play/pause 或 route pop。

### 3.2 视频控制栏计时与焦点恢复

在 `_VideoPlayerPageState` 持有并 dispose：

- `_playerFocusNode`：播放表面；
- `_topControlsFocusNode`：不可直接聚焦的 top bar 祖先节点，用于观察 descendant focus；
- `_bottomControlsFocusNode`：同理。

实现以下状态转移：

| 事件 | 结果 |
|---|---|
| 焦点进入 top/bottom 控制栏 | cancel hide timer；控制栏保持可见。 |
| 焦点在两个控制栏间移动 | 旧组离开可短暂 reset，新组进入立即 cancel；不得隐藏或丢失焦点。 |
| 焦点离开全部控制栏 | 调用现有 `resetHideTimer()`；不立即隐藏。 |
| 自动隐藏 timer 到期且控制栏无焦点 | 维持现有隐藏。 |
| 指针 tap 隐藏且控制栏 descendant 当前聚焦 | 状态更新后一帧 `_playerFocusNode.requestFocus()`。 |
| 路由 dispose | 先 dispose 三个 FocusNode，再/同时按现有顺序释放 gesture controller；不得留下回调。 |

不要把 FocusNode 放进 `VideoPlayerGestureController`；它是 presentation page 的资源，不属于播放业务状态。

### 3.3 消息锚点焦点状态

`_MessageAnchorRailState` 增加一个不可直接请求焦点的 rail ancestor FocusNode，用 `hasFocus` 表示任一锚点 descendant 聚焦：

| 事件 | rail 展开状态 |
|---|---|
| mouse enter 且消息数 >3 | 展开（现有行为）。 |
| mouse exit 且 rail 内无键盘焦点 | 折叠。 |
| long press 且消息数 >3 | 展开（现有行为）。 |
| keyboard focus 首次进入且消息数 >3 | 展开。 |
| keyboard focus 在锚点间移动 | 保持展开。 |
| `didUpdateWidget` 且 rail 内有 focus | 不折叠；保持焦点和预览。 |
| `didUpdateWidget` 且 rail 内无 focus | 沿用现有折叠。 |
| focus 完全离开 rail | 折叠。 |

锚点 item 不自建持久 FocusNode，使用 InkWell 的标准焦点生命周期，防止消息增删时维护错位的 FocusNode list。

### 3.4 通知与其他控件

- 通知插入：底层 primary focus 不变。
- 通知 action/close：标准 Material 焦点和 Enter/Space 激活；item 移除后下一个 Tab 必须仍能到达底层 sentinel，不要求强行返回到插入前的精确节点。
- MediaPathBar：根到叶自然顺序；selected 只表达当前位置，不禁用当前路径。
- ComposerPillToggle/ReasoningPanel：状态 rebuild 后同一 element 继续持有 focus；不得为了更新 Semantics 重新创建带随机 key 的 subtree。

---

## 四、生产代码逐文件修改

### 4.1 视频播放器

| 文件 | 精确修改 |
|---|---|
| `lib/features/media/presentation/pages/video_player_gesture.dart` | 新增公开 `seekRelative(Duration offset)`（或语义等价且名字明确的方法），统一初始化/error/duration guard、target clamp、`seekTo`、`beginGesture`、对应 rewind/fastForward hint 和 `endGesture` 回调；`handleDoubleTap` 只负责判断左右半屏并调用该方法。不得复制第二份 clamp。增加供 Focus 回调使用的“控制交互开始/结束”方法，内部只 cancel/reset 现有 hide timer。 |
| `lib/features/media/presentation/pages/video_player_page.dart` | 持有/释放三个 FocusNode；把现有 `onStateChanged = () => setState` 改为能检测“隐藏时控制栏仍聚焦”并 post-frame 恢复到播放表面的 handler；在页面 body 外建立局部 traversal group、播放表面 Focus/onKeyEvent、focus highlight 和显式 Semantics；top/bottom bar 增加 focus observer、`ExcludeFocus`、`ExcludeSemantics`；加载/error 状态增加不重复的状态语义。保留现有 GestureDetector 的 pointer hit test 与手势注册。 |
| `lib/features/media/presentation/widgets/video_player_controls.dart` | 为 top bar 的返回/倍速/音量和 bottom bar 的播放按钮增加第二节精确 tooltip/label；Slider 增加“播放进度”与实际时间 formatter，disabled 状态不造假 action；时间 Text、buffer progress 与中心提示可见子树按第二节排除重复语义；VideoCenterHint 生成离散 live region。不得改变布局尺寸、speed 列表、volume dialog、Slider 值域或 icon。 |

实现提示：

- 共享字符串计算可使用文件内私有函数/局部 getter；不要为当前中文文案新增 localization service。
- `VideoPlayerPage` 的 key handler 先检查 `_playerFocusNode.hasPrimaryFocus`，再匹配按键；不允许用 `FocusManager.primaryFocus` 的 debugLabel 判断。
- `seekRelative` 必须让现有双击测试继续通过；方向键 test 只验证同一 fake `seekToCalls`。
- 现有 `video_player_page_test.dart` 中含“Phase 6 新增了 onDoubleTap”的临时注释。该文件在本 Phase 定向回归范围内，顺手把注释改为持久原因描述（例如“onDoubleTap 会启动 double-tap countdown timer”），不得保留 Phase 编号。

### 4.2 通知气泡

| 文件 | 精确修改 |
|---|---|
| `lib/core/widgets/notification_bubble_data.dart` | 给 `NotificationBubbleType` 增加第二节固定映射的只读 semantic label getter；不改 Equatable props、duration、icon 或 color。 |
| `lib/core/widgets/notification_bubble.dart` | 用单一状态 Semantics 包裹视觉容器，`container/explicitChildNodes/liveRegion/label` 按第二节；只排除 icon 和 message 的重复语义，保留 action/close；close 增加 `tooltip: 关闭通知`；局部确保 inverse surface 上的 focus overlay 可见。不得改变 `_handleAction` 的 action-first、dismiss-second 顺序。 |
| `lib/core/widgets/notification_bubble_stack.dart` | `_buildRemoveItem` 的整个退出内容包 `IgnorePointer`、`ExcludeFocus`、`ExcludeSemantics`；插入 item 不 requestFocus；AnimatedList 同步、动画时长和宽度算法不改。 |

`notification_bubble_context_ext.dart` 与 `notification_bubble_provider.dart` 不修改；如果实现需要改 provider timer 才能通过测试，说明已经越过业务边界，必须停止并重新定界。

### 4.3 消息锚点

| 文件 | 精确修改 |
|---|---|
| `lib/features/chat/presentation/widgets/message_anchor_rail.dart` | 增加/释放 rail ancestor FocusNode；把 hover/focus/didUpdateWidget 的展开折叠规则改为第三节状态机；每个 item 使用第二节 label/value/button/selected/tap 契约；只排除预览视觉子树，确保 InkWell 标准 focus/tap 与父 Semantics 合并成单一节点；增加局部 focusColor。保留 `extractPreviewText` 算法、ScrollController、定位 callback、尺寸、动画和既有 test key。 |

不得修改 `ChatMessagesPanel`、`ChatScrollController`、active anchor 计算或消息树。焦点展开是 rail 本地纯 UI 状态。

### 4.4 盘点后纳入的关键自绘状态控件

| 文件 | 精确修改 |
|---|---|
| `lib/features/media/presentation/widgets/media_path_bar.dart` | `_PathChip` 从裸 GestureDetector 改为透明 Material + InkWell；增加根目录/普通目录 label、button、selected、tap；视觉 Text 排除重复语义；局部 focusColor。路径拆分、累计 path 和 onPathSelected 参数不改。 |
| `lib/features/chat/presentation/widgets/composer_pill_toggle.dart` | 计算 `isInteractive = enabled && onChanged != null`；Semantics 提供 label/toggled/enabled/tap；视觉 icon/text 排除重复；InkWell 只在 `isInteractive` 时有 onTap，并提供局部 focusColor；禁用颜色也以 `isInteractive` 为准。现有合法 enabled/disabled 状态的背景、边框、颜色和 animation 不改。 |
| `lib/features/chat/presentation/widgets/reasoning_panel.dart` | 抽取单一 toggle callback供 pointer/semantics 共用；header Semantics 提供 label/button/expanded/dynamic hint/tap；只排除 header 的 icon、“深度思考”和“展开/收起”重复语义，展开后的 Markdown 不排除；局部 focusColor。 |

`thinking_toggle.dart`、`auto_retry_toggle.dart`、Chat controller、Favorites presentation owner 均无需修改；通用控件的语义会自动覆盖现有使用点。

---

## 五、测试文件与测试策略

### 5.1 测试文件清单

新增：

- `test/features/media/presentation/video_player_accessibility_test.dart`
- `test/core/widgets/notification_bubble_accessibility_test.dart`
- `test/features/media/presentation/media_path_bar_accessibility_test.dart`
- `test/features/chat/widgets/composer_pill_toggle_accessibility_test.dart`
- `test/features/chat/widgets/reasoning_panel_accessibility_test.dart`

修改：

- `test/features/chat/widgets/message_anchor_rail_test.dart`
- `test/features/media/presentation/video_player_page_test.dart`（只清理临时 Phase 注释并作为行为回归；a11y 新用例放独立文件）

复用但不修改：

- `test/features/media/helpers/fake_video_player_controller.dart`
- `test/helpers/responsive_viewport_cases.dart`
- `test/helpers/test_harness.dart`

不得为了“统一测试结构”拆分现有 676 行视频测试或重写锚点的全部旧断言；这属于 Phase 15 的存量测试韧性工作。

### 5.2 Semantics 测试写法

每个 semantics test 必须：

1. `final handle = tester.ensureSemantics()`，用 `addTearDown(handle.dispose)` 或 `try/finally` 释放。
2. 用 `find.semantics.byLabel` 获取语义节点；使用 `containsSemantics` 只断言本用例关心的 label/value/flag/action，避免 `matchesSemantics` 默认把所有未列 flag 断言为 false。
3. 用 `tester.semantics.tap(finder)`、`increase`、`decrease` 模拟屏幕阅读器 action；随后 `pump()` 并断言公开回调、fake call 或可见状态。
4. 对“无重复”使用 semantics finder 数量：同一 status/header/anchor label 恰好一个；不通过 widget 类型数量间接推断。
5. 测 disabled 时同时断言 `hasEnabledState: true, isEnabled: false` 且无 tap/increase/decrease action；不要只断言回调没触发。

### 5.3 视频测试矩阵

`video_player_accessibility_test.dart` 使用 FakeVideoPlayerController，复制最小、文件内的 page pump/init helper；不要为此重构旧测试 harness。

| 场景 | 输入/操作 | 必须断言 |
|---|---|---|
| viewport smoke | 分别 390×844、1440×900 初始化 | 播放表面、返回、倍速、音量、暂停、播放进度各有一个可理解语义；无 framework exception。 |
| 播放表面 action | semantics tap | 控制栏 visible 状态切换；隐藏后控制节点从 semantics 消失，播放表面仍存在且 hint 改为“显示”。 |
| 播放状态 | Space；再次 Space；ended 初始状态 | fake pause/play 调用正确；按钮 label 在“暂停/播放/重新播放”间更新。 |
| 相对 seek | 初始 30s，ArrowLeft/ArrowRight | fake 最后 seek 分别 15s/45s；靠近边界时仍 clamp 到 0/duration。 |
| 返回 | 播放表面聚焦后 Escape | 现有测试 route 被 pop；fake dispose 仍只发生一次。 |
| 快进/快退 status | 方向键或现有双击 | 恰好一个 live region，label 为“已快进/快退 15 秒”；视觉“15s”不生成第二语义节点。 |
| 临时倍速 status | 现有 long press | “临时三倍速播放”为 live region；松手恢复原 speed，退出不播报重复节点。 |
| Slider value | current 30s / total 5m | `label=播放进度`、`value=00:30 / 05:00`、有 increase/decrease。 |
| Slider disabled | totalDuration = 0 | disabled、有 enabled state、无 increase/decrease；Tab 不停在该节点。 |
| focus order | 连续 Tab | focused 语义顺序为播放表面→返回→倍速→音量→暂停→播放进度。 |
| 控制焦点防隐藏 | 焦点停在任一 top/bottom 控制，pump >3s | 控制语义仍存在且焦点仍在原操作。 |
| 隐藏焦点恢复 | 控制聚焦时用 pointer tap 播放区域隐藏 | 下一帧播放表面语义 `isFocused: true`，隐藏控制无 focused/semantics 节点。 |
| 错误状态 | 可控失败 controller/factory | 一个 live error status + 可操作“重试”；没有可激活播放表面。 |

快捷键测试先用 Tab 把焦点移到播放表面，不直接读取私有 FocusNode。对多个键的同构用例使用参数化 case；一个 test 只验证一个决策分支。

### 5.4 通知测试矩阵

`notification_bubble_accessibility_test.dart` 同时覆盖纯 `NotificationBubbleContent` 与 Provider + Stack；可直接使用 `ProviderScope/ProviderContainer + MaterialApp`，不需要数据库。

| 场景 | 必须断言 |
|---|---|
| 四种 type 参数化 | 每种 type 只有一个 `<类型>：消息` live region。 |
| 无 action | status 与“关闭通知”两个语义节点；图标/message 不重复。 |
| 有 action | status、action label、“关闭通知”各一个；action/close 均有 tap action。 |
| semantics action | 对 action 执行 semantics tap | action callback 先执行一次，dismiss 后 provider 不含该通知。 |
| close action | 对“关闭通知”执行 semantics tap | 只 dismiss，不执行 action。 |
| 出场动画 | dismiss 后只 pump 小于 200ms | 视觉出场可仍存在，但 status/action/close 语义已不存在，Tab/点击也不能触发 outgoing action，证明退出副本已退出交互。 |
| 不抢焦点 | 先聚焦底层 sentinel，再通过 provider show | sentinel 保持 focused；notification 未自动 focused。 |
| keyboard traversal | standalone content 连续 Tab + Enter | 有 action 时 action 后 close；无 action 时直接 close；回调可观察。 |
| viewport smoke | 390×844、1440×900 | status/action/close 语义一致，无 overflow/exception。 |
| 最多三条回归 | 连续 show 4 条 | 保留 provider 既有 newest-first/最多三条；每个保留通知恰好一个 status。 |

不要使用真实 `Timer` 等待 3-8 秒验证 provider 业务；现有 timer 不是本 Phase 目标。需要验证出场时直接调用 notifier.dismiss。

### 5.5 消息锚点测试矩阵

在既有 `message_anchor_rail_test.dart` 新增独立 semantics/focus group，旧 hover/long-press 用例不重写。

| 场景 | 必须断言 |
|---|---|
| compact semantics | 5 条消息但未展开 | 每项 label 含序号和 preview，value 是 N/5；无须 hover 才能读到 preview。 |
| selected | activeMessageId 指向第 2 条 | 第二项 `isSelected: true`，其余 false；没有 liveRegion。 |
| empty preview | Markdown/标点清理后为空 | label 仅“第 N 条用户消息”，不带空冒号或“null”。 |
| semantics tap | 激活第 2 项 | callback 收到 `msg-2` 一次。 |
| keyboard order | 从 rail 前 sentinel 连续 Tab/Enter | 按消息列表顺序激活 msg-1、msg-2；进入 rail 后预览展开。 |
| offscreen reachability | 低 maxHeight + 10 条消息，连续 Tab 到末项 | focus 自动滚动并能激活第 10 条；不使用坐标/scroll extent 断言。 |
| parent rebuild | 某锚点 focused 时更新 active ID | rail 保持展开、同一锚点仍 focused/可 Enter 激活。 |
| focus leaves | Tab 到 rail 后 sentinel | rail 折叠；callback 不被误触发。 |
| viewport smoke | 390×844、1440×900 | 同一语义与 Tab 路径成立，无 exception。 |

新用例只用 semantics label 和 sentinel 文案定位，不使用现有 `railContainerFinder` 或 `find.byType(InkWell)`。

### 5.6 额外三个控件的测试矩阵

#### MediaPathBar

- currentPath `/相册/旅行` 时，语义顺序为“根目录”“目录：相册”“目录：旅行”；最后一项 selected。
- 对根目录和中间 segment 执行 semantics tap，callback 分别收到 `/`、`/相册`。
- keyboard 从前 sentinel Tab 到各 chip，Enter/Space 触发相同 path。
- 390×844 下使用足够长的多级路径，Tab 到末级后仍能激活；不检查横向 scroll 像素。
- 1440×900 重复一个语义/键盘 smoke，确保行为与 viewport 无关。

#### ComposerPillToggle

- 参数化 `(enabled, onChanged, value)`：enabled+callback 分别产生 toggled false/true 且可 tap；`enabled=false` 或 callback null 均 disabled、无 tap。
- semantics tap、Enter、Space 分别只调用一次 `onChanged(!value)`。
- 父 wrapper 接到回调后 rebuild 新 value；同一节点变为新 toggled 状态且保持 focused。
- disabled 控件在前后 sentinel 之间被 Tab 跳过。

#### ReasoningPanel

- 初始 header `expanded=false`，恰好一个“深度思考”语义节点；可见“展开”不形成第二节点。
- semantics tap 或 Enter/Space 后 `expanded=true`，Markdown 内容在语义树可读；header 保持 focused。
- 再次激活回到 `expanded=false`，内容移出语义树；hint 从“激活以展开”切换到“激活以收起”再恢复。
- Chat streaming 既有可见文字测试继续通过，证明没有删除产品文案。

### 5.7 测试反模式禁止项

本 Phase 新增/修改的用例禁止：

- 用 `find.byKey`、private key、widget type 数量证明语义；
- 断言 `Semantics` widget 本身的构造参数，而不读取生成后的 semantics node；
- 对焦点环颜色、边框宽度或控件坐标做像素断言；
- 通过 `FocusManager.primaryFocus.debugLabel` 判断顺序；
- 用 `pumpAndSettle` 等待 provider 长 duration timer；
- 测试末尾无条件 early return；
- 在测试标题/注释写 `Phase 14`、`TD-30`、审查轮次等临时编号。

---

## 六、分任务实施顺序与独立提交

### Task 0：建立实施基线并保护用户改动

1. `git status --short`，确认并保护既有未跟踪 `Phase 11 - Implement Plan.md`；任何后续 `git add` 都使用显式文件列表。
2. `flutter --version`，确认满足项目要求。计划时环境为 Flutter 3.44.8 / Dart 3.12.2；版本变化不是阻塞，但若升级 Flutter，按 AGENTS 先 `flutter clean`。
3. `flutter pub get`。
4. 运行点名控件和直接消费者的实施前基线：

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-baseline.log'
flutter test test/features/media/presentation/video_player_page_test.dart test/features/chat/widgets/message_anchor_rail_test.dart test/features/chat/chat_screen_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

5. `EXIT!=0` 时先从 temp log 定界既有失败；不得把 baseline failure 混入 a11y commit。

### Task 1：视频播放表面、控制栏与动态状态

#### Step 1：先写外部契约红灯测试

新增 `video_player_accessibility_test.dart`，先完成：

- compact/desktop semantics smoke；
- surface semantics tap；
- Space/方向键/Escape；
- controls hidden semantics/focus；
- Slider enabled/disabled；
- discrete live status。

红灯必须来自 label/flag/action/keyboard 尚不存在；不得用 skip 或宽松 finder 假造。

#### Step 2：统一相对 seek

先修改 `VideoPlayerGestureController`，让双击与键盘共享相对 seek。立即运行旧视频 test，保证 double-tap、clamp、hint 不回归。

#### Step 3：实现 page focus/keyboard 与 controls semantics

按第四节逐文件实施。每完成隐藏控制与焦点恢复后，单独跑相应用例，防止一次调试多个状态机。

#### Step 4：定向验证

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-video.log'
flutter test test/features/media/presentation/video_player_page_test.dart test/features/media/presentation/video_player_accessibility_test.dart test/features/media/presentation/media_route_pages_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

#### Step 5：提交

格式化三个生产 Dart、两个测试 Dart（含旧测试注释清理），显式暂存并复查格式。提交：

```bash
git commit -m "fix(media): 补齐视频播放器键盘与语义契约"
```

### Task 2：通知气泡 live region、子操作和退出语义

1. 新增通知 a11y test，先建立四种 type、无重复、action/close、出场排除、不抢焦点和 viewport 红灯。
2. 修改 type getter 与 content 语义结构；先让纯 content tests 通过。
3. 修改 stack 出场排除；让 provider+AnimatedList tests 通过。
4. 确认 provider/context extension 没有 diff。
5. 定向验证：

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-notification.log'
flutter test test/core/widgets/notification_bubble_accessibility_test.dart test/features/sync/application/sync_client_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

6. 格式化、显式暂存、format check 后提交：

```bash
git commit -m "fix(ui): 消除通知气泡重复语义"
```

### Task 3：消息锚点语义与焦点展开

1. 在现有 test 文件添加 semantics/focus group；不改旧组。
2. 实现单一节点 label/value/selected/action，先跑 semantics tests。
3. 实现 rail ancestor focus 状态机，再跑 hover、long-press、parent rebuild 全部旧用例。
4. 特别验证鼠标移出但 rail 内仍有键盘焦点时不折叠；焦点离开后才折叠。
5. 定向验证：

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-anchor.log'
flutter test test/features/chat/widgets/message_anchor_rail_test.dart test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

6. 提交：

```bash
git commit -m "fix(chat): 补齐消息锚点焦点契约"
```

### Task 4：媒体路径键盘导航

1. 新增 MediaPathBar a11y test，先确认裸 GestureDetector 无 focus/tap semantics 红灯。
2. 只替换 `_PathChip` 的交互壳，不改 path 构造。
3. 跑 compact 长路径与 desktop smoke，再跑现有 media navigation route tests。

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-media-path.log'
flutter test test/features/media/presentation/media_path_bar_accessibility_test.dart test/features/media/presentation/media_browser_navigation_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

4. 提交：

```bash
git commit -m "fix(media): 使媒体路径支持键盘导航"
```

### Task 5：Chat 关键状态控件

1. 分别新增 ComposerPillToggle 与 ReasoningPanel a11y tests。
2. 先实现通用 pill 的 toggled/enabled/action/focus；`ThinkingToggle`、`AutoRetryToggle` 不改。
3. 再实现 ReasoningPanel expanded/header 单节点；Markdown 子语义必须保留。
4. 跑两份新测试、Chat screen 和 Favorites 相关 widget tests（若仓库存在对应入口）。至少执行：

```powershell
$logPath = Join-Path $env:TEMP 'oh-my-llm-phase14-chat-controls.log'
flutter test test/features/chat/widgets/composer_pill_toggle_accessibility_test.dart test/features/chat/widgets/reasoning_panel_accessibility_test.dart test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 -LiteralPath $logPath; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 -Encoding utf8 -LiteralPath $logPath
```

5. 提交：

```bash
git commit -m "fix(chat): 显式标注关键状态控件语义"
```

### Task 6：最终范围审计与门禁

#### Step 1：diff 与范围审计

```powershell
git status --short
git diff --name-only HEAD~5..HEAD
git diff --check HEAD~5..HEAD
```

若实际 commit 数不是 5，不要机械使用 `HEAD~5`；以实施前记录的基线 hash 为 diff 起点。允许的生产文件仅第四节清单。`pubspec.yaml` 只允许 post-commit hook 自动产生版本变化。

#### Step 2：禁止项审计

```powershell
rg -n "flutter_localizations|supportedLocales|localizationsDelegates|\.arb|SemanticsService\.announce" lib pubspec.yaml
rg -n "Phase 14|TD-30|第一轮审查" lib/features/media/presentation lib/features/chat/presentation lib/core/widgets test/features/media test/features/chat test/core/widgets
git diff -U0 <实施前基线> -- test | Select-String -Pattern '^\+.*(find\.byKey|getTopLeft|getRect|debugLabel|pumpAndSettle\(const Duration\(seconds: [3-9])'
```

- 第一条不得出现本 Phase 新增 l10n/命令式播报；仓库既有无关命中需人工分类。
- 第二条在本 Phase 新增/修改代码和测试中必须无新增命中；既有视频 test 的 Phase 6 注释应已改成持久描述。
- 第三条必须无新增测试反模式；如果 PowerShell regex 因括号报错，可拆成多个 `Select-String -SimpleMatch`，不能跳过审计。

#### Step 3：Dart 格式与 staged 复检

每个任务提交前都执行，最终再检查一次：

```powershell
git diff --name-only -- '*.dart'
dart format <本任务修改的全部 Dart 文件>
git add <本任务显式文件列表>
dart format --output=none --set-exit-if-changed <本任务已暂存 Dart 文件列表>
git diff --cached --check
```

不得 `git add .`，不得暂存用户的 Phase 11 文件或 temp test log。

#### Step 4：架构与静态分析

```powershell
dart run tool/architecture/import_boundary_checker.dart
flutter analyze
```

两条均需成功；warning、timeout 或命令无输出都不能记为通过。

#### Step 5：全量测试

严格使用仓库强制命令：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

只有 `EXIT=0` 才完成。失败从 `fltest.log` 查询；不得无重定向重跑全量测试。`fltest.log` 不得进入提交。

---

## 七、行为验证矩阵

### 7.1 Compact 与 desktop

| 控件 | 390×844 | 1440×900 |
|---|---|---|
| 视频 | surface/control semantics、Tab、Space、方向键、隐藏恢复 | 同一契约 + 完整焦点顺序 |
| 通知 | status/action/close 可读可达，无 overflow | 同一契约、不抢底层焦点 |
| 锚点 | 紧凑 rail label 含 preview，Tab 可滚到末项 | 展开/折叠和 selected 契约一致 |
| MediaPathBar | 长路径 focus 自动 showOnScreen | 根到叶 traversal 顺序一致 |
| Composer/Reasoning | 通用控件行为与宽度无关，至少在一个真实 Chat compact case 回归 | 独立 semantics/focus tests + Chat 默认 desktop 回归 |

不要求为每个状态在两个 viewport 复制全部用例；每个关键控件做两端 smoke，状态决策树在一个稳定 viewport 完整覆盖。

### 7.2 用户输入方式等价表

| 操作 | 指针/触摸 | 键盘 | 屏幕阅读器 |
|---|---|---|---|
| 视频控制显隐 | 单击播放表面 | surface focus + Enter | surface tap action |
| 播放/暂停/重播 | 播放按钮 | surface Space 或按钮 Enter/Space | 播放按钮 tap action |
| 快退/快进 15s | 双击左/右半屏 | surface ArrowLeft/ArrowRight | 通过可调整进度 Slider；不为双击伪造左右屏 semantic 区域 |
| 视频返回 | 返回按钮 | surface Escape 或返回按钮 | 返回按钮 tap action |
| 通知 action/close | 点击按钮 | Tab + Enter/Space | 独立 action/close tap |
| 锚点定位 | 点击锚点 | Tab + Enter/Space | 锚点 tap action |
| 目录跳转 | 点击 chip | Tab + Enter/Space | path chip tap action |
| Composer toggle | 点击 pill | Tab + Enter/Space | toggled node tap action |
| 推理展开 | 点击 header | Tab + Enter/Space | expanded node tap action |

视频双击的屏幕阅读器等价路径是带实际时间 value 的 Slider，而不是把全屏拆成两个不可见按钮；这样避免遮挡视频表面和产生冲突语义。

---

## 八、提交序列与回滚

| 顺序 | Commit | 独立价值 | 回滚影响 |
|---|---|---|---|
| 1 | `fix(media): 补齐视频播放器键盘与语义契约` | 视频 surface/controls/hints 有完整语义、键盘和焦点恢复。 | 只回退视频 a11y；现有手势业务仍由旧测试保护。 |
| 2 | `fix(ui): 消除通知气泡重复语义` | 通知成为单次 live status，action/close 可达。 | 不影响 provider queue/timer。 |
| 3 | `fix(chat): 补齐消息锚点焦点契约` | 锚点可读、可 Tab、焦点展开稳定。 | 不影响消息滚动/定位算法。 |
| 4 | `fix(media): 使媒体路径支持键盘导航` | 媒体目录核心路径不再依赖点击。 | 只恢复旧 GestureDetector 外壳。 |
| 5 | `fix(chat): 显式标注关键状态控件语义` | Composer toggled/disabled 与 Reasoning expanded 成为外部契约。 | 不影响 Chat state owner 或生成参数。 |

每次 commit 都包含对应生产代码和绿色定向测试，不提交“只有红灯测试”的中间 commit。post-commit hook 会自动 bump version；不要手工修改 `pubspec.yaml`。提交使用 Bash，不使用 PowerShell here-string。

如果某一任务发现必须同时修改另一个任务文件才能成立，先判断是否只是公共测试 helper：

- 能在当前控件局部完成则保持独立提交；
- 需要全局 theme/app shortcut/provider lifecycle 时停止，不把跨范围依赖硬塞进 commit；
- 不通过 squash 五个任务掩盖耦合。

---

## 九、风险、停止条件与严格 Out of Scope

### 9.1 主要风险与控制

| 风险 | 控制 |
|---|---|
| 父/子 Semantics 重复 label/action | 装饰子树 ExcludeSemantics；action/close 用 explicit child nodes；测试每个 label 恰好一个。 |
| live region 反复重建造成重复播报 | 只对离散 status 标 live；position/buffer/selected/expanded 不标；退出副本排除。 |
| 视频快捷键抢 Slider/menu/dialog | 仅 `_playerFocusNode.hasPrimaryFocus` 且 KeyDown 时处理；其他情况 ignored。 |
| 控制栏隐藏后留下不可见焦点 | 控制 focus 时取消 timer；手动隐藏后 post-frame 恢复 surface；ExcludeFocus/ExcludeSemantics。 |
| 通知出现打断输入 | 禁止 autofocus/requestFocus；测试底层 sentinel focused 不变。 |
| anchor hover exit 与键盘 focus 打架 | collapse 前检查 rail ancestor `hasFocus`；父 rebuild 聚焦时不折叠。 |
| disabled pill 仍可聚焦的 no-op closure | `isInteractive = enabled && onChanged != null` 同时控制 Semantics action 和 InkWell onTap。 |
| 新测试冻结 widget tree | 只用 semantics finder、按键、callback/fake 状态和无 exception。 |
| 把中文 a11y 文案误升级为 l10n 项目 | 只增加当前中文 label；依赖产品需求的全量 l10n 继续延期。 |
| 增加 scope 到图片/全应用 | 严格使用 1.3 清单；额外命中只记录，不实现。 |

### 9.2 必须停止并请求重新定界的情况

1. 需要修改通知 provider 的 duration、timer、最大条数或 action 执行顺序才能完成焦点测试。
2. 需要在 `MaterialApp`/AppShell 注册全局快捷键，或修改全局 Theme 才能显示局部焦点。
3. 视频键盘实现必须改变 seek 秒数、播放结束语义、自动隐藏时长、手势竞技场或 route 结构。
4. 消息锚点实现必须修改 active anchor 计算、滚动 controller、消息树或 Chat application state。
5. MediaPathBar 键盘化必须改变 path 规范化、route URI、media protocol 或目录排序。
6. Composer/Reasoning 语义必须修改 generation payload、auto retry 业务、reasoning/content 分离或 Favorites domain。
7. 发现必须启用 localization/ARB 才能增加中文 semantic label。
8. 新 a11y tests 只能靠 internal key、widget 私有属性、像素坐标或 debug semantics snapshot 才能通过；应重新设计可观察契约。
9. 实施前 baseline 已失败，或 Phase 13 的 compact/desktop 行为出现与本 Phase 无关的 overflow；先报告，不夹带修复。
10. 需要把 ImageViewer zoom、全应用颜色对比、字号缩放或 WCAG 认证纳入本次才能宣称完成；这些都超出 Phase 14 结论。

### 9.3 严格 Out of Scope

- 不新增/修改 ARB、`intl`、`flutter_localizations`、supported locales 或文案翻译；
- 不做全应用 screen reader 审计、WCAG 认证、对比度/字号/触控目标全面整改；
- 不修改视频播放策略、初始化、资源释放、手势秒数、倍速选项、音量模型、控制栏三秒规则；
- 不修改通知 provider 生命周期、持久化、数量、排序、duration 或样式架构；
- 不修改 Chat message tree、generation、streaming、Prompt 顺序、inline error、reasoning/content 数据模型；
- 不修改消息锚点定位算法、active ID 计算或列表滚动策略；
- 不修改媒体 route、HTTP、路径协议、图片 zoom、Media grid 或播放器 URL；
- 不改 Phase 13 breakpoint、viewport helper 数值或响应式布局；
- 不执行/新增 Phase 16 的设备 release smoke 自动化；
- 不治理现有 test key、`find.byType(InkWell)`、坐标 helper 等 Phase 15 存量测试债务，除非本 Phase 新增代码直接要求替换相应用例；
- 不改全局 Theme、AppShell focus policy 或普通 Material 控件。

---

## 十、完成定义（Definition of Done）

- [ ] Phase 文档无矛盾，实施未回查或重新解释 Review Report，结论与技术选型未被改写。
- [ ] 生产 diff 仅包含第四节明确文件；用户既有 Phase 11 未跟踪文件未被修改/暂存。
- [ ] 视频播放表面有唯一 label/value/hint/button/tap 语义，加载/error 状态不伪装成播放器按钮。
- [ ] 视频键盘 Enter、Space、Left、Right、Escape 仅在 surface 主焦点时生效，不抢 controls/menu/dialog。
- [ ] 双击和方向键复用单一 relative seek clamp/提示路径，现有手势测试全绿。
- [ ] 视频 top/bottom controls 隐藏时同时退出 pointer/focus/semantics；控制聚焦时不自动隐藏；手动隐藏可恢复到 surface。
- [ ] 返回、倍速、音量、播放/暂停/重播和播放进度具有清晰、动态且不重复的语义。
- [ ] 快进、快退、临时倍速各只产生一个 live status；seek preview、position、buffer 不高频播报。
- [ ] 四种通知 type 各有一个完整 live region；message/icon 不重复；action 与“关闭通知”独立可达。
- [ ] 通知退出副本立即退出 pointer/focus/semantics，通知插入不抢底层焦点；provider timer/数量/顺序未改。
- [ ] 每个消息锚点有序号、preview、总数、button、selected 和 tap；active 滚动变化不是 live region。
- [ ] 锚点键盘 focus 进入展开、内部移动/父更新保持、离开折叠；hover/长按/点击旧行为全绿。
- [ ] MediaPathBar 根目录和各 segment 可 Tab、Enter/Space、screen reader tap，并正确标 selected。
- [ ] ComposerPillToggle 正确暴露 toggled/enabled；disabled 无 action且跳过 Tab；状态 rebuild 后保持焦点。
- [ ] ReasoningPanel header 正确暴露 expanded；展开内容语义仍可读；切换后 header 保持焦点。
- [ ] 视频、通知、锚点、MediaPathBar 在 390×844 和 1440×900 至少各有一个 semantic/keyboard smoke。
- [ ] 新测试使用 semantics finder/matcher/action 与公开行为，没有新增 key、widget tree、坐标、像素或 debugLabel 断言。
- [ ] 新增代码/测试注释不含 Phase/TD/审查临时编号；视频旧 Phase 6 timer 注释已改为持久原因。
- [ ] 没有新增 localization、SemanticsService imperative announcement、全局 shortcuts/theme 或普通 Material 重复 Semantics。
- [ ] 每个任务的 Dart 文件已格式化，暂存后 format check 与 `git diff --cached --check` 通过。
- [ ] `dart run tool/architecture/import_boundary_checker.dart` 通过。
- [ ] `flutter analyze` 通过。
- [ ] 全量测试按强制重定向命令运行并得到 `EXIT=0`，`fltest.log` 未提交。
- [ ] 五个独立 commit 均包含对应生产修改和绿色测试，可单独回滚；版本只由 post-commit hook 自动更新。
