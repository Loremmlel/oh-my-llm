# Oh My LLM - 项目协作指南

本地 LLM 聊天客户端，Flutter 应用，Windows + Android 双端。无厂商绑定，兼容任意 OpenAI 接口。

**技术栈**：Flutter 3.44.x stable（CI 固定 3.44.6）/ Dart `^3.11.5` · Riverpod 3（`NotifierProvider`）· `sqlite3`（原始包，非 drift/sqflite）· 原始 `package:http`（无厂商 SDK）· `go_router`。

---

## 1. 命令

仓库命令示例统一使用 **PowerShell 7**。原生 Windows Agent 应优先使用 PowerShell；仅执行 `.sh`、Git hook 验证或 POSIX 工具链时显式调用 Git Bash（如 `bash scripts/verify-version-hook.sh`）。不要在 Bash 中直接解释 PowerShell 语法，反之亦然。Claude Code 用户应启用原生 PowerShell tool（`CLAUDE_CODE_USE_POWERSHELL_TOOL=1`）；`CLAUDE.md` 通过 `@AGENTS.md` 复用本文件，不再维护第二份命令版本。

```powershell
flutter pub get
flutter analyze                                    # lint + 静态分析，提交前必过
dart run tool/check_import_boundaries.dart         # 架构依赖门禁
flutter test --reporter compact                    # 全量测试（dart_test.yaml: 并发 8, 超时 120s）
flutter test path/to/test.dart                     # 单文件
flutter test path/to/test.dart --plain-name "name" # 单用例
flutter run -d windows                             # 桌面调试
flutter build windows --release                    # Windows Release
flutter build apk --release                        # Android APK
```

**升级 Flutter 后先 `flutter clean` 再 `flutter test`**，旧 shader 缓存会导致 Asset manifest 假失败。

### 测试输出重定向（强制）

全量测试用例数随开发增长，直接跑会被截断。始终用单条复合命令：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

- `EXIT=0` -> 全过。`EXIT≠0` -> `logs/fltest.log` 的 tail 输出为失败摘要。
- 查详情：`Select-String -Pattern "关键词" -Path logs/fltest.log -Context 0,30`；仅失败名：`Select-String -Pattern " -[1-9]" -Path logs/fltest.log`。
- ❌ 禁止不重定向直接 `flutter test` / 用 `tee`（同样截断）。全量输出已在 `logs/fltest.log`，从该文件查即可。
- 只跑单个文件同样套用重定向模式。
- Agent 执行测试、`flutter analyze`、构建或诊断时，日志必须写入仓库根目录下 ignored 的 `logs/`，禁止在仓库根目录直接生成 `*.log`。
- 写日志前先执行 `New-Item -ItemType Directory -Force logs | Out-Null`。全量测试使用 `logs/fltest.log`；red/green 证据使用能表达任务的 `logs/<任务>-red.log` / `logs/<任务>-green.log`。
- `logs/` 内容是可再生成的本地产物，可以覆盖或清理；CI runner 根目录的 `fltest.log` 上传流程和应用 AppData 的 `network.log` 不受本规则影响。

### 测试执行超时兜底（强制）

`flutter test` 的 per-test `timeout`（`dart_test.yaml`: 120s）只覆盖测试体内部 `await` 卡住；编译/启动阶段、`setUpAll`/`tearDownAll`、native DLL 锁卡启动、测试进程不退出等进程级挂起不在其管辖。Agent 执行测试命令时必须**在命令层显式设置工具 `timeout`**（进程级硬超时，到点杀整棵进程树）：

- 单文件测试：工具 `timeout` 显式设 `60000`ms（正常数秒内完成，超 1 分钟即视为挂起）。
- 全量测试：工具 `timeout` 显式设 `240000`ms（并发 8 正常 2-3 分钟，超 4 分钟即视为挂起）。
- ❌ 禁止用 `run_in_background` 跑需要同步结果的测试（无强制超时，挂起会无限等）。
- 超时被杀 = 挂起信号：**先** `.\scripts\kill-stale-test-processes.ps1` 清理残留进程**再**诊断重跑，不得直接重跑（残留进程锁住 `sqlite3.dll` 会连环挂起）。被杀时 `logs/` 内已写入的部分输出仍可用于诊断。

### test 启动卡住排查（Windows）

`flutter test` 卡在启动、连用例都未开始时，先排查残留 Dart 进程是否锁住 native assets DLL。`package:sqlite3` 的 native assets hook 需要写入 `build\native_assets\windows\sqlite3.dll`，已加载该 DLL 的残留进程会阻止覆盖：

```powershell
.\scripts\kill-stale-test-processes.ps1
```

清理后重新运行测试。代码已通过后台仓库 close 超时保护和测试 tearDown 兜底处理根因；该脚本是异常退出后的缓解措施。

### 构建脚本

| 脚本 | 行为 |
|------|------|
| `build-windows-release.ps1` | Windows Release -> `artifacts\windows\oh_my_llm-windows-{version}.zip` |
| `build-android-apk.ps1` | 首次自动生成自签名 keystore（`android/app/self-use-release.jks`），构建 APK -> `artifacts\android\` |
| `scripts/bump-version.ps1 -Minor \| -Major` | 手动升 minor/major；日常 patch/minor/major 由 post-commit hook 自动管理 |

Agent 若重定向脚本输出，Windows/Android 分别使用 `logs/build-windows.log`、`logs/build-android.log`。

产物命名固定 `oh_my_llm-{platform}-{version}`，版本号从 `pubspec.yaml` 读取。

---

## 2. Git 工作流

### 分支策略（master 受保护）

- `master` 分支受保护：禁止直接 push，禁止直接在 master 上提交改动。
- 所有开发改动一律在按规范命名的新分支上完成并提交，再通过 Pull Request 合入 `master`。
- 分支命名沿用 conventional commit 前缀 + 简短 kebab-case 描述（英文或中文均可），与 commit message 语义一致，能一眼看出改动意图：
  - 新功能 `feat/<scope>-<描述>`（如 `feat/settings-transfer`）
  - 缺陷修复 `fix/<scope>-<描述>`（如 `fix/sync-server-dispose-test-proxy`）
  - 重构 / 测试 / 杂项 / 文档依此类推：`refactor/`、`test/`、`chore/`、`docs/`

### Pull Request 格式与撰写要求

PR 是代码审查和变更记录，不是 commit 列表的复制。保持单一目标、规模可审查；如变更已经大到需要多个独立审查重点，应拆成多个 PR。详细原则参考 [GitHub 的审查友好性指南](https://docs.github.com/en/pull-requests/concepts/helping-others-review-your-changes) 与 [Sourcery 审查文档](https://docs.sourcery.ai/reviews/)。

#### 标题

- 标题一律使用简体中文描述，保留 Conventional Commit 前缀：`type(scope): 简短结果`，`scope` 可省略。
- 标题描述合入后产生的结果，不写“更新代码”、“修改问题”等无信息表达，不在末尾加句号。
- 前缀应与分支、核心 commit 的语义一致，但 PR 标题不要拼接所有 commit subject。

#### 正文必填结构

PR 正文一律使用简体中文，并保留以下六个二级标题；某项不适用时写“无”并简述原因，不得删除标题。

```markdown
## 变更摘要

- 1~3 条说明可观察结果、主要范围和不在范围内的内容；不复制 commit 列表。

## 变更原因

说明现状、触发条件或目标，以及为什么需要这次变更。

## 实现说明

- 说明关键方案、受影响的组件和非显而易见的取舍；不逐文件复述 diff。

## 验证

- `实际执行的命令`：通过（简要结果）。
- 手工验证：平台 / 设备 / 操作 / 结果。
- 未执行项：明确原因与剩余风险；不得将未执行的检查写成已通过。

## 风险与影响

- 说明用户可见行为、兼容性 / 迁移、数据、安全和性能影响，以及必要的回滚或缓解方式。

## 审查重点

- 指出希望人工审查优先关注的文件、边界、取舍或仍有不确定性的部分。
```

#### 撰写与发布规则

- 只记录当前 PR head 已实现、已验证的事实；新增 commit 改变了范围、方案、验证或风险时，必须同步更新正文。
- 提请审查前先自审 base...head 完整 diff，确认没有意外文件、调试代码、敏感信息或与主题无关的变更，并确认正文与实际 diff 一致。
- 用可回读的 UTF-8 Markdown 文件传入 `gh pr create --body-file <path>`，不在 PowerShell 的 `--body` 参数中手工拼接多行文本和转义字符。
- 创建后必须用 `gh pr view --json title,body,baseRefName,headRefName,isDraft,url` 回读，确认标题、正文、base/head、draft 状态和 URL 正确。
- 尚未准备好接受人工审查时使用 draft PR；验证证据和正文齐备后再标记 Ready for review。

#### Sourcery AI 自动审查

仓库已接入 [Sourcery AI GitHub App](https://github.com/apps/sourcery-ai)。Sourcery 是补充审查者，不是验证命令、人工审查或 PR 正文的替代品。

- Sourcery 默认在 PR 打开及新 commit push 后审查，draft PR 默认跳过；标记 Ready for review 后确认 `Sourcery review` check 已触发。
- Sourcery 会在 PR 正文中追加自己的摘要，并发布 reviewer guide、inline comments 和 status check。人工撰写的六个章节仍必须完整；后续编辑正文时保留 Sourcery 生成的区块。
- 自动 re-review 不会重新生成摘要，摘要过期时发布独立评论 `@sourcery-ai summary`；需要重新完整审查或自动 re-review 计数已用尽时，发布独立评论 `@sourcery-ai review`。
- 对 Sourcery 意见先对照需求、代码和可复现证据判断是否成立，再决定接受、修正或拒绝；不得无条件套用自动建议。
- 每条意见都要有可追踪结果：成立则修改并回归验证，不成立则简要说明证据，已处理的对话再 resolve；超出本 PR 范围的建议不应顺手扩大当前 diff。

#### 完整示例

以“新增 PR 撰写规范”这类文档变更为例。示例只展示结构和证据粒度，实际使用时必须替换为当前 PR 的真实内容，禁止机械照抄。

```markdown
PR 标题：

docs: 规范 Pull Request 描述与 Sourcery 审查流程

PR 正文：

## 变更摘要

- 在 `AGENTS.md` 中增加 Pull Request 标题与正文规范。
- 提供统一的中文 PR 描述模板。
- 补充 Sourcery AI 自动审查的处理流程。

## 变更原因

仓库已启用 Sourcery AI 自动审查，但目前缺少统一的 PR 描述要求。不同作者可能遗漏变更背景、验证证据或审查重点，影响人工审查和自动审查对改动意图的理解。

## 实现说明

- PR 标题沿用 Conventional Commit 前缀，描述使用简体中文。
- PR 正文统一包含变更摘要、变更原因、实现说明、验证、风险与影响、审查重点。
- 要求如实记录已执行的验证命令与结果。
- 说明 Sourcery 的自动摘要、重新审查命令和反馈处理要求。

## 验证

- `git diff --check master...HEAD`：通过。
- 人工检查 `AGENTS.md` 的 Markdown 层级、列表缩进和示例格式：通过。
- 未运行 Flutter 测试：本次仅修改协作说明，不涉及 Dart、Flutter 或运行时行为。

## 风险与影响

- 仅影响后续 Pull Request 的撰写和审查流程。
- 不修改应用代码、构建配置、依赖或运行时行为。
- 无兼容性或迁移风险。

## 审查重点

- PR 模板是否足够明确且便于直接填写。
- 验证要求是否能阻止未执行测试却声称通过的情况。
- Sourcery 相关说明是否与仓库当前审查流程一致。
```

### 版本号自动 bump（post-commit hook）

安装：`git config core.hooksPath .githooks`。**版本号由 `post-commit` hook 根据 commit message 第一行语义自动 bump，再用 `git commit --amend --no-edit` 并回本次提交**（同批次写入，版本号与本次 commit 语义一致）。`pre-commit` 仅做 >500 行大改动提醒，不碰版本号。

为什么不是 `commit-msg`：只有 `pre-commit` 的 `git add` 能进入本次提交 tree，但 `pre-commit` 运行时拿不到 commit message；`commit-msg` / `prepare-commit-msg` 能拿到 message，但它们的 `git add` 不进本次 tree（Git 主进程用内存 index 快照、不重读磁盘，改动滞后到下一个 commit）。`post-commit` 在提交完成后读本次 message 并 amend 把版本号并回，兼顾两者。

行为细节：
- 读 `HEAD:pubspec.yaml` 当前版本 + 本次 message，按前缀算新版本，`sed` 改 `pubspec.yaml`，`git add` 后 `git commit --amend --no-edit --no-verify` 并入本次提交。
- **幂等**：对比第一 parent 版本判断「已为本次 message bump 过」则跳过--手动 `git commit --amend`（不改 message）不会重复 bump。
- **merge commit 跳过**：HEAD 有多个 parent 时不 bump，避免破坏 merge 结构。
- **逃生舱**：`OMLL_SKIP_BUMP=1 git commit ...` 跳过自动 bump。
- 内部用 `OMLL_BUMPING` 环境变量切断 amend 递归触发 post-commit。

| 第一行前缀                              | 版本策略                   |
|------------------------------------|------------------------|
| `type!:` / `type(scope)!:`         | major+1，minor/patch 归零 |
| `feat:` / `feat(scope):`           | minor+1，patch 归零       |
| 其他（fix/docs/refactor/test/chore 等） | patch+1（默认）            |

### commit message 格式

**commit message 一律使用简体中文**：subject 描述与 body 均用中文撰写；`type(scope):` 前缀保留 conventional 语义（英文小写，post-commit 版本 bump 按前缀判断，不得改写成中文）。测试类提交同理（如 `test(media): 移除过时的双击等待`）。

直接在当前 PowerShell 中调用 `git commit`，不要把 PowerShell here-string 作为文本转交给 Bash。常规多段消息使用多个 `-m`，复杂消息先赋给 PowerShell 变量再作为单个参数传入：

```powershell
# 方案 1：多个 -m 逐段追加（推荐，跨 shell 也最稳定）
git commit -m "feat: 简短描述（hook 只看第一行）" -m "详细 body" -m "更多 body"

# 方案 2：PowerShell here-string（复杂消息）
$Message = @'
feat: 简短描述

详细 body
'@
git commit -m $Message
```

### 提交粒度

每个功能点 / 修复单独提交，不批量合并无关改动。改动 >500 行且无标准前缀时 pre-commit 会提醒，但不阻塞。

### 提交前格式化（强制）

**每次提交前必须对本次改动的所有 Dart 文件执行 `dart format`，并在暂存后再次检查格式。**CI 会严格校验格式，即使仅一行未格式化也会失败。建议流程：先用 `git diff --name-only -- '*.dart'` 确认文件，再执行 `dart format <文件列表>`，随后 `git add` 并运行 `dart format --output=none --set-exit-if-changed <暂存的 Dart 文件列表>`；后者非零退出时不得提交。

---

## 3. 架构

### 分层（所有 feature 一致）

```
lib/
  app/                      # app 入口、路由、shell、theme、跨 feature composition
  bootstrap.dart            # 启动初始化
  core/                     # 跨 feature 基础设施（persistence / http / logging / utils / widgets）
  features/<feature>/
    domain/                 # 纯数据模型（Equatable），零框架依赖
    data/                   # Repository 实现、网络客户端、SSE 解析
    application/            # Riverpod Notifier、纯业务函数、上层所需 ports
    presentation/           # Screen / Widget
```

**单向依赖**：`presentation -> application -> domain`；`data -> domain`（+ `core/`）。

**禁忌**：
- `presentation` 不直接 `import` `data/` 或 `core/persistence/`，只通过 `ref.watch` / `ref.read` 消费 `application/` 的 Provider。
- `application` 所需接口归 `application/ports/`（或中性 domain contract）所有；`data` 只提供具体实现，绑定由 `app/composition/` / `bootstrap.dart` 完成。
- 跨 feature 组合通过少量 application facade/command 与 `app/composition/` 完成；一个 feature 的 presentation 不得直接嵌入另一个 feature 的内部 presentation。
- `domain` 零依赖，不导入 Flutter / Riverpod / sqlite3。
- `dart run tool/check_import_boundaries.dart` 是 CI 门禁；禁止用宽泛 allowlist 绕过，例外必须窄、可解释且会检测 stale allowance。

### 启动顺序（`bootstrap.dart`）

`bootstrap()` 接受五个可选参数用于测试注入：`sharedPreferences` / `database` / `networkLogger` / `windowsWindowInitializer` / `hostPlatform`。生产全部传 `null`，由内部 `.getInstance()` / `.open()` / `.create()` 获取；测试传实例注入，并可用 `hostPlatform` 显式指定目标平台（不改全局平台状态）、用 `windowsWindowInitializer` 注入 no-op 的 window runtime，避免测试依赖注册原生插件。

顺序：`WidgetsFlutterBinding.ensureInitialized()` -> Windows window runtime 初始化（仅 Windows 平台，生产调用 `windowManager.ensureInitialized()`）-> `SharedPreferences.getInstance()` -> `AppDatabase.open()` -> `AppNetworkLogger.create(directoryPath: db.path 父目录)` -> `logger.onAppLaunch()` -> `runApp(ProviderScope(...))`。

- `database` 与 `networkLogger` 成对：传 `database` 时 logger 不会自动按其路径建日志。
- network logger 依赖 `AppDatabase.path`，必须在 database 之后初始化。日志文件 `{db_parent}/network.log`，10MB 滚动。
- Provider overrides 注入 `sharedPreferencesProvider` / `appDatabaseProvider` / `appNetworkLoggerProvider` / `customHeadersMapProvider`。

### 持久化分工

| 数据                                            | 存储                                                       |
|-----------------------------------------------|----------------------------------------------------------|
| 聊天记录、消息树选择、收藏、收藏夹、Prompt 模板、固定顺序提示词、记忆提示词、检查点 | SQLite（`chat_history.sqlite`）                            |
| 服务商/模型配置、聊天默认值、最近选择记忆                         | SharedPreferences JSON（经 `VersionedJsonStorage` 带版本号编解码） |

**SQLite 基础设施**（`core/persistence/`）：
- `AppDatabase`：`.open()`（生产，`getApplicationSupportDirectory`）/ `.inMemory()`（测试）/ `.forPath()`（跨 Isolate）。构造自动 `_configure()`（PRAGMA）+ `_initializeSchema()`（滚动基线校验）。
- **滚动迁移基线（rolling baseline）**：schema 用 `PRAGMA user_version` 表达，当前基线为 `AppDatabase.currentSchemaVersion`。全新数据库直接创建完整当前 schema 并标记基线版本；等于基线的数据库正常打开、不迁移；低于或高于基线的数据库显式拒绝（`AppDatabaseSchemaVersionException`）。schema / `user_version` 断言用 `>=`，不用 `==`。
- **临时迁移只允许存在一步**：引入新版本时，只保留「最后一个仍支持的旧基线 → 新版本」的临时迁移；两端受控终端升级确认后，把基线推进到新版本并删除该迁移，让全新安装直接创建新 schema。历史迁移链通常保持 0~1 步，不保留无限累加的逐级迁移。
- 历史 JSON / settings 交换格式别名遵循同样的有界生命周期：当前格式是唯一 canonical，退出支持的旧格式必须显式失败，不做静默 fallback。
- **compatibility shim 必须有退出条件**：新增时同时说明为什么需要、位于哪个边界、何时可删除、由哪些测试保护；一次性 canonicalization 类临时代码不得变成新的永久迁移层。
- `SqliteEntityRepository<T>`：泛型基类，适用「全量加载 + 全量写入」。声明式配置 `tableName` / `selectColumns` / `insertColumns` / `rowToEntity` / `entityToValues`。
- `HasIdAndUpdatedAt` mixin：泛型约束，配合 `SettingsEntityController<T extends HasIdAndUpdatedAt>`。
- `BackgroundChatConversationRepository`：将写入委托到后台 Isolate，**80ms 防抖合并**。高频流式写入走这里，避免阻塞 UI。

### 状态管理（Riverpod）

- Provider 命名 `xxxProvider`；控制器类 `XxxController extends Notifier<XxxState>`，类名不带 `Provider`。
- 派生数据用 `Provider` + `ref.watch(xxxProvider.select((s) => s.field))`，避免不必要重建。
- 大控制器用 **mixin 拆分**（如 `ChatSessionsController` = 主体 + `ChatSessionsControllerStreaming` + `ChatSessionsControllerSupport`），通过 `import` 引入。
- `SettingsEntityController<T>`：模板方法基类，子类只提供 `repository`。
- Settings controller/model 示例按领域分组：`features/settings/application/preferences/chat_defaults_controller.dart` 对应 `features/settings/domain/models/preferences/chat_defaults.dart`；`features/settings/application/providers/llm_model_configs_controller.dart` / `features/settings/domain/models/providers/llm_model_config.dart`、`features/settings/application/prompts/template_prompts_controller.dart` / `features/settings/domain/models/prompts/template_prompt.dart`、`features/settings/application/transfer/settings_transfer_workflow.dart` / `features/settings/domain/models/transfer/settings_export_data.dart` 分别使用对应子目录。

### Chat generation 与 workspace ownership

- Generation 时序由 `ChatGenerationCoordinator` / `ChatGenerationRun` 独占：prepare、stream、stop、cancel、retry、finalize 与持久化终态必须经过显式 `ChatGenerationPhase` / `ChatGenerationOutcome`。`ChatSessionsState` 中兼容字段只是生命周期快照的投影，不得另建第二套 flag 状态机。
- Workspace 数据以不可变 `ChatWorkspaceViewState` / `ChatWorkspaceBindings` 传递；bindings 只在 build 时组合，不持久化 UI controller。
- Composer 会话草稿归 `ComposerDraftController`；编辑事务、焦点、滚动等纯页面状态留在 `ChatScreen` 本地。切换会话不得泄漏模板变量或编辑快照。

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
- **`isStreaming` 不持久化**（仅内存 UI 状态）；`finishReason` 持久化（当前 schema 的列）。
- **流式 300ms 节流**在 UI 刷新层（`streamUiFlushInterval`），不在 SSE 解析层。流式增量存独立 `ChatStreamingReply`，不直接写会话列表，避免侧栏等无关组件重建。
- **自动重试**：异常 `finish_reason`（如 `length`）触发重试，见 `chat_sessions_controller.dart` `_sendWithOptionalAutoRetry`。
- **输出正则**：`output_regex_processor.dart` 按 `order` 升序链式应用，带 `RegExp` 编译缓存。

---

## 5. 流式与厂商适配

网络层用原始 `package:http`，无官方 SDK。协议差异由三个协议客户端 + 共享传输/解码层处理，不按 host 做厂商适配：

- **HTTP 信任域**：外部 LLM 请求使用 `httpClientProvider`，可注入用户自定义 Header；局域网 Sync/Media peer 请求必须使用 `peerHttpClientProvider`，绝不继承 API key、Cookie 或自定义 Header。请求正文日志默认关闭，只有明确诊断路径可 opt-in；敏感 Header 必须统一脱敏。

- **协议客户端**（`features/chat/data/generation/`）：`chat_completions/chat_completions_client.dart`（Chat Completions；`ChatCompletionsParser` 处理 `[DONE]` / 错误 / JSON 解码，`InlineReasoningTagSplitter` 跨 chunk 解析 `<thought>` / `<thinking>` 标签）、`responses/responses_client.dart`（OpenAI Responses）、`anthropic/anthropic_messages_client.dart`（Anthropic Messages）。各客户端只负责本协议请求编码与增量解析；`protocol_routing_chat_generation_client.dart` 按 `request.target.protocol` 穷举路由，是生产唯一绑定。
- **共享传输**（`core/http/llm_http_stream_transport.dart`）：发起流式 POST、包装连接异常与非 2xx 响应；SSE 行/事件边界解码与 idle timeout 由 `SseEventDecoder`（`core/http/sse_event_decoder.dart`）负责。
- **SSE idle timeout**：仅在 `data:` 行到达时重置计时器，SSE 注释行 keepalive 不算活动。

### Sync 安全与协议

- UDP 只承担发现；所有业务数据必须经过 HTTP 配对与授权，不能存在匿名兼容入口。
- 当前 Sync v3 使用一次性配对码、持久化 peer identity/secret、加密 payload、短期 session token 与 nonce replay 防护。新增消息必须进入 typed `SyncProtocolMessage`，不得退回动态 Map 或二次 JSON 字符串。
- 协议版本与 Settings export format 都有 supported range、迁移/拒绝语义；旧版、未来版或 malformed payload 必须显式失败。
- 服务商 API key、自定义 Header 等敏感分类在请求端和导入端都需要显式确认；不得仅凭“同一局域网”视为可信。

### 导航、响应式与可访问性

- 收藏详情和媒体页面使用 GoRouter 的可序列化 ID/query 参数；禁止用 `state.extra` 传 domain entity，也不要在 feature 内新增 `MaterialPageRoute` 平行栈。
- 响应式阈值使用 `AppBreakpoints` 的 shell/content/form/bubble 语义 token；局部约束可以保留，但不得复制同义魔法数。
- 关键自绘交互必须提供非重复的 Semantics、键盘等价操作、可见焦点和 disabled/selected/live 状态；普通 Material 控件不重复包无价值 Semantics。
- 响应式组件优先使用 `LayoutBuilder` 获取父级实际宽度；除 app shell 等窗口级职责外，不用整窗宽度决策，也不按 Windows/Android/手机/平板标签切换布局。
- 连续网格使用 `AppAdaptiveGrid` 与 feature-owned 规格约束项目最大宽度；不要用固定列数模拟设备适配。固定列数只有在列数本身是稳定业务契约时才能保留并解释。
- 共享间距、圆角、内容限宽与命中区域使用 `AppSpacing` / `AppRadii` / `AppContentWidths` / `AppInteractionSizes`；局部业务几何可保留，不为追求零数字机械迁移。
- 密度偏好由各 feature 独立拥有；平台只可在 app composition 提供无持久化值时的默认密度，不建立全局密度开关。

---

## 6. 代码规范

- 注释**简体中文**。`///` doc，`//` 行间注释写「为什么」不写「做了什么」。
- **测试名称一律使用简体中文**：`test(...)` / `testWidgets(...)` 标题描述触发条件与预期行为时用中文撰写，不得使用英文标题。
- **禁止留下临时性审查/重构编号**：注释里不得出现 `P1-2`、`Phase 9`、`第一轮审查` 等指向某次审查计划或重构阶段的编号引用。这类编号是开发过程的临时路标，重构完成后必须清除；留下的注释应描述「代码为什么这么写」，而非「这次改动对应计划第几节」。如需追溯某次改动的来由，查 git history 与 `docs/` 下的计划文档，不要把编号刻进代码。测试用例标题与注释同样适用。
- **禁止 `part` / `part of`**，大文件用 `import` / `export` 拆分（全项目零 `part of`）。
- **导入路径风格**：跨 feature、跨 `core/`、跨 `app/` 的引用一律用 `package:oh_my_llm/...` 根路径（如 `import 'package:oh_my_llm/core/http/http_route_handler.dart';`），不用 `../../..` 深相对路径--文件在 feature 内挪位置时跨层 import 不必改。同一 feature 内部用相对路径（`../application/...`），更简洁。`package:oh_my_llm/` 只解析到 `lib/`，`test/` 文件互引只能用相对路径。
- 大类内部用 `// ── 分类 ────────────────────────────────────────────` 分隔线组织方法块。
- 数据模型用 `Equatable`。

---

## 7. 测试

### 基础设施

- `test/helpers/test_harness.dart` 的 `pumpTestApp()` 统一封装：内存 DB、视口、`ProviderScope`、tearDown 清理。**返回 `AppDatabase`**，需直接验证 SQL 时捕获。
  - `child` 与 `router` 互斥（至少传其一）；默认视口 `1440×1200`。
  - 注入 `appDatabaseProvider` / `sharedPreferencesProvider` / `customHeadersMapProvider`，可用 `extraOverrides` 追加。
  - 内部用 `createTestDatabase(preferences)`（`test/test_database.dart`）建内存库。
- `TestFixtures`（`fixtures.dart`）：类型安全工厂，返回真实模型对象（编译期检查），需 JSON 时用模型 `toJson`。typed factory：`model()` / `gpt41()` / `claudeSonnet()` / `deepSeekV4()` / `promptMessage()` / `presetPrompt()` / `codeAssistantPrompt()` / `fixedSequence()` / `sequenceStep()` …。`seedPreferences()` 批量注入 SharedPreferences。普通有效数据**不要手写 JSON**；malformed、旧版/未来版兼容、迁移与协议解码错误测试可直接构造原始 Map/JSON，但测试名称或注释必须说明所验证的边界。

### Widget 测试约定

- **Setup 默认用 `pump()`，不用 `pumpAndSettle()`**：数据层（sqlite3、SharedPreferences getter）完全同步，通常单帧即可。异步或动画场景优先等待可观察的完成条件（Provider 状态、受控 stream、`Completer`、Repository ACK、IO Future 或有限动画状态）；仅 test body 确实需要等待已知有限动画时使用 `pumpAndSettle()`，不得把它当作通用“稳定一下”。
- `FakeChatGenerationClient extends ChatGenerationClient` **只 `@override` `streamCompletion()`**，`complete()` 继承基类，不要重新实现。配 `enqueueChunks` / `enqueueDeltas` / `enqueueError` 排队响应，`requestHistory` / `requestedTargets` / `lastRequest` 记录调用。
- 种子数据走 Repository API（`seedFavorite()` / `seedCollection()`）或 `TestFixtures.seedPreferences()`，**不要在 widget 测试写 raw SQL**。

### 文件组织（case-file decomposition）

```
test/features/chat/presentation/
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

### 缺陷回归测试补充标准

- 已确认缺陷影响稳定的产品行为、持久化数据、协议兼容、安全边界或跨层 wiring，且能确定性复现时，必须补回归测试；安全、数据丢失和兼容性缺陷优先保留边界级验证。
- 新增前先检查现有测试。若已有测试本应捕获该缺陷，优先补强其输入或断言；只有外部契约、测试层级或预期失败原因不同，才新增独立用例。
- 回归测试必须证明修复前失败、修复后通过。可先写失败测试，或临时撤回最小修复验证失败后立即恢复；交付记录需包含这组 red/green 证据，不得只凭修复后单次通过声称具备回归保护。
- 在能暴露根因的最低稳定层测试：纯函数和状态分支用单元测试，Repository/协议边界用边界测试；只有缺陷来自真实 composition、生命周期或跨层数据流时才增加 Widget/integration 测试。
- 不为框架既有行为、私有实现细节、一次性环境故障、无法稳定复现的 timing flake、无契约要求的非法输入或已被同层测试覆盖的路径新增回归测试。Timing 问题应先找到可观察完成信号；安全与兼容性要求的 malformed 输入不属于此处的“无契约非法输入”。
- 测试名称描述触发条件和预期行为，不写临时 Issue、审查或阶段编号。回归测试仍是普通产品契约，可以参数化、迁移或与同契约测试合并；清理时必须指出继续承担该契约的测试。
- 缺陷修复与其聚焦回归测试原则上放在同一个功能提交中；不得把无关覆盖率补测混入该提交。

### 测试清理与去重

- 删除测试前必须回答：哪个具体产品行为退化时该测试会独立失败；删除后哪个现存测试仍验证同一契约。无法指出产品行为的构造器、类型、框架转发或恒真断言应删除。
- 行覆盖相同或操作相似不代表重复；只有**外部契约、测试层级和预期失败原因**都相同时才视为重复。不同层级对同一能力的互补验证可以保留。
- 不要求限定目录的行覆盖率绝对不下降，但每一处下降必须归类为：已由其他测试覆盖、仅覆盖非业务代码，或意外丢失的行为覆盖。最后一种必须恢复；行覆盖率是诊断证据，不是保留低价值测试的理由。
- integration 测试必须经过真实生产 wiring 或真实边界产生并验证下游结果。手工把控制器 A 的数据复制给控制器 B，不算集成测试。
- 测试不得提前完成待验证动作，再把结果归因给被测对象。例如注入前已经迁移完成的数据库，不能证明 bootstrap 执行了迁移。
- 当前 schema 契约集中验证一次；若存在临时基线迁移（旧基线→新版本），测试从旧基线起步，重点断言数据保留与迁移语义，不重复验证当前 schema 的全部列；历史逐级迁移测试随迁移一起退役。

### 反模式与脆弱红线

**禁止**：
- ❌ 断言 widget 实现细节：依赖未声明为稳定测试契约的内部 `Key`、用 `findsNothing` on 具体 widget 类型替代可观察行为断言、像素位置、widget 属性值（`maxLines` / `expands` 等）。公开稳定 Key 确实是导航/集成契约时可以使用，但需注明原因；仍优先使用可见文本、Semantics 和真实交互。
- ❌ controller 层测 ON DELETE SET NULL / 外键级联（属 schema 测试）。
- ❌ 条件 early-return 测试（必须执行到 `expect`）。
- ❌ schema / `user_version` 断言用 `==`（用 `>=`）。
- ❌ `getTopLeft().dy` / `getRect()` 比较；依赖 ID 字母序＝时间序巧合的排序测试；`chunkDelay` + `pump(delay+2ms)` 微秒级 timing 依赖。
- ❌ 用 `Future.delayed(Duration.zero)`、任意固定延迟或无条件 `pumpAndSettle()` 充当异步 flush。应等待真实完成信号；资源释放等例外必须窄化、解释并进入精确 allowlist。

**结构规范**：
- 结构相同的 round-trip / error-type / 比较器测试用循环或 `for` 参数化，不手动复制 4+ 次。
- 同一文件重复 setUp 提取到 `setUp` / 共享 helper。
- Widget 测试线性操作 >30 行是拆分审查信号，而非机械上限；当测试包含多个行为场景，或准备/操作细节掩盖核心断言时再提取 helper。一个完整连贯的用户场景可以保留较长流程，但仍只验证一个交互场景。
- 敏感字段脱敏测试全覆盖已知键名。

---

## 8. 环境要求

| 平台      | 必要条件                                      |
|---------|-------------------------------------------|
| Windows | Visual Studio 2022（含 **C++ 桌面开发** 工作负载）   |
| Android | Android SDK；JDK（`keytool` 生成自签名 keystore） |
| Flutter | 3.44.x stable（CI 固定 3.44.6）；Dart `^3.11.5` |
