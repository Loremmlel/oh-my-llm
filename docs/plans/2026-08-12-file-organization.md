# File Organization Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变产品行为、公开接口、状态所有权或持久化/协议契约的前提下，将 Chat、Settings、Media、Sync、Core Widgets 与共享测试辅助文件按稳定业务切片重新归档，使 `test/` 镜像 `lib/`，并把 Agent 本地日志统一收口到 ignored `logs/`。

**Architecture:** 保留 `features/<feature>/{domain,data,application,presentation}` 与现有 import boundary，只在 layer 内增加一层按业务能力命名的目录；生产文件与对应测试在同一任务中用 `git mv` 移动，随后仅修正 import/export、测试入口相对路径、活跃文档路径和 Settings 的 7 条精确 allowlist。整个实施分为 9 个日志/结构重构提交和 1 个最终活跃文档提交，最后以全仓路径审计、333 个生产 Dart 文件、163 个测试入口、架构门禁、analyzer 和全量测试共同验收。

**Tech Stack:** Flutter 3.44.x stable（CI 3.44.6，本机规划快照 3.44.8）/ Dart `^3.11.5`（本机规划快照 3.12.2）/ Riverpod 3 / PowerShell 7 / Git `mv` / Flutter Test / 自定义 import-boundary checker。

## Global Constraints

- 本计划以 [已确认设计规格](../specs/2026-08-12-file-organization-design.md) 为唯一范围依据；不得重新解释为 MVVM 迁移、纵向 feature 重切分或大文件拆分。
- 保留 `features/<feature>/<layer>` 的前三层路径语义；`tool/architecture/import_boundary_checker.dart` 的 `_featureLayer()` 算法不得修改。
- 除 import/export、测试入口相对路径、活跃文档路径、测试 ownership 文件名以及 Settings 7 条精确 allowlist 路径外，不修改生产逻辑或测试断言。
- 不改变任何 class、enum、typedef、Provider、方法签名、序列化字段、SQLite schema、Settings export version、Sync protocol version 或 composition ownership。
- 不拆 `chat_sessions_controller.dart`、`chat_screen.dart`、`sync_protocol_message.dart` 或其他生产文件；不新增 `part` / `part of`。
- 不抽取新 port，不消除 Settings application→data 存量债务；allowlist 始终恰好 7 条且必须全部被真实生产边消费。
- 不整理 `lib/core/persistence`、`lib/core/http`、`lib/features/sync/application`、`test/integration` 或 feature-specific test helpers。
- 不新增 package，不新增子目录 barrel；只保留并更新现有 `widgets.dart` 与 `settings_widgets.dart`。
- 跨 feature、跨 `core/`、跨 `app/` import 继续使用 `package:oh_my_llm/...`；同一 feature 内继续使用相对 import。
- `*_cases.dart` 后缀保持不变；测试移动前后 `*_test.dart` 入口数必须均为 163，不能漏跑或重复发现。
- 每个任务只在已验证的仓库根目录执行；不得使用递归宽泛删除。根目录 82 个 `*.log` 的删除已获用户明确授权，但必须逐个验证为根目录直接文件、ignored 且未跟踪。
- 所有本地测试、analyze、boundary 与诊断输出写入 `logs/`；CI 的 runner 根目录 `fltest.log` 和应用 AppData 的 `network.log` 不改。
- 每次提交前对本次变动 Dart 文件执行 `dart format`，暂存后再执行 `dart format --output=none --set-exit-if-changed`。
- commit message 的 subject/body 使用简体中文并保留 conventional 前缀；正常执行仓库 post-commit hook，不手工编辑 hook 生成的版本变化。
- 当前工作区若出现任务范围外改动，停止并保留用户改动；不得用 reset/checkout 覆盖。

---

## 0. Planning Baseline and Execution Contracts

### 0.1 已核对快照

- 计划编写前 HEAD：`851c823`（`docs: 设计项目文件组织重构`）。
- 计划编写前 `git status --short`：无输出。
- `lib/**/*.dart`：333 个。
- `test/**/*_test.dart`：163 个测试入口。
- 仓库根目录直接 `*.log`：82 个，全部 ignored，`git ls-files '*.log'` 无输出。
- Settings 生产 `legacyApplicationDataEdges`：7 条。
- 当前架构门禁：`dart run tool/check_import_boundaries.dart` 输出“检查 333 个文件，0 条违规”，退出码 0。
- 本轮规划未运行 `flutter analyze`、任何 Flutter 测试或全量测试；这些是实施门禁，不能从计划文档推断为已通过。

### 0.2 执行前统一仓库与工作区检查

每个任务开始都运行：

```powershell
$repoRoot = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw '当前目录不是 Git 仓库' }
$repoRoot = (Resolve-Path -LiteralPath $repoRoot).Path
$currentDirectory = (Resolve-Path -LiteralPath '.').Path
if (-not $currentDirectory.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "必须在仓库根目录执行：$repoRoot"
}
$statusBeforeTask = @(git status --short)
if ($statusBeforeTask.Count -ne 0) {
  throw "任务开始前工作区不干净：`n$($statusBeforeTask -join "`n")"
}
New-Item -ItemType Directory -Force -Path 'logs' | Out-Null
```

Expected: 不抛错；Task 1 完成后 `logs/` 被 `/logs/` ignore。Task 1 执行前全局 `*.log` 已使该目录中的日志 ignored。

### 0.3 安全移动与空目录清理 helper

每个含移动的任务在当前 PowerShell 会话定义并使用以下函数。移动矩阵中的 `From` 都是已验证现存文件，`To` 都是计划新路径：

```powershell
function Move-TrackedFile {
  param(
    [Parameter(Mandatory)][string]$From,
    [Parameter(Mandatory)][string]$To
  )

  if (-not (Test-Path -LiteralPath $From -PathType Leaf)) {
    throw "源文件不存在：$From"
  }
  if (Test-Path -LiteralPath $To) {
    throw "目标已存在：$To"
  }

  $targetParent = Split-Path -Parent $To
  New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
  $resolvedParent = (Resolve-Path -LiteralPath $targetParent).Path
  $repoPrefix = "$repoRoot$([IO.Path]::DirectorySeparatorChar)"
  if (-not $resolvedParent.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "目标目录越出仓库：$resolvedParent"
  }

  git mv -- $From $To
  if ($LASTEXITCODE -ne 0) { throw "git mv 失败：$From -> $To" }
}

function Remove-KnownEmptyDirectory {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $repoPrefix = "$repoRoot$([IO.Path]::DirectorySeparatorChar)"
  if (-not $resolved.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "待删目录越出仓库：$resolved"
  }
  if (@(Get-ChildItem -LiteralPath $resolved -Force).Count -ne 0) {
    throw "目录非空，拒绝删除：$Path"
  }
  Remove-Item -LiteralPath $resolved
}
```

不得把 `Remove-KnownEmptyDirectory` 改成递归删除，也不得传入设计未列出的目录。

### 0.4 Import/export 机械迁移合同

对每一行 `旧路径 -> 新路径` 执行以下确定性规则：

1. 若旧路径以 `lib/` 开头，将全仓每个
   `package:oh_my_llm/<旧路径去掉 lib/>` 精确替换为
   `package:oh_my_llm/<新路径去掉 lib/>`。
2. 对被移动文件自身的相对 import/export，按新目录重新计算 URI，但目标声明必须与
   移动前完全相同；不得趁机改成 package import 或改变依赖层级。
3. 对移动后的测试 case/helper 相对 import，同样只重算到相同入口或 helper 的 URI。
4. 内容改动必须用 `apply_patch`；禁止用脚本对全仓做不受审查的字符串写回。
5. 每个旧 package URI 先用 `rg -l -F` 列出消费者，再逐文件 patch；patch 后同一查询
   必须无命中。历史计划/规格中的快照路径不在机械替换范围，Task 10 单独分类。
6. `test/architecture/import_boundary_checker_test.dart` 中作为字符串 fixture 的路径只在
   Task 2（Chat 当前路径）和 Task 4（Settings allowlist 当前路径）明确更新；刻意构造
   的不存在路径仍可保留。

用于列出消费者的命令模板：

```powershell
$oldPackageUri = 'package:oh_my_llm/features/example/old.dart'
rg -l -F $oldPackageUri lib test tool
```

### 0.5 每个 Dart 任务的格式、差异与门禁模板

移动和 import 更新完成后：

```powershell
$changedDartFiles = @(
  git diff --name-only --diff-filter=ACMR -- '*.dart' |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
)
if ($changedDartFiles.Count -eq 0) { throw '预期存在变动 Dart 文件' }
dart format $changedDartFiles
if ($LASTEXITCODE -ne 0) { throw 'dart format 失败' }

git diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check 失败' }
git diff --find-renames=50% --summary
git diff --find-renames=50% --stat
```

审阅普通 diff，确认生产 Dart 内容仅有 import/export URI 变化；若出现方法体、声明、
常量值、测试断言或测试标题变化，停止并撤回该非路径改动。

每个 Dart 任务在目标测试通过后还运行：

```powershell
dart run tool/check_import_boundaries.dart 2>&1 |
  Out-File -Encoding utf8 'logs/current-task-boundary.log'
$currentTaskBoundaryExit = $LASTEXITCODE
Write-Host "BOUNDARY_EXIT=$currentTaskBoundaryExit"
Get-Content -Tail 80 'logs/current-task-boundary.log'
if ($currentTaskBoundaryExit -ne 0) { throw '架构门禁失败' }
```

提交前暂存任务精确范围，然后：

```powershell
$stagedDartFiles = @(
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart' |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
)
if ($stagedDartFiles.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $stagedDartFiles
  if ($LASTEXITCODE -ne 0) { throw '暂存 Dart 文件格式检查失败' }
}
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw '暂存 diff 检查失败' }
```

---

### Task 1: 清理根目录 Agent 日志并建立 `logs/` 规范

**Files:**
- Modify: `.gitignore`
- Modify: `AGENTS.md`
- Modify: `README.md`
- Delete locally, untracked/ignored only: repository-root direct `*.log`（规划快照 82 个）
- Preserve: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: 用户明确授权删除可再生成的根目录 Agent 日志；现有全局 `*.log` ignore。
- Produces: `/logs/` 本地日志契约；本地测试默认 `logs/fltest.log`；CI 仍上传 runner 根目录 `fltest.log`；AppData `network.log` 不变。

- [ ] **Step 1: 再次解析精确删除目标并验证全部 ignored、未跟踪**

```powershell
$repoRoot = (Resolve-Path -LiteralPath (git rev-parse --show-toplevel).Trim()).Path
if (-not (Resolve-Path -LiteralPath '.').Path.Equals(
    $repoRoot,
    [StringComparison]::OrdinalIgnoreCase
  )) { throw '不在仓库根目录' }

$rootLogs = @(Get-ChildItem -LiteralPath $repoRoot -File -Filter '*.log')
if ($rootLogs.Count -eq 0) { throw '未发现预期的根目录 Agent 日志，请重新确认环境' }

foreach ($log in $rootLogs) {
  if (-not $log.DirectoryName.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "日志不在仓库根目录：$($log.FullName)"
  }
  $relative = $log.Name
  git check-ignore -q -- $relative
  if ($LASTEXITCODE -ne 0) { throw "日志未被 ignore：$relative" }
  git ls-files --error-unmatch -- $relative 2>$null
  if ($LASTEXITCODE -eq 0) { throw "日志已被 Git 跟踪，拒绝删除：$relative" }
}

$rootLogs | Sort-Object Name | Select-Object Name,Length,LastWriteTime
Write-Host "ROOT_LOG_COUNT=$($rootLogs.Count)"
```

Expected: 当前快照 `ROOT_LOG_COUNT=82`。若数量变化可以继续，但每个文件仍必须通过三项安全验证；若出现 tracked 或 non-ignored 文件立即停止。

- [ ] **Step 2: 只删除已验证的根目录直接日志**

```powershell
foreach ($log in $rootLogs) {
  Remove-Item -LiteralPath $log.FullName
}
if (@(Get-ChildItem -LiteralPath $repoRoot -File -Filter '*.log').Count -ne 0) {
  throw '根目录仍残留 *.log'
}
```

Expected: 根目录直接 `*.log` 为 0。删除不可从 Git 恢复，但这些文件均为 ignored、可再生成 Agent 产物，用户已明确要求删除。

- [ ] **Step 3: 用 `apply_patch` 修改 ignore 规则**

将 `.gitignore` 开头的：

```gitignore
.buildlog/
```

精确替换为：

```gitignore
/logs/
```

保留全局 `*.log`，不得修改 `/artifacts/` 或 Android signing ignore。

- [ ] **Step 4: 用 `apply_patch` 扩充 `AGENTS.md` 日志规范**

将“测试输出重定向”命令改为：

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log; $TestExit = $LASTEXITCODE; Write-Host "EXIT=$TestExit"; Get-Content -Tail 150 logs/fltest.log
```

并在该小节明确写入：

```markdown
- Agent 执行测试、`flutter analyze`、构建或诊断时，日志必须写入仓库根目录下 ignored 的 `logs/`，禁止在仓库根目录直接生成 `*.log`。
- 写日志前先执行 `New-Item -ItemType Directory -Force logs | Out-Null`。全量测试使用 `logs/fltest.log`；red/green 证据使用能表达任务的 `logs/<任务>-red.log` / `logs/<任务>-green.log`。
- `logs/` 内容是可再生成的本地产物，可以覆盖或清理；CI runner 根目录的 `fltest.log` 上传流程和应用 AppData 的 `network.log` 不受本规则影响。
```

同时把原有 `Select-String`、失败摘要和“完整日志”示例路径全部改为
`logs/fltest.log`。在构建脚本小节补充：Agent 若重定向脚本输出，Windows/Android
分别使用 `logs/build-windows.log`、`logs/build-android.log`。

- [ ] **Step 5: 用 `apply_patch` 同步 README 的本地测试命令**

README“开发指南”中的全量测试改为相同的 `logs/fltest.log` PowerShell 命令；不要修改
README 对应用 `{AppData}/network.log` 的说明，也不要修改 CI workflow。

- [ ] **Step 6: 验证日志规范**

```powershell
git check-ignore -q --no-index logs/fltest.log
if ($LASTEXITCODE -ne 0) { throw 'logs/fltest.log 未被 ignore' }
if (Test-Path -LiteralPath '.buildlog') { throw '未使用的 .buildlog 仍存在' }
if (@(Get-ChildItem -LiteralPath '.' -File -Filter '*.log').Count -ne 0) {
  throw '仓库根目录仍存在 *.log'
}
rg -n "Out-File.*fltest\.log|Select-String.*fltest\.log|Get-Content.*fltest\.log" AGENTS.md README.md
rg -n "fltest\.log" .github/workflows/ci.yml
git diff --check
```

Expected: AGENTS/README 的本地命令只命中 `logs/fltest.log`；CI 仍命中根目录
`fltest.log`；根目录日志为 0。

- [ ] **Step 7: 提交日志规范**

```powershell
git add -- .gitignore AGENTS.md README.md
git diff --cached --check
git commit -m "chore: 统一 Agent 本地日志目录"
```

Expected: 提交只含三个跟踪文件；被删除的 82 个 ignored 日志不会出现在 Git diff。

---

### Task 2: 重组 Chat application、data、domain tests

**Files:**
- Move: `lib/features/chat/application/*.dart`（ports 除外）到 8 个业务切片
- Move: `lib/features/chat/data/**` 到 `generation/`、`persistence/`
- Move: `test/features/chat/application/**`、`test/features/chat/data/**` 和选定 domain tests
- Rename/Move: `test/features/chat/chat_conversation_repository_test.dart` -> `test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart`
- Modify: all production/test/composition consumers returned by the exact package-URI map
- Modify: `test/architecture/import_boundary_checker_test.dart`（Chat fixture 路径）

**Interfaces:**
- Consumes: 现有 `ChatGenerationClient`、`ChatConversationRepository` ports 与所有公开 Chat application/data declarations。
- Produces: 相同 declarations、相同 Provider 与 composition binding，只在新 URI 暴露；ports 原路径不变。

- [ ] **Step 1: 验证并执行 production application 精确移动矩阵**

```text
lib/features/chat/application/chat_composer_command.dart -> lib/features/chat/application/composer/chat_composer_command.dart
lib/features/chat/application/composer_collapsed_controller.dart -> lib/features/chat/application/composer/composer_collapsed_controller.dart
lib/features/chat/application/composer_draft_controller.dart -> lib/features/chat/application/composer/composer_draft_controller.dart
lib/features/chat/application/templated_user_message_builder.dart -> lib/features/chat/application/composer/templated_user_message_builder.dart
lib/features/chat/application/chat_favorite_intent_command.dart -> lib/features/chat/application/favorites/chat_favorite_intent_command.dart
lib/features/chat/application/chat_favorites_facade.dart -> lib/features/chat/application/favorites/chat_favorites_facade.dart
lib/features/chat/application/chat_generation_contract.dart -> lib/features/chat/application/generation/chat_generation_contract.dart
lib/features/chat/application/chat_generation_coordinator.dart -> lib/features/chat/application/generation/chat_generation_coordinator.dart
lib/features/chat/application/chat_generation_lifecycle.dart -> lib/features/chat/application/generation/chat_generation_lifecycle.dart
lib/features/chat/application/chat_generation_run.dart -> lib/features/chat/application/generation/chat_generation_run.dart
lib/features/chat/application/output_regex_processor.dart -> lib/features/chat/application/generation/output_regex_processor.dart
lib/features/chat/application/history_pagination_controller.dart -> lib/features/chat/application/history/history_pagination_controller.dart
lib/features/chat/application/chat_request_message_builder.dart -> lib/features/chat/application/requests/chat_request_message_builder.dart
lib/features/chat/application/checkpoint_request_context.dart -> lib/features/chat/application/requests/checkpoint_request_context.dart
lib/features/chat/application/request_message_filter.dart -> lib/features/chat/application/requests/request_message_filter.dart
lib/features/chat/application/chat_message_tree.dart -> lib/features/chat/application/sessions/chat_message_tree.dart
lib/features/chat/application/chat_sessions_controller.dart -> lib/features/chat/application/sessions/chat_sessions_controller.dart
lib/features/chat/application/chat_sessions_controller_streaming.dart -> lib/features/chat/application/sessions/chat_sessions_controller_streaming.dart
lib/features/chat/application/chat_sessions_controller_support.dart -> lib/features/chat/application/sessions/chat_sessions_controller_support.dart
lib/features/chat/application/chat_sessions_state.dart -> lib/features/chat/application/sessions/chat_sessions_state.dart
lib/features/chat/application/chat_sidebar_controller.dart -> lib/features/chat/application/sidebar/chat_sidebar_controller.dart
lib/features/chat/application/chat_workspace_view_state.dart -> lib/features/chat/application/workspace/chat_workspace_view_state.dart
```

`lib/features/chat/application/ports/*.dart` 不移动。逐行调用 `Move-TrackedFile`。

- [ ] **Step 2: 执行 production data 精确移动矩阵**

```text
lib/features/chat/data/protocol_routing_chat_generation_client.dart -> lib/features/chat/data/generation/protocol_routing_chat_generation_client.dart
lib/features/chat/data/anthropic/anthropic_message_transformer.dart -> lib/features/chat/data/generation/anthropic/anthropic_message_transformer.dart
lib/features/chat/data/anthropic/anthropic_messages_client.dart -> lib/features/chat/data/generation/anthropic/anthropic_messages_client.dart
lib/features/chat/data/anthropic/anthropic_parser.dart -> lib/features/chat/data/generation/anthropic/anthropic_parser.dart
lib/features/chat/data/chat_completions/chat_completions_client.dart -> lib/features/chat/data/generation/chat_completions/chat_completions_client.dart
lib/features/chat/data/chat_completions/chat_completions_parser.dart -> lib/features/chat/data/generation/chat_completions/chat_completions_parser.dart
lib/features/chat/data/chat_completions/inline_reasoning_tag_splitter.dart -> lib/features/chat/data/generation/chat_completions/inline_reasoning_tag_splitter.dart
lib/features/chat/data/responses/responses_client.dart -> lib/features/chat/data/generation/responses/responses_client.dart
lib/features/chat/data/responses/responses_parser.dart -> lib/features/chat/data/generation/responses/responses_parser.dart
lib/features/chat/data/background_chat_repository.dart -> lib/features/chat/data/persistence/background_chat_repository.dart
lib/features/chat/data/chat_sql_codec.dart -> lib/features/chat/data/persistence/chat_sql_codec.dart
lib/features/chat/data/chat_writer_entry_point.dart -> lib/features/chat/data/persistence/chat_writer_entry_point.dart
lib/features/chat/data/sqlite_chat_conversation_repository.dart -> lib/features/chat/data/persistence/sqlite_chat_conversation_repository.dart
```

移动后仅在确认空时清理：

```powershell
Remove-KnownEmptyDirectory 'lib/features/chat/data/anthropic'
Remove-KnownEmptyDirectory 'lib/features/chat/data/chat_completions'
Remove-KnownEmptyDirectory 'lib/features/chat/data/responses'
```

- [ ] **Step 3: 执行 application test 精确移动矩阵**

```text
test/features/chat/application/chat_composer_command_test.dart -> test/features/chat/application/composer/chat_composer_command_test.dart
test/features/chat/application/composer_collapsed_controller_test.dart -> test/features/chat/application/composer/composer_collapsed_controller_test.dart
test/features/chat/application/composer_draft_controller_test.dart -> test/features/chat/application/composer/composer_draft_controller_test.dart
test/features/chat/application/templated_user_message_builder_test.dart -> test/features/chat/application/composer/templated_user_message_builder_test.dart
test/features/chat/application/chat_favorite_intent_command_test.dart -> test/features/chat/application/favorites/chat_favorite_intent_command_test.dart
test/features/chat/application/chat_favorites_facade_test.dart -> test/features/chat/application/favorites/chat_favorites_facade_test.dart
test/features/chat/application/chat_generation_coordinator_test.dart -> test/features/chat/application/generation/chat_generation_coordinator_test.dart
test/features/chat/application/chat_generation_lifecycle_test.dart -> test/features/chat/application/generation/chat_generation_lifecycle_test.dart
test/features/chat/application/chat_generation_race_contract_test.dart -> test/features/chat/application/generation/chat_generation_race_contract_test.dart
test/features/chat/application/chat_generation_run_test.dart -> test/features/chat/application/generation/chat_generation_run_test.dart
test/features/chat/application/output_regex_processor_test.dart -> test/features/chat/application/generation/output_regex_processor_test.dart
test/features/chat/application/history_pagination_controller_test.dart -> test/features/chat/application/history/history_pagination_controller_test.dart
test/features/chat/application/chat_request_message_builder_test.dart -> test/features/chat/application/requests/chat_request_message_builder_test.dart
test/features/chat/application/checkpoint_request_context_test.dart -> test/features/chat/application/requests/checkpoint_request_context_test.dart
test/features/chat/application/request_message_filter_test.dart -> test/features/chat/application/requests/request_message_filter_test.dart
test/features/chat/application/chat_message_tree_test.dart -> test/features/chat/application/sessions/chat_message_tree_test.dart
test/features/chat/application/chat_sessions_controller_persistence_test.dart -> test/features/chat/application/sessions/chat_sessions_controller_persistence_test.dart
test/features/chat/application/chat_sessions_controller_test.dart -> test/features/chat/application/sessions/chat_sessions_controller_test.dart
test/features/chat/application/chat_sessions_state_test.dart -> test/features/chat/application/sessions/chat_sessions_state_test.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_branching_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_branching_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_checkpoint_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_checkpoint_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_crud_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_crud_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_generation_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_generation_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_retry_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_retry_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_stop_cases.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_stop_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart -> test/features/chat/application/sessions/chat_sessions_controller/chat_sessions_controller_test_helpers.dart
test/features/chat/application/chat_sidebar_controller_test.dart -> test/features/chat/application/sidebar/chat_sidebar_controller_test.dart
test/features/chat/application/chat_workspace_view_state_test.dart -> test/features/chat/application/workspace/chat_workspace_view_state_test.dart
test/features/chat/application/chat_generation_client_contract_test.dart -> test/features/chat/application/ports/chat_generation_client_contract_test.dart
```

移动后清理 `test/features/chat/application/chat_sessions_controller`（仅当空）。

- [ ] **Step 4: 执行 data/domain test 精确移动矩阵**

```text
test/features/chat/data/protocol_routing_chat_generation_client_test.dart -> test/features/chat/data/generation/protocol_routing_chat_generation_client_test.dart
test/features/chat/data/anthropic/anthropic_message_transformer_test.dart -> test/features/chat/data/generation/anthropic/anthropic_message_transformer_test.dart
test/features/chat/data/anthropic/anthropic_messages_client_test.dart -> test/features/chat/data/generation/anthropic/anthropic_messages_client_test.dart
test/features/chat/data/anthropic/anthropic_parser_test.dart -> test/features/chat/data/generation/anthropic/anthropic_parser_test.dart
test/features/chat/data/chat_completions/chat_completions_client_test.dart -> test/features/chat/data/generation/chat_completions/chat_completions_client_test.dart
test/features/chat/data/chat_completions/chat_completions_parser_test.dart -> test/features/chat/data/generation/chat_completions/chat_completions_parser_test.dart
test/features/chat/data/chat_completions/inline_reasoning_tag_splitter_test.dart -> test/features/chat/data/generation/chat_completions/inline_reasoning_tag_splitter_test.dart
test/features/chat/data/responses/responses_client_test.dart -> test/features/chat/data/generation/responses/responses_client_test.dart
test/features/chat/data/responses/responses_parser_test.dart -> test/features/chat/data/generation/responses/responses_parser_test.dart
test/features/chat/data/background_chat_repository_lifecycle_test.dart -> test/features/chat/data/persistence/background_chat_repository_lifecycle_test.dart
test/features/chat/data/background_chat_repository_test.dart -> test/features/chat/data/persistence/background_chat_repository_test.dart
test/features/chat/chat_conversation_repository_test.dart -> test/features/chat/data/persistence/sqlite_chat_conversation_repository_test.dart
test/features/chat/domain/chat_checkpoint_test.dart -> test/features/chat/domain/models/chat_checkpoint_test.dart
test/features/chat/domain/chat_conversation_summary_test.dart -> test/features/chat/domain/models/chat_conversation_summary_test.dart
test/features/chat/domain/chat_conversation_test.dart -> test/features/chat/domain/models/chat_conversation_test.dart
```

`test/features/chat/domain/models/chat_message_test.dart` 已在目标位置；
`chat_conversation_groups_test.dart`、`chat_word_counter_test.dart` 保持 domain 根目录。
清理旧 protocol test 目录时只删确认空目录。

- [ ] **Step 5: 记录结构性 red 证据**

在尚未改 import 前运行：

```powershell
flutter test test/features/chat/application/generation/chat_generation_run_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task2-chat-structure-red.log'
$task2RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task2RedExit"
Get-Content -Tail 80 'logs/task2-chat-structure-red.log'
if ($task2RedExit -eq 0) { throw '预期旧 URI 导致结构性编译失败' }
```

Expected: URI not found / undefined declaration 等由旧 import 路径引起的编译失败。该 red
只证明移动后的 import 尚未迁移，不新增测试或改变行为断言。

- [ ] **Step 6: 按 0.4 用 `apply_patch` 更新所有 import/export 与 Chat 架构 fixture**

重点必须覆盖：

- `lib/app/composition/cross_feature_bindings.dart`、`bootstrap.dart` 及其他 production consumers；
- `test/helpers/*.dart`、`test/integration/*.dart` 与其他 feature tests；
- 新目录内文件的相对 import；
- `test/architecture/import_boundary_checker_test.dart` 中反映当前 Chat 路径的 fixture：
  application sessions、data persistence、data generation；
- ports URI保持 `features/chat/application/ports/...` 不变。

禁止修改方法体和测试断言。

- [ ] **Step 7: 格式化、审阅并运行 Chat non-presentation green**

按 0.5 格式化与审阅，然后：

```powershell
flutter test test/features/chat/application test/features/chat/data test/features/chat/domain test/architecture/import_boundary_checker_test.dart test/integration/bootstrap_integration_test.dart test/integration/chat_lifecycle_integration_test.dart test/integration/chat_message_version_persistence_integration_test.dart test/integration/multi_protocol_chat_generation_integration_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task2-chat-application-data-green.log'
$task2GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task2GreenExit"
Get-Content -Tail 150 'logs/task2-chat-application-data-green.log'
if ($task2GreenExit -ne 0) { throw 'Chat application/data/domain 目标测试失败' }
```

再运行 boundary 模板，日志名改为 `logs/task2-chat-boundary.log`。

- [ ] **Step 8: 审计旧 URI、入口数和提交**

```powershell
$chatOldPackagePatterns = @(
  'package:oh_my_llm/features/chat/application/chat_',
  'package:oh_my_llm/features/chat/application/composer_',
  'package:oh_my_llm/features/chat/application/history_pagination_controller.dart',
  'package:oh_my_llm/features/chat/application/output_regex_processor.dart',
  'package:oh_my_llm/features/chat/application/request_message_filter.dart',
  'package:oh_my_llm/features/chat/application/templated_user_message_builder.dart',
  'package:oh_my_llm/features/chat/data/protocol_routing_chat_generation_client.dart',
  'package:oh_my_llm/features/chat/data/background_chat_repository.dart',
  'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart',
  'package:oh_my_llm/features/chat/data/chat_sql_codec.dart',
  'package:oh_my_llm/features/chat/data/chat_writer_entry_point.dart',
  'package:oh_my_llm/features/chat/data/anthropic/',
  'package:oh_my_llm/features/chat/data/chat_completions/',
  'package:oh_my_llm/features/chat/data/responses/'
)
foreach ($pattern in $chatOldPackagePatterns) {
  $hits = @(rg -n -F $pattern lib test tool)
  if ($hits.Count -ne 0) { throw "残留旧 Chat URI：$pattern`n$($hits -join "`n")" }
}
if (@(rg --files test -g '*_test.dart').Count -ne 163) { throw '测试入口数变化' }
```

暂存本任务全部移动和 import/fixture 改动，执行暂存格式检查：

```powershell
git add -A -- lib test tool
```

然后：

```powershell
git commit -m "refactor(chat): 按职责归档应用与数据文件"
```

---

### Task 3: 重组 Chat presentation widgets 与 screen tests

**Files:**
- Move: `lib/features/chat/presentation/widgets/**` 到 composer/messages/prompts/sidebar/workspace
- Modify: `lib/features/chat/presentation/widgets/widgets.dart`
- Move: `test/features/chat/chat_screen_test.dart` 与 `chat_screen/` 到 presentation
- Move: Chat widget tests 到 production-mirrored paths
- Modify: `lib/features/chat/presentation/chat_screen.dart`、相关 imports

**Interfaces:**
- Consumes: 现有 `ChatScreen`、`ChatWorkspace`、`ChatComposerCard`、message bubble 与 dialogs。
- Produces: `widgets.dart` 继续作为稳定 export 入口；所有 Widget class 名、构造参数和行为不变。

- [ ] **Step 1: 执行 production widget 精确移动矩阵**

```text
lib/features/chat/presentation/widgets/chat_composer_card.dart -> lib/features/chat/presentation/widgets/composer/chat_composer_card.dart
lib/features/chat/presentation/widgets/auto_retry_toggle.dart -> lib/features/chat/presentation/widgets/composer/controls/auto_retry_toggle.dart
lib/features/chat/presentation/widgets/composer_pill_toggle.dart -> lib/features/chat/presentation/widgets/composer/controls/composer_pill_toggle.dart
lib/features/chat/presentation/widgets/thinking_toggle.dart -> lib/features/chat/presentation/widgets/composer/controls/thinking_toggle.dart
lib/features/chat/presentation/widgets/composer/composer_effort_pill.dart -> lib/features/chat/presentation/widgets/composer/controls/composer_effort_pill.dart
lib/features/chat/presentation/widgets/composer/composer_send_button.dart -> lib/features/chat/presentation/widgets/composer/controls/composer_send_button.dart
lib/features/chat/presentation/widgets/composer/composer_message_field.dart -> lib/features/chat/presentation/widgets/composer/fields/composer_message_field.dart
lib/features/chat/presentation/widgets/composer/composer_template_variable_fields.dart -> lib/features/chat/presentation/widgets/composer/fields/composer_template_variable_fields.dart
lib/features/chat/presentation/widgets/composer/number_variable_field.dart -> lib/features/chat/presentation/widgets/composer/fields/number_variable_field.dart
lib/features/chat/presentation/widgets/composer/composer_compact_action_row.dart -> lib/features/chat/presentation/widgets/composer/layout/composer_compact_action_row.dart
lib/features/chat/presentation/widgets/composer/composer_desktop_settings_row.dart -> lib/features/chat/presentation/widgets/composer/layout/composer_desktop_settings_row.dart
lib/features/chat/presentation/widgets/composer/composer_provider_model_row.dart -> lib/features/chat/presentation/widgets/composer/layout/composer_provider_model_row.dart
lib/features/chat/presentation/widgets/composer/composer_template_header.dart -> lib/features/chat/presentation/widgets/composer/layout/composer_template_header.dart
lib/features/chat/presentation/widgets/chat_messages_panel.dart -> lib/features/chat/presentation/widgets/messages/chat_messages_panel.dart
lib/features/chat/presentation/widgets/empty_conversation_view.dart -> lib/features/chat/presentation/widgets/messages/empty_conversation_view.dart
lib/features/chat/presentation/widgets/cached_chat_message_bubble.dart -> lib/features/chat/presentation/widgets/messages/bubble/cached_chat_message_bubble.dart
lib/features/chat/presentation/widgets/chat_inline_empty_reply_card.dart -> lib/features/chat/presentation/widgets/messages/bubble/chat_inline_empty_reply_card.dart
lib/features/chat/presentation/widgets/chat_inline_error_card.dart -> lib/features/chat/presentation/widgets/messages/bubble/chat_inline_error_card.dart
lib/features/chat/presentation/widgets/chat_message_bubble.dart -> lib/features/chat/presentation/widgets/messages/bubble/chat_message_bubble.dart
lib/features/chat/presentation/widgets/reasoning_panel.dart -> lib/features/chat/presentation/widgets/messages/bubble/reasoning_panel.dart
lib/features/chat/presentation/widgets/streaming_markdown_view.dart -> lib/features/chat/presentation/widgets/messages/bubble/streaming_markdown_view.dart
lib/features/chat/presentation/widgets/user_message_collapse.dart -> lib/features/chat/presentation/widgets/messages/bubble/user_message_collapse.dart
lib/features/chat/presentation/widgets/message_anchor_rail.dart -> lib/features/chat/presentation/widgets/messages/navigation/message_anchor_rail.dart
lib/features/chat/presentation/widgets/message_version_info.dart -> lib/features/chat/presentation/widgets/messages/navigation/message_version_info.dart
lib/features/chat/presentation/widgets/message_version_navigator.dart -> lib/features/chat/presentation/widgets/messages/navigation/message_version_navigator.dart
lib/features/chat/presentation/widgets/preset_prompt_message_card.dart -> lib/features/chat/presentation/widgets/prompts/preset_prompt_message_card.dart
lib/features/chat/presentation/widgets/preset_prompt_message_detail_dialog.dart -> lib/features/chat/presentation/widgets/prompts/preset_prompt_message_detail_dialog.dart
lib/features/chat/presentation/widgets/preset_prompt_panel.dart -> lib/features/chat/presentation/widgets/prompts/preset_prompt_panel.dart
lib/features/chat/presentation/widgets/chat_activity_bar.dart -> lib/features/chat/presentation/widgets/sidebar/chat_activity_bar.dart
lib/features/chat/presentation/widgets/chat_compact_panel.dart -> lib/features/chat/presentation/widgets/sidebar/chat_compact_panel.dart
lib/features/chat/presentation/widgets/chat_sidebar_panel.dart -> lib/features/chat/presentation/widgets/sidebar/chat_sidebar_panel.dart
lib/features/chat/presentation/widgets/conversation_history_panel.dart -> lib/features/chat/presentation/widgets/sidebar/conversation_history_panel.dart
lib/features/chat/presentation/widgets/grouped_conversation_list.dart -> lib/features/chat/presentation/widgets/sidebar/grouped_conversation_list.dart
lib/features/chat/presentation/widgets/chat_workspace.dart -> lib/features/chat/presentation/widgets/workspace/chat_workspace.dart
lib/features/chat/presentation/widgets/chat_workspace_bindings.dart -> lib/features/chat/presentation/widgets/workspace/chat_workspace_bindings.dart
```

保持 `composer/composer_helpers.dart`、`dialogs/**` 与根 `widgets.dart` 原位。

- [ ] **Step 2: 执行 Chat presentation test 精确移动矩阵**

```text
test/features/chat/chat_screen_test.dart -> test/features/chat/presentation/chat_screen_test.dart
test/features/chat/chat_screen/chat_screen_basics_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_basics_cases.dart
test/features/chat/chat_screen/chat_screen_branching_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_branching_cases.dart
test/features/chat/chat_screen/chat_screen_favorites_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_favorites_cases.dart
test/features/chat/chat_screen/chat_screen_responsive_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_responsive_cases.dart
test/features/chat/chat_screen/chat_screen_streaming_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_streaming_cases.dart
test/features/chat/chat_screen/chat_screen_test_helpers.dart -> test/features/chat/presentation/chat_screen/chat_screen_test_helpers.dart
test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart -> test/features/chat/presentation/chat_screen/chat_screen_workspace_ownership_cases.dart
test/features/chat/presentation/widgets/chat_composer_card_responsive_test.dart -> test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart
test/features/chat/widgets/composer_pill_toggle_accessibility_test.dart -> test/features/chat/presentation/widgets/composer/controls/composer_pill_toggle_accessibility_test.dart
test/features/chat/presentation/widgets/chat_message_bubble_finish_reason_test.dart -> test/features/chat/presentation/widgets/messages/bubble/chat_message_bubble_finish_reason_test.dart
test/features/chat/widgets/reasoning_panel_accessibility_test.dart -> test/features/chat/presentation/widgets/messages/bubble/reasoning_panel_accessibility_test.dart
test/features/chat/presentation/widgets/user_message_collapse_test.dart -> test/features/chat/presentation/widgets/messages/bubble/user_message_collapse_test.dart
test/features/chat/widgets/message_anchor_rail_test.dart -> test/features/chat/presentation/widgets/messages/navigation/message_anchor_rail_test.dart
```

移动后只在为空时删除 `test/features/chat/chat_screen`、`test/features/chat/widgets`。

- [ ] **Step 3: 记录结构性 red**

```powershell
flutter test test/features/chat/presentation/widgets/composer/chat_composer_card_responsive_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task3-chat-presentation-red.log'
$task3RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task3RedExit"
Get-Content -Tail 80 'logs/task3-chat-presentation-red.log'
if ($task3RedExit -eq 0) { throw '预期旧 widget URI 导致结构性编译失败' }
```

- [ ] **Step 4: 更新 relative imports、package imports 与 `widgets.dart`**

用 `apply_patch`：

- 将 `widgets.dart` 的每个 export 精确指向上述新路径；dialogs exports 保持目录不变；
- `chat_screen.dart` 继续只导入 `widgets/widgets.dart`，但 application imports 使用 Task 2
  新目录；
- 更新 production widgets 之间的相对 import；
- 更新全部测试与其他 feature consumers 的 package URI；
- 不新增任何子目录 barrel。

- [ ] **Step 5: 格式化、审阅并运行 presentation green**

```powershell
flutter test test/features/chat/presentation test/integration/preset_prompt_request_integration_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task3-chat-presentation-green.log'
$task3GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task3GreenExit"
Get-Content -Tail 150 'logs/task3-chat-presentation-green.log'
if ($task3GreenExit -ne 0) { throw 'Chat presentation 测试失败' }
```

执行 0.5 的 boundary 与 diff 检查。

- [ ] **Step 6: 结构验收并提交**

```powershell
$chatWidgetRootFiles = @(Get-ChildItem -LiteralPath 'lib/features/chat/presentation/widgets' -File -Filter '*.dart')
if ($chatWidgetRootFiles.Count -ne 1 -or $chatWidgetRootFiles[0].Name -ne 'widgets.dart') {
  throw 'Chat widgets 根目录应只保留 widgets.dart'
}
if (@(rg --files test -g '*_test.dart').Count -ne 163) { throw '测试入口数变化' }
```

暂存任务精确范围并执行格式检查：

```powershell
git add -A -- lib/features/chat/presentation test/features/chat
```

然后：

```powershell
git commit -m "refactor(chat): 按界面职责归档组件与测试"
```

---

### Task 4: 重组 Settings application、domain、data 与 allowlist

**Files:**
- Move: Settings application/domain models/data production files
- Move: corresponding application/domain/data tests
- Modify: `tool/architecture/import_boundary_checker.dart`
- Modify: `test/architecture/import_boundary_checker_test.dart`
- Modify: all cross-feature and composition consumers

**Interfaces:**
- Consumes: 所有现有 Settings models/controllers/repositories/workflows；现有 7 条 application→data 精确例外。
- Produces: 相同公开 declarations 和序列化契约；7 条例外仅 source/target 路径变化，reason 文本不变。

- [ ] **Step 1: 执行 Settings application 精确移动矩阵**

```text
lib/features/settings/application/auto_retry_settings_controller.dart -> lib/features/settings/application/preferences/auto_retry_settings_controller.dart
lib/features/settings/application/chat_defaults_controller.dart -> lib/features/settings/application/preferences/chat_defaults_controller.dart
lib/features/settings/application/custom_headers_controller.dart -> lib/features/settings/application/preferences/custom_headers_controller.dart
lib/features/settings/application/font_size_settings_controller.dart -> lib/features/settings/application/preferences/font_size_settings_controller.dart
lib/features/settings/application/output_processing_settings_controller.dart -> lib/features/settings/application/preferences/output_processing_settings_controller.dart
lib/features/settings/application/settings_tab_preferences.dart -> lib/features/settings/application/preferences/settings_tab_preferences.dart
lib/features/settings/application/llm_model_configs_controller.dart -> lib/features/settings/application/providers/llm_model_configs_controller.dart
lib/features/settings/application/llm_provider_equivalence.dart -> lib/features/settings/application/providers/llm_provider_equivalence.dart
lib/features/settings/application/model_catalog_workflow.dart -> lib/features/settings/application/providers/model_catalog_workflow.dart
lib/features/settings/application/fixed_prompt_sequences_controller.dart -> lib/features/settings/application/prompts/fixed_prompt_sequences_controller.dart
lib/features/settings/application/memory_prompts_controller.dart -> lib/features/settings/application/prompts/memory_prompts_controller.dart
lib/features/settings/application/preset_prompts_controller.dart -> lib/features/settings/application/prompts/preset_prompts_controller.dart
lib/features/settings/application/settings_entity_controller.dart -> lib/features/settings/application/prompts/settings_entity_controller.dart
lib/features/settings/application/template_prompts_controller.dart -> lib/features/settings/application/prompts/template_prompts_controller.dart
lib/features/settings/application/settings_import_deduplicator.dart -> lib/features/settings/application/transfer/settings_import_deduplicator.dart
lib/features/settings/application/settings_import_executor.dart -> lib/features/settings/application/transfer/settings_import_executor.dart
lib/features/settings/application/settings_sync_facade.dart -> lib/features/settings/application/transfer/settings_sync_facade.dart
lib/features/settings/application/settings_transfer_workflow.dart -> lib/features/settings/application/transfer/settings_transfer_workflow.dart
```

- [ ] **Step 2: 执行 Settings domain/data 精确移动矩阵**

```text
lib/features/settings/domain/models/auto_retry_settings.dart -> lib/features/settings/domain/models/preferences/auto_retry_settings.dart
lib/features/settings/domain/models/chat_defaults.dart -> lib/features/settings/domain/models/preferences/chat_defaults.dart
lib/features/settings/domain/models/custom_headers_config.dart -> lib/features/settings/domain/models/preferences/custom_headers_config.dart
lib/features/settings/domain/models/font_size_settings.dart -> lib/features/settings/domain/models/preferences/font_size_settings.dart
lib/features/settings/domain/models/output_processing_settings.dart -> lib/features/settings/domain/models/preferences/output_processing_settings.dart
lib/features/settings/domain/models/llm_model_config.dart -> lib/features/settings/domain/models/providers/llm_model_config.dart
lib/features/settings/domain/models/llm_provider_config.dart -> lib/features/settings/domain/models/providers/llm_provider_config.dart
lib/features/settings/domain/models/model_catalog_entry.dart -> lib/features/settings/domain/models/providers/model_catalog_entry.dart
lib/features/settings/domain/models/fixed_prompt_sequence.dart -> lib/features/settings/domain/models/prompts/fixed_prompt_sequence.dart
lib/features/settings/domain/models/memory_prompt.dart -> lib/features/settings/domain/models/prompts/memory_prompt.dart
lib/features/settings/domain/models/preset_prompt.dart -> lib/features/settings/domain/models/prompts/preset_prompt.dart
lib/features/settings/domain/models/prompt_message.dart -> lib/features/settings/domain/models/prompts/prompt_message.dart
lib/features/settings/domain/models/prompt_message_placement.dart -> lib/features/settings/domain/models/prompts/prompt_message_placement.dart
lib/features/settings/domain/models/prompt_message_role.dart -> lib/features/settings/domain/models/prompts/prompt_message_role.dart
lib/features/settings/domain/models/template_prompt.dart -> lib/features/settings/domain/models/prompts/template_prompt.dart
lib/features/settings/domain/models/settings_export_codec.dart -> lib/features/settings/domain/models/transfer/settings_export_codec.dart
lib/features/settings/domain/models/settings_export_data.dart -> lib/features/settings/domain/models/transfer/settings_export_data.dart
lib/features/settings/data/llm_model_config_repository.dart -> lib/features/settings/data/providers/llm_model_config_repository.dart
lib/features/settings/data/model_list_client.dart -> lib/features/settings/data/providers/model_list_client.dart
lib/features/settings/data/fixed_prompt_sequence_repository.dart -> lib/features/settings/data/prompts/fixed_prompt_sequence_repository.dart
lib/features/settings/data/preset_prompt_repository.dart -> lib/features/settings/data/prompts/preset_prompt_repository.dart
lib/features/settings/data/sqlite_fixed_prompt_sequence_repository.dart -> lib/features/settings/data/prompts/sqlite_fixed_prompt_sequence_repository.dart
lib/features/settings/data/sqlite_memory_prompt_repository.dart -> lib/features/settings/data/prompts/sqlite_memory_prompt_repository.dart
lib/features/settings/data/sqlite_preset_prompt_repository.dart -> lib/features/settings/data/prompts/sqlite_preset_prompt_repository.dart
lib/features/settings/data/sqlite_template_prompt_repository.dart -> lib/features/settings/data/prompts/sqlite_template_prompt_repository.dart
lib/features/settings/data/template_prompt_repository.dart -> lib/features/settings/data/prompts/template_prompt_repository.dart
```

保持 `domain/template_prompt_parser.dart` 和 `data/chat_defaults_repository.dart` 原位。

- [ ] **Step 3: 执行 Settings application/domain/data test 移动矩阵**

```text
test/features/settings/application/persisted_settings_controllers_test.dart -> test/features/settings/application/preferences/persisted_settings_controllers_test.dart
test/features/settings/application/settings_tab_preferences_test.dart -> test/features/settings/application/preferences/settings_tab_preferences_test.dart
test/features/settings/application/llm_model_configs_controller_test.dart -> test/features/settings/application/providers/llm_model_configs_controller_test.dart
test/features/settings/application/llm_provider_equivalence_test.dart -> test/features/settings/application/providers/llm_provider_equivalence_test.dart
test/features/settings/application/model_catalog_workflow_test.dart -> test/features/settings/application/providers/model_catalog_workflow_test.dart
test/features/settings/application/settings_entity_controller_test.dart -> test/features/settings/application/prompts/settings_entity_controller_test.dart
test/features/settings/application/settings_import_deduplicator_test.dart -> test/features/settings/application/transfer/settings_import_deduplicator_test.dart
test/features/settings/application/settings_import_executor_test.dart -> test/features/settings/application/transfer/settings_import_executor_test.dart
test/features/settings/application/settings_sync_facade_test.dart -> test/features/settings/application/transfer/settings_sync_facade_test.dart
test/features/settings/application/settings_transfer_workflow_test.dart -> test/features/settings/application/transfer/settings_transfer_workflow_test.dart
test/features/settings/data/model_list_client_test.dart -> test/features/settings/data/providers/model_list_client_test.dart
test/features/settings/data/sqlite_repositories_test.dart -> test/features/settings/data/prompts/sqlite_repositories_test.dart
test/features/settings/domain/models/settings_value_objects_test.dart -> test/features/settings/domain/models/preferences/settings_value_objects_test.dart
test/features/settings/domain/models/llm_configs_test.dart -> test/features/settings/domain/models/providers/llm_configs_test.dart
test/features/settings/domain/models/prompt_models_test.dart -> test/features/settings/domain/models/prompts/prompt_models_test.dart
test/features/settings/domain/models/template_prompt_test.dart -> test/features/settings/domain/models/prompts/template_prompt_test.dart
test/features/settings/domain/models/settings_export_codec_test.dart -> test/features/settings/domain/models/transfer/settings_export_codec_test.dart
test/features/settings/domain/models/settings_export_data_test.dart -> test/features/settings/domain/models/transfer/settings_export_data_test.dart
```

保持 `data/shared_preferences_repositories_test.dart` 和
`domain/template_prompt_parser_test.dart` 在共同父目录。

- [ ] **Step 4: 记录结构性 red**

```powershell
flutter test test/features/settings/domain/models/providers/llm_configs_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task4-settings-structure-red.log'
$task4RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task4RedExit"
Get-Content -Tail 80 'logs/task4-settings-structure-red.log'
if ($task4RedExit -eq 0) { throw '预期旧 Settings model URI 导致结构性编译失败' }
```

- [ ] **Step 5: 精确更新 7 条 production allowance 与测试 fixture**

在 `tool/architecture/import_boundary_checker.dart` 中只改以下 source/target；每条 reason
保留原文：

```text
application/preferences/chat_defaults_controller.dart -> data/chat_defaults_repository.dart
application/prompts/fixed_prompt_sequences_controller.dart -> data/prompts/fixed_prompt_sequence_repository.dart
application/providers/llm_model_configs_controller.dart -> data/providers/llm_model_config_repository.dart
application/prompts/memory_prompts_controller.dart -> data/prompts/sqlite_memory_prompt_repository.dart
application/providers/model_catalog_workflow.dart -> data/providers/model_list_client.dart
application/prompts/preset_prompts_controller.dart -> data/prompts/preset_prompt_repository.dart
application/prompts/template_prompts_controller.dart -> data/prompts/template_prompt_repository.dart
```

同步更新 `test/architecture/import_boundary_checker_test.dart` 的 `_settingsAllowance` source、
target 与 fixture 内相对 import，使 resolved edge 正好匹配新路径；测试标题和断言不改。

- [ ] **Step 6: 按 0.4 更新全仓 Settings import/export**

必须覆盖 Chat/Sync composition、core HTTP custom headers、bootstrap、integration tests、
fixtures 与 Settings 自身相对 import。不得修改 JSON key、codec、dedup 等价逻辑或
controller repository wiring。

- [ ] **Step 7: 格式化、审阅并运行 Settings non-presentation green**

```powershell
flutter test test/features/settings/application test/features/settings/domain test/features/settings/data test/architecture/import_boundary_checker_test.dart test/integration/multi_protocol_chat_generation_integration_test.dart test/integration/preset_prompt_request_integration_test.dart test/integration/sync_multi_category_integration_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task4-settings-application-data-green.log'
$task4GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task4GreenExit"
Get-Content -Tail 150 'logs/task4-settings-application-data-green.log'
if ($task4GreenExit -ne 0) { throw 'Settings application/domain/data 测试失败' }
```

运行 boundary，Expected: 333 files、0 violations。

- [ ] **Step 8: allowlist/结构审计与提交**

```powershell
$policyText = Get-Content -LiteralPath 'tool/architecture/import_boundary_checker.dart' -Raw
$policySection = $policyText.Substring(
  $policyText.IndexOf('final architecturePolicy = ArchitecturePolicy('),
  $policyText.IndexOf('/// 扫描 lib/**/*.dart') - $policyText.IndexOf('final architecturePolicy = ArchitecturePolicy(')
)
if (@([regex]::Matches($policySection, 'ImportEdge\(')).Count -ne 7) {
  throw 'Settings production allowlist 不再是 7 条'
}
if (@(rg --files test -g '*_test.dart').Count -ne 163) { throw '测试入口数变化' }
if (@(Get-ChildItem -LiteralPath 'lib/features/settings/application' -File -Filter '*.dart').Count -ne 0) {
  throw 'Settings application 根目录仍有平铺 Dart 文件'
}
```

暂存并执行暂存格式检查：

```powershell
git add -A -- lib test tool
```

然后：

```powershell
git commit -m "refactor(settings): 按业务域归档应用与数据文件"
```

---

### Task 5: 重组 Settings presentation widgets 与 screen tests

**Files:**
- Move: Settings widget form/list/root files into providers/prompts/shared/tabs/transfer
- Modify: `lib/features/settings/presentation/widgets/settings_widgets.dart`
- Move: Settings screen entry/cases and widget tests
- Modify: all consumers and relative imports

**Interfaces:**
- Consumes: 现有 Settings screen、form dialogs、lists、tabs 与 `settings_widgets.dart`。
- Produces: 相同 Widget declarations；现有 barrel 继续提供相同 exports。

- [ ] **Step 1: 执行 production presentation 精确移动矩阵**

```text
lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart -> lib/features/settings/presentation/widgets/providers/forms/model_config_form_dialog.dart
lib/features/settings/presentation/widgets/form/model_fetch_section.dart -> lib/features/settings/presentation/widgets/providers/forms/model_fetch_section.dart
lib/features/settings/presentation/widgets/form/model_provider_form_dialog.dart -> lib/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog.dart
lib/features/settings/presentation/widgets/list/model_configs_list.dart -> lib/features/settings/presentation/widgets/providers/lists/model_configs_list.dart
lib/features/settings/presentation/widgets/list/provider_info.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_info.dart
lib/features/settings/presentation/widgets/list/provider_info_body.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_info_body.dart
lib/features/settings/presentation/widgets/list/provider_meta_chip.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_meta_chip.dart
lib/features/settings/presentation/widgets/list/provider_model_info.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_model_info.dart
lib/features/settings/presentation/widgets/list/provider_model_info_body.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_model_info_body.dart
lib/features/settings/presentation/widgets/list/provider_model_tile.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_model_tile.dart
lib/features/settings/presentation/widgets/list/provider_tile.dart -> lib/features/settings/presentation/widgets/providers/lists/provider_tile.dart
lib/features/settings/presentation/widgets/form/editable_preset_prompt_item.dart -> lib/features/settings/presentation/widgets/prompts/forms/editable_preset_prompt_item.dart
lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart -> lib/features/settings/presentation/widgets/prompts/forms/fixed_prompt_sequence_form_dialog.dart
lib/features/settings/presentation/widgets/form/memory_prompt_form_dialog.dart -> lib/features/settings/presentation/widgets/prompts/forms/memory_prompt_form_dialog.dart
lib/features/settings/presentation/widgets/form/preset_prompt_editor_role.dart -> lib/features/settings/presentation/widgets/prompts/forms/preset_prompt_editor_role.dart
lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart -> lib/features/settings/presentation/widgets/prompts/forms/preset_prompt_form_dialog.dart
lib/features/settings/presentation/widgets/form/preset_prompt_list_tile.dart -> lib/features/settings/presentation/widgets/prompts/forms/preset_prompt_list_tile.dart
lib/features/settings/presentation/widgets/form/template_prompt_form_dialog.dart -> lib/features/settings/presentation/widgets/prompts/forms/template_prompt_form_dialog.dart
lib/features/settings/presentation/widgets/list/fixed_prompt_sequences_list.dart -> lib/features/settings/presentation/widgets/prompts/lists/fixed_prompt_sequences_list.dart
lib/features/settings/presentation/widgets/list/memory_prompts_list.dart -> lib/features/settings/presentation/widgets/prompts/lists/memory_prompts_list.dart
lib/features/settings/presentation/widgets/list/preset_prompts_list.dart -> lib/features/settings/presentation/widgets/prompts/lists/preset_prompts_list.dart
lib/features/settings/presentation/widgets/list/template_prompts_list.dart -> lib/features/settings/presentation/widgets/prompts/lists/template_prompts_list.dart
lib/features/settings/presentation/widgets/settings_card_grid.dart -> lib/features/settings/presentation/widgets/shared/settings_card_grid.dart
lib/features/settings/presentation/widgets/settings_empty_state.dart -> lib/features/settings/presentation/widgets/shared/settings_empty_state.dart
lib/features/settings/presentation/widgets/settings_entity_card.dart -> lib/features/settings/presentation/widgets/shared/settings_entity_card.dart
lib/features/settings/presentation/widgets/settings_form_dialog_scaffold.dart -> lib/features/settings/presentation/widgets/shared/settings_form_dialog_scaffold.dart
lib/features/settings/presentation/widgets/settings_form_dialog_state_mixin.dart -> lib/features/settings/presentation/widgets/shared/settings_form_dialog_state_mixin.dart
lib/features/settings/presentation/widgets/settings_helpers.dart -> lib/features/settings/presentation/widgets/shared/settings_helpers.dart
lib/features/settings/presentation/widgets/settings_section_card.dart -> lib/features/settings/presentation/widgets/shared/settings_section_card.dart
lib/features/settings/presentation/widgets/section/chat_defaults_section.dart -> lib/features/settings/presentation/widgets/tabs/chat_defaults_section.dart
lib/features/settings/presentation/widgets/tab/header_form_dialog.dart -> lib/features/settings/presentation/widgets/tabs/header_form_dialog.dart
lib/features/settings/presentation/widgets/tab/network_settings_tab.dart -> lib/features/settings/presentation/widgets/tabs/network_settings_tab.dart
lib/features/settings/presentation/widgets/tab/other_settings_tab.dart -> lib/features/settings/presentation/widgets/tabs/other_settings_tab.dart
lib/features/settings/presentation/widgets/tab/output_processing_tab.dart -> lib/features/settings/presentation/widgets/tabs/output_processing_tab.dart
lib/features/settings/presentation/widgets/import_confirm_dialog.dart -> lib/features/settings/presentation/widgets/transfer/import_confirm_dialog.dart
```

保持根 `settings_widgets.dart`。移动后只在确认为空时删除旧 `form`、`list`、`section`、
`tab`。

- [ ] **Step 2: 执行 Settings presentation test 移动矩阵**

```text
test/features/settings/settings_screen_test.dart -> test/features/settings/presentation/settings_screen_test.dart
test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart -> test/features/settings/presentation/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart
test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart -> test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart
test/features/settings/settings_screen/settings_screen_responsive_cases.dart -> test/features/settings/presentation/settings_screen/settings_screen_responsive_cases.dart
test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart -> test/features/settings/presentation/settings_screen/settings_screen_tab_navigation_cases.dart
test/features/settings/settings_screen/settings_screen_test_helpers.dart -> test/features/settings/presentation/settings_screen/settings_screen_test_helpers.dart
test/features/settings/presentation/model_config_form_dialog_test.dart -> test/features/settings/presentation/widgets/providers/forms/model_config_form_dialog_test.dart
test/features/settings/presentation/model_provider_form_dialog_test.dart -> test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart
test/features/settings/presentation/output_processing_tab_test.dart -> test/features/settings/presentation/widgets/tabs/output_processing_tab_test.dart
test/features/settings/presentation/import_confirm_dialog_test.dart -> test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart
```

移动后只在为空时删除 `test/features/settings/settings_screen`。

- [ ] **Step 3: 记录结构性 red**

```powershell
flutter test test/features/settings/presentation/widgets/providers/forms/model_provider_form_dialog_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task5-settings-presentation-red.log'
$task5RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task5RedExit"
Get-Content -Tail 80 'logs/task5-settings-presentation-red.log'
if ($task5RedExit -eq 0) { throw '预期旧 Settings widget URI 导致结构性编译失败' }
```

- [ ] **Step 4: 更新 imports/exports，保持 barrel 合同**

用 `apply_patch` 更新 production/test 相对 URI 与 package URI；
`settings_widgets.dart` 对外导出原有相同文件集合，只改为新路径，不新增/删除 export。

- [ ] **Step 5: 格式化、审阅并运行 presentation green**

```powershell
flutter test test/features/settings/presentation --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task5-settings-presentation-green.log'
$task5GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task5GreenExit"
Get-Content -Tail 150 'logs/task5-settings-presentation-green.log'
if ($task5GreenExit -ne 0) { throw 'Settings presentation 测试失败' }
```

运行 boundary 与格式/diff 检查。

- [ ] **Step 6: 结构验收并提交**

```powershell
$settingsWidgetRoot = @(Get-ChildItem -LiteralPath 'lib/features/settings/presentation/widgets' -File -Filter '*.dart')
if ($settingsWidgetRoot.Count -ne 1 -or $settingsWidgetRoot[0].Name -ne 'settings_widgets.dart') {
  throw 'Settings widgets 根目录应只保留 settings_widgets.dart'
}
if (@(rg --files test -g '*_test.dart').Count -ne 163) { throw '测试入口数变化' }
```

暂存并执行暂存格式检查：

```powershell
git add -A -- lib/features/settings/presentation test/features/settings
```

然后：

```powershell
git commit -m "refactor(settings): 按界面域归档组件与测试"
```

---

### Task 6: 重组 Media data 与测试镜像

**Files:**
- Move: `lib/features/media/data/**` into libraries/scanning/http
- Move: Media application contract test and presentation tests
- Rename/Move: `media_mime_types_test.dart` -> `domain/media_file_classification_test.dart`
- Modify: all Media/Sync/composition consumers

**Interfaces:**
- Consumes: `MediaLibrary` ports、本地/远端实现、scanner/thumbnail pipeline、HTTP handlers。
- Produces: 相同 implementations 与 route behavior；生产 application/domain/presentation 不移动。

- [ ] **Step 1: 执行 production data 精确移动矩阵**

```text
lib/features/media/data/default_media_library_factory.dart -> lib/features/media/data/libraries/default_media_library_factory.dart
lib/features/media/data/local_media_library.dart -> lib/features/media/data/libraries/local_media_library.dart
lib/features/media/data/remote_media_library.dart -> lib/features/media/data/libraries/remote_media_library.dart
lib/features/media/data/media_directory_scanner.dart -> lib/features/media/data/scanning/media_directory_scanner.dart
lib/features/media/data/media_thumbnail_cache.dart -> lib/features/media/data/scanning/media_thumbnail_cache.dart
lib/features/media/data/media_thumbnail_generator.dart -> lib/features/media/data/scanning/media_thumbnail_generator.dart
lib/features/media/data/thumbnail_process_runner.dart -> lib/features/media/data/scanning/thumbnail_process_runner.dart
lib/features/media/data/media_http_handler_base.dart -> lib/features/media/data/http/media_http_handler_base.dart
lib/features/media/data/media_http_handler.dart -> lib/features/media/data/http/media_http_handler.dart
lib/features/media/data/media_image_http_handler.dart -> lib/features/media/data/http/media_image_http_handler.dart
lib/features/media/data/media_recursive_videos_handler.dart -> lib/features/media/data/http/media_recursive_videos_handler.dart
lib/features/media/data/media_thumbnail_http_handler.dart -> lib/features/media/data/http/media_thumbnail_http_handler.dart
lib/features/media/data/media_video_http_handler.dart -> lib/features/media/data/http/media_video_http_handler.dart
lib/features/media/data/dto/media_file_item_dto.dart -> lib/features/media/data/http/dto/media_file_item_dto.dart
```

移动后只在为空时删除 `lib/features/media/data/dto`。

- [ ] **Step 2: 执行 Media test 精确移动矩阵**

```text
test/features/media/application/media_library_contracts_test.dart -> test/features/media/application/models/media_library_contracts_test.dart
test/features/media/data/default_media_library_factory_test.dart -> test/features/media/data/libraries/default_media_library_factory_test.dart
test/features/media/data/local_media_library_test.dart -> test/features/media/data/libraries/local_media_library_test.dart
test/features/media/data/remote_media_library_test.dart -> test/features/media/data/libraries/remote_media_library_test.dart
test/features/media/data/media_directory_scanner_test.dart -> test/features/media/data/scanning/media_directory_scanner_test.dart
test/features/media/data/media_thumbnail_cache_test.dart -> test/features/media/data/scanning/media_thumbnail_cache_test.dart
test/features/media/data/media_thumbnail_generator_test.dart -> test/features/media/data/scanning/media_thumbnail_generator_test.dart
test/features/media/data/media_http_handler_test.dart -> test/features/media/data/http/media_http_handler_test.dart
test/features/media/data/media_image_http_handler_test.dart -> test/features/media/data/http/media_image_http_handler_test.dart
test/features/media/data/media_recursive_videos_handler_test.dart -> test/features/media/data/http/media_recursive_videos_handler_test.dart
test/features/media/data/media_thumbnail_http_handler_test.dart -> test/features/media/data/http/media_thumbnail_http_handler_test.dart
test/features/media/data/media_video_http_handler_test.dart -> test/features/media/data/http/media_video_http_handler_test.dart
test/features/media/data/media_file_item_dto_test.dart -> test/features/media/data/http/dto/media_file_item_dto_test.dart
test/features/media/data/media_mime_types_test.dart -> test/features/media/domain/media_file_classification_test.dart
test/features/media/presentation/image_viewer_page_test.dart -> test/features/media/presentation/pages/image_viewer_page_test.dart
test/features/media/presentation/media_route_pages_test.dart -> test/features/media/presentation/pages/media_route_pages_test.dart
test/features/media/presentation/media_video_controller_factory_test.dart -> test/features/media/presentation/pages/media_video_controller_factory_test.dart
test/features/media/presentation/video_player_accessibility_test.dart -> test/features/media/presentation/pages/video_player_accessibility_test.dart
test/features/media/presentation/video_player_page_test.dart -> test/features/media/presentation/pages/video_player_page_test.dart
test/features/media/presentation/media_image_resource_view_test.dart -> test/features/media/presentation/widgets/media_image_resource_view_test.dart
test/features/media/presentation/media_path_bar_accessibility_test.dart -> test/features/media/presentation/widgets/media_path_bar_accessibility_test.dart
test/features/media/presentation/shuffle_appbar_actions_test.dart -> test/features/media/presentation/widgets/shuffle_appbar_actions_test.dart
```

`media_browser_navigation_test.dart` 保留 presentation 根；`file_item_test.dart` 已在
domain/models；`test/features/media/helpers` 不动。

- [ ] **Step 3: 记录结构性 red**

```powershell
flutter test test/features/media/data/scanning/media_directory_scanner_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task6-media-structure-red.log'
$task6RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task6RedExit"
Get-Content -Tail 80 'logs/task6-media-structure-red.log'
if ($task6RedExit -eq 0) { throw '预期旧 Media data URI 导致结构性编译失败' }
```

- [ ] **Step 4: 更新 imports 并验证 ownership rename 不改断言**

按 0.4 patch Media、Sync composition、test helpers 与 integration consumers。
`media_file_classification_test.dart` 只改文件名/位置/import，不改测试标题或断言。

- [ ] **Step 5: 格式化、审阅并运行 Media green**

```powershell
flutter test test/features/media --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task6-media-green.log'
$task6GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task6GreenExit"
Get-Content -Tail 150 'logs/task6-media-green.log'
if ($task6GreenExit -ne 0) { throw 'Media 测试失败' }
```

执行 boundary、入口数与根目录平铺检查，暂存并执行暂存格式检查：

```powershell
git add -A -- lib/features/media test/features/media lib/app test/app test/integration
```

然后：

```powershell
git commit -m "refactor(media): 按传输职责归档数据与测试"
```

---

### Task 7: 重组 Sync data/domain 并修正 composition 测试归属

**Files:**
- Move: Sync data into http/udp/security
- Move: Sync domain models into discovery/protocol/session
- Move: corresponding data/domain tests
- Rename/Move: Sync screen test entry/cases into `test/app/composition/sync_workspace_screen*`
- Modify: Sync application, app composition, Media and integration consumers

**Interfaces:**
- Consumes: Sync v3 typed protocol、transport ports、crypto/pairing repository、`SyncWorkspaceScreen` composition。
- Produces: 相同 protocol/security/session behavior；production composition 仍在 `lib/app/composition`。

- [ ] **Step 1: 执行 Sync production data/domain 精确移动矩阵**

```text
lib/features/sync/data/http_sync_client_transport.dart -> lib/features/sync/data/http/http_sync_client_transport.dart
lib/features/sync/data/http_udp_sync_server_transport.dart -> lib/features/sync/data/http/http_udp_sync_server_transport.dart
lib/features/sync/data/sync_http_handler.dart -> lib/features/sync/data/http/sync_http_handler.dart
lib/features/sync/data/sync_http_server.dart -> lib/features/sync/data/http/sync_http_server.dart
lib/features/sync/data/sync_multicast_lock.dart -> lib/features/sync/data/udp/sync_multicast_lock.dart
lib/features/sync/data/sync_udp_announcement_codec.dart -> lib/features/sync/data/udp/sync_udp_announcement_codec.dart
lib/features/sync/data/sync_udp_discovery.dart -> lib/features/sync/data/udp/sync_udp_discovery.dart
lib/features/sync/data/sync_udp_scheduler.dart -> lib/features/sync/data/udp/sync_udp_scheduler.dart
lib/features/sync/data/sync_udp_sessions.dart -> lib/features/sync/data/udp/sync_udp_sessions.dart
lib/features/sync/data/sync_udp_socket.dart -> lib/features/sync/data/udp/sync_udp_socket.dart
lib/features/sync/data/cryptography_sync_crypto.dart -> lib/features/sync/data/security/cryptography_sync_crypto.dart
lib/features/sync/data/secure_sync_pairing_repository.dart -> lib/features/sync/data/security/secure_sync_pairing_repository.dart
lib/features/sync/domain/models/broadcast_prefix_length.dart -> lib/features/sync/domain/models/discovery/broadcast_prefix_length.dart
lib/features/sync/domain/models/discovered_server.dart -> lib/features/sync/domain/models/discovery/discovered_server.dart
lib/features/sync/domain/models/network_interface_info.dart -> lib/features/sync/domain/models/discovery/network_interface_info.dart
lib/features/sync/domain/models/network_interface_utils.dart -> lib/features/sync/domain/models/discovery/network_interface_utils.dart
lib/features/sync/domain/models/sync_message.dart -> lib/features/sync/domain/models/protocol/sync_message.dart
lib/features/sync/domain/models/sync_protocol_failure.dart -> lib/features/sync/domain/models/protocol/sync_protocol_failure.dart
lib/features/sync/domain/models/sync_protocol_message.dart -> lib/features/sync/domain/models/protocol/sync_protocol_message.dart
lib/features/sync/domain/models/sync_protocol_version.dart -> lib/features/sync/domain/models/protocol/sync_protocol_version.dart
lib/features/sync/domain/models/sync_types.dart -> lib/features/sync/domain/models/protocol/sync_types.dart
lib/features/sync/domain/models/sync_pairing.dart -> lib/features/sync/domain/models/session/sync_pairing.dart
lib/features/sync/domain/models/sync_session.dart -> lib/features/sync/domain/models/session/sync_session.dart
```

`lib/features/sync/application`、ports 和 production presentation 不移动。

- [ ] **Step 2: 执行 Sync data/domain test 精确移动矩阵**

```text
test/features/sync/data/http_sync_client_transport_test.dart -> test/features/sync/data/http/http_sync_client_transport_test.dart
test/features/sync/data/sync_http_server_test.dart -> test/features/sync/data/http/sync_http_server_test.dart
test/features/sync/data/sync_udp_announcement_codec_test.dart -> test/features/sync/data/udp/sync_udp_announcement_codec_test.dart
test/features/sync/data/sync_udp_discovery_lifecycle_test.dart -> test/features/sync/data/udp/sync_udp_discovery_lifecycle_test.dart
test/features/sync/data/sync_udp_discovery_test.dart -> test/features/sync/data/udp/sync_udp_discovery_test.dart
test/features/sync/data/sync_udp_test_fakes.dart -> test/features/sync/data/udp/sync_udp_test_fakes.dart
test/features/sync/data/cryptography_sync_crypto_test.dart -> test/features/sync/data/security/cryptography_sync_crypto_test.dart
test/features/sync/data/secure_sync_pairing_repository_test.dart -> test/features/sync/data/security/secure_sync_pairing_repository_test.dart
test/features/sync/domain/models/broadcast_prefix_length_test.dart -> test/features/sync/domain/models/discovery/broadcast_prefix_length_test.dart
test/features/sync/domain/models/sync_protocol_message_test.dart -> test/features/sync/domain/models/protocol/sync_protocol_message_test.dart
test/features/sync/domain/models/sync_protocol_version_test.dart -> test/features/sync/domain/models/protocol/sync_protocol_version_test.dart
```

- [ ] **Step 3: 执行 composition test ownership 精确重命名/移动**

```text
test/features/sync/sync_screen_test.dart -> test/app/composition/sync_workspace_screen_test.dart
test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart -> test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart
test/features/sync/sync_screen/sync_screen_render_cases.dart -> test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart
test/features/sync/sync_screen/sync_screen_responsive_cases.dart -> test/app/composition/sync_workspace_screen/sync_workspace_screen_responsive_cases.dart
test/features/sync/sync_screen/sync_screen_test_helpers.dart -> test/app/composition/sync_workspace_screen/sync_workspace_screen_test_helpers.dart
```

入口文件 imports 与每个 register/helper 函数名保持原样，只改文件 URI；不得把
`lib/app/composition/sync_workspace_screen.dart` 移入 feature。移动后只在为空时删除旧
`test/features/sync/sync_screen`。

- [ ] **Step 4: 记录结构性 red**

```powershell
flutter test test/features/sync/domain/models/protocol/sync_protocol_message_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task7-sync-structure-red.log'
$task7RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task7RedExit"
Get-Content -Tail 80 'logs/task7-sync-structure-red.log'
if ($task7RedExit -eq 0) { throw '预期旧 Sync model URI 导致结构性编译失败' }
```

- [ ] **Step 5: 按 0.4 更新全仓 imports 与 composition case imports**

重点覆盖 `sync/application`、`app/composition`、Media peer route、Settings transfer、
integration tests 和新的 `test/app/composition` 相对 helper 路径。不得改变协议 JSON、
配对、nonce/replay、session 或 UDP 生命周期逻辑。

- [ ] **Step 6: 格式化、审阅并运行 Sync green**

```powershell
flutter test test/features/sync/application test/features/sync/data test/features/sync/domain test/features/sync/presentation test/app/composition/sync_workspace_screen_test.dart test/integration/sync_e2e_integration_test.dart test/integration/sync_multi_category_integration_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task7-sync-green.log'
$task7GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task7GreenExit"
Get-Content -Tail 150 'logs/task7-sync-green.log'
if ($task7GreenExit -ne 0) { throw 'Sync/composition 测试失败' }
```

执行 boundary、入口数和 diff 检查，暂存并执行暂存格式检查：

```powershell
git add -A -- lib/features/sync lib/app test/features/sync test/features/media test/app test/integration
```

然后：

```powershell
git commit -m "refactor(sync): 按协议边界归档数据与测试"
```

---

### Task 8: 重组 Core Widgets 与对应测试

**Files:**
- Move: three shared dialogs
- Move: four Notification Bubble files
- Move: notification bubble accessibility test
- Modify: all app/feature/test consumers

**Interfaces:**
- Consumes: existing shared dialog and notification bubble declarations。
- Produces: 相同 Widget/extensions/data declarations at new package URIs；
  `adaptive_master_detail_layout.dart`、`app_empty_state.dart` 保持根位置。

- [ ] **Step 1: 执行精确移动矩阵**

```text
lib/core/widgets/app_confirm_dialog.dart -> lib/core/widgets/dialogs/app_confirm_dialog.dart
lib/core/widgets/detail_display_dialog.dart -> lib/core/widgets/dialogs/detail_display_dialog.dart
lib/core/widgets/rename_conversation_dialog.dart -> lib/core/widgets/dialogs/rename_conversation_dialog.dart
lib/core/widgets/notification_bubble.dart -> lib/core/widgets/notification_bubble/notification_bubble.dart
lib/core/widgets/notification_bubble_context_ext.dart -> lib/core/widgets/notification_bubble/notification_bubble_context_ext.dart
lib/core/widgets/notification_bubble_data.dart -> lib/core/widgets/notification_bubble/notification_bubble_data.dart
lib/core/widgets/notification_bubble_stack.dart -> lib/core/widgets/notification_bubble/notification_bubble_stack.dart
test/core/widgets/notification_bubble_accessibility_test.dart -> test/core/widgets/notification_bubble/notification_bubble_accessibility_test.dart
```

- [ ] **Step 2: 记录结构性 red**

```powershell
flutter test test/core/widgets/notification_bubble/notification_bubble_accessibility_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task8-core-widgets-red.log'
$task8RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task8RedExit"
Get-Content -Tail 80 'logs/task8-core-widgets-red.log'
if ($task8RedExit -eq 0) { throw '预期旧 Core Widget URI 导致结构性编译失败' }
```

- [ ] **Step 3: 更新 imports 并保持 core→feature 禁止边界**

按 0.4 patch app shell、Chat/Settings/Media/History/Favorites presentation 与 tests。
不得在 core 新增任何 feature import。

- [ ] **Step 4: 格式化、审阅并运行 Core/widget consumers green**

```powershell
flutter test test/core/widgets test/app test/features/chat/presentation test/features/settings/presentation test/features/media/presentation test/features/history test/features/favorites --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task8-core-widgets-green.log'
$task8GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task8GreenExit"
Get-Content -Tail 150 'logs/task8-core-widgets-green.log'
if ($task8GreenExit -ne 0) { throw 'Core Widgets 及主要消费者测试失败' }
```

执行 boundary。确认 `lib/core/widgets` 根只有
`adaptive_master_detail_layout.dart`、`app_empty_state.dart` 两个 Dart 文件和两个目录。

- [ ] **Step 5: 暂存并提交**

```powershell
git add -A -- lib/core/widgets test/core/widgets lib/app test/app lib/features test/features test/helpers
```

执行 0.5 的暂存格式检查后：

```powershell
git commit -m "refactor(core): 归档共享对话框与通知组件"
```

---

### Task 9: 重组共享测试 helpers

**Files:**
- Move: four async helpers/tests into `test/helpers/async`
- Move: four Chat fakes into `test/helpers/chat`
- Modify: all test consumers
- Preserve: five heterogeneous root helpers

**Interfaces:**
- Consumes: 现有 helper declarations、fake method signatures、test teardown semantics。
- Produces: 相同 helper APIs；仅 test-relative URIs 变化。

- [ ] **Step 1: 执行精确移动矩阵**

```text
test/helpers/async_test_signals.dart -> test/helpers/async/async_test_signals.dart
test/helpers/async_test_signals_test.dart -> test/helpers/async/async_test_signals_test.dart
test/helpers/widget_test_animation.dart -> test/helpers/async/widget_test_animation.dart
test/helpers/widget_test_animation_test.dart -> test/helpers/async/widget_test_animation_test.dart
test/helpers/controllable_chat_conversation_repository.dart -> test/helpers/chat/controllable_chat_conversation_repository.dart
test/helpers/fake_chat_generation_client.dart -> test/helpers/chat/fake_chat_generation_client.dart
test/helpers/fake_history_repository.dart -> test/helpers/chat/fake_history_repository.dart
test/helpers/flaky_chat_conversation_repository.dart -> test/helpers/chat/flaky_chat_conversation_repository.dart
```

根目录保留且不移动：`fixtures.dart`、`integration_test_helpers.dart`、`matchers.dart`、
`responsive_viewport_cases.dart`、`test_harness.dart`。

- [ ] **Step 2: 记录结构性 red**

选取当前直接消费 `widget_test_animation.dart` 的入口（迁移后路径已在前序任务完成）：

```powershell
flutter test test/features/chat/presentation/chat_screen_test.dart --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task9-test-helpers-red.log'
$task9RedExit = $LASTEXITCODE
Write-Host "RED_EXIT=$task9RedExit"
Get-Content -Tail 80 'logs/task9-test-helpers-red.log'
if ($task9RedExit -eq 0) { throw '预期旧 helper 相对 URI 导致结构性编译失败' }
```

- [ ] **Step 3: 更新全部 helper consumers**

使用以下查询分别列出所有消费者，再用 `apply_patch` 重算相对路径：

```powershell
rg -l -F 'async_test_signals.dart' test
rg -l -F 'widget_test_animation.dart' test
rg -l -F 'controllable_chat_conversation_repository.dart' test
rg -l -F 'fake_chat_generation_client.dart' test
rg -l -F 'fake_history_repository.dart' test
rg -l -F 'flaky_chat_conversation_repository.dart' test
```

helper 文件内容、fake 行为、test teardown 和断言全部不改。

- [ ] **Step 4: 格式化、审阅并运行 helper tests + 广覆盖 green**

```powershell
flutter test test/helpers test/features test/integration --reporter compact 2>&1 |
  Out-File -Encoding utf8 'logs/task9-test-helpers-green.log'
$task9GreenExit = $LASTEXITCODE
Write-Host "EXIT=$task9GreenExit"
Get-Content -Tail 150 'logs/task9-test-helpers-green.log'
if ($task9GreenExit -ne 0) { throw '共享 helpers 广覆盖测试失败' }
```

执行 boundary、diff 与测试入口数检查。

- [ ] **Step 5: 根 helper 结构验收并提交**

```powershell
$rootHelperDart = @(
  Get-ChildItem -LiteralPath 'test/helpers' -File -Filter '*.dart' |
    Select-Object -ExpandProperty Name |
    Sort-Object
)
$expectedRootHelpers = @(
  'fixtures.dart',
  'integration_test_helpers.dart',
  'matchers.dart',
  'responsive_viewport_cases.dart',
  'test_harness.dart'
) | Sort-Object
if (($rootHelperDart -join '|') -ne ($expectedRootHelpers -join '|')) {
  throw "test/helpers 根文件不符合设计：$($rootHelperDart -join ', ')"
}
```

暂存并执行暂存格式检查：

```powershell
git add -A -- test
```

然后：

```powershell
git commit -m "refactor(test): 按用途归档共享测试辅助文件"
```

---

### Task 10: 更新活跃文档、执行全仓旧路径与最终门禁审计

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Verify only: `.github/workflows/ci.yml`
- Verify only: historical `docs/plans/**`、`docs/specs/**`、`docs/第一轮审查/**`
- Verify: all production/test/tool files and final directory structure

**Interfaces:**
- Consumes: Tasks 1–9 的最终路径与日志契约。
- Produces: canonical instructions/README 与现行仓库一致；历史计划/规格仍保留当时快照，不伪装成当前代码索引。

- [ ] **Step 1: 更新 AGENTS 当前路径说明**

用 `apply_patch` 更新：

- Chat generation 客户端路径为 `features/chat/data/generation/...`；
- Settings controller/model 示例使用 preferences/providers/prompts/transfer 新路径；
- Chat case-file decomposition 示例根改为
  `test/features/chat/presentation/chat_screen_test.dart` 与
  `test/features/chat/presentation/chat_screen/`；
- `test/helpers/test_harness.dart` 保持原路径；
- Task 1 已新增的 `logs/` 规范保持 canonical，不改回根目录日志。

只改当前协作指南，不在注释中写本次计划编号。

- [ ] **Step 2: 更新 README 架构树与测试表**

README 必须明确：

- Chat application 有 composer/favorites/generation/history/requests/sessions/sidebar/workspace/ports；
- Chat data 有 generation/persistence；presentation widgets 有 composer/messages/prompts/sidebar/workspace/dialogs；
- Settings 各层按 preferences/providers/prompts/transfer，presentation 另有 shared/tabs；
- Media data 为 libraries/scanning/http；
- Sync data 为 http/udp/security，domain models 为 discovery/protocol/session；
- Core widgets 含 dialogs/notification_bubble；
- Chat screen tests 位于 `test/features/chat/presentation/chat_screen/`；
- Sync workspace composition tests 位于 `test/app/composition/sync_workspace_screen/`；
- Chat Presentation 测试不再列 `test/features/chat/widgets/`；
- 开发命令继续使用 `logs/fltest.log`。

- [ ] **Step 3: 分类全仓旧路径命中**

运行：

```powershell
rg -n "features/(chat|settings|media|sync)/(application|data|domain|presentation)|test/features/(chat|settings|media|sync)|test/helpers/|core/widgets/" AGENTS.md README.md lib test tool .github docs |
  Out-File -Encoding utf8 'logs/task10-path-audit.log'
Get-Content -Tail 250 'logs/task10-path-audit.log'
```

逐条分类：

- `lib/`、`test/`、`tool/`、`AGENTS.md`、`README.md` 中指向已移动生产/测试文件的旧
  路径必须为 0；
- `.github/workflows/ci.yml` 的根 `fltest.log` 是设计明确例外；
- 已提交历史规格/计划/第一轮审查文档中的旧路径是历史快照，不批量重写；
- 当前设计规格和本实施计划同时描述 old/new 路径，保留不改；
- 架构 fixture 中刻意构造的不存在路径可保留，但当前生产 allowance/合法路径 fixture
  必须使用新路径。

不得为了让 `rg` 绝对零命中而改写历史文档。

- [ ] **Step 4: 执行最终结构与计数审计**

```powershell
$libDartCount = @(rg --files lib -g '*.dart').Count
$testEntryCount = @(rg --files test -g '*_test.dart').Count
$rootLogCount = @(Get-ChildItem -LiteralPath '.' -File -Filter '*.log').Count
if ($libDartCount -ne 333) { throw "lib Dart 数变化：$libDartCount" }
if ($testEntryCount -ne 163) { throw "测试入口数变化：$testEntryCount" }
if ($rootLogCount -ne 0) { throw "根目录日志残留：$rootLogCount" }
git check-ignore -q --no-index logs/fltest.log
if ($LASTEXITCODE -ne 0) { throw 'logs/ 未被 ignore' }

$directFileExpectations = @(
  @('lib/features/chat/application', 0),
  @('lib/features/chat/data', 0),
  @('lib/features/chat/presentation/widgets', 1),
  @('lib/features/settings/application', 0),
  @('lib/features/settings/domain/models', 0),
  @('lib/features/settings/data', 1),
  @('lib/features/settings/presentation/widgets', 1),
  @('lib/features/media/data', 0),
  @('lib/features/sync/data', 0),
  @('lib/features/sync/domain/models', 0),
  @('lib/core/widgets', 2),
  @('test/helpers', 5)
)
foreach ($entry in $directFileExpectations) {
  $actual = @(Get-ChildItem -LiteralPath $entry[0] -File -Filter '*.dart').Count
  if ($actual -ne [int]$entry[1]) {
    throw "$($entry[0]) 直接 Dart 文件应为 $($entry[1])，实际 $actual"
  }
}
```

再确认 `test/features/chat/widgets`、`test/features/chat/chat_screen`、
`test/features/settings/settings_screen`、`test/features/sync/sync_screen` 与 Settings 旧
form/list/section/tab 目录不存在。

- [ ] **Step 5: 运行最终架构门禁**

```powershell
dart run tool/check_import_boundaries.dart 2>&1 |
  Out-File -Encoding utf8 'logs/final-boundary.log'
$finalBoundaryExit = $LASTEXITCODE
Write-Host "BOUNDARY_EXIT=$finalBoundaryExit"
Get-Content -Tail 100 'logs/final-boundary.log'
if ($finalBoundaryExit -ne 0) { throw '最终架构门禁失败' }
```

Expected: `检查 333 个文件，0 条违规`，且架构测试稍后的全量测试中证明 7 条 allowance
全部被消费。

- [ ] **Step 6: 串行运行 analyzer**

```powershell
flutter analyze --no-pub 2>&1 | Out-File -Encoding utf8 'logs/final-analyze.log'
$finalAnalyzeExit = $LASTEXITCODE
Write-Host "ANALYZE_EXIT=$finalAnalyzeExit"
Get-Content -Tail 150 'logs/final-analyze.log'
if ($finalAnalyzeExit -ne 0) { throw 'flutter analyze --no-pub 失败' }
```

Expected: `No issues found!`。不要与 Flutter test 并行运行。

- [ ] **Step 7: 串行运行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 'logs/fltest.log'
$finalTestExit = $LASTEXITCODE
Write-Host "EXIT=$finalTestExit"
Get-Content -Tail 150 'logs/fltest.log'
if ($finalTestExit -ne 0) { throw '全量测试失败' }
```

Expected: `EXIT=0`、`All tests passed!`。失败时从 `logs/fltest.log` 定向检索，不根据
截断终端输出猜测。

- [ ] **Step 8: 最终格式、diff 与范围审计**

```powershell
$allChangedDartFiles = @(
  git diff --name-only --diff-filter=ACMR 851c823 -- '*.dart' |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
)
if ($allChangedDartFiles.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $allChangedDartFiles
  if ($LASTEXITCODE -ne 0) { throw '最终 Dart 格式检查失败' }
}
git diff --check
git diff --find-renames=50% --summary
git status --short
```

审计必须得出：

- 无生产方法体/声明/常量值变化；
- 无测试断言、标题、数量或 case 注册变化；
- 无 `part` / `part of`；
- 无 `lib/core/persistence`、`lib/core/http`、`lib/features/sync/application`、
  `test/integration` 文件移动；
- 无新 package/barrel；
- 无 CI/AppData 日志语义变化；
- 只有 Task 6 的 media test 与 Task 7 的 composition test 发生批准的测试重命名。

- [ ] **Step 9: 提交活跃文档与最终审计修正**

如果 Tasks 1–9 后仅 AGENTS/README 有改动：

```powershell
git add -- AGENTS.md README.md
git diff --cached --check
git commit -m "docs: 同步文件组织与测试路径"
```

若最终门禁发现遗漏 import，只能把最小路径修正加入本提交，并在 commit body 写明遗漏
来源；不得在此加入行为修复。提交后再次运行 `git status --short`，Expected: 无输出。

---

## Failure Diagnosis and Stop Conditions

### URI / analyzer failure

- `Target of URI doesn't exist`：用错误中的旧 URI 对照当前任务移动矩阵，先查 package
  URI 消费者，再检查移动文件内部相对路径。
- 同名 declaration undefined：通常是 barrel export 未更新或新的相对 import 指向了
  错层；检查 `widgets.dart` / `settings_widgets.dart`，不要复制声明或新增 barrel。
- `APPLICATION_TO_DATA` / `STALE_ALLOWANCE`：只核对 Settings 7 组 source/target；不得
  放宽 checker 或增加通配 allowance。
- `CORE_TO_FEATURE`：Core Widget import 更新时错误引入了 feature；恢复 core 的向下
  独立性，不加例外。

### Test discovery failure

- 入口数不是 163：比较 `rg --files test -g '*_test.dart'`；检查 entry 是否重命名丢失，
  或 case-file 是否误加 `_test.dart`。
- 同一组测试重复注册：检查移动后的 entry imports 是否同时引用 old/new case paths。
- 测试编译失败但目标文件存在：优先检查 test-to-helper 相对层级，尤其 Task 9。

### File move / diff failure

- 源文件不存在或目标已存在：停止；可能已有并发/用户改动，不猜测合并。
- Git 将移动识别为 delete/add：用 `git diff --find-renames=50% --summary` 审阅；只要内容
  除 import 外一致可继续，不人为修改内容提高 rename score。
- 普通 diff 出现生产逻辑、测试断言或 serialization 变化：停止并撤回该行；本计划不
  授权顺手修复。
- 目标旧目录非空：列出残留文件并与设计核对；禁止递归删除。

### Environment / gate failure

- `flutter test` 在用例开始前卡住且日志指向 sqlite native DLL：按 `AGENTS.md` 运行
  `scripts/kill-stale-test-processes.ps1` 后重跑同一命令，不改业务代码。
- `flutter analyze` 在依赖解析后卡住：使用计划指定的 `flutter analyze --no-pub`，并与
  tests 串行。
- UDP 测试仅因环境不支持失败：保留现有 tag/CI 策略，不扩大本计划范围修改 Sync
  timeout 或协议。

### Hard stop conditions

出现以下任一情况立即停止并请求用户决定：

1. 工作区出现任务范围外的 tracked/untracked 改动且无法安全隔离。
2. 任何移动需要改变公开签名、状态所有权、数据格式、协议或 composition 才能通过。
3. Settings allowlist 不能在恰好 7 条精确边下通过。
4. 全量测试暴露确定性的既有产品缺陷；记录证据，但不在本结构重构中修复。
5. 根目录 `*.log` 中出现 tracked、non-ignored 或无法确认由 Agent 生成的文件。
6. 333 个 production Dart 文件或 163 个测试入口无法在不新增/删除代码的情况下保持。

## Definition of Done

- [ ] Tasks 1–10 均按顺序完成，每个功能提交可独立编译、测试、回滚。
- [ ] 所有设计列出的 production/test/helper 文件位于精确目标路径，旧目录无空壳。
- [ ] `widgets.dart`、`settings_widgets.dart` 对外声明集合不变且没有新增 barrel。
- [ ] Settings production allowlist 恰好 7 条、全部被消费、reason 未改。
- [ ] `lib/**/*.dart` 仍为 333，`test/**/*_test.dart` 仍为 163。
- [ ] 根目录直接 `*.log` 为 0；本地日志进入 ignored `logs/`；CI/AppData 日志不变。
- [ ] `dart run tool/check_import_boundaries.dart`：333 files / 0 violations。
- [ ] `flutter analyze --no-pub`：exit 0 / no issues。
- [ ] `flutter test --reporter compact`：exit 0 / all tests passed。
- [ ] `dart format --output=none --set-exit-if-changed` 与 `git diff --check` 通过。
- [ ] 最终工作区干净，所有 commit message 使用简体中文 conventional subject。

## Final Scope Audit

| 设计要求 | 实施任务 | 明确验证 |
|---|---|---|
| Agent logs 收口与根目录清理 | Task 1 | root logs=0、`logs/fltest.log` ignored、CI 路径保留 |
| Chat application/data/domain tests | Task 2 | target tests、boundary、163 entries |
| Chat presentation/widgets/screen tests | Task 3 | presentation tests、barrel export 审计 |
| Settings app/domain/data + 7 allowances | Task 4 | Settings tests、architecture test、7-edge count |
| Settings presentation/widgets/screen tests | Task 5 | presentation tests、barrel export 审计 |
| Media data 与测试镜像 | Task 6 | all Media tests、approved test rename |
| Sync data/domain 与 composition ownership | Task 7 | Sync + composition + integration tests |
| Core Widgets | Task 8 | core/app/feature consumer tests、CORE_TO_FEATURE gate |
| Shared test helpers | Task 9 | helpers + features + integration broad run |
| Active docs、old-path audit、final gates | Task 10 | path audit、333/163、boundary/analyze/full test |
| 不拆文件/不改行为/不越界 | All + Task 10 | rename diff、scope audit、hard stop conditions |
