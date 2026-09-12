---
version: alpha
name: oh-my-llm
description: 面向长文本阅读与创作的本地 Flutter 工作台
colors:
  primary-light: '#4F46E5'
  primary-dark: '#818CF8'
  background-light: '#F7F7FB'
  background-dark: '#0F1117'
  card-light: '#FFFFFF'
  card-dark: '#171A22'
typography:
  sans:
    fontFamily: 'Noto Sans SC'
spacing:
  small: '8px'
  medium: '16px'
  large: '24px'
rounded:
  control: '18px'
  card: '24px'
components:
  button: {}
  card: {}
  input: {}
  dialog: {}
---

# 设计约定

## Overview

这是 Windows、Android 双端的中文本地 LLM 客户端，主要任务是长文本阅读、对话与写作。当前任务明确增加独立 Agent 工作区；没有日本市场或其他地域业务规则的证据。产品界面保持简体中文，模型与协议名称保留原文。

视觉沿用现有 Material 3 主题。Agent 页顶部区分作品与会话，提供配置、上下文、资料入口和用量元信息；中间按时间展示用户任务、思考、工具与回复，底部固定输入。运行中的子 Agent 在顶部有持续可见的入口，进入独立详情仍可查看完整执行流。工作文档从顶部入口切换，世界书与人物卡可按类型筛选。长文优先于装饰，不另建品牌色或字体系统。

本文件记录现有设计意图，运行时 token 为唯一数值来源（Model B），不从本文生成 Dart 代码。行为约束来源是 AGENTS.md 与 Agent 调研文档。

## Colors

颜色来源为 `lib/app/theme/app_theme.dart`。浅色、深色种子分别对应 frontmatter 的 primary 值；前景、边线、错误色由 `ColorScheme.fromSeed` 派生。页面只消费 `Theme.of(context)`，不复制派生颜色。错误同时带文字，不只使用颜色。

## Typography

字体由 `AppTheme` 统一指定思源黑体，正文使用 `bodyMedium`，标题使用 `titleSmall`。用户字号偏好继续生效；执行记录与文档正文可选择复制。推理与正文分开；活动推理显示末尾预览，可展开全文，已完成推理默认折叠。工具名称使用加粗标签，参数与结果仅一层展开。

## Layout

`AppShellScaffold` 拥有顶层导航；`AppBreakpoints` 拥有 shell 与内容断点。Agent 在窄屏使用相同执行流和顶部入口；表单及长文滚动由各自内容区拥有，不使用平台名称推断布局。

`lib/core/constants/app_layout_tokens.dart` 中 `AppSpacing`、`AppRadii`、`AppContentWidths`、`AppInteractionSizes` 为共享几何来源。新增页面使用 `md=16` 的常规边距、`xs=8` 的紧凑间距；文档编辑使用 `readable=720` 内容宽度上限。代码审查与改动文件静态检查是当前 token 一致性检查方式。

## Elevation & Depth

用户任务使用轻背景块，Agent 输出以现有 SmoothMarkdown 直接铺在执行流中，避免嵌套运行卡片。对话框使用 Material overlay，底层页面不再增加透明玻璃或背景模糊。

## Shapes

输入框和 Card 沿用 `AppTheme` 的 18、24 圆角。页面不自行覆盖全局形状。

## Components

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
| --- | --- | --- | --- | --- |
| 导航 | `AppDestination` / `AppShellScaffold` / GoRouter | AGENTS.md | 独立 `/agent` 与 `workspaces/:workspaceId/runs/:runId` 子路由 | 共享导航测试与页面测试 |
| Select/Listbox | Flutter `DropdownButton` / `DropdownButtonFormField` | Settings 模型表单与本文 | 应用绘制 popup；运行时禁止更改模型；已有历史时通过新会话应用配置 | 页面测试、键盘及 popup 渲染检查 |
| Form | Material `TextField` / `InputDecorationTheme` | 本文与 Agent 运行契约 | 真实 label、保留失败输入、按钮或 Ctrl+Enter 发送；Enter 换行，IME 组合输入期间不发送 | 页面改稿与任务提交测试 |
| Scrollbar | Flutter `ScrollBehavior` / Material `ScrollbarTheme` | AppTheme 与 Flutter 默认 | 使用默认可操作滚动条，不隐藏；各列表独立滚动 | 窄屏页面测试与离线渲染检查 |
| Dialog | Material `AlertDialog` / `AppConfirmDialog` | AGENTS.md | 保存保留旧版，放弃未保存编辑时确认 | 文档修订及历史查看测试 |
| 状态反馈 | Agent runtime 与页面 inline 文本 | AgentRunStatus | 运行、完成、失败、中断、上限、停止；状态变化 live region | runtime、controller 与页面停止测试 |
| 文档版本 | AgentStore | 版本事务 | 历史仅查看，再次保存生成新版本，冲突保留编辑内容 | repository 与页面测试 |
| 配置方案 | AgentConfiguration / AgentStore | 保存的方案版本与会话快照 | 选择职责后编辑对应模型与提示词；共享预设勾选适用职责；保存与应用分别表示持久化和会话采用 | controller 与配置页面测试 |

按钮沿用 Filled（主要动作）、Outlined（次要动作）和带 tooltip 的 IconButton。运行中不能重复提交；停止保持可达。材料控件保留原生焦点、hover、disabled、selected 语义，不重复包裹无效 Semantics。图标使用 Material Icons。

没有新增装饰动画；展开与弹窗使用 Flutter 既有动画。执行流按启动时间正序，停留底部时跟随输出；阅读历史时暂停跟随并显示“回到最新”。工具在开始执行时就显示，不能等子任务完成才出现。主视图显示最近 50 条记录内的主任务及其子任务，数据库保留全部记录，子任务链接可直接回读。切换详情不会停止执行，详情底部说明委派关系；停止操作取消整棵任务树。

同一作品的新会话共享资料，拥有独立草稿、历史和配置快照。用户更新设定后，新会话首次运行采用最新版，已有会话继续使用原版。配置对话框运行中只读；关闭未保存编辑需要确认。人物卡只编辑一份完整作者设定；人物动态状态与知情管理留待剧情数据库设计。正文编辑、人物卡编辑和配置编辑复用相同的弹窗滚动与保存行为。窄屏将会话选择放在独立行，动作按钮允许换行。

发送前入口标为“下一次输入预览”；模型步骤入口展示当时保存的可读输入，旧记录缺少边界时说明不可恢复。字符／字节数不称为 Token。顶部合计最近一次任务的主子 Agent 已报告用量，缺失时显示不完整；运行详情显示当时实际模型。

## Do's and Don'ts

- 使用既有主题与共享 token；保留浅色、深色和窄屏可读性。
- 用运行器真实终态表示完成，用已保存版本号表示文档结果。
- 不把错误或唯一结果藏进短暂通知。
- 不把原生协议回放、API key 或网络错误原文展示为产品操作选项。
