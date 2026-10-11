# Oh My LLM

一个面向长文本阅读与创作的本地 LLM 工作台，支持 Windows 和 Android，包含聊天、写作 Agent、提示词管理与局域网媒体浏览。

- 📱 **多端**：Windows 桌面、Android
- 🔌 **无厂商绑定**：支持 Chat Completions、Responses、Anthropic Messages 协议，按服务商显式配置
- 🧠 **推理模型支持**：内置 thinking / reasoning_effort 控制，推理内容独立展示
- 📚 **高性能 Markdown 渲染**：基于 `flutter_smooth_markdown`，支持流式场景与 LaTeX 公式
- 📝 **消息树**：每条用户消息可编辑生成新分支，无限版本切换
- 🗂️ **预设与模板提示词**：多角色预设、注入位置与宏，以及带类型变量和条件分支的输入模板
- ✍️ **写作 Agent**：按作品组织主时间线、角色配置、工作文档、剧情状态与累计总结，可查看工具执行和子任务
- 🔢 **固定顺序提示词**：预设多步 Prompt，比较测试时逐步手动发送
- 💾 **记忆提示词**：为检查点生成不同风格的总结
- 🔍 **历史搜索**：按对话标题和用户消息全文检索，按时间分组展示，分页加载
- ⭐ **收藏**：保存满意的模型回复，按收藏夹筛选并查看详情
- 🖥️ **响应式布局**：桌面/移动导航 + 父约束驱动的内容与媒体网格
- 🌐 **网络设置**：为外部 LLM 请求配置自定义 HTTP Header；局域网 Sync/Media 请求使用隔离的 peer 信任域
- 🔤 **中文阅读字体**：黑体用于操作与编辑，宋体用于阅读；字体随应用离线打包，正文字号可调
- 🔁 **自动重试**：支持每分钟窗口 / 固定间隔两种模式
- 🔄 **安全同步**：通过配对、加密会话与分类授权在设备间同步设置
- 🖼️ **媒体浏览器**：本地图片浏览与视频播放

---

## 界面与设计

界面采用暖白／绿色与平面布局：正文优先，列表用分隔线组织，操作和阅读内容通过字体区分。Material 继续提供键盘、焦点与可访问性行为。

| 页面 | 布局 |
| --- | --- |
| 聊天、Agent | 宽屏共用一列主导航与会话／作品选择；窄屏按需打开辅助抽屉。正文开放呈现，输入区只有一个外边界。 |
| 服务商、预设与其它设置 | 宽屏按列对齐，窄屏重排为紧凑记录；保留编辑、能力开关和批量操作。 |
| 预设编辑 | 独立页面，条目选择、排序与语法置顶；窄屏压缩工具区，保存失败保留输入，离开时保护未保存修改。 |
| 历史、收藏、同步、媒体 | 平铺列表或自适应网格，保留搜索、分页、选择与既有操作，减少重复标题和层叠卡片。 |

操作界面使用完整的 **Noto Sans SC**，阅读使用 **Noto Serif SC** 子集：8105 个规范汉字及源字体中的 2990 个非汉字字符，缺字回退到完整黑体。两套字体合计约 24.23 MiB，启动时无需下载。来源、许可与裁剪复现见[字体说明](assets/fonts/README.md)。

当前界面约定见 [DESIGN.md](DESIGN.md)；设计来源、用户意见与 11 张概念参考图见[设计基准](docs/design/ui-redesign/README.md)，实施与实际验收范围见[收尾检查记录](docs/design/ui-redesign/final-audit.md)。参考图用于表达设计方向，不是应用截图。

---

## 快速开始

### 运行要求

| 工具                             | 版本                      |
|--------------------------------|-------------------------|
| Flutter                        | 3.47.x stable（CI 固定 3.47.1） |
| Dart                           | `^3.13.1`                |
| Android SDK                    | 仅构建 Android 时需要         |
| Visual Studio 2022（含 C++ 桌面开发） | 仅构建 Windows 时需要         |

### 本地运行

```powershell
git clone https://github.com/Loremmlel/oh-my-llm.git
cd oh-my-llm
flutter pub get
flutter run -d windows   # 或 -d <your_android_device_id>
```

### 发布构建

```powershell
# Windows 压缩包（输出到 artifacts\windows\）
.\build-windows-release.ps1

# Android APK（输出到 artifacts\android\，首次运行自动生成自签名 keystore）
.\build-android-apk.ps1
```

两个脚本均从 `pubspec.yaml` 自动读取版本号，产物命名格式为 `oh_my_llm-{platform}-{version}`。

---

## 功能详解

### 服务商与模型

在设置页先新增一条服务商，再在所属服务商分组内添加模型：

| 层级  | 字段         | 说明                                                                      |
|-----|------------|-------------------------------------------------------------------------|
| 服务商 | 服务商名称      | 例如 `DeepSeek 官方`、`OpenRouter`                                             |
| 服务商 | 协议         | 生成接口协议：Chat Completions / Responses / Anthropic，其下全部模型继承          |
| 服务商 | API URL    | 域名、API 根地址或完整生成端点，例如 `https://api.openai.com`（按所选协议解析）        |
| 服务商 | API Key    | 接口密钥                                                                    |
| 模型  | 显示名称       | 列表中展示的名字，可随意填写                                                          |
| 模型  | Model Name | 模型名称，原样传给 API                                                           |
| 模型  | 支持推理       | 勾选后在聊天页可开启 thinking                                                     |
| 模型  | 支持图像       | 声明模型可接收图片，聊天页按此能力校验图文输入                                         |

聊天页模型选择器为二级：先选服务商，再选该服务商下的模型。

> 勾选「支持推理」的模型开启 thinking 后，各协议按自身语义编码：
> Chat Completions 发送 `reasoning_effort`；Responses 发送 `reasoning` 配置
> （summary 自动）；Anthropic 使用自适应 thinking（不手动传 `budget_tokens`）。
> 不按模型名称或主机猜测协议能力。

### 日志系统

应用在启动时自动初始化网络日志系统，用于定位请求、流式传输与错误。

- **日志位置**：应用 Support 目录下的 `network.log`，与 SQLite 数据库同目录
- **日志内容**：请求标识、响应状态与诊断信息；默认不记录请求正文，敏感 Header 统一脱敏。正文诊断仅在明确启用的路径记录，工具与原生续接请求保留无内容摘要
- **自动清理**：仅在日志超过 10 MB 时重置，应用退出或再次启动都不会主动清空日志

### 多协议聊天生成

Chat 与 Agent 共用 `core/llm/` 的调用基础设施。`ProtocolRoutingLlmClient`
按服务商显式配置的协议路由，不按厂商 host 猜测。Chat 的文本政策由
`features/chat/data/generation/chat_text_generation_adapter.dart` 处理。

| 协议                 | 客户端 / 解析器                                                        | 推理内容展示                                        |
|--------------------|---------------------------------------------------------------------|-------------------------------------------------|
| **Chat Completions** | `core/llm/protocols/chat_completions/` | 优先使用 `reasoning_content`，其次使用字符串 `reasoning`；Chat 单独提取内联 `<thought>` / `<thinking>` 标签 |
| **Responses**      | `core/llm/protocols/responses/` | 本轮 reasoning summary / reasoning text 增量 |
| **Anthropic Messages** | `core/llm/protocols/anthropic/` | thinking 与正文分离，保留协议原生续接信息 |

三个客户端共用 `core/http/` 下的 `LlmHttpStreamTransport`（流式 POST、取消、
SSE 行与事件边界解码、idle timeout、网络日志与脱敏）与 `SseEventDecoder`
（不解析任何协议 JSON），只通过 `LlmEndpointResolver` 从配置的 API URL
归一化请求端点。generation 生命周期会把每个协议 chunk 投影到独立流式状态，
不会在 SSE 解析层合并或丢弃增量。

### 预设 Prompt

预设由有序的 System／User／Assistant 条目组成，每条可单独启停和选择注入位置。支持普通文本、有限宏语法、SillyTavern 导入，以及将 System 内容归并的「单条 System」选项。

预设在独立页面编辑，排序操作与语法选择放在顶部。保存失败保留输入，返回时确认未保存修改。聊天页在侧栏选择预设。

实际请求按以下顺序组装：

1. 检查点记忆消息（system）
2. 预设中 `placement == before` 的消息
3. 经请求过滤器处理的历史消息（不含本次最新输入）
4. 预设中 `placement == beforeLatestInput` 的消息
5. 本次最新用户输入
6. 预设中 `placement == after` 的消息

宏预设先按条目列表顺序求值，再按注入位置组装；普通预设不执行宏。上下文查看复用同一准备流程，生成中读取当前请求快照。

### 模板提示词

模板正文中的变量占位符支持三种类型（未带类型标记时默认为文本）：

```text
{{主角名字}}              # 文本
{{章节数:number}}         # 数字，只接受十进制整数
{{人称:select|一|二|三}}   # 单选，选项按声明顺序展示
```

- 单选变量在聊天页以下拉框展示，保存的是选项的字符串值（不是索引），调整选项顺序后历史值仍有效；
- 正文变量 `{{正文}}` 对应主输入框：不允许声明为数字或单选，且只能出现在条件块之外；
- 在聊天页输入区选择模板后才会按条件渲染，不会自动触发。

**条件块**：使用 `{{#if 条件}}`、`{{else if 条件}}`、`{{else}}`、`{{/if}}` 按顺序渲染第一个成立的分支；所有条件都不成立且没有 `else` 时输出空字符串。

```text
{{#if 人称 == "一"}}
以第一人称叙述。
{{else if 人称 == "二"}}
以第二人称叙述。
{{else}}
使用第三人称叙述。
{{/if}}
```

条件固定为「变量名 比较运算符 字面量」，支持范围：

| 变量类型 | 支持的运算符 | 右值 |
| --- | --- | --- |
| `text` | `==`、`!=` | 双引号字符串 |
| `select` | `==`、`!=` | 双引号字符串，且必须是已声明选项 |
| `number` | `==`、`!=`、`>`、`>=`、`<`、`<=` | 十进制整数 |

切换单选分支时，隐藏分支中的变量字段会保留其当前草稿值，切回时自动恢复；控制变量始终显示。

支持范围：不支持嵌套条件块、多个条件的布尔组合、模板引用、预览、选项内容中的 `|` 转义以及字面量 `{{` 转义。

**设置导出的兼容性**：导出格式带版本；受支持的旧格式按顺序迁移，不受支持或未来版本明确拒绝。

**应用降级提示**：旧版本可能拒绝较新的数据库或设置格式，也可能无法解释条件模板。降级前先备份数据，不在不支持该语法的版本中编辑或发送条件模板。

### 固定顺序提示词

适用于需要对多个模型/配置运行相同测试套件的场景。

1. 在设置页创建一个序列，添加多个步骤（每步一条用户消息）
2. 从聊天输入区的 **固定顺序提示词** 入口打开运行器；窄屏入口收在更多设置中
3. 选择序列与步骤，查看当前正文和进度
4. 选择「填入输入框」或「发送当前步骤」，执行后关闭运行器
5. 再次打开时继续下一步；到最后一步后停留在该步，不自动执行整套序列

### 写作 Agent

每部作品拥有独立的主时间线、草稿、模型与角色配置、工作文档和剧情状态。界面先呈现采用正文，推理、工具执行与子任务按需展开；运行中可以停止整棵任务树。

- 配置主 Agent 及职责模型，管理人物卡、世界书、剧本等资料，运行中配置只读
- 在正文、工作文档与剧情状态间切换，查看下一次输入预览及模型步骤实际输入
- 按连续楼数生成累计总结，可编辑、重新总结或恢复原文；原始记录保留在本地
- 支持最新回复重试与撤回最新一轮；覆盖正文、子任务和状态前明确说明后果

### 记忆提示词

为检查点生成不同风格的总结提示词。在设置页创建多个记忆提示词模板，在需要时选择使用。

### 消息树与版本切换

- **编辑用户消息**：长按或点击编辑按钮，修改内容后发送，形成新分支（原内容保留）
- **重试**：仅对最新一条 assistant 回复生效，点击重试生成同一 parent 下的新版本
- **版本导航**：通过消息的版本控件切换同级分支，原消息与分支保留

### 历史对话

- 按**最近 / 一天内 / 三天内 / 一周内 / 一月内 / 更早**分组展示
- 支持**全文搜索**（匹配标题和用户消息，不匹配助手回复）
- 支持**批量选择**后删除
- 支持单条对话**重命名**，手动命名后不显示消息摘要
- 使用**分页栏**切换页码和每页数量

### 收藏与收藏夹

- 在聊天页点击助手消息上的**书签**按钮即可收藏，收藏内容会保存用户消息、模型回复和推理内容的完整副本
- 收藏页支持按**全部 / 未分类 / 收藏夹**筛选
- 支持新建、重命名、删除收藏夹，以及批量选择和移动收藏
- 删除收藏夹时可将内容移到其它收藏夹／未分类，也可确认一并删除内容
- 收藏详情页可以跳回来源对话，原对话删除后收藏内容仍然保留

### 通知系统

一般应用通知使用右上角气泡（`NotificationBubble`）。聊天生成错误保留为内联助手消息；表单校验、保存失败与禁用原因在所属区域显示。

### 网络设置

在设置页的「网络」标签页中定义外部 LLM 请求的自定义 HTTP Header，同名 Header 会覆盖应用默认值。Chat completion 与模型列表请求使用这套配置；局域网 Sync/Media 请求始终使用独立的 `peerHttpClientProvider`，不会继承 API key、Cookie 或其他用户 Header。网络日志默认不记录正文，并统一脱敏 token/key/secret/auth 类 Header。

### 自动重试

支持两种重试模式：
- **每分钟窗口**：每分钟在前 n 秒内随机一个毫秒重试
- **固定间隔**：每 n 秒 + 随机 1000ms 抖动重试

### 同步

设备间按分类同步服务商、预设、提示词、网络、输出处理及其它设置，不包含聊天记录。Windows 与 Android 均提供连接、同步和媒体 Tab：Windows 直接浏览已配置的本地媒体根目录；Android 通过已配对的局域网 peer 浏览同一逻辑根目录。

- 首次连接使用一次性配对码建立 peer identity 与长期密钥
- 业务 payload 加密传输，并使用短期 session token 与 nonce replay 防护
- UDP 只负责发现，未配对或未授权设备无法读取同步数据
- 服务商 API key、自定义 Header 等敏感分类需要请求端与导入端显式确认
- Sync protocol 与 Settings export 均有支持版本范围、迁移和明确拒绝语义

### 媒体浏览器

支持目录浏览、路径导航、图片查看、视频播放与随机播放。Windows 与 Android 共用同一浏览界面：Windows 直接访问连接 Tab 中配置的本地媒体根目录（不经 HTTP）；Android 通过已配对的局域网 peer 访问同一逻辑根目录。网格按父级可用宽度自适应列数，并提供紧凑/标准/舒适三档设备本地密度（Windows 默认紧凑、Android 默认标准）。

视频播放器操控按平台区分：Windows 采用桌面键鼠（`←`/`→` 快退/快进 5 秒，`→` 长按 400ms 临时 3 倍速，`↑`/`↓` 与垂直滚轮调音 5%，`M` 静音，`F`/双击原生全屏，`Escape` 退出全屏或关闭，单击播放/暂停）；Android 保留触摸手势（单击控制栏、双击 ±15 秒、长按 3 倍速、横拖 Seek）。

---

## 架构概览

```
lib/
├── main.dart                   # 入口
├── bootstrap.dart              # 初始化：SharedPreferences + SQLite + 数据迁移 + 日志系统
├── app/
│   ├── app.dart                # MaterialApp + ProviderScope
│   ├── composition/            # 跨 feature facade/port 绑定与 Sync+Media 组合页面
│   ├── navigation/             # 顶层入口枚举（chat / agent / history / favorites / settings / sync）
│   ├── router/                 # GoRouter：可恢复 ID/query 路由
│   ├── shell/                  # 响应式导航壳与工作区侧栏组合
│   └── theme/                  # 应用主题（app_theme.dart）
├── core/
│   ├── constants/              # 响应式断点
│   ├── http/                   # HTTP 工具
│   ├── llm/                    # Chat / Agent 共用调用、协议客户端与原生工具续接
│   ├── logging/                # 日志系统（network.log）
│   ├── persistence/            # SQLite AppDatabase + SharedPreferences provider
│   ├── providers/              # 通用 Riverpod provider（通知气泡等）
│   ├── utils/                  # ID 生成器、文本格式化等工具
│   └── widgets/                # 通用 UI 组件
│       ├── dialogs/            # 通用确认/操作对话框
│       └── notification_bubble/ # 应用内通知气泡
└── features/
    ├── agent/
    │   ├── application/        # Agent 运行、作品、配置、文档、总结与剧情状态
    │   ├── data/               # 持久化仓库与运行依赖实现
    │   ├── domain/             # Agent 任务、配置、资料与状态模型
    │   └── presentation/       # 主时间线、子任务、配置与资料编辑
    ├── chat/
    │   ├── application/        # 会话命令、Generation 生命周期、Workspace view-state
    │   │   ├── composer/       # 会话草稿与编辑命令
    │   │   ├── favorites/      # 收藏命令与 facade
    │   │   ├── generation/     # 显式 prepare/stream/retry/stop/finalize 生命周期
    │   │   ├── history/        # 历史查询与分组
    │   │   ├── ports/          # ChatGenerationClient / ChatConversationRepository 抽象
    │   │   ├── requests/       # 请求消息与请求目标
    │   │   ├── sessions/       # 会话状态与控制器
    │   │   ├── sidebar/        # 侧栏视图状态
    │   │   └── workspace/      # Workspace view-state 与 bindings
    │   ├── data/               # Chat 文本生成适配与持久化仓库
    │   │   ├── generation/     # 共享 LLM 适配、空回复政策与内联推理提取
    │   │   └── persistence/    # SQLite 会话仓库与后台写入器
    │   ├── domain/             # ChatMessage / ChatConversation 等领域模型
    │   ├── presentation/       # 聊天页 + 流式 Markdown 组件 + 滚动控制器
    │   │   ├── chat_screen.dart
    │   │   ├── chat_scroll_controller.dart          # 滚动/锚点管理器
    │   │   └── widgets/         # 聊天页组件
    │   │       ├── composer/   # 输入框与发送控制
    │   │       ├── dialogs/    # 聊天相关确认对话框
    │   │       ├── messages/   # 消息气泡与推理面板
    │   │       ├── prompts/    # Prompt 选择与变量
    │   │       ├── sidebar/    # 会话侧栏
    │   │       └── workspace/  # Workspace 组合组件
    │   └── ...
    ├── favorites/
    │   ├── application/        # 收藏控制器、application-owned ports 与跨 feature command
    │   ├── data/               # SQLite 收藏仓库 + 迁移
    │   ├── domain/             # 收藏 / 收藏夹模型
    │   └── presentation/       # 收藏页 + 收藏详情页
    ├── history/
    │   ├── presentation/       # Chat read model：搜索 + 分组 + 批量操作 + 分页
    │   └── ...
    ├── media/
    │   ├── application/        # 媒体库会话 + 浏览器/随机播放控制器 + 资源解析
    │   ├── data/               # 本地/远端媒体库适配器 + 目录扫描 + HTTP 处理
    │   │   ├── libraries/     # 本地与远端媒体库
    │   │   ├── scanning/      # 目录扫描
    │   │   └── http/          # 媒体 HTTP 处理
    │   ├── domain/             # 媒体模型
    │   └── presentation/       # 媒体浏览器 Tab + 图片查看器 + 视频播放器
    ├── settings/
    │   ├── application/        # 各 Notifier（按 preferences / providers / prompts / transfer 分组）
    │   │   ├── preferences/    # 聊天默认值、字号、请求头与重试设置
    │   │   ├── providers/      # 服务商、模型与目录工作流
    │   │   ├── prompts/        # 模板、序列与记忆提示词
    │   │   └── transfer/       # 导入导出与同步 facade
    │   ├── data/               # SharedPreferences 仓库 + SQLite 仓库 + 迁移
    │   │   ├── providers/      # 服务商与模型仓库
    │   │   └── prompts/        # Prompt SQLite 仓库
    │   ├── domain/             # 设置相关模型（按 preferences / providers / prompts / transfer 分组）
    │   │   └── models/
    │   │       ├── preferences/
    │   │       ├── providers/
    │   │       ├── prompts/
    │   │       └── transfer/
    │   └── presentation/       # 六类设置工作区与独立预设编辑页
    │       └── widgets/
    │           ├── providers/  # 服务商与模型表单、列表组件
    │           ├── prompts/    # Prompt 表单与列表组件
    │           ├── shared/     # 设置通用表单与列表组件
    │           ├── tabs/       # 设置标签页组件
    │           └── transfer/   # 设置导入确认组件
    └── sync/
        ├── application/        # 客户端/服务端 protocol coordinator、session registry
        │   └── ports/          # transport、crypto、pairing、settings/media facade
        ├── data/               # HTTP/UDP transport、加密实现、安全配对仓库
        │   ├── http/           # Sync HTTP transport
        │   ├── udp/            # UDP discovery
        │   └── security/       # 加密与安全配对仓库
        ├── domain/             # typed/versioned protocol、配对与 session 模型
        │   └── models/
        │       ├── discovery/  # 发现模型
        │       ├── protocol/   # typed/versioned protocol 模型
        │       └── session/    # 配对与 session 模型
        └── presentation/       # 连接、同步与授权确认子视图
```

跨 feature construction 集中在 `app/composition/`；presentation 不直接依赖 data 或 core persistence。收藏详情使用 ID 路由，媒体查看/播放使用 GoRouter query 路由。顶层目前有意保持平铺 `GoRoute`：尚无需要为状态保持引入 `StatefulShellRoute` 的明确 UX 触发条件。

### 持久化策略

| 数据            | 存储方式                                                 |
|---------------|------------------------------------------------------|
| 聊天记录 / 收藏 / 收藏夹 | SQLite（`chat_history.sqlite`，位于应用 Support 目录）        |
| 预设 / 模板提示词  | SQLite                                               |
| 固定顺序提示词       | SQLite                                               |
| 记忆提示词         | SQLite                                               |
| Agent 作品 / 配置方案 / 任务 / 文档 / 剧情状态 | SQLite                  |
| 服务商与模型配置      | SharedPreferences 版本化 JSON                         |
| 最近一次聊天选择记忆   | SharedPreferences JSON（单对象）                          |
| 正文字号设置        | SharedPreferences JSON                                |
| 自定义请求头        | SharedPreferences JSON                                |
| 自动重试设置        | SharedPreferences JSON                                |
| Sync identity / 配对 metadata | SharedPreferences 版本化 JSON                    |
| Sync 长期配对密钥    | OS-backed secure storage                              |

SQLite 使用顺序 schema 迁移，保留受支持的历史迁移链；不支持的旧版本、未来版本或异常结构明确拒绝。本次 UI 重构未修改数据库结构。

### 流式渲染性能

默认 `flutter_smooth_markdown` 路径使用 `StreamMarkdown` 直接消费增量 chunk，
由库内 50 ms 刷新机制合并 Markdown 重建，不附加普通文本尾巴。

`ChatGenerationRun` 将每个协议 chunk 的累计内容写入独立 `ChatStreamingReply`，
但不重写持久化会话列表。消息区域通过窄 Provider 独立刷新，`ChatScreen`、
侧栏、composer、收藏查询和滚动导航元数据不会随 chunk 重建。流式内容增长
不再自动追底；打开或切换会话仍会定位到最新消息，用户原先位于底部时新增
一轮消息也会一次性定位。

---

## 开发指南

Windows 命令使用 PowerShell 7。完整的日志、测试超时、提交与架构规则见 [AGENTS.md](AGENTS.md)；界面改动同时遵循 [DESIGN.md](DESIGN.md)。

```powershell
flutter pub get          # 安装依赖
flutter analyze          # 静态分析
dart run tool/check_import_boundaries.dart  # 架构依赖门禁
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

### 代码规范

- 文件过大时用 `import` / `export` 拆分，不用 `part` / `part of`
- 注释使用简体中文，`///` 用于 doc 注释，行间注释侧重解释「为什么」
- 大型类用 `// ── 分类 ──────...` 分隔线组织方法块
- 每个功能点/修复单独提交，不批量合并无关改动

### 测试

测试覆盖主要模块（用例数随开发增长，详见各模块目录）：

| 模块 | 位置 | 覆盖范围 |
|-----|------|---------|
| Agent | `test/features/agent/` | 运行与工具调用、任务树、作品配置、资料、总结、剧情状态与界面交互 |
| Shared LLM | `test/core/llm/` | 协议路由、流式解析、原生工具往返、续接、取消与用量 |
| Favorites Widget | `test/features/favorites/` | 主页、详情页、收藏夹管理对话框 |
| Favorites Controller | `test/features/favorites/application/` | 收藏和收藏夹 CRUD、过滤、级联 |
| Favorites Repository | `test/features/favorites/data/`、`test/features/favorites/domain/` | SQLite 仓库、收藏 / 收藏夹模型 |
| Chat↔Favorites Flow | `test/features/chat/presentation/chat_screen/` | 书签按钮、对话框、新建收藏夹流程 |
| Chat Application | `test/features/chat/application/` | `composer/` 草稿、模板/用户消息构建与编辑命令；`favorites/` 收藏命令；`generation/` Generation phase/outcome、停止/重试竞态；`history/` 分页；`ports/` Generation client contract；`requests/` 请求消息过滤与检查点上下文；`sessions/` 会话 CRUD、消息树与状态；`sidebar/` 侧栏；`workspace/` Workspace ownership |
| Chat Domain | `test/features/chat/domain/`、`test/features/chat/domain/models/` | `domain/` 根目录：会话分组、字数统计；`domain/models/`：聊天模型 |
| Chat Data | `test/features/chat/data/generation/`、`test/features/chat/data/persistence/` | `generation/` 文本生成适配、空回复与内联推理；`persistence/` SQLite 会话仓库与后台写入器 |
| Chat Presentation | `test/features/chat/presentation/` | 聊天页、锚点 Rail、消息折叠 |
| AppDatabase Migration | `test/core/persistence/` | schema、外键级联、索引、数据迁移、后台写入器、replace-all、版本化 JSON 存储 |
| Core Utils | `test/core/utils/` | 日期格式化、ID 生成、文本格式化、JSON 截断 |
| Core Logging | `test/core/logging/` | 日志存储、网络日志脱敏 redactor |
| App / Architecture | `test/app/`、`test/app/composition/sync_workspace_screen/`、`test/architecture/` | 响应式壳、可恢复路由、Sync workspace 组合、import boundary、测试韧性门禁 |
| History | `test/features/history/` | 历史搜索、分组、分页 |
| Media | `test/features/media/` | 本地/远端媒体库、媒体浏览器、目录扫描、随机播放、缩略图、GoRouter 页面、视频/路径可访问性 |
| Settings | `test/features/settings/` | 服务商/模型配置、预设编辑、模板、序列、记忆提示词、字号、请求头、自动重试、导入导出去重 |
| Sync | `test/features/sync/` | 配对、加密协议、session/replay、版本拒绝、UDP 发现、transport 与同步页 |
| Integration | `test/integration/` | 启动、消息版本持久化、多对话切换/重启恢复、收藏夹级联、PresetPrompt 拼接、Sync 多品类/端到端 |

Widget 测试统一通过 `test/helpers/test_harness.dart` 的 `pumpTestApp()` 注入 SharedPreferences、内存数据库、视口和 Provider overrides，并由 harness 完成 tearDown。测试数据优先使用 `TestFixtures` 和 Repository seed API；不要在 Widget 测试中手写 JSON 或 raw SQL。

UI 的内置浏览器预览使用生产组件与内存测试数据，用于桌面／窄屏布局和交互检查；它不是完整 Web 发行版，也不替代 Windows 原生、Android 真机的输入法与媒体验证。检查范围和结果记录在[收尾检查记录](docs/design/ui-redesign/final-audit.md)。

---

## 数据文件位置

| 平台      | 路径                                  |
|---------|-------------------------------------|
| Windows | `%APPDATA%\<org>\oh_my_llm\`        |
| Android | `/data/data/yuzu.shiki.oh_my_llm/`  |

SQLite 文件 `chat_history.sqlite` 保存聊天记录、预设与提示词、收藏、Agent 作品与运行资料等；服务商与模型配置、最近一次聊天选择记忆、正文字号、自定义请求头、自动重试设置等保存在系统 SharedPreferences 中。

---

## 许可证

本项目仅供个人自用，暂未设置开源许可证。

随应用分发的 Noto 字体采用 SIL Open Font License，来源与许可文件见[字体说明](assets/fonts/README.md)。
