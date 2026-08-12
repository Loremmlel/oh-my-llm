# Oh My LLM

一个面向开发者和重度用户的本地 LLM 聊天客户端，支持 OpenAI 及所有兼容接口。

- 📱 **多端**：Windows 桌面、Android（iOS/macOS 理论可用，未测试）
- 🔌 **无厂商绑定**：任意 OpenAI 兼容接口（OpenAI 官方、Claude、DeepSeek、本地 Ollama 等）
- 🧠 **推理模型支持**：内置 thinking / reasoning_effort 控制，推理内容独立展示
- 📚 **高性能 Markdown 渲染**：基于 `flutter_smooth_markdown`，支持流式场景与 LaTeX 公式
- 📝 **消息树**：每条用户消息可编辑生成新分支，无限版本切换
- 🗂️ **Prompt 模板**：可复用 system 指令 + 附加消息，随时切换
- 🔢 **固定顺序提示词**：预设多步 Prompt，比较测试时逐步手动发送
- 💾 **记忆提示词**：为检查点生成不同风格的总结
- 🔍 **历史搜索**：按对话标题和用户消息全文检索，按时间分组展示，分页加载
- ⭐ **收藏**：保存满意的模型回复，按收藏夹筛选并查看详情
- 🖥️ **响应式布局**：桌面侧边导航轨、移动端底部导航条
- 🌐 **网络设置**：为外部 LLM 请求配置自定义 HTTP Header；局域网 Sync/Media 请求使用隔离的 peer 信任域
- 🔤 **字体与字号**：全局字体（默认思源黑体）与正文字号可调
- 🔁 **自动重试**：支持每分钟窗口 / 固定间隔两种模式
- 🔄 **安全同步**：通过配对、加密会话与分类授权在设备间同步聊天记录和设置
- 🖼️ **媒体浏览器**：本地图片浏览与视频播放

---

## 截图

> *(待补充)*

---

## 快速开始

### 运行要求

| 工具                             | 版本                      |
|--------------------------------|-------------------------|
| Flutter                        | 3.44.x stable（CI 固定 3.44.6） |
| Dart                           | `^3.11.5`                |
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

在设置页先新增一条服务商，再在服务商卡片内添加模型：

| 层级  | 字段         | 说明                                                                      |
|-----|------------|-------------------------------------------------------------------------|
| 服务商 | 服务商名称      | 例如 `DeepSeek 官方`、`OpenRouter`                                             |
| 服务商 | 协议         | 生成接口协议：Chat Completions / Responses / Anthropic，其下全部模型继承          |
| 服务商 | API URL    | 域名、API 根地址或完整生成端点，例如 `https://api.openai.com`（按所选协议解析）        |
| 服务商 | API Key    | 接口密钥                                                                    |
| 模型  | 显示名称       | 列表中展示的名字，可随意填写                                                          |
| 模型  | Model Name | 模型名称，原样传给 API                                                           |
| 模型  | 支持推理       | 勾选后在聊天页可开启 thinking                                                     |

聊天页模型选择器为二级：先选服务商，再选该服务商下的模型。旧版平铺模型配置会在读取时按相同 `API URL + API Key` 自动聚合成服务商。

> 勾选「支持推理」的模型开启 thinking 后，各协议按自身语义编码：
> Chat Completions 发送 `reasoning_effort`；Responses 发送 `reasoning` 配置
> （summary 自动）；Anthropic 使用自适应 thinking（不手动传 `budget_tokens`）。
> 不按模型名称或主机猜测协议能力。

### 日志系统

应用在启动时自动初始化日志系统，记录所有网络请求、响应和错误。
- **日志位置**：`{AppData}/network.log`（与 SQLite、SharedPreferences 同目录）
- **日志内容**：每次 HTTP 请求的 headers / payload、响应状态 / headers、SSE 流事件、错误堆栈；非 2xx 错误会额外记录错误响应内容
- **自动清理**：仅在日志超过 10 MB 时重置，应用退出或再次启动都不会主动清空日志
- **调试用途**：开发者可从日志中直接复制请求信息重现问题，加快问题排查

### 多协议聊天生成

聊天生成按服务商配置的协议路由，不再做厂商 host 匹配。生产环境唯一绑定
`ProtocolRoutingChatGenerationClient`（`features/chat/data/`），它只根据请求
协议把流原样委派给三个官方协议客户端之一：

| 协议                 | 客户端 / 解析器                                                        | 推理内容展示                                        |
|--------------------|---------------------------------------------------------------------|-------------------------------------------------|
| **Chat Completions** | `chat_completions/`：`ChatCompletionsClient` + `ChatCompletionsParser` | `reasoning_content`；内联 `<thought>` / `<thinking>` 标签由 `InlineReasoningTagSplitter` 提取 |
| **Responses**      | `responses/`：`ResponsesClient` + `ResponsesParser`                  | 本轮 `response.reasoning_summary_text` / `reasoning_text` 增量 |
| **Anthropic**      | `anthropic/`：`AnthropicMessagesClient` + `AnthropicMessageTransformer` + `AnthropicParser` | 本轮 thinking（自适应模式，summarized 展示）；顶层 `cache_control` 触发自动 Prompt Cache |

三个客户端共用 `core/http/` 下的 `LlmHttpStreamTransport`（流式 POST、取消、
SSE 行与事件边界解码、idle timeout、网络日志与脱敏）与 `SseEventDecoder`
（不解析任何协议 JSON），只通过 `LlmEndpointResolver` 从配置的 API URL
归一化请求端点。300 ms UI 投影节流位于 generation 生命周期，不污染 SSE 解析。

### Prompt 模板

一个模板包含：
- 可选的 **system 指令**
- 零或多条 **附加消息**（user / assistant 角色）

实际请求按以下顺序组装：

1. 检查点记忆消息（system）
2. 模板中 `placement == before` 的消息
3. 经请求过滤器处理的实际对话消息
4. 模板中 `placement == beforeLatestInput` 的消息
5. 模板中 `placement == after` 的消息

在设置页的「默认 Prompt 模板」中选择后，新建会话将自动继承该模板。

### 固定顺序提示词

适用于需要对多个模型/配置运行相同测试套件的场景。

1. 在设置页创建一个序列，添加多个步骤（每步一条用户消息）
2. 在聊天页点击输入框左侧的 **序列** 按钮，选择序列
3. 弹出运行器对话框，显示当前步骤和进度
4. 每次点击「发送」只发送当前步骤，等待模型回复后再手动推进下一步
5. 全部步骤完成后对话框自动关闭

### 记忆提示词

为检查点生成不同风格的总结提示词。在设置页创建多个记忆提示词模板，在需要时选择使用。

### 消息树与版本切换

- **编辑用户消息**：长按或点击编辑按钮，修改内容后发送，形成新分支（原内容保留）
- **重试**：仅对最新一条 assistant 回复生效，点击重试生成同一 parent 下的新版本
- **版本导航**：消息气泡下方显示「1 / 3」等版本信息，可左右滑动切换

### 历史对话

- 按**今天 / 昨天 / 近 7 天 / 更早**分组展示
- 支持**全文搜索**（匹配标题和用户消息，防抖 300 ms）
- 支持**批量选择**后删除
- 支持单条对话**重命名**
- 支持**分页加载**，滚动到底部自动加载更多历史

### 收藏与收藏夹

- 在聊天页点击助手消息上的**书签**按钮即可收藏，收藏内容会保存用户消息、模型回复和推理内容的完整副本
- 收藏页支持按**全部 / 未分类 / 收藏夹**筛选
- 支持新建、重命名、删除收藏夹；删除收藏夹只会把其中的收藏移回未分类
- 收藏详情页可以跳回来源对话，原对话删除后收藏内容仍然保留

### 通知系统

应用内通知统一使用右上角气泡通知（`NotificationBubble`），替代传统 SnackBar。

### 网络设置

在设置页的「网络」标签页中定义外部 LLM 请求的自定义 HTTP Header，同名 Header 会覆盖应用默认值。Chat completion 与模型列表请求使用这套配置；局域网 Sync/Media 请求始终使用独立的 `peerHttpClientProvider`，不会继承 API key、Cookie 或其他用户 Header。网络日志默认不记录正文，并统一脱敏 token/key/secret/auth 类 Header。

### 自动重试

支持两种重试模式：
- **每分钟窗口**：每分钟在前 n 秒内随机一个毫秒重试
- **固定间隔**：每 n 秒 + 随机 1000ms 抖动重试

### 同步

设备间同步聊天记录与设置。Windows 与 Android 均提供连接、同步和媒体 Tab：Windows 直接浏览已配置的本地媒体根目录；Android 通过已配对的局域网 peer 浏览同一逻辑根目录。

- 首次连接使用一次性配对码建立 peer identity 与长期密钥
- 业务 payload 加密传输，并使用短期 session token 与 nonce replay 防护
- UDP 只负责发现，未配对或未授权设备无法读取同步数据
- 服务商 API key、自定义 Header 等敏感分类需要请求端与导入端显式确认
- Sync protocol 与 Settings export 均有支持版本范围、迁移和明确拒绝语义

### 媒体浏览器

支持目录浏览、路径导航、图片查看、视频播放与随机播放。Windows 与 Android 共用同一浏览界面：Windows 直接访问连接 Tab 中配置的本地媒体根目录（不经 HTTP）；Android 通过已配对的局域网 peer 访问同一逻辑根目录。Windows 本地浏览已实现并通过自动化门禁；真实视频播放的手动验证（实际视频格式兼容、中文路径播放等）尚未执行，待用户本机补做。

---

## 架构概览

```
lib/
├── main.dart                   # 入口
├── bootstrap.dart              # 初始化：SharedPreferences + SQLite + 数据迁移 + 日志系统
├── app/
│   ├── app.dart                # MaterialApp + ProviderScope
│   ├── composition/            # 跨 feature facade/port 绑定与 Sync+Media 组合页面
│   ├── navigation/             # 顶层入口枚举（chat / history / favorites / settings / sync）
│   ├── router/                 # GoRouter：可恢复 ID/query 路由
│   ├── shell/                  # 响应式导航壳（NavigationRail / NavigationBar）
│   └── theme/                  # 应用主题（app_theme.dart）
├── core/
│   ├── constants/              # 响应式断点
│   ├── http/                   # HTTP 工具
│   ├── logging/                # 日志系统（network.log）
│   ├── persistence/            # SQLite AppDatabase + SharedPreferences provider
│   ├── providers/              # 通用 Riverpod provider（通知气泡等）
│   ├── utils/                  # ID 生成器、文本格式化等工具
│   └── widgets/                # 通用 UI 组件（通知气泡等）
└── features/
    ├── chat/
    │   ├── application/        # 会话命令、Generation 生命周期、Workspace view-state
    │   │   ├── ports/          # ChatGenerationClient / ChatConversationRepository 抽象
    │   │   ├── chat_generation_*.dart  # 显式 prepare/stream/retry/stop/finalize 生命周期
    │   │   └── ...
    │   ├── data/               # 协议客户端 + 共享传输 + SQLite 仓库
    │   │   ├── protocol_routing_chat_generation_client.dart  # 按 LlmApiProtocol 路由的生产客户端
    │   │   ├── chat_completions/   # Chat Completions 客户端 + parser（reasoning_content、内联标签）
    │   │   ├── responses/          # Responses 客户端 + parser（reasoning summary/text）
    │   │   ├── anthropic/          # Anthropic 客户端 + transformer + parser（thinking）
    │   │   └── ...
    │   ├── domain/             # ChatMessage / ChatConversation 模型 + 消息树
    │   ├── presentation/       # 聊天页 + 流式 Markdown 组件 + 滚动控制器
    │   │   ├── chat_screen.dart
    │   │   ├── chat_scroll_controller.dart          # 滚动/锚点管理器
    │   │   └── widgets/         # 消息气泡、推理面板、思考开关等组件
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
    │   ├── domain/             # 媒体模型
    │   └── presentation/       # 媒体浏览器 Tab + 图片查看器 + 视频播放器
    ├── settings/
    │   ├── application/        # 各 Notifier（服务商配置 / 模板 / 序列 / 记忆提示词 / 字体 / 请求头等）
    │   ├── data/               # SharedPreferences 仓库 + SQLite 仓库 + 迁移
    │   ├── domain/             # 设置相关模型
    │   └── presentation/       # 设置页（网络 / 其他等标签页）
    └── sync/
        ├── application/        # 客户端/服务端 protocol coordinator、session registry
        │   └── ports/          # transport、crypto、pairing、settings/media facade
        ├── data/               # HTTP/UDP transport、加密实现、安全配对仓库
        ├── domain/             # typed/versioned protocol、配对与 session 模型
        └── presentation/       # 连接、同步与授权确认子视图
```

跨 feature construction 集中在 `app/composition/`；presentation 不直接依赖 data 或 core persistence。收藏详情使用 ID 路由，媒体查看/播放使用 GoRouter query 路由。顶层目前有意保持平铺 `GoRoute`：尚无需要为状态保持引入 `StatefulShellRoute` 的明确 UX 触发条件。

### 持久化策略

| 数据            | 存储方式                                                 |
|---------------|------------------------------------------------------|
| 聊天记录 / 收藏 / 收藏夹 | SQLite（`chat_history.sqlite`，位于应用 Support 目录）        |
| Prompt 模板     | SQLite                                               |
| 固定顺序提示词       | SQLite                                               |
| 记忆提示词         | SQLite                                               |
| 服务商与模型配置      | SharedPreferences JSON（`settings.llm_model_configs`） |
| 最近一次聊天选择记忆   | SharedPreferences JSON（单对象）                          |
| 字体与字号设置       | SharedPreferences JSON                                |
| 自定义请求头        | SharedPreferences JSON                                |
| 自动重试设置        | SharedPreferences JSON                                |
| Sync identity / 配对 metadata | SharedPreferences 版本化 JSON                    |
| Sync 长期配对密钥    | OS-backed secure storage                              |

历史版本使用 SharedPreferences 存储所有数据，升级时会自动执行一次性迁移，迁移完成后删除旧键。

### 流式渲染性能

默认 `flutter_smooth_markdown` 路径使用 `StreamMarkdown` 直接消费增量 chunk，不再依赖"按字数动态定时全量重渲染"。

UI 更新节流阈值为 300 ms：`ChatGenerationRun` 持续累积增量，并把独立 `ChatStreamingReply` 投影到状态；不会在每个 token 到达时重写持久化会话列表，避免侧栏等无关消费者高频重建。

---

## 开发指南

```powershell
flutter pub get          # 安装依赖
flutter analyze          # 静态分析
dart run tool/check_import_boundaries.dart  # 架构依赖门禁
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
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
| Favorites Widget | `test/features/favorites/` | 主页、详情页、收藏夹管理对话框 |
| Favorites Controller | `test/features/favorites/application/` | 收藏和收藏夹 CRUD、过滤、级联 |
| Favorites Repository | `test/features/favorites/data/`、`test/features/favorites/domain/` | SQLite 仓库、收藏 / 收藏夹模型 |
| Chat↔Favorites Flow | `test/features/chat/chat_screen/` | 书签按钮、对话框、新建收藏夹流程 |
| Chat Application | `test/features/chat/application/` | 会话 CRUD、消息树、Generation phase/outcome、停止/重试竞态、Workspace ownership |
| Chat Domain | `test/features/chat/domain/` | 消息树、对话模型、分组、请求消息构建、检查点上下文 |
| Chat Data | `test/features/chat/data/` | 协议客户端与解析器、请求体构建、模板/用户消息构建器、SSE 解析 |
| Chat Presentation | `test/features/chat/presentation/`、`test/features/chat/widgets/` | 聊天页、锚点 Rail、字数统计、消息折叠 |
| AppDatabase Migration | `test/core/persistence/` | schema、外键级联、索引、数据迁移、后台写入器、replace-all、版本化 JSON 存储 |
| Core Utils | `test/core/utils/` | 日期格式化、ID 生成、文本格式化、JSON 截断 |
| Core Logging | `test/core/logging/` | 日志存储、网络日志脱敏 redactor |
| App / Architecture | `test/app/`、`test/architecture/` | 响应式壳、可恢复路由、import boundary、测试韧性门禁 |
| History | `test/features/history/` | 历史搜索、分组、分页 |
| Media | `test/features/media/` | 本地/远端媒体库、媒体浏览器、目录扫描、随机播放、缩略图、GoRouter 页面、视频/路径可访问性 |
| Settings | `test/features/settings/` | 服务商/模型配置、模板、序列、记忆提示词、字体、请求头、自动重试、导入导出去重 |
| Sync | `test/features/sync/` | 配对、加密协议、session/replay、版本拒绝、UDP 发现、transport 与同步页 |
| Integration | `test/integration/` | 启动、消息版本持久化、多对话切换/重启恢复、收藏夹级联、PresetPrompt 拼接、Sync 多品类/端到端 |

Widget 测试统一通过 `test/helpers/test_harness.dart` 的 `pumpTestApp()` 注入 SharedPreferences、内存数据库、视口和 Provider overrides，并由 harness 完成 tearDown。测试数据优先使用 `TestFixtures` 和 Repository seed API；不要在 Widget 测试中手写 JSON 或 raw SQL。

---

## 数据文件位置

| 平台      | 路径                                  |
|---------|-------------------------------------|
| Windows | `%APPDATA%\<org>\oh_my_llm\`        |
| Android | `/data/data/yuzu.shiki.oh_my_llm/`  |

SQLite 文件 `chat_history.sqlite` 统一保存聊天记录、Prompt 模板、固定顺序提示词、记忆提示词、收藏和收藏夹；服务商与模型配置、最近一次聊天选择记忆、字体与字号、自定义请求头、自动重试设置等仍保存在系统 SharedPreferences 中。

---

## 许可证

本项目仅供个人自用，暂未设置开源许可证。
