# Windows 桌面视频操控与跨平台播放控制设计

**日期：** 2026-08-13

**状态：** 已批准

**范围：** Windows 桌面视频输入、原生全屏、共享播放控制抽象与 Android 行为等价迁移

## 1. 背景

Windows 已能在同步页“媒体”Tab 中直接浏览配置的本地媒体根目录，并复用原有视频播放器。媒体资源访问已经通过 `MediaLibrary`、本地/远端资源值对象和播放器 controller factory 完成跨平台统一，但播放器的输入系统仍然以 Android 触摸交互为中心。

当前页面在所有平台无条件安装以下全屏手势：

- 单击切换控制栏；
- 双击左右半屏快退/快进 15 秒；
- 长按临时切换到 3 倍速；
- 水平拖动预览并提交 Seek。

Windows 虽然后续增加了 `Space`、左右方向键和 `Escape` 等可访问性快捷键，但这只是页面内的附加映射，并没有形成桌面输入模型。现有 `VideoPlayerGestureController` 同时负责播放器生命周期、共享播放命令、控制栏状态、中央提示和移动端手势，导致以下问题：

1. Windows 仍响应移动端双击、长按和横拖 Seek；
2. 按键处理只接受 `KeyDownEvent`，无法表达“短按右键 Seek、长按右键临时 3 倍速、松开恢复”的互斥状态机；
3. PC 缺少上下方向键音量、静音恢复、滚轮音量、鼠标活动和真正的原生全屏；
4. Android 的方向与沉浸式系统 UI 操作也由共享页面无条件执行；
5. 共享 UI state 混有双击位置、触摸拖动、长按等移动端字段，不适合继续加入桌面按键和鼠标字段；
6. 中央提示把 15 秒和 3 倍速写死在 Widget 中，不能正确表达 Windows 的 5 秒 Seek 和动态音量反馈。

本设计把“播放能力”与“输入如何翻译为播放命令”分开。Windows 始终采用桌面方案，即使设备带触摸屏也不动态切换为移动端手势；Android 保持既有产品行为。

## 2. 已确认的产品决定

1. Windows 始终使用桌面操控，不根据触摸屏、指针类型或窗口宽度切换输入方案。
2. Windows 播放画面不再支持左右半屏双击 Seek、全屏长按三倍速或横拖 Seek。
3. Windows 左右方向键按固定 5 秒 Seek；Android 双击继续按固定 15 秒 Seek。
4. Windows 右方向键短按与长按互斥：短按松开才快进 5 秒；按住约 400ms 后只进入临时 3 倍速，不附带 Seek；松开恢复常驻倍速。
5. Windows 左方向键首次按下立即快退 5 秒；长按重复事件全部忽略，不设计连续快退或其他长按行为。
6. Windows 上下方向键每次调整播放器音量 5%；长按接受键盘重复事件以连续调整。
7. Windows `M` 静音；再次按下恢复静音前的非零音量。
8. Windows 播放画面单击切换播放/暂停；鼠标活动显示控制栏。
9. Windows 垂直滚轮按方向调整播放器音量 5%；水平滚动无播放行为。
10. Windows 播放器初始化完成后自动聚焦播放表面，无需先点击即可使用快捷键。
11. Windows `F` 或双击播放画面切换真正的原生全屏；`Escape` 在全屏时先退出全屏，窗口模式时关闭播放器。
12. 不新增常驻倍速快捷键；现有顶部倍速菜单仍是常驻倍速的唯一调整入口。
13. 不改变现有控制栏布局、按钮集合和进度条结构；中央提示容器只扩展动态内容。
14. 采用“共享播放核心 + Mobile/Desktop 输入控制器 + 窄全屏端口”的组合式架构，不建立继承式平台控制器树。

## 3. 目标与非目标

### 3.1 目标

- 为 Windows 建立完整、一致、可测试的键盘和鼠标操控模型；
- 彻底停止 Windows 播放画面对移动端高级手势的响应；
- 把播放器生命周期、播放命令和输入状态拆成边界清晰的单元；
- 让 Android 触摸与 Windows 键鼠复用同一套播放、Seek、音量和倍速业务规则；
- 支持 Windows 原生全屏及进入前窗口状态恢复；
- 保持菜单、弹窗、Slider 和可访问性焦点不被页面快捷键抢占；
- 对短按/长按、窗口失焦、页面销毁和异步全屏竞争建立确定性收口；
- 保持当前本地/远端媒体资源、GoRouter 路由和 `MediaLibrary` 行为不变。

### 3.2 非目标

- 不重做播放器控制栏视觉或布局；
- 不新增快捷键设置页、用户自定义映射或持久化输入偏好；
- 不新增常驻倍速快捷键；
- 不新增播放列表、上一集/下一集、字幕、音轨、逐帧、章节或画面缩放；
- 不根据 Windows 指针来源动态切换移动端手势；
- 不让 Windows 触摸屏保留 Android 双击、长按或横拖行为；
- 不拦截系统音量键并同时修改播放器音量；
- 不替换 `video_player` 或 `video_player_win`；
- 不修改媒体资源模型、媒体路由参数、Sync 协议或 `MediaLibrary`；
- 不把输入 controller、`FocusNode`、Timer、窗口对象或 UI 瞬态存入 Riverpod、SQLite 或 SharedPreferences；
- 不扩展到图片查看器或其他 feature 的桌面操控。

## 4. 方案比较与结论

### 4.1 继承式平台控制器

该方案建立 `BaseVideoPlayerController`，再派生 Mobile 与 Desktop 子类。形式直观，但基类必须暴露大量供子类组合的内部状态和受保护方法。移动端拖动字段与桌面按键字段仍容易进入同一个基类 state，最终只是把当前大控制器拆成三个相互依赖的大类。

该方案不采用。

### 4.2 共享播放核心 + 平台输入控制器

该方案让共享核心独占播放器控制和跨平台业务规则，让 Mobile/Desktop controller 只把平台输入翻译为共享命令。窗口全屏通过窄端口接入，页面负责组合 UI、焦点和交互层。

共享的是稳定的播放能力，变化的是输入方式；各单元能独立测试，且平台输入 state 不会污染共享 state。该方案为批准方案。

### 4.3 全部使用 Flutter Shortcuts/Actions

`Shortcuts`/`Actions` 很适合无状态快捷键，但右方向键需要按下、计时、重复、松开、失焦取消和临时倍速所有权。若把这些状态分散在 Intent、Action 和页面 State 中，边界会比独立输入 controller 更难理解。

Flutter 焦点系统仍用于事件作用域和冒泡，但不作为全部状态管理方案。

## 5. 总体架构与依赖方向

```text
VideoPlayerPage
├── VideoPlaybackController
│   └── VideoPlayerController
├── MobileVideoInteractionController
│   └── MobileVideoSystemUiController
├── DesktopVideoInteractionController
│   └── VideoFullscreenController
└── VideoPlayerControls / VideoCenterHint
```

页面在一次生命周期内只创建一种平台输入 controller：Android 创建 Mobile，Windows 创建 Desktop。两个 controller 不同时存活，也不支持运行时热切换。

依赖规则如下：

1. `VideoPlaybackController` 不知道 Windows、Android、键盘、鼠标、手势识别器或窗口插件；
2. Mobile/Desktop controller 依赖共享核心的公开命令，不直接调用 `VideoPlayerController`；
3. `VideoPlayerPage` 可以读取共享核心暴露的底层 controller 以构建 `VideoPlayer` Widget，但不能绕过共享核心修改其状态；
4. `VideoFullscreenController` 是 media presentation 所有的窄端口，Windows app/platform adapter 实现它；
5. `MobileVideoSystemUiController` 是 media presentation 所有的窄端口，Android app/platform adapter 负责 `SystemChrome` 沉浸式与方向操作；
6. 平台选择发生在 app composition/router，不根据 `LocalMediaResource` 或 `NetworkMediaResource` 猜测平台；
7. media application/domain 不导入 Flutter 输入、`window_manager`、`video_player` 或平台适配代码；
8. `window_manager` 只允许出现在 app/platform adapter 和 bootstrap 初始化路径，不进入共享播放核心或 media application。

## 6. 组件职责

### 6.1 VideoPlayerPage

`VideoPlayerPage` 继续是唯一页面 owner，负责：

- 创建并释放共享播放核心和当前平台输入 controller；
- 持有播放表面、顶部控制栏和底部控制栏的 `FocusNode`；
- 组合播放画面、中央提示、控制栏和平台交互层；
- 把 Flutter `KeyEvent`、pointer、hover、scroll、tap 和 gesture details 转交给对应输入 controller；
- 保持 PopupRoute/Dialog 的键盘优先级；
- 在控制栏隐藏后恢复不可见焦点；
- 把共享状态投影到现有控制栏 Widget；
- 通过同一关闭命令完成全屏恢复和 route pop。

页面不保存与共享核心重复的播放事实值，也不直接操作底层播放器。

### 6.2 VideoPlaybackController

共享核心唯一拥有以下职责：

- 创建、初始化、重试、监听、暂停和释放 `VideoPlayerController`；
- 维护初始化、错误、播放、结束、位置、时长和缓冲状态；
- 播放/暂停与结束后从零重播；
- 相对 Seek、绝对 Seek 和边界 clamp；
- 进度条拖动开始、预览、提交与取消；
- 常驻倍速和临时倍速；
- 音量、显式静音、静音恢复和最后非零音量；
- 控制栏显示、隐藏和自动隐藏计时；
- 结构化中央反馈及其生命周期；
- 初始化重试、应用生命周期暂停和 dispose 的幂等清理。

共享核心不包含以下平台输入字段：

- 双击位置或屏幕左右半区；
- 触摸长按状态；
- 横拖起点、像素位移或系统手势取消标志；
- 物理/逻辑按键集合；
- 右方向键长按计时器；
- 鼠标 hover、滚轮或光标状态；
- 原生全屏窗口状态。

### 6.3 MobileVideoInteractionController

移动端输入 controller 负责：

- 单击切换控制栏；
- 记录双击落点并选择左右 15 秒 Seek；
- 申请和释放 Android 长按临时 3 倍速；
- 管理水平拖动起点、Seek 预览与松手提交；
- 把 pointer cancel 转换为拖动回滚；
- 在手势期间隐藏控制栏、结束后恢复手势前状态；
- 配合 `systemGestureInsets` 避让 Android 系统边缘手势。

现有取消感知横拖识别器可保留在 Mobile 路径，但 Windows 不构建该识别器。

### 6.4 DesktopVideoInteractionController

桌面输入 controller 负责：

- 把 Windows 按键 down/repeat/up 序列翻译为共享命令；
- 管理右方向键短按/长按互斥状态；
- 管理鼠标活动、控制栏 hover 和光标显隐；
- 把垂直滚轮翻译为 5% 音量步进；
- 请求原生全屏切换和退出；
- 在窗口失焦、页面关闭、重试和 dispose 时取消所有进行中的桌面输入；
- 控制哪些事件被处理，哪些交还 Flutter 焦点系统或平台。

它不保存播放器位置、音量、常驻倍速或播放状态副本，只读取共享核心快照并调用命令。

### 6.5 平台 bindings factory

app composition 提供页面级 bindings factory。每次打开视频时由页面 State 调用一次，生成互不共享瞬态的 bindings：

- Windows：Desktop interaction 配置 + 新的 `VideoFullscreenController` 会话；
- Android：Mobile interaction 配置 + 新的 `MobileVideoSystemUiController` 会话。

bindings factory 通过 app router 传入媒体视频 route adapter，再传给 `VideoPlayerPage`。测试显式注入 Mobile/Desktop bindings 和 Fake 端口。route 仍只携带规范化相对路径，bindings 不进入 URL、route state、Provider state 或媒体会话。

## 7. 共享播放状态与命令契约

### 7.1 状态分层

共享 UI 快照包含：

- controller 与初始化/错误状态；
- `isPlaying`、`hasEnded`；
- `currentPosition`、`totalDuration`、`bufferedPercent`；
- `persistentSpeed` 与当前有效速度；
- `volume`、`isMuted`、`lastNonZeroVolume`；
- 控制栏显隐和进度 Slider 拖动状态；
- 当前结构化中央反馈。

Mobile/Desktop 私有状态不得并入该快照。共享快照可以是 controller 私有 mutable state 的只读投影，但不得演变成 Riverpod application state。

### 7.2 Seek

共享命令接收明确的 `Duration offset`，统一执行：

1. 拒绝未初始化、错误或无 controller 状态；
2. 基于共享核心的最新位置计算目标；
3. 将目标 clamp 到 `[Duration.zero, totalDuration]`；
4. 调用一次 `seekTo`；
5. 生成包含实际 offset、方向和目标位置的中央反馈。

平台只决定 offset：

- Android 双击：`-15s` 或 `+15s`；
- Windows 左右键：`-5s` 或 `+5s`。

不得为两个平台复制 clamp、结束态修正或提示逻辑。

### 7.3 常驻与临时倍速

共享核心区分：

- `persistentSpeed`：由顶部倍速菜单选择，取值继续使用现有列表；
- `effectiveSpeed`：底层播放器当前实际速度；
- temporary speed lease：由某个输入 owner 暂时覆盖常驻倍速。

临时倍速使用 owner 身份建立和释放：

```text
beginTemporarySpeed(owner, 3.0)
endTemporarySpeed(owner)
```

契约如下：

1. Android 长按与 Windows 右键长按使用不同 owner；
2. 只有当前 owner 能释放自己的临时倍速；
3. 错误 owner 的结束请求是无副作用操作；
4. 临时状态中修改常驻倍速时，只更新 `persistentSpeed`；临时状态结束后恢复最新常驻值；
5. dispose、初始化重试和生命周期暂停强制清理所有临时 lease；
6. 播放未开始、已暂停、已结束或错误时不申请临时 3 倍速；
7. 清理和重复释放必须幂等。

本次只有一个临时 lease 可以处于 active；不设计叠加或优先级队列。

### 7.4 音量与静音

音量始终 clamp 到 `[0.0, 1.0]`，桌面步进固定为 `0.05`。共享状态区分显式 `M` 静音与用户把音量手动调到零：

- 音量大于零时按 `M`：保存当前非零音量，设置显式静音并把底层音量设为零；
- 显式静音时再次按 `M`：恢复 `lastNonZeroVolume`，清除显式静音；
- 用户通过 Slider 直接设置音量时先清除显式静音；设置为零不标记为显式静音，也不覆盖最后非零音量；
- 非静音状态通过步进把音量降到零时同样不标记为显式静音，也不覆盖最后非零音量；
- 非显式静音且当前为零时按 `M`：恢复最后非零音量；
- 显式静音时按 `↑`/`↓` 或滚轮：先以 `lastNonZeroVolume` 为基准解除静音，再应用 `+5%`/`-5%`；
- 手动零音量时按 `↑`：从 0% 增加到 5%；按 `↓` 仍为 0%；
- 任何大于零的有效音量写入都会更新 `lastNonZeroVolume`；
- 若会话从未出现非零音量，恢复默认使用 100%。

每次音量命令更新同一个结构化反馈；不创建多个叠加提示或高频 live region。

### 7.5 控制栏活动

共享核心继续拥有控制栏显隐事实和三秒自动隐藏计时。平台 controller 通过语义化命令表达活动：

- Mobile 单击可显式 toggle；手势开始/结束可暂存并恢复；
- Desktop 鼠标活动、键盘播放命令和滚轮可请求显示并重置计时；
- 控制栏 hover、控制栏内键盘焦点、菜单或音量弹窗打开时暂停自动隐藏；
- 暂停、播放结束或错误状态不自动隐藏控制栏；
- Desktop 隐藏控制栏时同步隐藏光标，Mobile 不管理桌面光标。

控制栏隐藏后必须继续退出 pointer、focus 和 semantics；若隐藏前焦点位于控制栏，下一帧恢复到播放表面。

## 8. 结构化中央反馈

中央提示从固定枚举升级为携带数据的 presentation 模型，至少表达：

- 相对 Seek：方向、实际秒数和目标位置；
- Seek 预览：目标位置；
- 临时倍速：有效倍速；
- 音量：百分比与静音状态；
- 原生全屏切换失败：安全、可重试的固定消息。

暂停图标继续从共享播放状态派生，不需要创建长期反馈。

可见文本和 Semantics 必须使用反馈中的实际值：

- Android 双击播报“已快进/快退 15 秒”；
- Windows 方向键播报“已快进/快退 5 秒”；
- 音量显示实际百分比；
- 静音显示“已静音”，恢复显示恢复后的实际百分比；
- 临时倍速显示实际 `3.0x`。

离散 Seek、静音和临时倍速可以使用单一 live region。按键重复或滚轮产生的连续音量变化只更新同一节点，不生成节点队列；Seek 拖动预览仍不高频播报。

## 9. Windows 键盘状态机

Flutter 硬件键盘事件采用规则化序列：一个 `KeyDownEvent`、零个或多个 `KeyRepeatEvent`、一个 `KeyUpEvent`。右方向键长按以本地 400ms 计时判定，不以系统首次 repeat 的时间判定，从而不受 Windows 键盘重复设置影响。

### 9.1 映射与作用域

| 输入 | 作用域 | 行为 |
|---|---|---|
| `Space` | 播放表面主焦点 | 播放/暂停；忽略 repeat |
| Media Play/Pause | 播放表面主焦点 | 播放/暂停；忽略 repeat |
| `←` down | 播放表面主焦点 | 立即快退 5 秒 |
| `←` repeat | 播放表面主焦点 | 已处理但无播放副作用 |
| `→` down/up | 播放表面主焦点 | 进入短按/长按互斥状态机 |
| `↑`/`↓` down/repeat | 播放表面主焦点 | 音量 ±5% |
| `M` | 视频页面且无更高层弹层 | 切换播放器静音；忽略 repeat |
| `F` | 视频页面且无更高层弹层 | 切换原生全屏；忽略 repeat |
| `Enter` | 播放表面主焦点 | 切换控制栏显隐；忽略 repeat |
| `Escape` | 视频页面回退作用域 | 弹层优先，其次退出全屏，最后关闭页面 |

控制栏按钮、PopupMenu、Dialog 和 Slider 持有焦点时，Space、Enter 和方向键交给当前控件，不被播放表面处理。`M`/`F` 只在没有 PopupRoute/Dialog 等更高层弹层时由视频页面处理；弹层先获得按键机会。系统音量键不映射到播放器音量。

### 9.2 右方向键短按/长按

状态机包含 `idle`、`pending` 和 `longHold` 三种稳定状态，并为“达到长按阈值但当前不能加速”保留已分类标志。

```text
idle
  └─ KeyDown → pending，启动 400ms timer，不 Seek

pending
  ├─ 400ms 前 KeyUp → 取消 timer，快进 5 秒，回 idle
  ├─ repeat → 保持 pending，无播放副作用
  └─ timer 到期 → 本次输入分类为长按
       ├─ 正在正常播放 → 申请 Desktop owner 的临时 3x，进入 longHold
       └─ 暂停/结束/错误 → 不申请倍速，但保持“已分类为长按”

longHold 或已分类长按
  ├─ repeat → 无播放副作用
  └─ KeyUp/失焦/关闭/dispose → 释放 Desktop lease（若有），回 idle，不 Seek
```

补充约束：

1. down 期间再次收到异常 down 不重启 timer；
2. 达到阈值后即使未能启动 3 倍速，松开也不补做 5 秒 Seek；
3. 短按在暂停状态仍允许快进 5 秒；
4. 临时加速期间播放暂停或结束时可以提前释放 lease，后续 KeyUp 仍幂等收口；
5. Windows 窗口失焦必须按长按取消路径处理，不等待可能丢失的 KeyUp；
6. 播放表面失去主焦点时同样取消 pending/longHold，不执行短按 Seek；这覆盖 Tab 到控制栏、鼠标打开菜单或 Dialog 后 KeyUp 被新焦点接收的情况；
7. 页面初始化重试或底层 controller 替换前必须先取消 pending/longHold。

### 9.3 左方向键

- 首个 `KeyDownEvent` 立即快退 5 秒；
- 后续 `KeyRepeatEvent` 不再 Seek；
- `KeyUpEvent` 只清理 pressed 标志；
- 不设置 timer，不提供连续快退，不与右方向键共享长按分类。

### 9.4 上下方向键

- `↑` 每个 down/repeat 增加 5%；
- `↓` 每个 down/repeat 减少 5%；
- 达到 0% 或 100% 后继续事件保持边界值，不重复调用底层 controller；
- 音量命令显示控制栏/反馈并重置桌面活动计时；
- Slider 或其他控制持有焦点时不由播放表面截获。

## 10. Windows 鼠标状态机

### 10.1 单击与双击

- 单击播放画面：播放/暂停，并把焦点恢复到播放表面；
- 双击播放画面：切换原生全屏，不播放/暂停、不 Seek；
- Flutter 识别器必须让一次双击只产生双击结果，不能先触发两次单击；
- 右键、中键和按住拖动画面没有播放器行为；
- 进度 Slider 的鼠标拖动继续有效，不属于全屏画面拖动手势。

### 10.2 鼠标活动、控制栏与光标

- 播放器初始化后控制栏和光标可见；
- 鼠标在播放区域移动时显示控制栏和光标，重置三秒计时；
- 正在播放且鼠标静止三秒时隐藏控制栏和光标；
- 暂停、播放结束、加载或错误时保持控制栏/光标可见；
- pointer 位于顶部/底部控制栏内时暂停隐藏；
- 控制栏内有键盘焦点、PopupMenu 或音量 Dialog 打开时暂停隐藏；
- pointer 离开控制栏且控制栏内无焦点/弹层时恢复计时；
- 页面关闭、窗口失焦和错误恢复时强制恢复系统默认光标，不能留下不可见 cursor。

光标显隐使用 Flutter 播放区域的 `MouseRegion` cursor，不修改 Windows 全局 cursor。

### 10.3 滚轮音量

- 只处理播放区域内的垂直 `PointerScrollEvent`；
- 向上滚增加 5%，向下滚减少 5%；
- `scrollDelta.dy == 0` 或以水平分量为主的事件忽略；
- 每次被接受的事件只产生一个 5% 步进，不按 delta 像素线性放大；
- 使用 50ms leading-edge 节流：窗口内首个有效事件立即执行，其余事件忽略；
- 该上限防止高分辨率滚轮和触控板一次动作产生音量风暴，同时允许持续滚动连续调节；
- 滚轮调音量不强制改变当前键盘焦点，但视为桌面活动并显示控制栏/光标。

## 11. 焦点与弹层优先级

### 11.1 初始焦点

Windows 播放器初始化成功并出现播放表面后的下一帧自动请求播放表面焦点。加载态和错误态不抢焦点；重试成功后重新请求。

Android 不新增自动硬件键盘焦点，保留既有首次 Tab 进入播放表面的可访问性行为。

### 11.2 焦点恢复

- 鼠标单击播放画面后请求播放表面焦点；
- PopupMenu 或音量 Dialog 关闭后恢复播放表面焦点；
- 控制栏被手动或自动隐藏时，若焦点仍在隐藏控制内，下一帧恢复播放表面；
- 仅鼠标移动或滚轮调音量不抢走按钮、Slider 或其他当前焦点；
- 页面已卸载或新的弹层已获得焦点时，延迟恢复回调不得再次抢焦点。
- 播放表面主动失焦时先通知 Desktop controller 取消在途方向键状态，再允许焦点进入控制栏或弹层。

### 11.3 Escape

回退优先级固定为：

1. PopupMenu/Dialog 等最上层 route 自己关闭；
2. 没有弹层且 Windows 当前或期望处于原生全屏时，只退出全屏，留在播放器；
3. 已是窗口模式时，恢复视频全屏会话原始状态并 pop 视频 route。

顶部关闭按钮、窗口模式 `Escape` 和系统 route back 都调用同一页面关闭命令，避免一条路径遗漏窗口恢复。

## 12. Windows 原生全屏

### 12.1 端口

media presentation 定义窄 `VideoFullscreenController`，表达：

- 开始一次播放器窗口会话并记录初始状态；
- 查询缓存的实际/期望全屏状态；
- 切换期望全屏状态；
- 如果当前或期望为全屏则退出；
- 恢复会话初始状态并释放；
- 报告外部全屏进入/退出事件；
- 把插件失败转换为安全结果，而不是把平台异常泄漏到 Widget。

Windows adapter 使用 `window_manager: ^0.5.0` 的 `ensureInitialized()`、`isFullScreen()`、`setFullScreen()` 和窗口事件。`VideoPlayerPage`、共享播放核心和 Desktop 输入 controller 不直接 import 插件。

### 12.2 初始化

- 仅 Windows 生产 bootstrap 调用一次 `windowManager.ensureInitialized()`；
- 测试 bootstrap 注入 no-op/fake window runtime，不能依赖 Flutter test 中注册原生插件；
- Android 不初始化或调用桌面窗口 API；
- 每个 `VideoPlayerPage` 创建独立全屏 controller 会话，但不重复初始化插件 runtime。

### 12.3 原始状态与所有权

打开视频时记录 `initialFullscreen`，但不自动改变窗口状态：

- 初始窗口模式：播放中进入全屏，关闭视频时恢复窗口模式；
- 初始全屏：播放中允许退出全屏，关闭视频时恢复全屏；
- 播放期间外部窗口操作改变全屏状态时，窗口事件校准实际状态，但关闭视频仍恢复 `initialFullscreen`；
- Alt+Tab 或普通窗口失焦不退出全屏，只取消 pending 输入和临时倍速；
- 初始化失败但页面仍存在时不改变窗口状态。

正常 `setFullScreen(false)` 交由窗口管理器恢复进入全屏前的大小、位置和最大化状态。本功能不另行持久化或手动重放窗口 bounds。

### 12.4 异步串行化

全屏命令维护 `actualState` 与 `desiredState`。输入先更新 desired，再进入单一串行队列；后续输入依据 desired 而不是尚未更新的 actual 计算。

例如快速输入 `F → F → Escape` 时，命令按顺序收敛到最后期望状态，不因第一次平台调用尚未返回而连续发送三个“进入全屏”。

契约如下：

1. 同时最多一个 `setFullScreen` 平台调用在途；
2. 已满足 desired 时不重复调用插件；
3. 由当前在途命令预期产生的窗口事件只更新 actual，并继续收敛到既有 desired；
4. 没有平台命令在途时收到的外部窗口事件同时更新 actual 与 desired，接受用户或系统改变而不立即弹回；关闭页面仍恢复 initial；
5. 页面关闭首先把 desired 设置为 initial，再等待恢复命令完成后 pop；
6. State `dispose` 不能 await，必须触发幂等 fallback restore，覆盖外部强制移除 route 的路径；
7. 重复 restore/dispose 不重复改变窗口；
8. 页面卸载后平台 Future 完成不得调用页面 `setState`。

### 12.5 失败语义

插件调用失败时：

- 不伪造 actual 已改变；
- 不因为全屏失败关闭或暂停视频；
- 若失败命令尚未被更新输入取代，则把 desired 回退到已确认 actual，避免队列无限重试；若已有更新输入，则保留更新后的 desired 并继续串行收敛；
- 通过现有中央反馈显示固定文案“无法切换全屏”；
- 下一次用户输入可以重新尝试；
- 关闭页面恢复失败时仍允许 route 退出，但记录安全日志，不能把用户困在播放器。

## 13. Android 等价迁移

Android 继续保持：

- 单击切换控制栏；
- 双击左/右半屏快退/快进 15 秒；
- 长按播放画面临时 3 倍速，松开恢复最新常驻倍速；
- 水平拖动只更新 Seek 预览，松手提交一次 `seekTo`；
- pointer cancel 回滚预览且不提交；
- 播放画面手势层避让 `systemGestureInsets`；
- 手势期间隐藏控制栏，结束后恢复手势前状态；
- Android 沉浸式系统 UI、允许方向和退出后恢复；
- 外接键盘的 `Enter`、`Space`、左右 15 秒和 `Escape` 可访问性路径。

Android 不获得 Windows 的：

- 右方向键 400ms 临时 3 倍速状态机；
- 上下方向键播放器音量；
- `M` 或 `F`；
- 鼠标 hover、cursor 或滚轮；
- Windows 原生全屏端口。

Android 外接键盘左右键继续在 `KeyDownEvent` 上立即 Seek 15 秒，并忽略 repeat；不得因共享 Desktop 状态机而改成 KeyUp 后执行。

移动端 `SystemChrome` 操作迁移到 Mobile system UI adapter 后，进入、应用暂停、退出和异常销毁的可观察行为必须与迁移前一致。

## 14. 生命周期与取消矩阵

| 事件 | 共享核心 | Mobile controller | Desktop controller | 全屏会话 |
|---|---|---|---|---|
| 初始化重试 | 清理临时倍速、替换 controller | 取消手势/预览 | 取消按键 timer、恢复 cursor | 保持窗口状态 |
| 应用 inactive/paused | 暂停播放、清理临时倍速 | 取消在途手势 | 取消 pending/hold | 不自动退出全屏 |
| Windows 窗口失焦 | 保持当前播放策略，释放临时倍速 | 不适用 | 取消 pending/hold、恢复 cursor | 保持全屏 |
| 播放结束 | 显示控制栏、清理临时倍速 | 长按/拖动收口 | hold 收口、恢复 cursor | 保持全屏 |
| route 正常关闭 | dispose controller | 取消全部手势 | 取消全部输入 | await 恢复 initial 后 pop |
| route 强制移除 | 幂等 dispose | 幂等 dispose | 幂等 dispose | unawaited 幂等 fallback restore |

窗口失焦以 Windows window event 或可靠的 desktop lifecycle 信号触发；不得仅依赖可能保留 primary focus 的 Flutter `FocusNode`。

## 15. 错误处理与日志

- 视频初始化错误继续使用现有 inline 页面错误和“重试”按钮；
- 播放命令在未初始化/错误状态下安全 no-op，不抛到 Widget tree；
- 全屏失败使用中央固定消息，不显示插件异常、路径或系统细节；
- controller factory、媒体资源和网络错误语义不因本设计改变；
- 异步完成必须检查 controller/session generation，旧初始化或旧全屏命令不得覆盖新会话；
- 非预期平台窗口错误写入现有安全日志路径，日志不得包含媒体敏感 header；
- 失焦、KeyUp、dispose 多次到达必须幂等，不视为错误。

## 16. 测试设计

### 16.1 共享核心单元测试

使用 Fake `VideoPlayerController` 验证：

- 相对 Seek 的前后边界 clamp；
- Android 15 秒与 Windows 5 秒只是不同参数；
- 暂停、播放、结束后重播；
- 音量每次 5% 并 clamp 到 0%–100%；
- 显式静音保存并恢复最后非零音量；
- 手动降到零不覆盖最后非零音量；
- 显式静音时上下调音先恢复记忆音量再应用步进；
- 手动零音量时上调从 5% 开始、下调保持零；
- 临时 3 倍速结束后恢复最新常驻倍速；
- 错误 owner 不能释放当前 lease；
- dispose、重试和生命周期暂停清理 lease；
- 结构化反馈包含实际秒数、目标位置、音量和静音状态；
- 边界无变化时不重复调用底层音量 setter。

### 16.2 Desktop 输入 controller 单元测试

使用 fake clock/timer 和 fake playback/fullscreen 端口验证：

- 右键 down 不立即 Seek；
- 400ms 前 KeyUp 只快进 5 秒；
- 400ms 到期且播放中只申请 3 倍速，不 Seek；
- repeat 不改变短按/长按分类；
- 暂停、结束或错误时长按不加速，松开不补 Seek；
- KeyUp、窗口失焦、播放结束、重试和 dispose 恢复临时倍速；
- 播放表面在 pending/hold 中失焦时取消输入、不 Seek，并让迟到 KeyUp 成为无副作用事件；
- 左键 down 只快退一次，repeat 不重复 Seek；
- 上下键 down/repeat 每次调音 5%；
- `Space`、`M`、`F` 和媒体键 repeat 无副作用；
- 非播放表面焦点时 Space、方向键和 Enter 返回 ignored；
- 失焦后迟到的 KeyUp 不产生 Seek 或重复恢复；
- 快速重复全屏输入按 desired 状态排队。

不得用真实 400ms 等待、任意 `Future.delayed` 或 Windows 键盘重复设置驱动测试。

### 16.3 Windows Widget 测试

- 初始化成功后播放表面自动获得焦点；
- 单击只播放/暂停并恢复表面焦点；
- 双击只切换全屏，不附带单击结果或 Seek；
- Windows 不安装移动端长按与横拖 Seek；
- 鼠标移动显示控制栏与光标；
- 播放中静止三秒隐藏，暂停/结束/hover/focus/弹层时保持；
- 垂直滚轮按 5% 调音，水平滚动忽略，50ms 节流生效；
- `M` 的中央反馈与顶部音量 tooltip 同步；
- `Escape` 按弹层、全屏、页面顺序分发；
- 菜单/Dialog 关闭后恢复表面焦点；
- 控制栏隐藏后不可 pointer/focus/semantics 访问；
- 全屏失败显示安全反馈且播放器继续可用。

### 16.4 全屏 adapter 测试

使用 fake window runtime 验证：

- 初始窗口模式与初始全屏两种会话；
- `F`/双击切换；
- `Escape` 的 exit-if-fullscreen；
- 快速 `F → F → Escape` 串行收敛；
- 外部 enter/leave event 校准 actual；
- 页面关闭恢复 initial；
- 正常关闭与 dispose fallback 重复到达仍幂等；
- 平台调用失败不伪造 actual、不无限重试；
- Future 在页面销毁后完成不触发 UI 更新。

### 16.5 Android 回归测试

保留并强化现有测试以证明：

- 双击左右半屏仍为 ±15 秒；
- 长按仍申请 Android owner 的临时 3 倍速并恢复常驻倍速；
- 暂停或播放结束时长按不切换倍速；
- 横拖只在松手提交一次 Seek；
- pointer cancel 回滚且不 Seek；
- 系统手势边缘不被播放器抢占；
- 单击仍切换控制栏，而不是播放暂停；
- Android 方向/沉浸式进入退出行为不变；
- Android 外接键盘左右仍立即 15 秒 Seek；
- Android 不响应 Windows 的 `M`、`F`、滚轮或右键 hold。

### 16.6 真实平台 smoke

Windows 手工验证至少覆盖：

- 本地视频正常初始化、播放、暂停和退出；
- 左右 5 秒、右键短按/长按互斥、上下音量与 `M`；
- 单击、双击、鼠标活动、滚轮和 cursor 隐藏；
- F/双击原生全屏、全屏 Escape、窗口模式 Escape；
- 初始最大化/窗口模式进入全屏再退出后的窗口恢复；
- Alt+Tab 时临时 3 倍速取消但全屏保持；
- 关闭播放器后恢复打开视频前的全屏状态；
- Debug 与 Release 中至少一个本地视频样本。

Android 手工验证至少覆盖远端视频的单击、双击、长按、横拖、返回边缘和退出后方向恢复。

未实际执行手工 smoke 时必须明确标记 pending；Widget 测试、构建或插件 API 测试不能替代真实窗口与设备验证。

## 17. 预计文件边界

最终实施计划可以调整不影响职责的文件名，但不得改变以下边界：

| 位置 | 职责 |
|---|---|
| `lib/features/media/presentation/pages/video_playback_controller.dart` | 共享播放核心与共享 UI 快照 |
| `lib/features/media/presentation/pages/mobile_video_interaction_controller.dart` | Android 触摸/外接键盘输入状态机 |
| `lib/features/media/presentation/pages/desktop_video_interaction_controller.dart` | Windows 键盘/鼠标输入状态机 |
| `lib/features/media/presentation/pages/video_player_platform_bindings.dart` | 平台 bindings、全屏与移动系统 UI 窄端口 |
| `lib/features/media/presentation/pages/video_player_page.dart` | 页面组合、Focus、Widget/pointer 事件转发 |
| `lib/features/media/presentation/widgets/video_player_controls.dart` | 动态中央反馈渲染，现有控制栏布局保持 |
| `lib/features/media/presentation/pages/media_route_pages.dart` | 将 app composition 提供的 bindings factory 传入播放器 |
| `lib/app/platform/windows_video_fullscreen_controller.dart` | `window_manager` adapter 与全屏会话队列 |
| `lib/app/platform/android_video_system_ui_controller.dart` | Android SystemChrome/方向会话 |
| `lib/app/router/app_router.dart` | 注入页面级平台 bindings factory |
| `lib/bootstrap.dart` | 仅 Windows 初始化 window runtime，保留测试注入 seam |
| `pubspec.yaml` | 添加兼容 Flutter 3.44 的 `window_manager: ^0.5.0` |

现有 `video_player_gesture.dart` 与 `video_player_state.dart` 在职责迁移完成后删除或改名，不保留兼容转发壳。不得让新旧 controller 同时成为播放状态来源。

测试按生产职责镜像拆分；不得把所有新增单元与 Widget case 继续塞入现有单个大文件。现有产品契约测试可迁移到对应新文件，但删除前必须指出承接同一契约的后继测试。

## 18. 验证门禁

实施完成前至少执行：

1. 新增共享核心、Desktop controller、全屏 adapter 的定向测试；
2. `test/features/media` 全目录测试；
3. app router、bootstrap 与 composition 相关测试；
4. `dart run tool/check_import_boundaries.dart`；
5. `flutter analyze`；
6. 全量 `flutter test --reporter compact`，按仓库规则重定向到 `logs/fltest.log`；
7. Windows Debug 与 Release build；
8. Windows 和 Android 手工 smoke，或明确记录尚未执行的项目。

所有 Flutter 测试、分析和构建日志写入仓库 ignored 的 `logs/`，不得在根目录生成散落日志。缺陷回归测试必须提供修复前失败、修复后通过的 red/green 证据。

## 19. 验收标准

1. Windows 播放画面不再响应 Android 双击 Seek、长按 3 倍速或横拖 Seek；
2. Windows 左右键按 5 秒规则工作，右键短按/长按互斥且不发生额外 Seek；
3. Windows 左键 repeat 不连续快退；
4. Windows 上下键与垂直滚轮按 5% 调音并正确 clamp；
5. `M` 能恢复静音前音量，手动零音量与显式静音语义明确；
6. Windows 单击播放/暂停，双击/F 切换原生全屏；
7. 全屏 `Escape` 只退出全屏，窗口模式 `Escape` 关闭视频；
8. 打开视频前的全屏状态在关闭视频后恢复；
9. 快速全屏输入、窗口失焦、迟到 KeyUp、重试和 dispose 不留下错误状态；
10. Windows 初始化成功后快捷键无需先点击即可使用；
11. 菜单、Dialog、按钮和 Slider 不被播放快捷键抢占；
12. 控制栏/光标按桌面活动规则显隐，暂停和结束态保持可见；
13. Android 单击、双击 15 秒、长按、横拖、系统边缘与方向恢复行为不变；
14. 共享播放核心是底层播放器命令的唯一 owner，Mobile/Desktop 不复制播放规则；
15. 平台选择只发生在 app composition，不从媒体资源类型推断；
16. application/domain 不依赖 presentation、窗口插件或平台输入；
17. 定向测试、媒体测试、架构门禁、analyze、全量测试和 Windows build 通过；
18. 真实 smoke 的完成与 pending 状态如实记录。

## 20. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 短按右键在 KeyUp 才 Seek，产生轻微延迟 | 这是与纯长按 3 倍速互斥的明确产品取舍；400ms 内松开立即执行 |
| Windows 丢失 KeyUp 后一直 3 倍速 | 窗口失焦、生命周期、播放结束、重试和 dispose 都强制释放 Desktop lease |
| 双击先触发单击导致播放状态变化 | 使用互斥 tap/double-tap 识别并做 Widget 回归测试 |
| 快速 F/Esc 读取陈旧全屏状态 | actual/desired 分离并串行化平台调用 |
| 页面关闭时异步恢复未完成 | 正常关闭 await 恢复；dispose 提供幂等 fallback |
| 初始全屏被播放器错误退出 | 记录 `initialFullscreen`，关闭始终恢复初始值 |
| 桌面快捷键抢 Slider/menu/dialog | 表面快捷键要求主焦点，页面级 M/F/Esc 服从 PopupRoute 优先级 |
| 高频触控板滚动导致音量暴涨 | 每事件固定 5% 且 50ms leading-edge 节流 |
| 平台字段再次聚合到共享 state | Mobile/Desktop 瞬态私有，测试和文件边界单独审查 |
| Android 在重构中行为漂移 | 先用旧测试锁定行为，再做等价迁移并补平台差异断言 |
| window plugin 在 Flutter test 未注册 | bootstrap/window runtime 可注入，自动测试使用 Fake/No-op |

## 21. 设计完成定义

本设计完成并可进入实施计划的条件是：

- 产品映射、短按/长按时序、焦点作用域和全屏恢复语义均已明确；
- 共享核心、平台 controller 和窗口端口的所有权明确；
- Android 保持项与 Windows 禁用项逐项列明；
- 错误、生命周期和异步竞争有单一收口；
- 测试层级、真实 smoke 和非目标清晰；
- 文档中没有占位符、互相矛盾的映射或超出范围的隐式功能。
