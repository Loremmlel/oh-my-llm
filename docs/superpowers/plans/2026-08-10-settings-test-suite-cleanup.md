# Settings Test Suite Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce low-value Settings tests and Flutter test-file startup cost while preserving unique behavioral, compatibility, persistence, failure, and UI-wiring contracts.

**Architecture:** Classify every change by trigger, public observable, test layer, and expected regression failure reason. Consolidate cohesive microfiles, merge data-only variants into named tables, seed widget state through production repositories instead of replaying unrelated UI setup, and delete only strict duplicates or implementation-only checks. Production code remains unchanged.

**Tech Stack:** Flutter 3.44.x, Dart 3.11+, Riverpod 3, `flutter_test`, `shared_preferences`, raw `sqlite3`, PowerShell 7, LCOV.

## Global Constraints

- Modify only `test/features/settings`, this plan, and `docs/superpowers/specs/2026-08-10-settings-test-suite-cleanup-design.md`.
- Do not modify `lib/`, product behavior, persistence formats, `dart_test.yaml`, CI workflows, timeouts, tags, or concurrency.
- Preserve every unique protocol, compatibility, malformed-input, persistence-failure, rollback, security Header, SQLite, and UI-wiring branch.
- Do not add arbitrary delays, generic `pumpAndSettle`, internal `Key` finders, pixel assertions, timeout increases, or allowlist entries.
- Use production repository APIs or `TestFixtures.seedPreferences()` for widget seeds; do not add raw SQL to widget tests.
- Format all changed Dart files and run Flutter tests only with redirected compact output.
- Baseline: 45 Dart files, 353 executed cases, 85.41-second first run, 43.44-second warm coverage run, and Settings production coverage of 3,027/3,547 executable lines (85.34%).
- Do not commit unless the user explicitly requests a commit.

---

### Task 1: Consolidate Domain Model Contract Tests

**Files:**
- Create: `test/features/settings/domain/models/settings_value_objects_test.dart`
- Create: `test/features/settings/domain/models/prompt_models_test.dart`
- Create: `test/features/settings/domain/models/llm_configs_test.dart`
- Modify: `test/features/settings/domain/models/template_prompt_test.dart`
- Delete: `test/features/settings/domain/models/auto_retry_settings_test.dart`
- Delete: `test/features/settings/domain/models/chat_defaults_test.dart`
- Delete: `test/features/settings/domain/models/custom_headers_config_test.dart`
- Delete: `test/features/settings/domain/models/font_size_settings_test.dart`
- Delete: `test/features/settings/domain/models/output_processing_settings_test.dart`
- Delete: `test/features/settings/domain/models/fixed_prompt_sequence_test.dart`
- Delete: `test/features/settings/domain/models/memory_prompt_test.dart`
- Delete: `test/features/settings/domain/models/preset_prompt_test.dart`
- Delete: `test/features/settings/domain/models/prompt_message_placement_test.dart`
- Delete: `test/features/settings/domain/models/prompt_message_role_test.dart`
- Delete: `test/features/settings/domain/models/prompt_message_round_trip_test.dart`
- Delete: `test/features/settings/domain/models/prompt_message_test.dart`
- Delete: `test/features/settings/domain/models/llm_model_config_test.dart`
- Delete: `test/features/settings/domain/models/llm_provider_config_test.dart`

**Interfaces:**
- Consumes: public constructors, JSON codecs, equality, labels, summary getters, placement filters, fallback-title builder, and protocol resolution.
- Produces: three cohesive entry files that retain compatibility and behavior contracts without direct `Equatable.props` inspection or isolated constructor forwarding checks.

- [x] **Step 1: Build `settings_value_objects_test.dart` from five existing files**

  Preserve these exact contracts:

  - `AutoRetrySettings`: all clear flags reset to documented defaults; missing/unknown JSON defaults; full round-trip including abnormal-finish retry; named table for `stop`, `tool_calls`, `null`, `length`, `content_filter`, and an unknown reason.
  - `ChatDefaults`: clear/override semantics in one scenario; missing JSON defaults; round-trip.
  - `CustomHeadersConfig`: one input containing valid, duplicate, empty, and whitespace-only keys must produce the exact final map; missing headers and missing entry fields retain defaults; round-trip.
  - `FontSizeSettings`: missing and non-number JSON values default to 14 through a named table; non-default round-trip. Delete the constructor-default, normal-parse, and direct `copyWith` checks because they add no separate persistence contract.
  - `OutputProcessingSettings`: rule defaults, rule round-trip, list round-trip, and malformed non-list fallback. Delete the direct `copyWith` test because widget/controller behavior exercises mutations.

  Use loop records with a `name`, `input`, and `expected` field so failures identify the exact variant.

- [x] **Step 2: Build `prompt_models_test.dart` from seven existing files**

  Preserve the fixed-sequence and memory summary behavior. Replace three `messagesForPlacement` tests with one table covering `before`, `beforeLatestInput`, and `after`; remove the empty-list case because the same filter path already returns no nonmatching items and Dart iterable emptiness is not a product branch. Replace role parsing/label, placement parsing/label, and fallback-title repetitions with named tables. Retain the `PromptMessage` before-latest-input JSON round-trip.

- [x] **Step 3: Build `llm_configs_test.dart` from model and provider files**

  Keep independent JSON defaults, conditional provider fields, explicit storage values, all-protocol round-trips, malformed protocol rejection, provider-to-model resolution, and resolved-model expansion. Delete both direct `props` assertions, both isolated protocol `copyWith` assertions, the empty `resolvedModels` case, and the second all-protocol resolution loop because these prove implementation forwarding already observed by equality, resolution, and codec contracts.

- [x] **Step 4: Parameterize `template_prompt_test.dart`**

  Replace five `TemplatePromptVariableType.fromString` cases with a named table. Merge body-variable projection/presence checks into one scenario containing both a body variable and an input variable plus a second no-body prompt. Keep the number/text `isNumber` distinction, number JSON round-trip, and missing-type backward compatibility. Delete direct `props` and isolated `copyWith` checks because parser reconciliation and equality/round-trip tests protect the externally used semantics.

- [x] **Step 5: Remove the superseded microfiles and format the domain batch**

  Run:

  ```powershell
  dart format test/features/settings/domain/models/settings_value_objects_test.dart test/features/settings/domain/models/prompt_models_test.dart test/features/settings/domain/models/llm_configs_test.dart test/features/settings/domain/models/template_prompt_test.dart
  dart format --output=none --set-exit-if-changed test/features/settings/domain/models/settings_value_objects_test.dart test/features/settings/domain/models/prompt_models_test.dart test/features/settings/domain/models/llm_configs_test.dart test/features/settings/domain/models/template_prompt_test.dart
  ```

- [x] **Step 6: Verify the domain batch**

  ```powershell
  $Log = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup\task1-domain.log'
  flutter test test/features/settings/domain --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

  Expected: exit 0; no deleted filename remains imported or discovered.

---

### Task 2: Consolidate Persisted Settings Controllers and Repositories

**Files:**
- Create: `test/features/settings/application/persisted_settings_controllers_test.dart`
- Create: `test/features/settings/data/shared_preferences_repositories_test.dart`
- Delete: `test/features/settings/auto_retry_settings_controller_test.dart`
- Delete: `test/features/settings/application/custom_headers_controller_test.dart`
- Delete: `test/features/settings/application/font_size_settings_controller_test.dart`
- Delete: `test/features/settings/application/output_processing_settings_controller_test.dart`
- Delete: `test/features/settings/data/chat_defaults_repository_test.dart`
- Delete: `test/features/settings/data/llm_model_config_repository_test.dart`

**Interfaces:**
- Consumes: `settingsKeyValueStoreProvider`, SharedPreferences-backed Providers, durable controller `save`/CRUD operations, `ChatDefaultsRepository`, and `LlmModelConfigRepository`.
- Produces: one controller entry file and one SharedPreferences repository entry file with shared rejecting-store infrastructure and no duplicate save/rebuild scenarios.

- [x] **Step 1: Create a shared rejecting store and controller boot helpers**

  In `persisted_settings_controllers_test.dart`, define one `_RejectingSettingsKeyValueStore` implementing both string and integer writes as `false`. Keep each controller group responsible for its own ProviderContainer and dispose it with `addTearDown` or `tearDown`; do not share mutable state across tests.

- [x] **Step 2: Merge Custom Headers controller duplicates**

  Replace the separate single-add, multiple-add, stored-load, and save/rebuild cases with one durable two-header scenario that asserts current order and a rebuilt container's exact `toHeaderMap()`. Retain empty fallback, corrupt-data fallback, valid remove/update, negative/high index no-op tables, and rejected-write rollback.

- [x] **Step 3: Merge scalar controller save/restore cases**

  For Font Size and Output Processing, use one durable-save scenario per controller that asserts immediate state and state from a rebuilt container. Retain missing-data default, corrupted-data fallback, Font Size `updateLocal` non-persistence, and rejected-write rollback. For Auto Retry, merge the two old-JSON default tests because they use the same input, and replace raw JSON substring assertions with a rebuilt-container equality assertion after save.

- [x] **Step 4: Create `shared_preferences_repositories_test.dart`**

  Keep Chat Defaults empty/default, full round-trip, and non-map fallback. Keep LLM provider/model round-trip and rejected-write propagation. Combine missing and empty-string LLM storage fallbacks into one named input table rather than two registered tests.

- [x] **Step 5: Remove superseded files, format, and verify**

  ```powershell
  dart format test/features/settings/application/persisted_settings_controllers_test.dart test/features/settings/data/shared_preferences_repositories_test.dart
  dart format --output=none --set-exit-if-changed test/features/settings/application/persisted_settings_controllers_test.dart test/features/settings/data/shared_preferences_repositories_test.dart
  $Log = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup\task2-persistence.log'
  flutter test test/features/settings/application/persisted_settings_controllers_test.dart test/features/settings/data/shared_preferences_repositories_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

---

### Task 3: Remove Protocol Multiplication and Import/Deduplication Repetition

**Files:**
- Modify: `test/features/settings/data/model_list_client_test.dart`
- Modify: `test/features/settings/application/llm_model_configs_controller_test.dart`
- Modify: `test/features/settings/application/settings_sync_facade_test.dart`
- Modify: `test/features/settings/application/settings_import_deduplicator_test.dart`

**Interfaces:**
- Consumes: protocol-specific authentication Header switch, protocol-independent OpenAI-list parsing/error handling, provider merge/deduplication, sync facade export/import, import comparators, and scalar configuration deduplication.
- Produces: the same protocol and import decision branches without running common parsing eight times for every protocol or retesting `SettingsExportCodec` from a facade file.

- [x] **Step 1: Run protocol-independent `ModelListClient` cases once**

  Remove the outer `for (final protocol in LlmApiProtocol.values)` around parsed list, empty/missing data, HTTP error, invalid JSON, client exception, invalid URL, and truncation tests. Run these with `LlmApiProtocol.chatCompletions`; the production method branches on protocol only while building authentication Headers. Preserve the two Bearer protocols as a named auth table, the Anthropic Header case, and the custom-Header wire/logger override case.

- [x] **Step 2: Delete controller cases strictly subsumed by stronger durable cases**

  Remove `build() returns stored providers from SharedPreferences` because `upsertProvider() adds a new provider` already asserts current state and a fresh container. Remove `upsertModels() persists changes` because `upsertModels() adds multiple models to existing provider` already asserts the same durable result. Keep all distinct add/update/sort/merge/normalize/protocol/no-op/dedup branches.

- [x] **Step 3: Remove misplaced codec duplication from `settings_sync_facade_test.dart`**

  Delete the complete `Sync snapshot 版本化 codec` group and its now-unused codec imports/helper. `settings_export_codec_test.dart` already protects current round-trip, v5/v6 migrations, unsupported versions, and malformed input at the correct domain layer. Retain the two facade tests that exercise Riverpod export selection and deduplicate-then-import wiring.

- [x] **Step 4: Parameterize import comparators and scalar configurations**

  In `settings_import_deduplicator_test.dart`, replace separate comparator tests with one named case table per comparator: equivalent, length mismatch, and each field mismatch still execute with a reason label. Replace absent/equal/different Auto Retry, Custom Headers, and Font Size repetitions with named scalar-category cases that call `deduplicate` and project the corresponding result field. Keep the remote-empty Custom Headers rule, the all-equal `hasContent == false` aggregate, the mixed scenario, and every provider identity/protocol/URL/query/model branch.

- [x] **Step 5: Format and verify the protocol/import batch**

  ```powershell
  dart format test/features/settings/data/model_list_client_test.dart test/features/settings/application/llm_model_configs_controller_test.dart test/features/settings/application/settings_sync_facade_test.dart test/features/settings/application/settings_import_deduplicator_test.dart
  dart format --output=none --set-exit-if-changed test/features/settings/data/model_list_client_test.dart test/features/settings/application/llm_model_configs_controller_test.dart test/features/settings/application/settings_sync_facade_test.dart test/features/settings/application/settings_import_deduplicator_test.dart
  $Log = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup\task3-import.log'
  flutter test test/features/settings/data/model_list_client_test.dart test/features/settings/application/llm_model_configs_controller_test.dart test/features/settings/application/settings_sync_facade_test.dart test/features/settings/application/settings_import_deduplicator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

---

### Task 4: Rewrite Fragile and Duplicate Presentation Tests

**Files:**
- Modify: `test/features/settings/presentation/model_provider_form_dialog_test.dart`
- Modify: `test/features/settings/presentation/model_config_form_dialog_test.dart`
- Modify: `test/features/settings/presentation/output_processing_tab_test.dart`
- Modify: `test/features/settings/presentation/import_confirm_dialog_test.dart`

**Interfaces:**
- Consumes: visible form labels, callbacks, Provider state, persisted controller outcomes, dialog titles/lifecycle, controlled catalog Futures, and Material interactions.
- Produces: component tests that assert observable behavior rather than `FilledButton.onPressed`, `CircularProgressIndicator`, or dialog widget-class presence.

- [x] **Step 1: Merge Model Provider edit inheritance cases**

  Keep the default Chat Completions full submission. Run explicit selection only for the two non-default protocols because selecting the already-default Chat value adds no branch. Merge the two edit tests into one Responses edit case that asserts the visible initial protocol and submitted unchanged protocol/name.

- [x] **Step 2: Replace Model Config implementation assertions**

  Delete `shows fetch section when switching to fetch mode`, which every fetch test strictly subsumes. In the loading test, assert only visible loading copy and remove the spinner-type assertion. Merge disabled-button, enabled-button, and batch callback tests into one bounded scenario: before selection, tapping the visible submit action must not call `onBatchAdd`; after selecting `gpt-4o`, tapping the same action must submit exactly that model. Keep manual mode/edit mode, protocol propagation, error, results, existing-model marker, and fetch-state preservation.

- [x] **Step 3: Make Output Processing tests observe state changes**

  Merge dialog-open into empty-pattern validation while retaining the visible dialog title. Merge edit-open into edit-submit. Merge delete-confirmation into confirmed deletion. Rewrite the Switch test to assert the Provider rule's `enabled` value becomes false. Rewrite move-down to assert Provider rule title order becomes `['规则B', '规则A']`; visible presence alone does not prove ordering. Keep empty/nonempty rendering, invalid-regex validation, valid add, and cancel-delete behavior.

- [x] **Step 4: Merge full import coverage and remove stale implementation comments**

  Combine the main import and Auto Retry import tests into one full-data scenario asserting all list categories plus `autoRetrySettingsProvider`. Delete the obsolete comment claiming the deduplicator drops Auto Retry. Replace `find.byType(ImportConfirmDialog)` lifecycle checks with visible `检测到配置导入数据` and action/error text. Keep cancel and failed-import retryability as separate decision branches.

- [x] **Step 5: Format and verify presentation tests**

  ```powershell
  dart format test/features/settings/presentation/model_provider_form_dialog_test.dart test/features/settings/presentation/model_config_form_dialog_test.dart test/features/settings/presentation/output_processing_tab_test.dart test/features/settings/presentation/import_confirm_dialog_test.dart
  dart format --output=none --set-exit-if-changed test/features/settings/presentation/model_provider_form_dialog_test.dart test/features/settings/presentation/model_config_form_dialog_test.dart test/features/settings/presentation/output_processing_tab_test.dart test/features/settings/presentation/import_confirm_dialog_test.dart
  $Log = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup\task4-presentation.log'
  flutter test test/features/settings/presentation --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

---

### Task 5: Seed SettingsScreen State and Strengthen Ordering Assertions

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_responsive_cases.dart`

**Interfaces:**
- Consumes: `TestFixtures.seedPreferences`, SQLite prompt repositories, existing `pumpSettingsScreen`, visible action labels, and persisted entity order.
- Produces: focused edit/delete widget tests that do not replay creation setup, and insertion tests that prove stored order rather than mere widget presence.

- [x] **Step 1: Extend `setUpSettingsScreen` with typed seed inputs**

  Add optional lists for resolved LLM models, preset prompts, fixed sequences, template prompts, and memory prompts. Feed models/presets/sequences through `TestFixtures.seedPreferences`; save template and memory prompts through their production SQLite repositories before pumping. Preserve `useDefaultsSeed` for existing callers and reject combining it with explicit equivalent lists using an assertion.

- [x] **Step 2: Seed provider/model edit and delete tests**

  Add a test-only resolved model fixture with explicit provider ID/name/API fields. Update protocol-edit, name-edit, and delete tests to start from this seed rather than opening create-provider/create-model dialogs first. Fold the default protocol-card assertion into `creates a provider and verifies persistence`, then delete `shows protocol name in provider list`. Keep selected-protocol creation, model creation, provider/model edits, provider/model deletion, and collapsed-list expansion as distinct UI wiring branches.

- [x] **Step 3: Seed prompt edit/delete cases through repositories**

  Update preset, template, memory, and fixed-sequence edit/delete tests to start with one typed seed. Creation tests continue to exercise their respective dialogs. This removes unrelated creation animation/setup from edit/delete failure paths and shortens execution without merging independent CRUD branches.

- [x] **Step 4: Replace weak preset insertion tests with one persisted-order contract**

  Merge `inserts a new item below the selected item` and `inserts items and keeps them ordered`. Build before/after items, select the first item, insert a middle item, save, and assert `presetPromptRepository.loadAll(database).single.messages.map((m) => m.title)` equals the exact expected order. Do not use widget coordinates or list-child indices.

- [x] **Step 5: Strengthen fixed-sequence insertion**

  After inserting the new step below the selected step, give it observable content, save, and assert the repository's step-title order exactly. Remove the `DecoratedBox`, `Card`, `SettingsScreen`, and `ListView` implementation finders made unnecessary by seeded single-entity setup and persisted-order assertions.

- [x] **Step 6: Remove duplicate responsive variants**

  Run the six-tab heading reachability matrix only at 390px; 600px follows the same compact shell/card branch and already has a dedicated compact preset-form reachability test. Keep one wide provider-page smoke at 1024px and delete the identical 1440px smoke because neither test asserts the dynamic card-column count. Preserve the 390px provider form and 600px preset form cases.

- [x] **Step 7: Format and verify the SettingsScreen entry file**

  ```powershell
  dart format test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart
  dart format --output=none --set-exit-if-changed test/features/settings/settings_screen/settings_screen_test_helpers.dart test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart test/features/settings/settings_screen/settings_screen_responsive_cases.dart
  $Log = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup\task5-screen.log'
  flutter test test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 $Log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 $Log
  if ($E -ne 0) { exit $E }
  ```

---

### Task 6: Recount, Compare Coverage, and Run Repository Gates

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: `%TEMP%\oh-my-llm-settings-test-cleanup\baseline-lcov.info`, the baseline logs, and the modified Settings tests.
- Produces: after-LCOV, line-level hit-to-miss classification, timing evidence, analyzer/gate evidence, full-suite evidence, and final scope audit.

- [x] **Step 1: Audit remaining test smells and inventory**

  Recount Dart files, static declarations, and executed cases. Search `test/features/settings` with `rg --pcre2` for `Future(?:<[^>]+>)?\.delayed`, `pumpAndSettle`, `find.byKey`, `getTopLeft`, `getRect`, `\.props`, `tester.widget`, and stale review/defect comments. Investigate every remaining match rather than enforcing a blind zero count for legitimate Material-control interaction.

- [x] **Step 2: Run the Settings directory twice and capture warm timing**

  ```powershell
  $Dir = Join-Path $env:TEMP 'oh-my-llm-settings-test-cleanup'
  1..2 | ForEach-Object {
    $Run = $_
    $Elapsed = Measure-Command {
      flutter test test/features/settings --reporter compact 2>&1 |
        Out-File -Encoding utf8 (Join-Path $Dir "after-run-$Run.log")
      $script:ExitCode = $LASTEXITCODE
    }
    Write-Host "RUN=$Run EXIT=$script:ExitCode ELAPSED_SECONDS=$([math]::Round($Elapsed.TotalSeconds, 2))"
    if ($script:ExitCode -ne 0) {
      Get-Content -Tail 150 (Join-Path $Dir "after-run-$Run.log")
      exit $script:ExitCode
    }
  }
  ```

- [x] **Step 3: Generate and compare coverage**

  Run the Settings directory with `--coverage-path` set to `%TEMP%\oh-my-llm-settings-test-cleanup\after-lcov.info`. Compare `DA` records for `lib/features/settings` with the baseline. List every hit-to-miss line and classify it as implementation-only/incidental or restore a meaningful behavior test for any lost contract.

- [x] **Step 4: Run static and architecture gates**

  ```powershell
  dart run tool/check_import_boundaries.dart
  flutter analyze --no-pub
  git diff --check
  ```

  Expected: zero import-boundary violations, no analyzer issues, and no diff-check output.

- [x] **Step 5: Run the full suite exactly as required**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
  $E = $LASTEXITCODE
  Write-Host "EXIT=$E"
  Get-Content -Tail 150 fltest.log
  if ($E -ne 0) { exit $E }
  ```

- [x] **Step 6: Perform the final scope and disposition audit**

  Confirm `git status --short` contains only the two approved documentation files and paths under `test/features/settings`. Prepare the final deletion/merge/rewrite/retention report with before/after files, cases, warm timing, Settings coverage, line-loss classification, and every verification result. Do not stage or commit.
