# Scoped Test Suite Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove tautological, duplicate, pseudo-integration, and implementation-coupled tests from the approved directories while preserving unique behavioral contracts and deterministic coverage.

**Architecture:** Treat each test as a trigger/observable/decision-branch contract. Delete tests only when another test fully subsumes that triple, consolidate data-only variants, and replace event-loop timing guesses with explicit stream/listener completion signals. Production code and tests outside the approved directories remain unchanged.

**Tech Stack:** Flutter 3.44.x, Dart 3.11+, `flutter_test`, Riverpod 3, raw `sqlite3`, PowerShell 7, LCOV.

## Global Constraints

- Modify only `test/app`, `test/architecture`, `test/core`, `test/integration`, and `test/helpers`, plus this plan artifact.
- Do not modify `lib/`, `dart_test.yaml`, CI workflows, timeouts, test concurrency, or tests under `test/features`.
- Preserve unique error, migration, security, protocol, persistence, accessibility, and lifecycle branches even when they do not add line coverage.
- Do not introduce `find.byKey`, pixel assertions, generic settling, real sleeps, timeout increases, or new allowlist entries.
- Use PowerShell 7 and redirect every Flutter test run to a log file.
- Format every changed Dart file before verification. Do not create implementation commits unless the user explicitly requests them.
- Baseline from 2026-08-09: 324 executed cases passed in 27.41 seconds; scoped coverage was 4,463/14,991 lines (29.77%). Baseline artifacts are under `%TEMP%\oh-my-llm-scoped-test-cleanup`.

---

### Task 1: Replace Event-loop Guesses With Deterministic Stream Signals

**Files:**
- Modify: `test/core/http/llm_http_stream_transport_test.dart`
- Modify: `test/core/http/sse_event_decoder_test.dart`
- Modify: `test/architecture/test_resilience_policy_test.dart`

**Interfaces:**
- Consumes: `StreamController.onListen`, listener callbacks, `Completer<T>`, and subscription cancellation futures.
- Produces: the same transport/decoder behavioral coverage with no `Future.delayed` outside the existing UDP exception; `_futureDelayedAllow` contains only `test/features/sync/data/sync_udp_discovery_test.dart: 3`.

- [x] **Step 1: Replace transport stream flushes with explicit events**

  In the mid-stream failure test, complete one `Completer<void>` from the first event callback and one `Completer<Object>` from `onError`; await them after `source.add` and `source.addError`. In the timeout test, await an error completer. In the cancellation test, construct the source controller with `onListen` and `onCancel` completers, then await the first delivered event before cancelling and adding the wake-up chunk. Remove all five `Future<void>.delayed(Duration.zero)` calls.

- [x] **Step 2: Replace decoder subscription probing with `onListen`**

  Construct the byte controller with an `onListen` completer, await it, assert `hasListener`, cancel the subscription, and assert the listener was removed. Remove the sole `Future<void>.delayed(Duration.zero)` call.

- [x] **Step 3: Tighten the resilience policy tests**

  Remove the scanner test that merely recounts the same three tokens already covered by the first two scanner tests. Replace the mislabeled stale-allowance test with two real verifier tests: an unlisted occurrence must fail the excess branch, and an allow entry absent from actual counts must fail the stale branch. Update `_futureDelayedAllow` to retain only the three tagged UDP delays and update its comment accordingly.

- [x] **Step 4: Format and verify the deterministic-wait batch**

  Run:

  ```powershell
  dart format test/core/http/llm_http_stream_transport_test.dart test/core/http/sse_event_decoder_test.dart test/architecture/test_resilience_policy_test.dart
  $Log = Join-Path $env:TEMP 'oh-my-llm-scoped-test-cleanup\task1.log'
  flutter test test/core/http/llm_http_stream_transport_test.dart test/core/http/sse_event_decoder_test.dart test/architecture/test_resilience_policy_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  rg --pcre2 -n "Future(?:<[^>]+>)?\.delayed" test/core/http test/architecture --glob "*.dart"
  ```

  Expected: test exit 0; the final search reports only token fixtures inside `test_resilience_policy_test.dart`, not executable delays in the two HTTP tests.

---

### Task 2: Remove Tautological and Repeated Core Tests

**Files:**
- Delete: `test/core/persistence/background_worker_command_test.dart`
- Delete: `test/core/http/peer_http_client_provider_test.dart`
- Modify: `test/core/http/http_client_provider_test.dart`
- Modify: `test/core/constants/app_breakpoints_test.dart`
- Modify: `test/core/widgets/adaptive_master_detail_layout_test.dart`
- Modify: `test/core/widgets/notification_bubble_accessibility_test.dart`
- Modify: `test/core/utils/date_formatting_test.dart`
- Modify: `test/core/utils/id_generator_test.dart`
- Modify: `test/core/logging/network_log_redactor_test.dart`
- Modify: `test/core/logging/json_truncator_test.dart`
- Modify: `test/core/logging/sse_log_buffer_test.dart`
- Modify: `test/core/persistence/sqlite_replace_all_test.dart`
- Modify: `test/core/persistence/versioned_json_storage_test.dart`
- Modify: `test/core/persistence/app_database_migration_test.dart`
- Modify: `test/core/http/sse_event_decoder_test.dart`
- Modify: `test/helpers/widget_test_animation_test.dart`

**Interfaces:**
- Consumes: documented ID format, public request/header behavior, schema migration contracts, public widget semantics, and the shared finite-animation helper.
- Produces: fewer cases with the same meaningful branch matrix; no test that merely proves a sealed subtype constructor, Provider generic type, unused `Equatable` implementation, or statistically sampled randomness.

- [x] **Step 1: Delete value-object and provider duplicates**

  Delete `background_worker_command_test.dart`; command payloads and response pattern matching are exercised by repository/worker lifecycle tests, while this file only reads constructor fields and checks inheritance. Delete `peer_http_client_provider_test.dart`; both cases are already covered more strongly in `http_client_provider_test.dart`. In `http_client_provider_test.dart`, remove the two Provider type assertions and the identity assertion, retaining only LLM header synchronization and peer header non-leakage behavior.

- [x] **Step 2: Collapse simple boundary redundancy**

  In `app_breakpoints_test.dart`, remove the `breakpoint + 1` assertions because `breakpoint` already proves the wide-side comparison. In `adaptive_master_detail_layout_test.dart`, remove the 841 test because 840 and 839 uniquely establish the boundary. In `date_formatting_test.dart`, retain single-digit padding, representative two-digit values, and midnight, but remove year-end/deep-night variants that execute no distinct branch.

- [x] **Step 3: Replace probabilistic ID assertions with the documented format contract**

  Replace the five ID tests with one test that matches `^\d+-[0-9a-f]+$` and parses a positive timestamp prefix. Delete the non-empty, delimiter, suffix-only, and 100-sample collision tests because they are subsumed by the format assertion or are nondeterministic statistical checks.

- [x] **Step 4: Consolidate redaction matrices without losing sensitive keys**

  Replace the nine header tests with one all-known-sensitive-key map plus safe headers and one case-insensitive map. Replace the seven payload tests with one recursive map/list case containing every known sensitive category and one scalar passthrough table. Keep the two text-redaction tests. Delete direct `isSensitiveHeader` tests because the same public classification is exhaustively observed through `redactHeaders`.

- [x] **Step 5: Remove JSON truncation composites that add no branch**

  Delete the realistic LLM payload composition test because map, list, short string, and truncation behavior are already independently covered. Remove the CJK-only truncation case and merge the three overlapping emoji tests into two contracts: the default 500-grapheme boundary and an injected odd `maxLength`. Preserve short/boundary/over-limit, nested container, scalar, and null behavior.

- [x] **Step 6: Merge repeated persistence assertions**

  In `sse_log_buffer_test.dart`, merge normal flush and no-in-flight idempotence into one test; rewrite the empty-flush conditional so it always compares file length before and after. In `sqlite_replace_all_test.dart`, delete first-call insertion because the replacement happy path already inserts new rows. In `versioned_json_storage_test.dart`, merge current empty/non-empty list decoding into a named table and merge version 0/negative acceptance into one table-driven test; remove the separate empty-list encoder case because the encoder has no empty branch and current-list decoding retains the empty contract.

- [x] **Step 7: Remove fresh-schema migration duplicates**

  Rename the top version test to the current lower-bound contract and assert `>= 13`. Delete the V10/V13 tests that separately reassert current column existence or lower user versions when the fresh-schema default-value tests already prove those columns exist. Preserve legacy V8, V9, and V12 migration tests, default-value behavior, cascades, and old-data preservation.

- [x] **Step 8: Remove implementation-coupled widget/helper assertions**

  In notification bubble tests, remove the viewport smoke test because the content has no responsive branch and the exact status/action/close semantics are already tested. Remove the assertion that a semantics-only type label is absent as visible text; retain the non-duplicated semantics-node checks. In the animation helper test, drive an explicit finite `AnimationController`, await the helper, and assert `AnimationStatus.completed` instead of reading `AnimatedOpacity.opacity` from the widget implementation.

- [x] **Step 9: Remove unused SSE value equality coverage**

  Delete `SseEvent 值相等（Equatable）`; no production consumer compares `SseEvent` values, while decoder output fields remain directly asserted throughout the file.

- [x] **Step 10: Format and verify the Core batch**

  Format every surviving changed Dart file, then run `test/core`, `test/helpers`, and the resilience policy test with redirected output. Expected: exit 0 and no analyzer warning from deleted imports/helpers.

---

### Task 3: Remove Duplicate App and Pseudo-integration Coverage

**Files:**
- Delete: `test/integration/chat_favorites_integration_test.dart`
- Modify: `test/app/router/app_router_test.dart`
- Modify: `test/app/shell/app_shell_scaffold_test.dart`
- Modify: `test/integration/bootstrap_integration_test.dart`
- Modify: `test/integration/collections_cascade_integration_test.dart`
- Modify: `test/integration/chat_lifecycle_integration_test.dart`
- Modify: `test/integration/chat_multi_conversation_integration_test.dart`
- Modify: `test/integration/preset_prompt_request_integration_test.dart`

**Interfaces:**
- Consumes: URL restoration, responsive shell navigation, bootstrap composition, SQLite collection cascade, message-branch persistence, generation lifecycle, multi-conversation persistence, and prompt ordering.
- Produces: integration tests that cross a real boundary rather than manually copying output from one controller into another.

- [x] **Step 1: Merge duplicate router restoration coverage**

  Delete the first direct-favorite test after adding its assistant model display assertion to the fresh-router rebuild test. The rebuild test mounts the same direct URL twice from the database and therefore strictly subsumes a single direct mount.

- [x] **Step 2: Reduce shell viewport repetitions locally**

  Keep `phonePortrait`, `shellBelowBoundary`, `shellAtBoundary`, and `wideDesktop` for navigation. Keep `phonePortrait` and `shellBelowBoundary` for drawer behavior. Do not alter the shared viewport catalog, because tests outside the approved scope explicitly consume it.

- [x] **Step 3: Delete the false bootstrap migration attribution**

  Remove `启动后执行了数据迁移`: `AppDatabase.inMemory()` completes migration before the injected database reaches `bootstrap`, so the test cannot prove bootstrap performed migration. Extract the repeated viewport/preferences/database/bootstrap setup used by the two remaining tests into a local helper.

- [x] **Step 4: Delete pseudo-integration favorites tests**

  Delete `chat_favorites_integration_test.dart`. Its tests manually read chat strings and pass them to Favorites/Collections controllers; no production cross-feature command or UI path connects those actions. The actual integration is already covered by chat favorite command/facade/widget tests and Favorites repository/controller tests outside this cleanup scope.

- [x] **Step 5: Remove duplicate collection and chat lifecycle cases**

  Delete `删除收藏夹后落回的收藏在未分类筛选中可见`, which is subsumed by the preceding cascade test plus existing repository filter tests. Delete `分支编辑后重建容器 — 分支选择保留`, which is subsumed by both old-branch and new-branch persistence cases in `chat_message_version_persistence_integration_test.dart`. Delete `generation 期间 stop 后新 generation 不被旧回调覆盖`, which is covered more precisely by controlled controller stop/race tests. Preserve the one-time repository recovery case and the checkpoint busy-guard case because they add distinct higher-level recovery and command-exclusion contracts.

- [x] **Step 6: Remove controller-only cases from integration files**

  Delete `创建多对话后切换 - 各对话消息独立`; controller CRUD tests cover in-memory selection, while the remaining two cases cross the persistence/restart boundary. Delete `未选择 PresetPrompt 时请求仅包含对话消息`; the request builder already covers the null-preset baseline, while the remaining integration cases prove selected-preset propagation and multi-turn reapplication.

- [x] **Step 7: Format and verify the App/Integration batch**

  Format all changed Dart files, then run `test/app` and `test/integration` with redirected output. Expected: exit 0; imports for deleted chat favorites helpers and lifecycle-only types are removed.

---

### Task 4: Compare Coverage and Run Repository Gates

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: baseline log and LCOV under `%TEMP%\oh-my-llm-scoped-test-cleanup`.
- Produces: fresh scoped coverage, line-level coverage delta, analyzer/gate results, full-suite log, and final scope audit.

- [x] **Step 1: Recount the scoped suite**

  Re-run the inventory script and record Dart file count, source lines, static test declarations, executed cases, and elapsed time. Expected: fewer files, declarations, executed cases, and source lines than the baseline, without using these reductions as correctness proof.

- [x] **Step 2: Generate post-cleanup scoped coverage**

  Run the same five directories with `--coverage-path` pointing to `%TEMP%\oh-my-llm-scoped-test-cleanup\after-lcov.info`. Compare `DA` line hits by production file against `baseline-lcov.info`. Investigate every line that changes from hit to unhit; accept only losses attributable to deleted constructor/inheritance/statistical checks, otherwise restore a meaningful behavior test.

- [x] **Step 3: Run static and architecture gates**

  Run:

  ```powershell
  dart run tool/check_import_boundaries.dart
  flutter analyze --no-pub
  git diff --check
  ```

  Expected: architecture gate reports zero violations, analyzer reports no issues, and diff check emits no output.

- [x] **Step 4: Run the full suite exactly as required by the repository**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 fltest.log
  if ($E -ne 0) { exit $E }
  ```

  Expected: `EXIT=0` and `All tests passed!`.

- [x] **Step 5: Audit scope and prepare the handoff**

  Confirm `git status --short` contains only this plan and files under the five approved directories. Report each deleted file/test, each merged matrix, each fragility rewrite, noteworthy retained cases, exact coverage delta, and every verification command result. Do not claim completion if any full-suite, analyzer, architecture, formatting, coverage-explanation, or scope check remains pending.
