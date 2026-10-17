# UI 残留问题修整进度

依据：[审计报告快照](ui-audit-report-2026-10-17.md)，原文件来自 `C:/Users/HinanawiYuzu/.gemini/antigravity/brain/569af8ce-58ba-412e-844b-1e7ca5ef26a9/ui_audit_report.md`。

用户于 2026-10-17 明确指定：与 `DESIGN.md` 冲突时，以审计报告为准。保留墨绿主色、暖白画布、现有业务能力及数据格式，修整控件外观与页面组织。

## 进度

| 分组 | 工作 | 状态 | 实现与验证 |
| --- | --- | --- | --- |
| 基线 | 独立 Flutter 浏览器预览及截图 | 已完成 | 从修改前 Git HEAD 归档源码，使用相同内存夹具构建；已有聊天、设置、编辑器与 Agent 基线 |
| 全局 | 暖灰中性色、完整组件主题、字距、阅读字号、语义颜色与圆角 | 已完成 | `AppTheme`、`AppUiColors`、`AppRadii.tag`、`readingMarkdownStyle` |
| 共享 | 上置字段标签、分段控件、选中底、提示与返回最新按钮 | 已完成 | `AppInputLabel`、`AppTextField`、`AppDropdownField`、`AppTextTab`、`AppInlineNotice`、`AppScrollToLatestButton` |
| A 外壳 | 手机底栏、中宽图标导航、宽屏导航统一 | 已完成 | 底栏细线与中性选中底，中宽仅图标，宽屏上下入口复用同一导航项 |
| B 聊天 | 画布、正文与操作行、元信息、推理、异常与空状态 | 已完成 | 正文默认 16px；操作在正文下方；正常 stop 不显示；异常提示用细色条 |
| C 输入 | 输入边界、编辑提示、发送停止、次级设置、移动面板 | 已完成 | 16 圆角输入边界与局部淡阴影；40px 箭头/停止按钮；中性次级设置；面板分段与列表入口 |
| D 侧栏 | 历史平铺、预设复选框、选择器与抽屉 | 已完成 | 单行会话、无缝列表、复选框启停、上置标签与扁平抽屉 |
| E 设置 | 宽屏分类导航、编辑列表、表单、能力与其它设置 | 已完成 | 七分类纵向导航；字段共享标签；能力复选框；轻量排序按钮 |
| F 历史收藏 | 选中底、收藏夹、批量工具栏与详情动作 | 已完成 | 保留收藏夹响应式网格，图标次级色、名称宋体；批量工具栏细边框 |
| G Agent | 步骤、任务块、文档标签与职责勾选 | 已完成 | 共用用户输入底、阅读字号和返回最新；文档下划线标签；职责复选框 |
| H 同步等 | 同步状态、接口、过滤与检查点、通知 | 已完成 | 去除硬编码状态色；过滤复选框；次级动作描边；通知主题语义色与细边框 |
| 规范 | 同步更新 `DESIGN.md` | 已完成 | 消息操作移至正文下方；设置宽屏纵向导航；字段与语义颜色归属 |
| 验证 | 格式、分析、导入门禁、相关测试、构建与视觉检查 | 已完成 | 本轮最终 1936 项测试通过；分析、格式、导入门禁、Web/Windows Release 构建通过；共 33 张截图已核对 |
| 交付 | 受影响页面统计与前后截图索引 | 已完成 | 14 类路由页面；33 张截图，9 组基线对比及 2 组本轮复核对比 |

## 视觉检查约定

桌面 1440×1000、中宽 900×900、手机 390×844；检查浅色与深色。基线和结果采用相同示例数据与视口。截图保存在 ignored 的 `logs/ui-audit/`。浏览器夹具直接调用生产组件，不依赖真实服务商或个人资料。

## 页面与截图

按 `app_router.dart` 的页面类型计数，新建与编辑使用同一种页面时只计一次：6 个顶层入口、8 类子页面，共 14 类路由页面共享主题。其中 11 类有直接组件或布局调整；聊天图片预览、媒体图片与视频查看 3 类以共享主题变化为主。设置 7 个页签、Agent 3 个视图、同步 3 个页签记录在所属页面内，不重复计为独立路由。

| 路由页面类型 | 影响 |
| --- | --- |
| 对话 | 消息、输入区、历史/预设侧栏、上下文过滤与检查点 |
| 历史对话 | 选中底、批量工具栏、分页字段与重命名 |
| 设置 | 七分类导航、三类提示词、表单、模型能力、输出规则与其它设置 |
| 预设编辑、世界书编辑 | 上置标签、字段网格、排序与选中条目 |
| Agent、子任务详情 | 任务与阅读正文、步骤、返回最新、文档与配置 |
| 收藏夹总览、收藏夹内容、收藏全文 | 标题、图标、选中底、批量工具栏与详情动作 |
| 同步工作区 | 连接/同步/媒体页签、状态、表单、分段与媒体缩略图圆角 |
| 聊天图片预览、媒体图片、媒体视频 | 共享按钮、浮层与 Slider 主题；媒体查看页圆角等值改用 token，视频画面上的白色叠加控件保留 |

### 截图与复现

[完整截图画廊](E:/Code/oh-my-llm/logs/ui-audit/screenshots.md) 收录 33 张截图：基线 9 张、首轮结果 19 张、本轮复核结果 5 张。首轮 9 组基线对比，加上本轮 2 组复核前后对比，均按相同示例数据与视口并排展示；最新效果位于画廊首节。

| 内容 | 基线与结果 | 尺寸 |
| --- | --- | --- |
| 聊天、服务商、其它设置、预设编辑、世界书编辑、Agent | 6 组对比 | 1440×1000 |
| 聊天浅色、聊天深色、世界书编辑 | 3 组对比 | 390×844 |
| 设置手机/中宽、角色下拉菜单 | 结果补充 | 390×844 / 900×900 |
| 模型表格、Agent 文档、历史、收藏、同步连接/同步操作/媒体 | 结果补充 | 1440×1000 |
| 本轮导航与输入区、短窗口、无网卡提示及深色手机 | 2 组复核对比与 3 张补充 | 900×900 / 1440×1000 / 900×300 / 390×844 |

基线冻结自 `859eb8c57f9424811c5b0e7cd722ad79444b5aec`，归档源码位于 `logs/ui-audit/baseline-source/`。当前与基线共用内存示例夹具，直接调用生产页面和组件，通过独立 Flutter Web 构建在 Codex 内置浏览器中截图；没有启动原生应用、读取个人数据库或调用服务商。

当前预览入口：`logs/ui-review/audit_preview.dart`；基线入口：`logs/ui-audit/baseline-scaffold/lib/audit_preview.dart`。两个 scaffold 分别是 `logs/ui-review/generated-scaffold/`、`logs/ui-audit/baseline-scaffold/`。构建命令（在各自 scaffold 内运行）：

```powershell
# 当前预览
flutter build web --release --no-wasm-dry-run --target ../audit_preview.dart --output E:/Code/oh-my-llm/logs/ui-audit/after-web
# 基线预览
flutter build web --release --no-wasm-dry-run --target lib/audit_preview.dart --output E:/Code/oh-my-llm/logs/ui-audit/baseline-web
```

两份构建分别通过仅监听 `127.0.0.1` 的静态服务提供；浏览器启用 Flutter 无障碍语义后操作组件。页面参数：`surface=chat`、`surface=settings&tab=0`、`surface=settings&tab=5`、`surface=chat&page=preset`、`surface=forms`（选择编辑世界书）、`surface=agent`、`surface=browse`、`surface=browse&view=favorites`、`surface=sync&tab=0/1/2`；`dark=1` 切换聊天深色夹具。`surface=settings&tab=6` 是夹具占位，不作为世界书页面截图。

本次完成 Windows 编译与离线 UI 验证；原生运行、Android 软键盘/IME、真实服务商、媒体播放和跨设备同步未执行。媒体截图采用透明示例缩略图，展示布局和控件。

## 验证记录

首轮代码检查（2026-10-17，包含下拉菜单阴影修正；本轮复核记录见下节）：

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| Dart 格式与只读格式检查 | 108 个改动 Dart 文件，0 个待格式化 | `logs/ui-audit/format-final.log`、`format-check-final.log` |
| `flutter analyze --no-pub` | 0 问题 | `logs/ui-audit/analyze-final.log` |
| 导入边界 | 466 个文件，0 违规 | `logs/ui-audit/import-boundaries-final.log` |
| 仓库有界全量测试 | 1934 项通过，退出码 0 | `logs/ui-audit-full-final.log` |
| 独立 Flutter Web Release 预览 | 构建成功 | `logs/ui-audit/after-build-final.log` |
| Windows Release | 构建成功；没有启动原生程序 | `logs/ui-audit/build-windows.log` |
| `git diff --check` | 通过 | 命令退出码 0 |

- 字段焦点回归：上置标签的展开布局切换曾重建文本字段；改为保留 `Flexible` 身份、只切换 fit。原有模板键盘/组合输入用例修复后通过，日志为 `logs/ui-audit-field-focus-red.log` 与 `logs/ui-audit-field-focus-green.log`。
- 主题回归：归零字距改为逐项设置，避免 `TextTheme.apply` 对未定义字距的断言；主题测试及消费页面通过。日志为 `logs/ui-audit-theme-red.log` 与 `logs/ui-audit-theme-green.log`。
- 下拉帮助回归：保留原有自定义帮助按钮，恢复细线箭头；组件和真实侧栏用例通过。日志为 `logs/ui-audit-dropdown-help-red.log` 与 `logs/ui-audit-dropdown-help-green.log`。
- 浏览器交互：角色菜单展开、Escape 关闭并返回原字段焦点；展开菜单单独指定零 elevation，去除 Flutter Dropdown 的默认阴影。
- 长错误提示：滚动到重试动作后可点击；日志为 `logs/ui-audit-long-error-retry.log`。
- `DESIGN.md` 官方 lint：0 错误、13 个 orphan-token 警告。本项目为运行时 token 模式，没有生成的 token 消费文件；日志为 `logs/ui-audit/design-lint.log`。
- Premium 静态审计按 `lib/` 范围运行 strict 为 0 项；该工具只识别 Web 源码格式，不识别 Dart。本项目依靠 Flutter 检查、行为测试与真实浏览器截图验证。

## 外部 AI 审计复核 · 2026-10-17

先对照当前源码与原审计的实际措辞，再决定修改；保留原报告中的可选方案和适用范围。

| 意见 | 核验与价值判断 | 处理 |
| --- | --- | --- |
| 中宽导航仍为原生 Rail | 部分成立。主题已经显式覆盖暖灰选中底与圆角，原意见所称“默认 M3 胶囊”不准确；结构确实未复用宽屏导航，设置/同步也未沉底。900×300 下还复现 28px 底部溢出。 | 采用同一个导航项，compact 模式只显示图标并提供 tooltip；主入口区可滚动，设置/同步固定底部。 |
| 输入框没有淡阴影 | 事实成立。原报告写的是“可以”，并非必需条件；轻微浮起有助于识别主要输入区，改动局部且成本低。 | 仅聊天输入卡片设 elevation 1、12% 不透明度 shadow；其余卡片继续为 0。 |
| onSecondaryContainer 与圆角数字残留 | 引用存在，但该前景色已在主题中固定为正文墨色，当前没有旧的绿色字问题。语义归属仍应与实际背景一致；等值圆角改用 token 便于统一维护。 | 收藏夹选中内容改用 onSurface；无网卡提示复用 AppInlineNotice 与 warning；聊天锚点、同步、导入确认及媒体查看的 6/8/12/16 圆角收拢到现有 token。 |
| 用户操作按钮应 hover 显示 | 原报告允许“块外右下或 hover”，当前已经满足第一种。常驻操作便于发现、键盘与触屏使用，隐藏还需增加聚焦显隐规则。 | 保留正文下方右对齐、常驻可达的操作。 |
| 世界书详情启用应改复选框 | 当前每次只编辑一个条目，只有一个启停开关；原报告优先改造的是密集启用列表。详情开关沿用统一主题，与其它独立设置项一致。 | 保留独立 Switch；密集列表继续使用复选框。 |

圆角扫描现在仅保留两个有特定控件含义的数字：主题内 Checkbox 小方角 3，以及视频进度轨道圆角 2。组件内没有 `onPrimaryContainer` / `onSecondaryContainer` / `onTertiaryContainer` 直接使用。

短视口回归由 `test/app/shell/app_shell_scaffold_test.dart` 负责：修复前因 RenderFlex 溢出失败，修复后可滚动至收藏入口，切换同步与设置；壳层 10 项测试全部通过。证据：`logs/ui-audit-navigation-red.log`、`logs/ui-audit-navigation-green.log`。原有 720 断点与中宽导航用例改为验证可见入口和路由结果。

全量检查同时暴露了聊天滚动用例的范围假设：它拖动全页首个 Scrollable，新增导航滚动区后实际拖到了导航。将两个聊天滚动用例都限定到 ChatMessagesPanel 后继续验证原有返回最新和锚点行为，首个失败记录保留在 `logs/ui-audit-review-scroll-red.log`。

浏览器补充验证：中宽导航图标名称与 Tab 焦点可达；900×300 无溢出；服务端无网卡提示使用共享 warning；浅色桌面与深色手机输入边界正常。本轮截图位于 `logs/ui-audit/review-followup/`，预览依然使用内存夹具，没有启动真实广播或原生应用。

本轮最终检查：

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| 全量测试 | 1936 项通过，退出码 0；包含两个限定消息区的滚动用例 | `logs/ui-audit-review-full.log` |
| Flutter 分析 | 0 问题 | `logs/ui-audit/review-analyze.log` |
| Dart 格式检查 | 114 个改动 Dart 文件，0 个待格式化 | `logs/ui-audit/review-format-check.log` |
| 导入边界 | 466 个文件，0 违规 | `logs/ui-audit/review-import-boundaries.log` |
| Flutter Web / Windows Release | 两份构建成功 | `logs/ui-audit/review-web-build.log`、`review-windows-build.log` |
| DESIGN 官方 lint | 0 错误、13 个已有 orphan-token 警告 | `logs/ui-audit/review-design-lint.log` |
| Premium strict / diff 空白检查 | 静态审计 0 项；`git diff --check` 通过 | `logs/ui-audit/review-premium-audit.json` |

交付分支为 `fix/ui-audit-refinement`，通过 PR 合入 `master`。截图及夹具保存在 ignored 的 `logs/`，不包含在 Git 提交中；审计报告快照、进度文档和 `DESIGN.md` 随源码保留。PR 正文记录页面统计和最终本地验证结果，远端 CI 状态以 PR 检查为准。截图完成后已关闭临时预览服务。
