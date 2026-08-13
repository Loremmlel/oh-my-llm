# 渐进式响应式设计系统与媒体网格设计

**日期：** 2026-08-13

**状态：** 已批准，已按书面审阅意见修订，待复审

**范围：** 应用级响应式设计基础设施 + 媒体浏览器首个完整落地

## 1. 背景

当前媒体浏览器使用固定三列网格：

```dart
SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)
```

该实现没有根据父级可用空间调整列数。手机竖屏下三列尚可使用，但 Windows 窗口越宽，单个文件夹和媒体卡片就越大；桌面屏幕增加的空间没有转化为更多可见项目，反而降低了信息密度。

项目并非没有响应式基础。现有代码已经具备：

- 按布局职责命名的 `AppBreakpoints`；
- 使用父约束的 `AdaptiveMasterDetailLayout`；
- shell、Chat、Settings、Sync 和 Media 的响应式视口测试；
- Windows 与 Android 共用的媒体 presentation 与 application 状态。

真正缺少的是一套覆盖令牌、布局原语、feature 策略、偏好默认值和验证方式的统一约束。只把媒体网格改成更多固定列，或按 Windows/Android 写两个分支，只能修复当前症状，不能防止其他页面重复出现同类问题。

## 2. 已确认的产品与架构决定

1. 建立应用级的响应式设计基础设施，而不是只修媒体网格。
2. 采用“完整基础设施、渐进迁移”：媒体浏览器作为首个完整样板，旧页面不做大爆炸式重写。
3. 布局根据组件实际获得的空间决策，不根据 Windows、Android、手机、平板或桌面等设备标签决策。
4. 平台只影响尚无用户选择时的默认密度；用户偏好一旦存在，以用户偏好为准。
5. 媒体浏览器支持紧凑、标准、舒适三种密度，Windows 默认紧凑，Android 默认标准。
6. 宽布局在右上角显示互斥密度按钮；紧凑布局收敛为一个“显示密度”菜单，避免挤占 AppBar。
7. 媒体密度是设备本地 UI 偏好，不参与 Settings export、局域网同步或跨设备迁移。
8. 共享设计系统不内置媒体业务默认值；媒体 feature 将自身策略映射为共享网格规格。
9. 不追求消灭所有数字。只有跨 feature 重复、具有稳定语义，或影响响应式、一致性、可访问性的值才进入共享令牌。

## 3. 目标与非目标

### 3.1 目标

- 为跨平台页面提供统一的空间测量与布局决策方式；
- 防止宽窗口中的卡片、表单和正文无限拉伸；
- 让响应式规则表达布局职责，而不是设备类别；
- 建立少量可复用、可独立测试的布局原语；
- 让媒体网格随可用宽度自动增加或减少列数；
- 支持媒体密度切换、平台默认值和设备本地持久化；
- 保持目录、媒体会话、缩略图和路由行为不因密度切换而重启；
- 建立统一视口矩阵、边界测试和无障碍约束；
- 允许现有页面在后续改动中按需渐进迁移。

### 3.2 非目标

- 一次性替换全项目所有 `EdgeInsets`、圆角、字号或尺寸字面量；
- 建立 `mobile/tablet/desktop` 全局设备枚举；
- 根据窗口宽度等比缩放整个 UI 或字体；
- 覆盖系统文字缩放或改变现有用户正文字号设置；
- 在本次迁移 Chat、Settings、History、Favorites 或 Sync 的全部页面；
- 新建一个同时持有平台、窗口、主题和业务状态的全局响应式管理器；
- 增加一个粗暴禁止所有固定列数或数字字面量的静态扫描；
- 改变媒体目录读取、缩略图生成、图片查看、视频播放或随机播放协议；
- 将媒体密度偏好同步到其他设备。

## 4. 方案比较与结论

### 4.1 只增加几个共享响应式组件

该方案改动小，可快速修复媒体网格。但间距、内容宽度、交互尺寸、密度默认值和测试矩阵仍各自为政，长期只能形成新的零散 helper。该方案不足以达到统一约束的目标。

### 4.2 一次性建立设计系统并全量迁移

该方案理论上一致性最高，但当前代码中存在大量合理的局部几何参数。机械替换会产生巨大 diff，并把视觉回归、行为变化和目录迁移混在一起，难以审查与验证。该方案风险过高，不采用。

### 4.3 完整基础设施、媒体首落地、旧页面渐进迁移

该方案先定义令牌、布局原语、偏好边界和测试契约，再让媒体浏览器完整使用。新代码遵循统一约束；旧页面仅在被修改或确认存在问题时迁移。它既提供长期架构，也保持本次范围可验证，因此为批准方案。

## 5. 设计原则

### 5.1 空间优先于设备

组件使用 `LayoutBuilder` 读取父级 `BoxConstraints`。只有应用壳层等确实拥有窗口级职责的组件才读取窗口宽度。不得用平台、横竖屏或硬件类别替代可用空间。

### 5.2 语义优先于数值

断点和令牌必须描述用途，例如 shell 导航切换、内容限宽、表单主从布局、最小交互区域。不得新增含义模糊的 `compact` 全局断点或 `desktopWidth`。

### 5.3 共享机制与业务策略分离

共享网格只计算布局，不知道媒体文件、收藏或设置卡片。Feature 负责选择密度和卡片规格，并将其传给共享原语。

### 5.4 视觉密度与命中区域分离

紧凑模式可以缩小可见图标、卡片和间距，但不能让触摸、鼠标或键盘操作失去合理的命中区域、焦点状态或 Semantics。

### 5.5 渐进迁移

共享基础设施必须能与现有页面共存。不得为了目录整齐或令牌覆盖率而顺带重写无关 feature。

## 6. 总体架构

响应式设计系统按职责分为三层，继续使用项目现有目录边界，不新建包罗万象的 `design_system` 模块。

```text
core/constants
  固定基础令牌 + 语义断点
            │
            ▼
core/widgets
  无业务含义的响应式布局原语
            │
            ▼
features/<feature>/presentation + application
  feature 布局规格、偏好状态与业务内容
```

### 6.1 基础令牌层

职责：定义稳定、跨 feature 可复用的视觉与布局语义。

首批范围：

- `AppSpacing`；
- `AppRadii`；
- `AppContentWidths`；
- `AppInteractionSizes`；
- 现有 `AppBreakpoints`。

这些类型是不可实例化的常量容器，不读取 `BuildContext`、平台、主题或业务状态。

### 6.2 响应式原语层

职责：根据调用方提供的规格和父约束构建布局。

首批范围：

- `AppAdaptiveGrid`；
- `AppConstrainedContent`；
- `AppAdaptiveActions`；
- 现有 `AdaptiveMasterDetailLayout` 的契约对齐。

本次只有 `AppAdaptiveGrid` 必须被媒体生产页面使用。其他原语建立最小、可测试的公共契约，不要求立刻迁移全部旧页面。

### 6.3 Feature 策略层

职责：拥有业务密度偏好、内容比例、可见字段与平台默认值映射。

媒体 feature 负责：

- `MediaGridDensityController`；
- 三种密度到共享网格规格的映射；
- 密度操作入口；
- `MediaFileTile` 在已分配空间内的呈现。

### 6.4 单向数据流

```text
app composition 覆盖 mediaGridDensityDefaultProvider
                    │
SharedPreferences ──┼──> MediaGridDensityController
                    │             │
                    │             ▼
                    │      MediaAdaptiveGridSpec
                    │             │
                    │             ▼
父级 BoxConstraints ─────> AppAdaptiveGrid
                                  │
                                  ▼
                           列数、项目宽度、间距
```

平台判断只允许出现在 app composition 的默认值绑定处。媒体 presentation、共享网格和媒体卡片不得根据平台分支布局。

## 7. 基础令牌

### 7.1 间距

`AppSpacing` 提供有限的基础阶梯：

| Token | 值 |
|---|---:|
| `xxs` | 4 |
| `xs` | 8 |
| `sm` | 12 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |

共享组件使用这些阶梯；业务组件仍可保留有明确局部原因的特殊值。基础阶梯不随窗口或密度自动缩放，密度策略通过选择不同 token 组合表达差异。

### 7.2 圆角

`AppRadii` 首批提供：

| Token | 值 |
|---|---:|
| `sm` | 8 |
| `md` | 12 |
| `lg` | 18 |
| `xl` | 24 |

本次不强制迁移现有 `AppTheme` 或全部 Card。该令牌用于新增共享原语，并在后续触及相关组件时逐步替换重复语义。

### 7.3 内容宽度

`AppContentWidths` 首批提供：

| Token | 值 | 用途 |
|---|---:|---|
| `readable` | 720 | 长文本和说明内容 |
| `form` | 900 | 单个设置表单或编辑表单 |
| `wide` | 1200 | 需要更多横向信息但不应无限拉伸的内容 |

`AppConstrainedContent` 默认使用 `readable`，调用方必须按内容职责显式选择其他上限。

### 7.4 交互尺寸

`AppInteractionSizes` 区分可见尺寸与命中区域：

- `minimumHitTarget = 48`；
- `compactVisualControl = 32`；
- `standardVisualControl = 40`。

紧凑可见控件必须通过外层约束、padding 或 Material 行为保持合理命中区域。现有普通 Material 控件不重复包裹无价值 Semantics。

### 7.5 断点与字体

现有 `AppBreakpoints` 的 shell、content、dialog、form、bubble 语义和“等号属于宽侧”规则保持不变。只有出现新的结构切换职责时才新增 token；媒体网格连续计算列数，不新增“媒体桌面断点”。

字体继续来自 `ThemeData.textTheme`。现有 `bodyFontSize` 设置保持生效，系统 `TextScaler` 不被覆盖。窗口变宽或变窄不直接改变字体大小。

## 8. 密度模型

### 8.1 共享值对象，不设全局开关

Core 提供 `AppLayoutDensity` 值对象：

```text
compact
standard
comfortable
```

该类型可以被多个 feature 复用，但不对应一个全局 Provider。每个 feature 独立决定是否暴露密度选择、如何持久化以及如何映射规格。

媒体使用独立的 `MediaGridDensityController` 持有 `AppLayoutDensity`。切换媒体密度不会改变 Chat、Settings 或其他页面。

### 8.2 平台默认值

media application 声明 `mediaGridDensityDefaultProvider`，其无 override 默认值为
`standard`，保证独立测试与未来平台安全退化。生产环境由
`appCompositionOverrides()` 根据 `defaultTargetPlatform` 覆盖该 provider：

- Windows：`compact`；
- Android：`standard`；
- 其他平台：`standard`。

`MediaGridDensityController` 读取该 provider，并先检查设备本地持久化值；只有值缺失或无法识别时才使用注入默认值。Feature application/presentation 均不读取 `defaultTargetPlatform`，平台判断只留在 app composition。

### 8.3 持久化

媒体密度使用 SharedPreferences 的独立 key
`app.feature.media.grid_density` 和显式字符串编解码。该命名空间固定采用
`app.feature.<feature>.<preference>`，避免未来其他 feature 的设备本地偏好
与通用设置 key 混杂：

- 只存 `compact`、`standard`、`comfortable`；
- 未知值回退平台默认值；
- 选择仅在当前设备生效；
- 不加入 Settings export/import；
- 不加入 Sync 协议；
- 不复制到会话、目录或媒体 domain 模型。

持久化失败属于非关键 UI 偏好失败：当前运行继续使用内存选择，不阻塞浏览，也不弹出侵入式错误。下次启动若仍无有效持久化值，则再次采用平台默认值。

## 9. 自适应网格

### 9.1 公共规格

`AppAdaptiveGrid` 接收不可变规格，至少包含：

- `maxCrossAxisExtent`；
- `crossAxisSpacing`；
- `mainAxisSpacing`；
- `padding`；
- feature 提供的 `mainAxisExtentBuilder`，根据项目宽度与当前
  `BuildContext` 解析本轮统一行高；
- builder、item count 和可选 scroll controller/key。

它必须使用 `LayoutBuilder` 的父约束，不读取整窗宽度，不读取平台，也不持有业务状态。

### 9.2 列数算法

给定：

- 父级最大宽度 `W`；
- 左右 padding 合计 `P`；
- 横向间距 `S`；
- 项目最大宽度 `M`。

先得到 `usable = max(0, W - P)`。列数判定使用固定的
`layoutTolerance = 0.5` 逻辑像素，吸收窗口缩放与 DPI 换算在临界宽度产生的
亚像素抖动：

```text
columns = max(1, ceil(((usable + S) - layoutTolerance) / (M + S)))
itemWidth = max(0, (usable - S * (columns - 1)) / columns)
```

容差只参与离散列数判定，不修改 Flutter 下发的实际约束。因此在临界区间内，
`itemWidth` 最多比 `M` 大 `layoutTolerance`；超过该区间后必须增加一列。
窗口变宽时通过增加列数吸收空间；窗口变窄时减少列数；极窄场景保底一列。
`W` 必须有限，`M` 必须为有限正数，spacing 与 padding 必须为有限非负数；
无效规格在 debug 下断言失败。

布局计算应提取为不依赖 Widget 的纯值对象或纯函数，由 `AppAdaptiveGrid` 消费，以便精确覆盖边界测试。

### 9.3 高度与文字缩放

Flutter 的 regular sliver grid 会为同一布局中的所有 child 下发相同
`childMainAxisExtent`。共享网格不允许某个 child 通过 intrinsic measurement
反向改变单独一格的高度；feature 必须在构造 grid delegate 前解析出统一行高。

媒体新增纯 presentation 规格解析器 `MediaGridTileMetrics.resolve(...)`。它接收：

- 当前密度对应的 `MediaGridTileSpec`；
- 已由网格算法算出的 `itemWidth`；
- `ThemeData` 中的文件名与辅助文字样式；
- 当前 `MediaQuery.textScalerOf(context)`。

它使用 `TextPainter.preferredLineHeight` 取得经过 `TextScaler` 处理的典型单行
高度，再按下式得到本轮所有 tile 共用的 `mainAxisExtent`：

```text
contentWidth = max(0, itemWidth - 2 * tilePadding)
thumbnailHeight = contentWidth / thumbnailAspectRatio
titleHeight = scaledTitleLineHeight * maxTitleLines
sizeHeight = scaledSizeLineHeight
mainAxisExtent = 2 * tilePadding
               + thumbnailHeight
               + thumbnailMetadataGap
               + titleHeight
               + metadataLineGap
               + sizeHeight
```

文件夹虽然没有文件大小，也预留同样的辅助文字行高度；短文件名也预留当前
密度允许的最大标题行数。这样同一网格内的目录、短名称、长名称和带缩略图
文件始终使用同一行高，内容差异不会造成错位或布局抖动。

`MediaFileTile` 消费已经解析的 metrics，在固定 thumbnail/metadata 区域内呈现
内容；它本身不测量并反向通知父级。放大文字时统一行高随 metrics 增加，
不得通过缩小字体解决溢出。文件名使用密度规定的最大行数和省略号，完整名称
通过 Semantics/tooltip 可达。Card 设为零外边距，网格 spacing 独占项目间距，
避免默认 Card margin 成为行高公式外的隐式几何。

### 9.4 懒构建与状态

`AppAdaptiveGrid` 使用 `GridView.builder` 和计算后的
`SliverGridDelegateWithFixedCrossAxisCount`；固定列 delegate 用于同时传入容差
算法得出的列数和 metrics 得出的统一 `mainAxisExtent`。它不把未知长度列表展开
为完整 children。

Windows 实时拖动窗口时，约束变化可以触发 `LayoutBuilder` 和可见 tile 的
正常 build；本设计不承诺 build context 永不重建。性能契约是：

- `GridView` 的 key、scroll controller 和 PageStorage identity 保持稳定；
- tile 根节点使用 `ValueKey(item.relativePath)`，不得使用 `UniqueKey`；
- item 顺序发生变化的调用方提供按稳定 key 查 index 的 callback，使已有 state
  能映射到新位置；仅改变列数不改变 item 顺序；
- 宽度变化只更新 grid delegate/metrics，不重建 ProviderScope，不修改媒体会话、
  `FileItem` 或 `MediaThumbnailRequest` identity；
- 可见 tile 在窗口缩放期间不得因为布局更新重复调用媒体库解析同一缩略图；
- 不为所有离屏 tile 强制 keep-alive。正常滚出惰性 viewport 的 tile 仍可释放，
  避免用无限缓存换取拖拽性能；
- 不主动清理 Flutter image cache、媒体库磁盘缩略图缓存或现有资源缓存。

Widget 重建次数不是验收目标；可观察目标是滚动位置与子项状态保持、缩略图不
重复解析，以及 profile-mode 窗口拖动无持续严重卡顿。

## 10. 媒体网格规格

媒体缩略图区域统一采用 `4:3`（宽:高），图片与视频继续使用
`BoxFit.cover`；文件夹和回退图标在同一区域居中。媒体将三种密度映射为下列
首批规格：

| 密度 | 最大卡片宽度 | 横纵间距 | 外层 padding | tile padding | 缩略图比例 | 文件名行数 | 主要用途 |
|---|---:|---:|---:|---:|---:|---:|---|
| `compact` | 160 | 8 | 8 | 8 | 4:3 | 1 | 桌面快速浏览大量文件 |
| `standard` | 220 | 12 | 12 | 12 | 4:3 | 2 | 常规图库与手机默认布局 |
| `comfortable` | 360 | 16 | 16 | 16 | 4:3 | 2 | 强调缩略图和预览 |

这些值是产品规格，不按设备再次改写。平台差异只体现在首次默认密度。

`MediaFileTile` 保持单一职责：

- 文件夹显示文件夹图标；
- 图片/视频使用现有懒解析缩略图；
- 失败时回退文件类型图标；
- 展示文件名和可用的文件大小；
- 不读取平台、窗口宽度或持久化偏好。

密度切换只改变网格规格和卡片约束，不改变 `FileItem`、当前目录、导航历史、媒体会话或资源 provider 的业务 identity。

## 11. 密度操作入口

媒体 Tab 可见且会话可用时，AppBar actions 增加媒体密度入口，并与现有随机播放 actions 共存。

### 11.1 宽布局

使用三个互斥的 Material 3 `IconButton`：

- 紧凑；
- 标准；
- 舒适。

当前选择提供 selected 状态、可见焦点、tooltip 和非重复 Semantics。鼠标、触摸与键盘都能切换。

### 11.2 紧凑布局

使用一个“显示密度”菜单按钮，菜单内展示三个互斥选项和当前选择。紧凑/宽
布局的切换由 `AppAdaptiveActions` 使用现有 shell 导航语义统一解析，不新增
媒体专属设备断点。

### 11.3 组合边界

媒体 presentation 提供窄的 `MediaGridDensityActions`，分别构造展开按钮组和
紧凑菜单。App composition 将这两个分支包装为 `AppAdaptiveActions`，交给
`AppShellScaffold`；媒体内部 presentation 不直接读取 shell 宽度或控制应用壳。

## 12. 共享布局原语

### 12.1 AppConstrainedContent

接收最大内容宽度、padding、alignment 和 child。在父宽度超过上限时保持内容限宽并对齐；窄宽度下使用全部可用空间。它不自动决定内容角色，调用方显式选择 `AppContentWidths` token。

### 12.2 AppAdaptiveActions

`AppAdaptiveActions` 是不可变的响应式 action 规格，接收宽侧 actions、紧凑
fallback 和语义断点。`AppShellScaffold` 新增可选的 `adaptiveActions` 参数，
在其现有顶层 `LayoutBuilder` 中把有界窗口宽度交给该规格解析，再与固定
`actions` 合并放入 AppBar。

该原语不在 AppBar 的 action `Row` 内另建 `LayoutBuilder`，因为 action 子项
未必获得适合判断整页模式的有界横向约束。空间测量由 shell 负责，分支内容与
阈值由 `AppAdaptiveActions` 负责。它也不自行把任意按钮塞进 overflow menu；
紧凑 fallback 必须由业务提供，以保证菜单文案和操作优先级可审查。媒体密度
入口是首个生产消费者，现有固定 actions API 保持兼容。

### 12.3 AdaptiveMasterDetailLayout

保留现有 API 与 `AppBreakpoints.contentMasterDetail` 默认值。实现和文档对齐“父约束决策、等号属于宽侧”的统一规则；本次不迁移无关调用方。

## 13. 错误与退化策略

| 场景 | 行为 |
|---|---|
| 密度偏好缺失 | 使用 app composition 注入的平台默认值 |
| 持久化字符串未知 | 忽略该值并使用平台默认值 |
| SharedPreferences 写入失败 | 当前运行保留内存选择，不阻塞媒体浏览 |
| 极窄父约束 | 网格退化为一列，不横向溢出 |
| 系统文字放大 | 重新解析全网格统一 `mainAxisExtent`，不覆盖 TextScaler、不缩小字体 |
| 密度切换 | 保持目录、历史、会话、资源 identity 与滚动状态 |
| 缩略图失败 | 单 tile 回退图标，不升级为网格级错误 |
| 加载、目录错误或空目录 | 继续沿用现有 MediaGridView 状态呈现 |

密度是非关键 UI 偏好，不为其增加 SnackBar、Dialog 或媒体 inline 错误卡。媒体目录与资源错误模型不因本设计改变。

## 14. 渐进迁移与项目约束

### 14.1 本次生产迁移

- 新增基础令牌；
- 新增共享响应式原语及其测试；
- 对齐现有 `AdaptiveMasterDetailLayout` 契约；
- 新增媒体密度 controller 与设备本地存储；
- 将 `MediaGridView` 从固定三列迁移到 `AppAdaptiveGrid`；
- 增加宽/紧凑密度 actions；
- 扩充媒体响应式、状态与无障碍测试；
- 更新 AGENTS/相关设计文档中的响应式规则。

### 14.2 暂不迁移

Chat、Settings、History、Favorites、Sync 的现有稳定页面不因本设计批量替换 padding、圆角或字号。后续修改相关组件时遵循“触及即评估”：只有重复语义或真实响应式问题才迁移到共享令牌/原语。

### 14.3 开发规则

新增或修改响应式页面时：

1. 根据父级可用空间决策，不根据平台设备标签决策；
2. 结构切换使用语义断点，连续网格优先使用尺寸约束；
3. 全宽正文、表单和卡片在宽屏上评估合理最大宽度；
4. 列表与网格使用 builder；
5. 关键页面覆盖统一视口矩阵；
6. 固定列数若确有业务语义可以保留，但必须由局部契约解释；
7. 不为追求令牌覆盖率替换合理的业务局部尺寸。

本次不增加全仓数字扫描或禁止所有 `SliverGridDelegateWithFixedCrossAxisCount` 的 lint。自动门禁应验证外部契约，不能以宽泛规则制造误报。

## 15. 测试设计

### 15.1 基础令牌与断点

- 保持现有 shell/form/bubble 等号边界测试；
- 为新增具有分支行为的 token 覆盖断点前、等号、断点后；
- 常量值只在它构成公开设计契约时断言一次。

### 15.2 网格计算

纯函数/值对象参数化覆盖：

- 宽度小于单卡上限时一列；
- 恰好容纳一列/两列的边界；
- 每个列数临界点的 `-0.5`、等号、`+0.5` 容差边界与刚越过容差的值；
- `411.42857142857144` 等长小数父宽度，重复计算结果稳定；
- padding 与 spacing 参与后的列数；
- 390、720、844、960、1440 等代表宽度；
- 宽度增加时列数不减少；
- 每个有效结果的项目宽度不超过“上限 + 0.5 逻辑像素”，且只有容差临界区
  可以超过名义上限；
- 零宽约束安全退化；
- 非正最大卡片宽度触发 debug 断言。

### 15.3 共享组件

- 嵌套在限宽父组件内时使用父宽度，不误用 `MediaQuery` 整窗宽度；
- 运行时改变父约束会重新排布；
- item builder 保持惰性；
- 重排不丢失具有稳定 identity 的子项状态；
- 可见子项在仅改变父宽度时保持稳定 key，且不重复触发对应缩略图解析；
- `AppAdaptiveActions` 在边界等号遵循宽侧规则。

### 15.4 密度 controller

- Windows 无持久化值默认紧凑；
- Android 无持久化值默认标准；
- 已保存偏好覆盖平台默认值；
- 三个合法字符串 round-trip；
- 未知字符串回退默认值；
- 偏好不进入 Settings export/import。

### 15.5 媒体 presentation 与 composition

- 三种密度分别映射正确的媒体规格；
- 每种密度使用 4:3 缩略图和规定的文件名最大行数；
- 同一密度、项目宽度和 TextScaler 下，目录、短文件名、长文件名与带大小文件
  解析出同一个 `mainAxisExtent`；
- 增大 TextScaler 后全网格统一行高增加，长名称仍受最大行数约束；
- 宽布局显示互斥密度 actions；
- 紧凑布局显示密度菜单；
- selected、tooltip、键盘焦点和 Semantics 正确；
- 切换密度不调用媒体库、不重建会话、不改变当前路径；
- 目录、图片、视频和缩略图失败行为保持不变；
- 放大文字时无布局异常且完整名称可访问；
- Windows 与 Android 的媒体 Tab 均能切换密度。

Widget 测试不使用 `getTopLeft()`、`getRect()` 或像素位置比较。列数精确契约由纯布局算法测试承担；Widget 层验证可见行为、状态与无异常。

### 15.6 统一视口矩阵

至少覆盖：

| 场景 | 视口 |
|---|---|
| 紧凑竖屏 | 390×844 |
| Android 低高度横屏 | 844×390 |
| shell 边界前/等号/后 | 719、720、721 宽 |
| 普通 Windows 窗口 | 960×640 |
| 宽桌面 | 1440×900 或更高 |
| 放大文字 | 代表视口 + `TextScaler` 放大 |

### 15.7 手工 smoke

Windows：

1. 在 960px 和 1440px 宽度打开同一目录，确认卡片不会随窗口无限放大；
2. 在 profile mode 实时拖动窗口，确认列数稳定增减、无临界点闪烁、无溢出，
   且没有持续严重卡顿或重复缩略图解析；
3. 切换三种密度，确认目录与滚动状态保持；
4. 使用鼠标、键盘操作密度入口；
5. 关闭重开应用，确认设备本地偏好恢复。

Android：

1. 竖屏和横屏打开同一目录；
2. 确认默认标准密度；
3. 通过紧凑菜单切换密度；
4. 放大系统文字后确认无溢出；
5. 关闭重开应用，确认本机偏好恢复。

## 16. 实施顺序与提交边界

1. 基础令牌、网格计算与共享原语；
2. 媒体密度状态与持久化；
3. 媒体网格接入与密度 actions；
4. 响应式、无障碍和组合测试；
5. 项目规范与相关文档更新。

每个功能点独立提交。实现阶段遵循测试驱动：先用聚焦测试证明固定三列和缺失偏好契约的问题，再写最小实现并保留 red/green 日志证据。

## 17. 验收标准

以下条件全部满足才算实现完成：

1. 媒体网格不再使用固定三列作为生产布局；
2. 960px 与 1440px Windows 窗口中，卡片宽度不超过当前密度规格上限加
   0.5 逻辑像素容差，额外空间转化为更多列；
3. 极窄宽度保底一列且无横向溢出；
4. Windows 默认紧凑，Android 默认标准；
5. 用户可在两个平台切换紧凑、标准、舒适密度；
6. 已保存偏好覆盖平台默认值，并且不跨设备同步；
7. 密度切换不重新加载目录、不重建媒体会话、不改变当前路径；
8. 共享网格只依赖父约束和调用方规格，不读取平台或媒体状态；
9. 媒体卡片不读取窗口宽度、平台或持久化偏好；
10. 宽/紧凑操作入口具有 selected、tooltip、键盘和 Semantics 状态；
11. 同一网格内所有媒体 tile 使用由当前密度、项目宽度、主题和 TextScaler
    统一解析的确定行高；单个 tile 内容不能改变本行高度；
12. 系统文字缩放保持生效且代表视口无布局异常；
13. 窗口缩放不重复解析仍可见项目的同一缩略图，且不清理既有图片/磁盘缓存；
14. 新增令牌与原语遵循现有 core/app/feature import 边界；
15. import boundary、`flutter analyze`、定向测试和全量测试通过；
16. Windows 与 Android 手工 smoke 已执行，或明确标记 pending 而不声称视觉验收完成。

## 18. 风险与控制

| 风险 | 控制 |
|---|---|
| 设计系统变成全局常量仓库 | 令牌进入条件明确，局部业务尺寸继续留在 feature |
| 平台判断重新泄漏到组件 | 默认值由 app composition 注入，presentation 只消费状态 |
| 密度切换导致网络或缩略图重载 | 保持 item/resource identity，只替换布局规格 |
| 临界宽度受浮点误差影响而闪烁 | 列数判定使用 0.5 逻辑像素容差并覆盖长小数边界 |
| 子 tile 内容尝试撑高 regular grid | 上游 metrics 统一解析 `mainAxisExtent`，tile 只消费约束 |
| 为避免 rebuild 而无限 keep-alive | 允许正常 build，只保持稳定 identity 和可见资源解析；离屏项仍惰性释放 |
| 紧凑模式损害可访问性 | 可见尺寸与命中区域分离，覆盖键盘与 Semantics 测试 |
| 固定宽高导致文字放大溢出 | 媒体行高考虑 TextScaler，不缩小系统字体 |
| 一次性迁移产生大规模视觉回归 | 本次只完整迁移媒体，其他页面触及时评估 |
| 过度自动门禁制造误报 | 不扫描全部数字或固定列数，验证共享契约和关键页面行为 |
| 密度偏好跨平台互相覆盖 | 使用设备本地 key，不纳入导出或同步 |

## 19. 范围审计

本设计建立响应式基础设施，并用媒体浏览器验证整条链路。它不改变媒体数据来源、同步安全、路由参数、图片/视频资源协议、播放器实现、聊天布局或设置业务模型。

如果实施中发现必须全量迁移现有页面、修改一级导航、改变 Settings export 格式、引入跨设备 UI 偏好同步，或重写媒体资源生命周期，均视为超出本设计，必须停止并请求新的范围批准。
