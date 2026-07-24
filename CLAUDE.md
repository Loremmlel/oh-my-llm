# Oh My LLM - 项目协作指南

本地 LLM 聊天客户端，Flutter 应用，Windows + Android 双端。无厂商绑定，兼容任意 OpenAI 接口。

**技术栈**：Flutter ≥ 3.11.5 / Dart ≥ 3.x · Riverpod 3（`NotifierProvider`）· `sqlite3`（原始包，非 drift/sqflite）· 原始 `package:http`（无厂商 SDK）· `go_router`。

---

## 1. 命令

> **所有命令用 PowerShell 语法。** 底层 shell 是 `pwsh`：用 `$LASTEXITCODE` 而非 `$?`，`Get-Content -Tail` 而非 `tail`，`Out-File` 而非 `>`，`Select-String` 而非 `grep`。

```powershell
flutter pub get
flutter analyze                                    # lint + 静态分析，提交前必过
flutter test --reporter compact                    # 全量测试（dart_test.yaml: 并发 4, 超时 120s）
flutter test path/to/test.dart                     # 单文件
flutter test path/to/test.dart --plain-name "name" # 单用例
flutter run -d windows                             # 桌面调试
flutter build windows --release                    # Windows Release
flutter build apk --release                        # Android APK
```

**升级 Flutter 后先 `flutter clean` 再 `flutter test`**，旧 shader 缓存会导致 Asset manifest 假失败。

### 测试输出重定向（强制）

全量测试 400+ 用例，直接跑会被截断。始终用单条复合命令：

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

- `EXIT=0` -> 全过。`EXIT≠0` -> 失败摘要在 tail 输出。
- 查详情：`Select-String -Pattern "关键词" -Path fltest.log -Context 0,30`；仅失败名：`Select-String -Pattern " -[1-9]" -Path fltest.log`。
- ❌ 禁止不重定向直接 `flutter test` / 用 `tee`（同样截断）。全量输出已在 `fltest.log`，从该文件查即可。
- 只跑单个文件同样套用重定向模式。

### 构建脚本

| 脚本 | 行为 |
|------|------|
| `build-windows-release.ps1` | Windows Release -> `artifacts\windows\oh_my_llm-windows-{version}.zip` |
| `build-android-apk.ps1` | 首次自动生成自签名 keystore（`android/app/self-use-release.jks`），构建 APK -> `artifacts\android\` |
| `scripts/bump-version.ps1 -Minor \| -Major` | 手动升 minor/major；日常 patch/minor/major 由 commit-msg hook 自动管理 |

产物命名固定 `oh_my_llm-{platform}-{version}`，版本号从 `pubspec.yaml` 读取。

---

## 2. Git 工作流

### 版本号自动 bump（commit-msg hook）

安装：`git config core.hooksPath .githooks`。**版本号由 `commit-msg` hook 根据 commit message 第一行语义自动更新**（pre-commit 仅做大改动提醒，不碰版本号）。

commit-msg 通过 `$1` 接收 Git 传入的消息文件，对 `git commit -m` 与编辑器提交都可靠。它从 `HEAD:pubspec.yaml` 读当前版本（避免暂存区已改时重复递增），改完 `git add pubspec.yaml` 随本次提交写入。

| 第一行前缀 | 版本策略 |
|------|------|
| `type!:` / `type(scope)!:` | major+1，minor/patch 归零 |
| `feat:` / `feat(scope):` | minor+1，patch 归零 |
| 其他（fix/docs/refactor/test/chore 等） | patch+1（默认） |

### commit message 格式

**在 Bash 中执行 `git commit`，不要用 PowerShell here-string（`@'...'@`）**--Bash 不认识该语法，会原样写入 `.git/COMMIT_EDITMSG`，匹配不上 Conventional Commits 前缀。多行消息用多个 `-m` 或 Bash heredoc：

```bash
# 方案 1：多个 -m 逐段追加（推荐）
git commit -m "feat: 简短描述（hook 只看第一行）" \
           -m "详细 body" \
           -m "更多 body"

# 方案 2：Bash here-doc（复杂消息）
git commit -m "$(cat <<'EOF'
feat: 简短描述

详细 body
EOF
)"
```

### 提交粒度

每个功能点 / 修复单独提交，不批量合并无关改动。改动 >500 行且无标准前缀时 pre-commit 会提醒，但不阻塞。

---

## 3. 架构

### 分层（所有 feature 一致）

```
lib/
  app/                      # app 入口、路由、shell、theme
  bootstrap.dart            # 启动初始化
  core/                     # 跨 feature 基础设施（persistence / http / logging / utils / widgets）
  features/<feature>/
    domain/                 # 纯数据模型（Equatable），零框架依赖
    data/                   # Repository 实现、网络客户端、SSE 解析
    application/            # Riverpod Notifier 控制器、纯业务函数
    presentation/           # Screen / Widget
```

**单向依赖**：`presentation -> application -> domain`；`data -> domain`（+ `core/`）。

**禁忌**：
- `presentation` 不直接 `import` `data/` 或 `core/persistence/`，只通过 `ref.watch` / `ref.read` 消费 `application/` 的 Provider。
- `application` 通过接口（如 `ChatConversationRepository`、`ChatCompletionClient`）访问 `data/`，不耦合具体实现。
- `domain` 零依赖，不导入 Flutter / Riverpod / sqlite3。

### 启动顺序（`bootstrap.dart`）

`bootstrap()` 接受三个可选参数用于测试注入：`sharedPreferences` / `database` / `networkLogger`。生产传 `null`，由内部 `.getInstance()` / `.open()` / `.create()` 获取；测试传实例注入。

顺序：`WidgetsFlutterBinding.ensureInitialized()` -> `SharedPreferences.getInstance()` -> `AppDatabase.open()` -> `AppNetworkLogger.create(directoryPath: db.path 父目录)` -> `logger.onAppLaunch()` -> `runApp(ProviderScope(...))`。

- `database` 与 `networkLogger` 成对：传 `database` 时 logger 不会自动按其路径建日志。
- network logger 依赖 `AppDatabase.path`，必须在 database 之后初始化。日志文件 `{db_parent}/network.log`，10MB 滚动。
- Provider overrides 注入 `sharedPreferencesProvider` / `appDatabaseProvider` / `appNetworkLoggerProvider` / `customHeadersMapProvider`。

### 持久化分工

| 数据 | 存储 |
|------|------|
| 聊天记录、消息树选择、收藏、收藏夹、Prompt 模板、固定顺序提示词、记忆提示词、检查点 | SQLite（`chat_history.sqlite`） |
| 服务商/模型配置、聊天默认值、最近选择记忆 | SharedPreferences JSON（经 `VersionedJsonStorage` 带版本号编解码） |

**SQLite 基础设施**（`core/persistence/`）：
- `AppDatabase`：`.open()`（生产，`getApplicationSupportDirectory`）/ `.inMemory()`（测试）/ `.forPath()`（跨 Isolate）。构造自动 `_configure()`（PRAGMA）+ `_migrate()`。
- **迁移用 `PRAGMA user_version`**：当前 9->13，每个版本一个 `_migrateVN()` 方法。schema / `user_version` 断言用 `>=`，不用 `==`。
- `SqliteEntityRepository<T>`：泛型基类，适用「全量加载 + 全量写入」。声明式配置 `tableName` / `selectColumns` / `insertColumns` / `rowToEntity` / `entityToValues`。
- `HasIdAndUpdatedAt` mixin：泛型约束，配合 `SettingsEntityController<T extends HasIdAndUpdatedAt>`。
- `BackgroundChatConversationRepository`：将写入委托到后台 Isolate，**80ms 防抖合并**。高频流式写入走这里，避免阻塞 UI。

### 状态管理（Riverpod）

- Provider 命名 `xxxProvider`；控制器类 `XxxController extends Notifier<XxxState>`，类名不带 `Provider`。
- 派生数据用 `Provider` + `ref.watch(xxxProvider.select((s) => s.field))`，避免不必要重建。
- 大控制器用 **mixin 拆分**（如 `ChatSessionsController` = 主体 + `ChatSessionsControllerStreaming` + `ChatSessionsControllerSupport`），通过 `import` 引入。
- `SettingsEntityController<T>`：模板方法基类，子类只提供 `repository`。

---

## 4. 核心域规则（最容易写错）

### Reasoning / Content 分离

推理过程与正文在 **三处**保持分离，不可混用：
- `ChatMessage`：`content`（正文）+ `reasoningContent`（推理），`toJson` / `fromJson` 分别序列化。
- SQLite：`content TEXT NOT NULL` + `reasoning_content TEXT NOT NULL DEFAULT ''`。
- UI：`ReasoningPanel` 独立渲染 `reasoningContent`，仅在非空时显示。

### 消息树（编辑用户消息 -> 新分支）

- 每条消息有 `parentId`；`effectiveParentId = parentId ?? rootConversationParentId`（`'__root__'`）。
- 会话用 `selectedChildByParentId` 记录每个父节点当前选中的子节点；`_resolveActivePath()` 从 root 沿选择链解析当前可见路径，无选择时取同级第一条。
- **编辑用户消息**：创建新 `ChatMessage` 节点（`parentId` 指向原消息的 `parentId`），更新 `selectedChildByParentId` 使新版本成为选中分支；旧分支保留在 `messageNodes`。
- **仅最新一条 assistant 回复可重试**。
- 树操作集中在 `chat_message_tree.dart`（`resolveMessageTreeState` / `appendNodeToTree` / `replaceAssistantMessageInTree` / `removeNodeFromTree`）。

### 错误显示：inline，不用 SnackBar/Dialog

聊天错误以 **inline assistant 消息**呈现（`ChatInlineErrorCard` / `ChatInlineEmptyReplyCard`，嵌入 assistant 气泡内）。**禁止 `showSnackBar`**。`showDialog` 仅用于确认操作（删除、重命名、序列选择），不用于错误提示。

### Prompt 拼接顺序（`chat_request_message_builder.dart`）

实际顺序（5 步，非简单的 system->模板->对话）：
1. 检查点记忆消息（system 角色）
2. 模板 `placement == before` 消息
3. 对话消息（经 `request_message_filter` 过滤）
4. 模板 `placement == beforeLatestInput` 消息
5. 模板 `placement == after` 消息

### 其他易错点

- **对话标题**：未手动命名时取首条用户消息前 15 字符（`characters` 包，`normalizedContent.characters.take(15)`）；手动命名后历史列表**不显示预览**。`hasCustomTitle` 检查 `title != null && title!.trim().isNotEmpty`。
- **历史搜索**：只匹配对话标题 + 用户消息，**不匹配 assistant 回复**。
- **`isStreaming` 不持久化**（仅内存 UI 状态）；`finishReason` 持久化（V13 新增列）。
- **流式 300ms 节流**在 UI 刷新层（`streamUiFlushInterval`），不在 SSE 解析层。流式增量存独立 `ChatStreamingReply`，不直接写会话列表，避免侧栏等无关组件重建。
- **自动重试**：异常 `finish_reason`（如 `length`）触发重试，见 `chat_sessions_controller.dart` `_sendWithOptionalAutoRetry`。
- **输出正则**：`output_regex_processor.dart` 按 `order` 升序链式应用，带 `RegExp` 编译缓存。

---

## 5. 流式与厂商适配

网络层用原始 `package:http`，无官方 SDK。厂商差异用两个 Strategy 链处理：

- **`VendorPayloadAdapter`**（`vendor_payload_adapters.dart`）：`matches(host)` + `buildPatch(reasoningEffort)`，按 host 注入 `thinking` / `extra_body.google.thinking_config` / `reasoning_effort`。`VendorPayloadAdapterRegistry` 优先级链式 `resolve(host)`，`DefaultPayloadAdapter` 兜底。
- **`ChunkParseStrategy`**（`chunk_parse_strategy.dart`）：`canHandle(delta)` + `extract(delta)`，优先级 Gemini -> DeepSeek -> StandardOpenAi。处理 `delta.content` 为 List、`reasoning_content` / `reasoning` 字段等差异。
- **SSE 解析**（`chat_chunk_parser.dart`）：`ChatChunkParser` 处理 `[DONE]` / 错误 / JSON 解码；`InlineReasoningTagSplitter` 跨 chunk 状态机解析 `<thought>` / `<thinking>` 标签。
- **SSE idle timeout**（`openai_compatible_chat_client.dart`）：仅在 `data:` 行到达时重置计时器，SSE 注释行 keepalive 不算活动。

---

## 6. 代码规范

- 注释**简体中文**。`///` doc，`//` 行间注释写「为什么」不写「做了什么」。
- **禁止 `part` / `part of`**，大文件用 `import` / `export` 拆分（全项目零 `part of`）。
- 大类内部用 `// ── 分类 ────────────────────────────────────────────` 分隔线组织方法块。
- 数据模型用 `Equatable`。

---

## 7. 测试

### 基础设施

- `test/helpers/test_harness.dart` 的 `pumpTestApp()` 统一封装：内存 DB、视口、`ProviderScope`、tearDown 清理。**返回 `AppDatabase`**，需直接验证 SQL 时捕获。
  - `child` 与 `router` 互斥（至少传其一）；默认视口 `1440×1200`。
  - 注入 `appDatabaseProvider` / `sharedPreferencesProvider` / `customHeadersMapProvider`，可用 `extraOverrides` 追加。
  - 内部用 `createTestDatabase(preferences)`（`test/test_database.dart`）建内存库。
- `TestFixtures`（`fixtures.dart`）：类型安全工厂，返回真实模型对象（编译期检查），需 JSON 时用模型 `toJson`。typed factory：`model()` / `gpt41()` / `claudeSonnet()` / `deepSeekV4()` / `promptMessage()` / `presetPrompt()` / `codeAssistantPrompt()` / `fixedSequence()` / `sequenceStep()` …。`seedPreferences()` 批量注入 SharedPreferences。**不要手写 JSON**。

### Widget 测试约定

- **Setup 用 `pump()`，不用 `pumpAndSettle()`**：数据层（sqlite3、SharedPreferences getter）完全同步，单帧即可。仅 test body 需等动画时用 `pumpAndSettle()`。
- `FakeChatCompletionClient extends ChatCompletionClient` **只 `@override` `streamCompletion()`**，`complete()` 继承基类，不要重新实现。配 `enqueueChunks` / `enqueueDeltas` / `enqueueError` 排队响应，`requestHistory` / `requestedModels` 记录调用。
- 种子数据走 Repository API（`seedFavorite()` / `seedCollection()`）或 `TestFixtures.seedPreferences()`，**不要在 widget 测试写 raw SQL**。

### 文件组织（case-file decomposition）

```
test/features/chat/
  chat_screen_test.dart            <- 入口：import cases，调用 register*()
  chat_screen/
    chat_screen_test_helpers.dart  <- pump 助手、Fake 实现、Finder 工厂
    chat_screen_basics_cases.dart  <- registerChatScreenBasicsTests()
    chat_screen_streaming_cases.dart
    ...
```

- `*_test.dart` 才被测试运行器发现；`*_cases.dart` 不自动发现。
- 此模式用于 chat / sync / favorites / settings / history。

### 测试粒度三原则

1. **测行为，不测实现**：测外部契约（输入->输出 / 状态变更），不测内部细节（中间状态、调用顺序）。`copyWith` 随数据类模型测，不随 Controller 测。
2. **测不可变契约，不测可变布局**：用逻辑 finder（`findsOneWidget` / `findsWidgets` / `hasLength`），不用像素定位（`getTopLeft().dy` / `getRect()`）。
3. **测决策树分支，不测框架行为**：每个测试验证一个独立执行路径。空列表上查不到内容 -> 不需要测试；框架自动建 tab -> 不需要测「显示了 4 个 tab」。

### 反模式与脆弱红线

**禁止**：
- ❌ 断言 widget 实现细节：`find.byKey`（内部 key）、`findsNothing` on widget 类型、像素位置、widget 属性值（`maxLines` / `expands` 等）。
- ❌ controller 层测 ON DELETE SET NULL / 外键级联（属 schema 测试）。
- ❌ 条件 early-return 测试（必须执行到 `expect`）。
- ❌ schema / `user_version` 断言用 `==`（用 `>=`）。
- ❌ `getTopLeft().dy` / `getRect()` 比较；依赖 ID 字母序＝时间序巧合的排序测试；`chunkDelay` + `pump(delay+2ms)` 微秒级 timing 依赖。

**结构规范**：
- 结构相同的 round-trip / error-type / 比较器测试用循环或 `for` 参数化，不手动复制 4+ 次。
- 同一文件重复 setUp 提取到 `setUp` / 共享 helper。
- Widget 测试线性操作 >30 行应拆分；一个测试只验证一个交互场景。
- 敏感字段脱敏测试全覆盖已知键名。

---

## 8. 环境要求

| 平台 | 必要条件 |
|------|------|
| Windows | Visual Studio 2022（含 **C++ 桌面开发** 工作负载） |
| Android | Android SDK；JDK（`keytool` 生成自签名 keystore） |
| Flutter | ≥ 3.11.5（Dart ≥ 3.x） |
