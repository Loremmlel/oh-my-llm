# Oh My LLM

一个面向开发者和重度用户的本地 LLM 聊天客户端，支持 OpenAI 及所有兼容接口。

- 📱 **多端**：Windows 桌面、Android（iOS/macOS 理论可用，未测试）
- 🔌 **无厂商绑定**：任意 OpenAI 兼容接口（OpenAI 官方、Claude、DeepSeek、本地 Ollama 等）
- 🧠 **推理模型支持**：内置 thinking / reasoning_effort 控制，推理内容独立展示
- 📝 **消息树**：每条用户消息可编辑生成新分支，无限版本切换
- 🗂️ **Prompt 模板**：可复用 system 指令 + 附加消息，随时切换
- 🔢 **固定顺序提示词**：预设多步 Prompt，比较测试时逐步手动发送
- 🔍 **历史搜索**：按对话标题和用户消息全文检索，按时间分组展示
- ⭐ **收藏**：保存满意的模型回复，按收藏夹筛选并查看详情
- 🖥️ **响应式布局**：桌面侧边导航轨、移动端底部导航条

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

### 模型配置

在设置页新增一条模型配置，填入：

| 字段         | 说明                                                                      |
|------------|-------------------------------------------------------------------------|
| 显示名称       | 列表中展示的名字，可随意填写                                                          |
| API URL    | 完整的 chat completions 端点，例如 `https://api.openai.com/v1/chat/completions` |
| API Key    | 接口密钥                                                                    |
| Model Name | 模型名称，原样传给 API                                                           |
| 支持推理       | 勾选后在聊天页可开启 thinking                                                     |

> **OpenAI 官方主机**使用原生 `reasoning_effort` 字段；  
> **其他兼容主机**使用 `thinking: {"type": "enabled"|"disabled"}` 字段，
> effort 值会自动归一化后传入。

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

### 消息树与版本切换

- **编辑用户消息**：长按或点击编辑按钮，修改内容后发送，形成新分支（原内容保留）
- **重试**：仅对最新一条 assistant 回复生效，点击重试生成同一 parent 下的新版本
- **版本导航**：消息气泡下方显示「1 / 3」等版本信息，可左右滑动切换

### 历史对话

- 按**今天 / 昨天 / 近 7 天 / 更早**分组展示
- 支持**全文搜索**（匹配标题和用户消息，防抖 300 ms）
- 支持**批量选择**后删除
- 支持单条对话**重命名**

### 收藏与收藏夹

- 在聊天页点击助手消息上的**书签**按钮即可收藏，收藏内容会保存用户消息、模型回复和推理内容的完整副本
- 收藏页支持按**全部 / 未分类 / 收藏夹**筛选
- 支持新建、重命名、删除收藏夹；删除收藏夹只会把其中的收藏移回未分类
- 收藏详情页可以跳回来源对话，原对话删除后收藏内容仍然保留

---

## 架构概览

```
lib/
├── main.dart                   # 入口
├── bootstrap.dart              # 初始化：SharedPreferences + SQLite + 数据迁移
├── app/
│   ├── app.dart                # MaterialApp + ProviderScope
│   ├── navigation/             # 顶层入口枚举（chat / history / favorites / settings）
│   ├── router/                 # GoRouter 四个顶层页面 + 收藏详情页路由
│   └── shell/                  # 响应式导航壳（NavigationRail / NavigationBar）
├── core/
│   ├── constants/              # 响应式断点
│   ├── persistence/            # SQLite AppDatabase + SharedPreferences provider
│   ├── utils/                  # ID 生成器（时间戳 + 随机后缀）
│   └── widgets/                # 通用 UI 组件
└── features/
    ├── chat/
    │   ├── application/        # ChatSessionsController（核心编排器）
    │   ├── data/               # OpenAI 兼容 HTTP 客户端 + SQLite 仓库 + 迁移
    │   ├── domain/             # ChatMessage / ChatConversation 模型 + 消息树
    │   └── presentation/       # 聊天页 + 流式 Markdown 组件
    ├── favorites/
    │   ├── application/        # 收藏与收藏夹控制器
    │   ├── data/               # SQLite 收藏仓库 + 迁移
    │   ├── domain/             # 收藏 / 收藏夹模型
    │   └── presentation/       # 收藏页 + 收藏详情页
    ├── history/
    │   └── presentation/       # 历史页（搜索 + 分组 + 批量操作）
    └── settings/
        ├── application/        # 各 Notifier（模型配置 / 模板 / 序列 / 默认项）
        ├── data/               # SharedPreferences 仓库 + SQLite 仓库 + 迁移
        ├── domain/             # 设置相关模型
        └── presentation/       # 设置页
```

### 持久化策略

| 数据            | 存储方式                                                 |
|---------------|------------------------------------------------------|
| 聊天记录 / 收藏 / 收藏夹 | SQLite（`chat_history.sqlite`，位于应用 Support 目录）        |
| Prompt 模板     | SQLite                                               |
| 固定顺序提示词       | SQLite                                               |
| 模型配置          | SharedPreferences JSON（`settings.llm_model_configs`） |
| 聊天默认项         | SharedPreferences JSON（单对象）                          |

历史版本使用 SharedPreferences 存储所有数据，升级时会自动执行一次性迁移，迁移完成后删除旧键。

### 流式渲染性能

`StreamingMarkdownView` 把长文本分为两层：
- **渲染快照**（`MarkdownBody`）：以动态定时器按 `clamp(length × 0.4 + 1000, 1000, 5000) ms` 间隔刷新，内容越长刷新越慢
- **实时尾部**（`SelectableText`）：快照之后新增的纯文本，每次 build 即时更新，成本极低

UI 更新节流阈值为 300 ms，高频 SSE token 在内存中聚合后统一触发 Riverpod 状态更新。

---

## 开发指南

```powershell
flutter pub get          # 安装依赖
flutter analyze          # 静态分析
flutter test             # 运行全部测试（约 40 个 widget + 集成测试）
```

### 代码规范

- 文件过大时用 `import` / `export` 拆分，不用 `part` / `part of`
- 注释使用简体中文，`///` 用于 doc 注释，行间注释侧重解释「为什么」
- 大型类用 `// ── 分类 ──────...` 分隔线组织方法块
- 每个功能点/修复单独提交，不批量合并无关改动

### 测试

测试用 `SharedPreferences.setMockInitialValues(...)` 注入存储，用 `ProviderScope` 覆盖依赖。
涉及聊天记录、收藏或收藏夹时同时覆盖 `appDatabaseProvider`（内存数据库）。

---

## 数据文件位置

| 平台      | 路径                                  |
|---------|-------------------------------------|
| Windows | `%APPDATA%\<org>\oh_my_llm\`        |
| Android | `/data/data/com.example.oh_my_llm/` |

SQLite 文件 `chat_history.sqlite` 统一保存聊天记录、Prompt 模板、固定顺序提示词、收藏和收藏夹；模型配置与聊天默认项仍保存在系统 SharedPreferences 中。

---

## 许可证

本项目仅供个人自用，暂未设置开源许可证。
