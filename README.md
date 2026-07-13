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
- 🌐 **网络设置**：自定义 HTTP 请求头规则，附加到所有发出的请求
- 🔤 **字体与字号**：全局字体（默认思源黑体）与正文字号可调
- 🔁 **自动重试**：支持每分钟窗口 / 固定间隔两种模式
- 🔄 **同步**：设备间同步聊天记录与设置
- 🖼️ **媒体浏览器**：本地图片浏览与视频播放

---

## 截图

> *(待补充)*

---

## 快速开始

### 运行要求

| 工具                             | 版本                      |
|--------------------------------|-------------------------|
| Flutter                        | ≥ 3.11.5（对应 Dart ≥ 3.x） |
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
| 服务商 | API URL    | 完整的 chat completions 端点，例如 `https://api.openai.com/v1/chat/completions` |
| 服务商 | API Key    | 接口密钥                                                                    |
| 模型  | 显示名称       | 列表中展示的名字，可随意填写                                                          |
| 模型  | Model Name | 模型名称，原样传给 API                                                           |
| 模型  | 支持推理       | 勾选后在聊天页可开启 thinking                                                     |

聊天页模型选择器为二级：先选服务商，再选该服务商下的模型。旧版平铺模型配置会在读取时按相同 `API URL + API Key` 自动聚合成服务商。

> **OpenAI 官方主机**使用原生 `reasoning_effort` 字段；
> **其他兼容主机**使用 `thinking: {"type": "enabled"|"disabled"}` 字段，
> effort 值会自动归一化后传入。

### 日志系统

应用在启动时自动初始化日志系统，记录所有网络请求、响应和错误。
- **日志位置**：`{AppData}/network.log`（与 SQLite、SharedPreferences 同目录）
- **日志内容**：每次 HTTP 请求的 headers / payload、响应状态 / headers、SSE 流事件、错误堆栈；非 2xx 错误会额外记录错误响应内容
- **自动清理**：仅在日志超过 10 MB 时重置，应用退出或再次启动都不会主动清空日志
- **调试用途**：开发者可从日志中直接复制请求信息重现问题，加快问题排查

### 厂商 OpenAI 兼容处理

`openai_compatible_chat_client.dart` 使用 **Strategy 模式**处理各厂商 API 差异，详见 `vendor_payload_adapters.dart`：

| 厂商                    | 差异处理                                                 |
|------------------------|------------------------------------------------------|
| **OpenAI 官方**         | 发送 `reasoning_effort` 字段；接收 `delta.reasoning_content` |
| **Google AI（兼容）**   | 发送 `extra_body.google.thinking_config.include_thoughts: true`；接收 `delta.thinking` 或 `extra_content.google.thought_signature` |
| **DeepSeek**            | 发送 `thinking` 字段；接收 `delta.thinking_content`        |
| **其他兼容主机**        | 发送 `thinking: {"type": "enabled"\|"disabled"}`；接收 `delta.reasoning_content` |

SSE 解析器（`chat_chunk_parser.dart`）同时支持：
- 解析 `<thought>` XML 标签内容（Google Gemma 等模型）
- 300 ms 节流合并窗口内正确累积各种 thinking 字段，防止内容丢失

### Prompt 模板

一个模板包含：
- 可选的 **system 指令**
- 零或多条 **附加消息**（user / assistant 角色）

模板在每次请求前被拼接到对话历史开头，顺序为：
1. system 指令
2. 模板附加消息
3. 实际对话消息

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

在设置页的「网络」标签页中自定义 HTTP 请求头规则，定义的请求头会附加到所有发出的请求中，同名请求头会覆盖应用的默认值。

### 自动重试

支持两种重试模式：
- **每分钟窗口**：每分钟在前 n 秒内随机一个毫秒重试
- **固定间隔**：每 n 秒 + 随机 1000ms 抖动重试

### 同步

设备间同步聊天记录与设置。Android 端提供连接 / 同步 / 媒体三个 Tab。

### 媒体浏览器

本地图片浏览与视频播放。支持目录浏览、路径导航和随机播放。

---

## 架构概览

```
lib/
├── main.dart                   # 入口
├── bootstrap.dart              # 初始化：SharedPreferences + SQLite + 数据迁移 + 日志系统
├── app/
│   ├── app.dart                # MaterialApp + ProviderScope
│   ├── navigation/             # 顶层入口枚举（chat / history / favorites / settings / sync）
│   ├── router/                 # GoRouter 路由
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
    │   ├── application/        # ChatSessionsController + ChatSessionsState（核心编排器）
    │   ├── data/               # HTTP 客户端 + SSE 解析 + 厂商适配 + SQLite 仓库
    │   │   ├── chat_completion_client.dart          # 抽象接口 + 异常类
    │   │   ├── openai_compatible_chat_client.dart   # HTTP 客户端实现
    │   │   ├── chat_chunk_parser.dart               # SSE 解析器（支持 `<thought>` 标签）
    │   │   ├── vendor_payload_adapters.dart         # Strategy 模式（厂商 API 差异）
    │   │   └── ...
    │   ├── domain/             # ChatMessage / ChatConversation 模型 + 消息树
    │   ├── presentation/       # 聊天页 + 流式 Markdown 组件 + 滚动控制器
    │   │   ├── chat_screen.dart
    │   │   ├── chat_scroll_controller.dart          # 滚动/锚点管理器
    │   │   └── widgets/         # 消息气泡、推理面板、思考开关等组件
    │   └── ...
    ├── favorites/
    │   ├── application/        # 收藏与收藏夹控制器
    │   ├── data/               # SQLite 收藏仓库 + 迁移
    │   ├── domain/             # 收藏 / 收藏夹模型
    │   └── presentation/       # 收藏页 + 收藏详情页
    ├── history/
    │   ├── presentation/       # 历史页（搜索 + 分组 + 批量操作 + 分页）
    │   └── ...
    ├── media/
    │   ├── application/        # 媒体浏览器控制器 + 随机播放控制器
    │   ├── data/               # 目录扫描 + HTTP 处理
    │   ├── domain/             # 媒体模型
    │   └── presentation/       # 媒体浏览器 Tab + 图片查看器 + 视频播放器
    ├── settings/
    │   ├── application/        # 各 Notifier（服务商配置 / 模板 / 序列 / 记忆提示词 / 字体 / 请求头等）
    │   ├── data/               # SharedPreferences 仓库 + SQLite 仓库 + 迁移
    │   ├── domain/             # 设置相关模型
    │   └── presentation/       # 设置页（网络 / 其他等标签页）
    └── sync/
        ├── application/        # 同步客户端 / 服务端控制器
        ├── data/               # 同步数据层
        ├── domain/             # 同步模型
        └── presentation/       # 同步页（连接 / 同步 / 媒体 Tab）
```

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

历史版本使用 SharedPreferences 存储所有数据，升级时会自动执行一次性迁移，迁移完成后删除旧键。

### 流式渲染性能

默认 `flutter_smooth_markdown` 路径使用 `StreamMarkdown` 直接消费增量 chunk，不再依赖"按字数动态定时全量重渲染"。

UI 更新节流阈值仍为 300 ms：高频 SSE token 先在控制器层聚合，再统一触发 Riverpod 状态更新，减少状态层高频重建。

---

## 开发指南

```powershell
flutter pub get          # 安装依赖
flutter analyze          # 静态分析
flutter test             # 运行全部测试（1016 个测试）
```

### 代码规范

- 文件过大时用 `import` / `export` 拆分，不用 `part` / `part of`
- 注释使用简体中文，`///` 用于 doc 注释，行间注释侧重解释「为什么」
- 大型类用 `// ── 分类 ──────...` 分隔线组织方法块
- 每个功能点/修复单独提交，不批量合并无关改动

### 测试

测试覆盖主要模块，共 1016 个测试（99 个测试文件）：

| 模块 | 位置 | 覆盖范围 |
|-----|------|---------|
| Favorites Widget | `test/features/favorites/` | 主页、详情页、收藏夹管理对话框 |
| Favorites Controller | `test/features/favorites/application/` | 收藏和收藏夹 CRUD、过滤、级联 |
| Favorites Repository | `test/features/favorites/data/`、`test/features/favorites/domain/` | SQLite 仓库、收藏 / 收藏夹模型 |
| Chat↔Favorites Flow | `test/features/chat/chat_screen/` | 书签按钮、对话框、新建收藏夹流程 |
| ChatSessionsController | `test/features/chat/application/` | 会话增删改、消息树编辑、重试、错误处理、内联错误显示 |
| Chat Domain | `test/features/chat/domain/` | 消息树、对话模型、分组、请求消息构建、检查点上下文 |
| Chat Data | `test/features/chat/data/` | HTTP 客户端、请求体构建、模板/用户消息构建器、SSE 解析、厂商适配 |
| Chat Presentation | `test/features/chat/presentation/`、`test/features/chat/widgets/` | 聊天页、锚点 Rail、字数统计、消息折叠 |
| AppDatabase Migration | `test/core/persistence/` | schema、外键级联、索引、数据迁移、后台写入器、replace-all、版本化 JSON 存储 |
| Core Utils | `test/core/utils/` | 日期格式化、ID 生成、文本格式化、JSON 截断 |
| Core Logging | `test/core/logging/` | 日志存储、网络日志脱敏 redactor |
| AppShellScaffold | `test/app/shell/` | 响应式布局、导航栏/Rail 切换、路由 |
| History | `test/features/history/` | 历史搜索、分组、分页 |
| Media | `test/features/media/` | 媒体浏览器、目录扫描、随机播放、缩略图、图片/视频 HTTP 处理、MIME 类型 |
| Settings | `test/features/settings/` | 服务商/模型配置、模板、序列、记忆提示词、字体、请求头、自动重试、导入导出去重 |
| Sync | `test/features/sync/` | 同步客户端/服务端、UDP 发现、HTTP 服务、消息模型、同步页 |
| Integration | `test/integration/` | 启动、消息版本持久化、多对话切换/重启恢复、收藏夹级联、PresetPrompt 拼接、Sync 多品类/端到端、厂商 payload 集成 |

测试用 `SharedPreferences.setMockInitialValues(...)` 注入存储，用 `ProviderScope` 覆盖依赖。
涉及聊天记录、收藏或收藏夹时同时覆盖 `appDatabaseProvider`（内存数据库）。

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
