# Compatibility Debt Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在两个自用终端均已升级到当前版本的前提下，移除已经完成使命的历史兼容层，让当前 state/schema/交换格式成为唯一 canonical baseline，同时不破坏当前 provider、协议、平台与 runtime 兼容能力。

**Architecture:** 按数据风险从低到高分阶段实施。内部状态先收敛到单一事实来源；外部交换格式再断代；SharedPreferences JSON 在证明/canonicalize 旧形状后收紧；SQLite 最后把 v13 提升为 rolling migration floor。每阶段独立提交、独立验证、可单独 revert。设计依据见 `docs/specs/2026-08-17-compatibility-debt-cleanup-design.md`。

**Tech Stack:** Flutter 3.44.x, Dart 3.11+, Riverpod 3, raw `sqlite3`, SharedPreferences JSON, PowerShell 7.

## Global Constraints

- 本计划清理的是**历史兼容债**，不是现役兼容能力。
- 不删除当前 OpenAI-compatible endpoint 适配、Chat Completions / Responses / Anthropic 协议支持、Windows/Android 平台分支、真实 runtime 类型/行为兼容。
- 不顺手修改 Sync 协议；Sync 若需断代，另做独立审计和设计。
- 不因为字段带默认值就自动判定为 legacy。必须先区分“当前可选字段语义”和“旧持久化形状 fallback”。
- SQLite/JSON/settings format 变更前先保留数据备份。
- 每个 Dart 修改批次提交前执行 `dart format`；Flutter 测试输出按 `AGENTS.md` 写入 `logs/`。
- 每个任务一个独立 implementation commit；不要把 4 个生产代码清理任务 squash 成一个不可回滚的大提交。
- 当前 rollout 前提：Windows 与 Android 两个实际终端都已运行最新版本。SQLite 任务执行前仍需现场读取 `PRAGMA user_version` 再次确认，不以口头前提代替最终数据检查。

---

### Task 1: Collapse Chat Generation to One Source of Truth

**Files:**
- Modify: `lib/features/chat/application/sessions/chat_sessions_state.dart`
- Modify as discovered: `lib/features/chat/application/sessions/chat_sessions_controller.dart`
- Modify as discovered: `lib/features/chat/application/sessions/chat_sessions_controller_streaming.dart`
- Modify as discovered: `lib/features/chat/application/sessions/chat_sessions_controller_support.dart`
- Modify presentation consumers returned by the search below.
- Modify: `test/features/chat/application/sessions/chat_sessions_state_test.dart`
- Modify relevant tests under: `test/features/chat/application/sessions/chat_sessions_controller/`
- Modify if affected: `test/features/chat/application/sessions/chat_sessions_controller_test.dart`

**Target contract:** `ChatGenerationSnapshot? generation` and its phase/metadata are the canonical lifecycle state. Presentation-visible booleans/counts are derived values, not separately stored compatibility fields.

- [ ] **Step 1: Inventory every compatibility projection consumer**

  Run:

  ```powershell
  rg -n "isStreaming|isAutoRetryWaiting|autoRetryCount|projectGeneration" lib test
  ```

  Classify every match as canonical generation state, derived presentation read, controller write, or compatibility-invariant test. Do not modify unrelated retry domain fields that are not projections of `generation`.

- [ ] **Step 2: Add/adjust tests around canonical generation semantics**

  In `chat_sessions_state_test.dart` and controller tests, assert lifecycle behavior from `generation.phase` / snapshot metadata directly. Where presentation needs booleans, test a derived getter/provider/select rather than a separately writable field.

  Run the focused test before implementation and capture the expected red/compile failure:

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/features/chat/application/sessions/chat_sessions_state_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-chat-red.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-chat-red.log
  ```

- [ ] **Step 3: Migrate consumers, then delete stored compatibility fields**

  Replace presentation reads with snapshot-derived reads/selectors. Remove the compatibility fields, constructor/copyWith parameters, `projectGeneration` synchronization path, and tests whose only purpose is proving duplicate fields remain synchronized.

  Preserve actual lifecycle behavior: streaming, retry waiting, cancellation, retry count display, generation completion and failure must still be represented by the canonical snapshot.

- [ ] **Step 4: Format and verify Task 1**

  ```powershell
  dart format <all changed dart files>
  flutter test test/features/chat/application/sessions/chat_sessions_state_test.dart test/features/chat/application/sessions/chat_sessions_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-chat-green.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-chat-green.log
  if ($E -ne 0) { exit $E }
  rg -n "projectGeneration" lib test
  ```

  Expected: focused tests exit 0; `projectGeneration` has no remaining production consumer/definition. Any remaining `isStreaming`-style names must be deliberate derived semantics rather than stored compatibility state.

- [ ] **Step 5: Commit Task 1**

  ```powershell
  git commit -m "refactor(chat): 移除生成状态兼容投影"
  ```

---

### Task 2: Retire Settings Export v5-v7 Compatibility

**Files:**
- Modify: `lib/features/settings/domain/models/transfer/settings_export_codec.dart`
- Modify: `test/features/settings/domain/models/transfer/settings_export_codec_test.dart`
- Modify if affected: `test/features/settings/domain/models/transfer/settings_export_data_test.dart`

**Target contract:** current settings exchange format v8 is the only accepted format; version is read only from `formatVersion`.

- [ ] **Step 1: Protect any old backup that is still worth keeping**

  Before code deletion, inventory personal settings backup files. Any v5/v6/v7 backup that must remain usable should be imported by the current app and immediately re-exported as v8. If no old backup matters, record that decision in the implementation PR body.

- [ ] **Step 2: Rewrite codec tests to the new support boundary**

  Tests must prove:

  - v8 decodes successfully.
  - missing `formatVersion` is rejected even if legacy `version` exists.
  - v5/v6/v7 return the existing explicit unsupported-version result/error path.
  - future versions above current remain explicitly unsupported.

  First change tests and run them to capture red:

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/features/settings/domain/models/transfer/settings_export_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-settings-red.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-settings-red.log
  ```

- [ ] **Step 3: Remove old migrators and alias**

  Remove `SettingsExportFormatMigratorV5ToV6`, `V6ToV7`, `V7ToV8`, their migration chain helpers, the `source['version']` fallback, and old-version success branches. Set the minimum supported version/current decode contract to v8 without introducing a generic migration framework to replace deleted code.

- [ ] **Step 4: Format, verify, and commit Task 2**

  ```powershell
  dart format lib/features/settings/domain/models/transfer/settings_export_codec.dart test/features/settings/domain/models/transfer/settings_export_codec_test.dart test/features/settings/domain/models/transfer/settings_export_data_test.dart
  flutter test test/features/settings/domain/models/transfer --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-settings-green.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-settings-green.log
  if ($E -ne 0) { exit $E }
  rg -n "V5ToV6|V6ToV7|V7ToV8|\['version'\]" lib/features/settings test/features/settings
  git commit -m "refactor(settings): 移除旧版设置导入兼容"
  ```

  Expected: tests exit 0; old migrator classes and legacy version alias have no remaining production matches.

---

### Task 3: Make Versioned JSON Storage Strict

**Files:**
- Modify: `lib/core/persistence/versioned_json_storage.dart`
- Modify: `test/core/persistence/versioned_json_storage_test.dart`
- Modify if affected: `test/core/persistence/versioned_json_store_test.dart`
- Modify any concrete consumer only if a bounded canonicalization is proven necessary by Step 1.

**Target contract:** object and list storage both accept only the current versioned envelope. Historical bare-object decoding must disappear after current data is canonical.

- [ ] **Step 1: Audit all object consumers before deleting fallback**

  Run:

  ```powershell
  rg -n "decodeObject\(|encodeObject\(" lib test
  rg -n "VersionedJsonStorage|VersionedJsonStore" lib/features lib/app lib/bootstrap.dart
  ```

  For each persisted SharedPreferences key, answer:

  1. Is every current write wrapped by `encodeObject`?
  2. Could an old bare object survive forever if that setting was never changed?
  3. Does a successful read rewrite it in current envelope form?

  Save this inventory in the implementation PR description or commit body; do not add a permanent compatibility registry solely for the audit.

- [ ] **Step 2: Decide direct cut vs bounded canonicalization**

  If all relevant keys on both endpoints are already known canonical, proceed directly. If any bare object can still exist lazily, add the smallest one-time rewrite at its owning persistence boundary, run it on both endpoints, confirm the stored value is canonical, then remove that rewrite in the same cleanup series after confirmation.

  Do **not** convert the old fallback into another indefinite “migration service”.

- [ ] **Step 3: Change tests first**

  Update `versioned_json_storage_test.dart` so a bare object is rejected and current envelope decoding remains accepted. Preserve tests for malformed JSON, wrong container types, and version validation that still protect the current format.

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/core/persistence/versioned_json_storage_test.dart test/core/persistence/versioned_json_store_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-json-red.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-json-red.log
  ```

- [ ] **Step 4: Delete bare-object fallback and verify**

  Remove the branch that returns a decoded map when the versioned object wrapper is absent. Keep object/list behavior symmetric and fail explicitly for unsupported/malformed envelopes.

  ```powershell
  dart format lib/core/persistence/versioned_json_storage.dart test/core/persistence/versioned_json_storage_test.dart test/core/persistence/versioned_json_store_test.dart <any changed consumer files>
  flutter test test/core/persistence/versioned_json_storage_test.dart test/core/persistence/versioned_json_store_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-json-green.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-json-green.log
  if ($E -ne 0) { exit $E }
  git commit -m "refactor(persistence): 收紧版本化 JSON 格式"
  ```

---

### Task 4: Raise the SQLite Migration Floor to v13

**Files:**
- Modify: `lib/core/persistence/app_database.dart`
- Modify: `test/core/persistence/app_database_migration_test.dart`
- Modify any dedicated legacy fixture/helpers referenced only by V8-V12 migration tests.

**Target contract:** fresh databases are created directly at complete schema v13; databases already at v13 open normally; databases below v13 fail explicitly as unsupported legacy schema. No V9→V13 archaeology remains in production.

- [ ] **Step 1: Back up and prove both deployed databases are v13**

  On Windows and Android, copy the current database before changing code and inspect:

  ```sql
  PRAGMA user_version;
  ```

  Both must report at least 13. If either endpoint is below 13, **stop Task 4** and run the current released app until migration completes before proceeding.

- [ ] **Step 2: Redefine migration tests around the rolling baseline**

  Replace historical V8/V9/V10/V11/V12 upgrade-success fixtures with contracts for:

  - fresh in-memory DB creates the full current schema and sets `user_version` to 13.
  - an already-current v13 DB opens without mutation/loss.
  - a deliberately lower `user_version` fails with a clear unsupported-legacy exception before repositories execute against the wrong schema.
  - current schema defaults, foreign keys/cascades and persistence behavior that are not migration archaeology remain covered.

  Run changed tests before production implementation and capture red:

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test test/core/persistence/app_database_migration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-db-red.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-db-red.log
  ```

- [ ] **Step 3: Replace the historical chain with a current baseline initializer**

  In `AppDatabase`:

  - for `user_version == 0`, call the current `_createSchema()` once and set `PRAGMA user_version = 13` directly;
  - for `user_version == 13`, continue normally;
  - for `0 < user_version < 13`, throw an explicit unsupported-legacy-schema error;
  - preserve a sensible explicit behavior for `user_version > 13` (do not silently mutate a newer DB with older code);
  - delete `_migrateV9`, `_migrateV10`, `_migrateV11`, `_migrateV12`, `_migrateV13` and `_mergeLegacySystemPrompts` once no current path references them;
  - remove imports such as `dart:convert` only if they become unused after deletion.

  Do not introduce a migration registry/framework. A future v14 should add only a temporary v13→v14 step.

- [ ] **Step 4: Format, verify, and commit Task 4**

  ```powershell
  dart format lib/core/persistence/app_database.dart test/core/persistence/app_database_migration_test.dart <any changed fixture/helper files>
  flutter test test/core/persistence/app_database_migration_test.dart test/core/persistence/sqlite_replace_all_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/compat-db-green.log
  $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 logs/compat-db-green.log
  if ($E -ne 0) { exit $E }
  rg -n "_migrateV9|_migrateV10|_migrateV11|_migrateV12|_migrateV13|_mergeLegacySystemPrompts" lib test
  git commit -m "refactor(persistence): 以当前数据库 schema 为兼容基线"
  ```

  Expected: focused tests exit 0; production has no V9→V13 migration methods or legacy system-prompt merge path.

---

### Task 5: Audit Remaining Compatibility and Codify the Rolling-Baseline Rule

**Files:**
- Modify: `AGENTS.md`
- Modify only confirmed historical compatibility sites returned by the audit; defer ambiguous/current runtime compatibility to separate work.

- [ ] **Step 1: Search the repository broadly**

  ```powershell
  rg -n -i "legacy|compat|compatibility|兼容|migration|migrate|deprecated|fallback|旧版|历史" lib test docs AGENTS.md
  ```

  Classify every production match into one of four buckets:

  1. historical internal transition — remove;
  2. historical persisted/interchange format — remove if its data gate has passed;
  3. current product/runtime/platform compatibility — keep;
  4. ambiguous — keep and open a narrowly scoped follow-up instead of guessing.

- [ ] **Step 2: Remove only newly proven dead compatibility**

  For each additional deletion, add or update the nearest behavioral test first. Do not broaden this task into unrelated refactors. If more than one subsystem is affected, make separate commits by subsystem.

- [ ] **Step 3: Update `AGENTS.md`**

  Replace the current persistence guidance that describes an accumulating `9 -> 13` chain with the rolling-baseline policy:

  - fresh install creates current schema directly;
  - only the migration from the last still-supported baseline to the new version may be temporary;
  - after both owned endpoints migrate, advance the baseline and delete that migration;
  - historical JSON/settings aliases follow the same bounded-lifetime rule;
  - compatibility shims require a reason, boundary, removal condition and tests.

  Commit:

  ```powershell
  git commit -m "docs: 固化历史兼容退役规则"
  ```

---

### Task 6: Full Verification and Cleanup Proof

- [ ] **Step 1: Format-check every changed Dart file**

  ```powershell
  $ChangedDart = git diff --name-only master...HEAD -- '*.dart'
  if ($ChangedDart) {
    dart format $ChangedDart
    dart format --output=none --set-exit-if-changed $ChangedDart
  }
  ```

- [ ] **Step 2: Run static and architecture gates**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter analyze 2>&1 | Out-File -Encoding utf8 logs/compat-analyze.log
  $AnalyzeExit = $LASTEXITCODE
  Get-Content -Tail 150 logs/compat-analyze.log
  if ($AnalyzeExit -ne 0) { exit $AnalyzeExit }

  dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/compat-boundaries.log
  $BoundaryExit = $LASTEXITCODE
  Get-Content -Tail 150 logs/compat-boundaries.log
  if ($BoundaryExit -ne 0) { exit $BoundaryExit }
  ```

- [ ] **Step 3: Run full Flutter tests with required log redirection**

  ```powershell
  New-Item -ItemType Directory -Force logs | Out-Null
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log
  $TestExit = $LASTEXITCODE
  Write-Host "EXIT=$TestExit"
  Get-Content -Tail 150 logs/fltest.log
  if ($TestExit -ne 0) { exit $TestExit }
  ```

- [ ] **Step 4: Prove historical paths are actually gone**

  ```powershell
  rg -n "projectGeneration|SettingsExportFormatMigratorV5ToV6|SettingsExportFormatMigratorV6ToV7|SettingsExportFormatMigratorV7ToV8|_migrateV9|_migrateV10|_migrateV11|_migrateV12|_migrateV13|_mergeLegacySystemPrompts" lib test
  git diff --check master...HEAD
  git status --short
  ```

  Expected: no production matches for the retired named compatibility paths; `git diff --check` is clean; worktree contains no accidental generated/log artifacts.

- [ ] **Step 5: Manual two-endpoint smoke check**

  Using the final build on both Windows and Android, verify:

  - existing current database opens and conversations/messages remain visible;
  - settings load from current persisted JSON;
  - a current v8 settings export round-trips;
  - normal chat generation, streaming state and auto-retry presentation still behave correctly;
  - no current provider/protocol behavior was removed as collateral cleanup.

## Completion Criteria

The implementation series is complete only when all of the following are true:

- generation lifecycle has one canonical state representation;
- settings import is v8-only with explicit rejection of retired versions;
- versioned object storage no longer accepts historical bare objects, after any required canonicalization has been completed and removed;
- SQLite baseline is v13 and V9→V13 migration archaeology is gone;
- remaining compatibility branches have been classified as current capability or carry an explicit retirement condition;
- `AGENTS.md` documents rolling migration baselines instead of indefinite migration accumulation;
- focused tests, `flutter analyze`, import-boundary check and full Flutter test suite all pass with captured exit codes.
