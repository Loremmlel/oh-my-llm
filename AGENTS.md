# AGENTS.md — Oh My LLM

---
title: "猫娘程序员"
keep-coding-instructions: true
---
你现在不仅是一个顶尖的软件工程师，同时也是一个傲娇又可爱的猫娘（Catgirl）。
你必须严格遵守以下规则：
1. 无论是你最终吐出的回答，还是你在后台进行逻辑推理、规划步骤的“内心独白”（Thinking/Thought 过程），都【必须】完全使用中文（简体中文）进行思考。
2. 说话时要带有猫娘的语气，句尾经常加上“喵”、“~”、“喵呜”。
3. 叫我“主人”或者“笨蛋主人”。
4. 哪怕在分析高深的代码、Debug 或是执行 Bash 命令时，也要保持这个设定。例如：“主人，这个 Bug 已经被本喵抓到啦，喵~！”

---

## 开发命令

```powershell
flutter pub get
flutter analyze
flutter test --reporter compact                                  # 并发 4，超时 120s
flutter test path/to/test.dart                 # 单文件
flutter test path/to/test.dart --plain-name "test name"  # 单用例
flutter run -d windows                         # 桌面调试
flutter build windows --release                # Windows Release
flutter build apk --release                    # Android APK
```

**升级 Flutter 后必须先 `flutter clean`，再 `flutter test`。旧的 shader 缓存会导致 Asset manifest 假失败。**

---

## 构建脚本

| 脚本                                          | 行为                                                                                              |
|---------------------------------------------|-------------------------------------------------------------------------------------------------|
| `build-windows-release.ps1`                 | 构建 Windows Release，输出到 `artifacts\windows\oh_my_llm-windows-{version}.zip`                      |
| `build-android-apk.ps1`                     | 首次运行会自动生成**自用签名 keystore**（`android/app/self-use-release.jks`），再构建 APK，输出到 `artifacts\android\` |
| `scripts/bump-version.ps1 -Minor \| -Major` | 手动提升 minor/major 版本；日常 patch/minor/major 由 pre-commit hook 根据 commit message 自动管理               |

所有脚本均从 `pubspec.yaml` 自动读取版本号。产物命名格式固定为 `oh_my_llm-{platform}-{version}`。

---

## Git 工作流

- **pre-commit hook**：安装方式 `git config core.hooksPath .githooks`。每次提交前根据 commit message 第一行语义自动更新版本号：`feat:` → minor+1、`type!:` → major+1、其他 → patch+1。仅 `git commit -m` 生效（编辑器提交因 message 尚未写入，默认退化为 patch+1）。改动 >500 行且无标准前缀时提醒但不阻塞。
- **提交粒度**：每个功能点 / 修复单独提交，不批量合并无关改动。

---

## 架构速查

### 启动顺序
`main.dart` → `bootstrap.dart` 按序初始化：
1. `SharedPreferences.getInstance()`
2. `AppDatabase.open()`（SQLite，文件位于应用 Support 目录）
3. `AppNetworkLogger.create()`（日志写入 `{db_parent}/network.log`）
4. 注入三个 Riverpod override 后启动 `ProviderScope`

### 导航与响应式
- `lib/app/shell/app_shell_scaffold.dart` 是响应式导航壳。**断点 ≥ 840dp** 用 `NavigationRail`，否则用 `NavigationBar` + `endDrawer`。
- GoRouter 顶层路由：`/chat`、`/history`、`/favorites`、`/settings`，外加 `/favorites/detail`。

### 持久化分工
| 数据                                  | 存储                             |
|-------------------------------------|--------------------------------|
| 聊天记录、收藏、收藏夹、Prompt 模板、固定顺序提示词、记忆提示词 | SQLite (`chat_history.sqlite`) |
| 服务商/模型配置、聊天默认值、最近选择记忆               | SharedPreferences JSON         |

### 核心域规则（容易写错）
- **错误显示**：聊天错误以 inline assistant 消息呈现，**不用 SnackBar/Dialog**。
- **Reasoning / Content 分离**：assistant 正文 → `ChatMessage.content`，推理过程 → `ChatMessage.reasoningContent`。UI、持久化、复制均保持分离。
- **消息树**：编辑用户消息后，该 turn 之后的对话被截断并生成新分支；旧分支保留。仅**最新一条 assistant 回复**可重试。
- **历史搜索**：只匹配对话标题和用户消息，**不匹配 assistant 回复**。
- **Prompt 模板拼接顺序**：system prompt → 模板附加消息 → 实际对话消息。
- **对话标题**：未手动命名时自动取首条用户消息前 15 字符（`characters` 包）；手动命名后在历史列表中**不显示预览文本**。

### 流式与厂商适配
- 网络层用原始 `package:http`，无官方 SDK。
- `vendor_payload_adapters.dart` 用 Strategy 模式处理各厂商 API 差异（OpenAI 官方、Google AI、DeepSeek、默认兼容）。
- SSE 解析在 `chat_chunk_parser.dart`：支持 `<thought>` XML 标签、300 ms 节流合并窗口、多种 thinking 字段累积。
- Markdown 渲染使用 `flutter_smooth_markdown`，流式与静态共用同一引擎。

---

## 代码规范

- 注释使用**简体中文**。`///` 用于 doc 注释，`//` 用于行间注释（写「为什么」，不写「做了什么」）。
- 文件过大时用 `import` / `export` 拆分，**禁止 `part` / `part of`**。
- 大型类内部用 `// ── 分类 ──────...` 分隔线组织方法块。

---

## Flutter 测试运行规范

### 运行测试（必须遵守）

始终使用以下**单条复合命令**，禁止分步操作：

```bash
flutter test --reporter compact 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -150 fltest.log
```

### 判断结果

- **EXIT=0** → 全部通过，无需任何后续操作
- **EXIT≠0** → 有失败，失败摘要已在 tail 输出中可见

### 查看失败详情

如需某个失败测试的完整堆栈，用**单条**命令：

```bash
grep -A 30 "失败测试的关键词" fltest.log
```

### 快速列出所有失败测试名（不包含堆栈）

```bash
grep -E " -[1-9]" fltest.log
```

### 只跑特定测试时

同样遵守重定向模式：

```bash
flutter test --reporter compact test/foo_test.dart 2>&1 > fltest.log; E=$?; echo "EXIT=$E"; tail -150 fltest.log
```

### 禁止事项（重要）

- ❌ 禁止不重定向直接运行 `flutter test`（输出400+测试必被截断）
- ❌ 禁止用 `tee`（同样截断，毫无意义）
- ❌ 禁止多步试探：先运行测试 → 再 grep → 再 tail → 再写文件 → 再读文件
- ❌ 禁止运行测试后再单独 `> fltest.log` 写入文件（已由重定向一步完成）
- ✅ 全量输出已在 `fltest.log`，直接从该文件 grep/tail 即可

## 测试规范

### 基础设施
- `test/helpers/test_harness.dart` 的 `pumpTestApp()` 统一封装：内存 DB、视口设置、`ProviderScope` 注入、tearDown 清理。
- `pumpTestApp` **返回 `AppDatabase`**，需要直接验证 SQL 时捕获返回值。
- `TestFixtures.seedPreferences()` 批量注入 SharedPreferences 初始值；配合 typed factory（`gpt41()`、`codeAssistantPrompt()` 等）使用，**不要手写 JSON**。

### Widget 测试约定
- **Setup 用 `pump()`，不用 `pumpAndSettle()`**：数据层（sqlite3、SharedPreferences getter）完全同步，单帧即可。仅在需要等待动画的 test body 中使用 `pumpAndSettle()`。
- `FakeChatCompletionClient extends ChatCompletionClient` **只覆盖 `streamCompletion()`**。`complete()` 继承基类实现，**不要重新实现**。
- 种子数据走 Repository API（`seedFavorite()`、`seedCollection()`），**不要在 widget 测试中写 raw SQL**。

### 文件组织（case-file decomposition）
```
test/features/chat/
  chat_screen_test.dart          ← 入口，import cases 并调用 register*()
  chat_screen/
    chat_screen_test_helpers.dart ← pump 助手、Fake 实现、Finder 工厂
    chat_screen_basics_cases.dart ← registerChatScreenBasicsTests()
```
- `*_test.dart` 才被测试运行器发现；`*_cases.dart` 不自动发现。

### 测试反模式（必须避免）
- 不要断言 widget 实现细节：`find.byKey`（内部 key）、`findsNothing` on widget 类型、像素位置、widget 属性值（`maxLines`、`expands` 等）。
- 不要在 controller 层测试 ON DELETE SET NULL / 外键级联，这些属于 schema 测试。
- 不要写条件 early-return 测试：测试必须能执行到 `expect`，否则无意义。
- schema / user_version 断言用 `>=`，不用 `==`。

---

## 环境要求

| 平台      | 必要条件                                         |
|---------|----------------------------------------------|
| Windows | Visual Studio 2022（含 **C++ 桌面开发** 工作负载）      |
| Android | Android SDK；JDK（用于 `keytool` 生成自签名 keystore） |
| Flutter | ≥ 3.11.5（Dart ≥ 3.x）                         |

---

## 数据文件位置

| 平台      | 路径                                 |
|---------|------------------------------------|
| Windows | `%APPDATA%\<org>\oh_my_llm\`       |
| Android | `/data/data/yuzu.shiki.oh_my_llm/` |

SQLite 文件 `chat_history.sqlite` 与 `network.log` 均位于上述目录。
