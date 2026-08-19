### Task 9: Retire the legacy field aggregate and prove end-to-end composition

**Files:**
- Delete: `lib/features/settings/domain/models/transfer/settings_export_data.dart`
- Delete: `lib/features/settings/domain/models/transfer/settings_export_codec.dart`
- Delete: `lib/features/settings/application/transfer/settings_transfer_workflow.dart`
- Delete: `lib/features/settings/application/transfer/settings_import_deduplicator.dart`
- Delete: `lib/features/settings/application/transfer/settings_import_executor.dart`
- Delete: `test/features/settings/domain/models/transfer/settings_export_data_test.dart`
- Delete: `test/features/settings/domain/models/transfer/settings_export_codec_test.dart`
- Delete: `test/features/settings/application/transfer/settings_transfer_workflow_test.dart`
- Delete: `test/features/settings/application/transfer/settings_import_deduplicator_test.dart`
- Delete: `test/features/settings/application/transfer/settings_import_executor_test.dart`
- Modify: `test/integration/sync_e2e_integration_test.dart`
- Modify: `test/integration/sync_multi_category_integration_test.dart`

**Integration contracts:**

1. real Provider composition exports/imports at least one SQLite merge participant (`memoryPrompts`) and one SharedPreferences replace participant (`customHeaders` or `autoRetrySettings`);
2. loopback Sync v4 pairs, requests stable group IDs, receives a structured v9 document and prepares/imports it;
3. sensitive group false is rejected by server, true exports, and import execution still requires its own true;
4. client asking for prompts rejects a response that injects providers before any write;
5. a successful retry after an injected participant failure sees prior successful changes as no-op and completes only remaining changes;
6. local-only media density, media root, Settings Tab and `ChatDefaults` never appear in sections or group descriptors.

- [ ] **Step 1: Update integration tests to final v4/v9 vocabulary before deletion**

Rename existing v3 test titles to v4, replace category requests with `SettingsSyncGroupId`, replace `SettingsExportData` assertions with `SettingsTransferDocument`, and make fake facade implement descriptors/export/prepare. Add the cross-store composition case using real app providers and deterministic in-memory DB/SharedPreferences.

- [ ] **Step 2: Record the cleanup red and verify the new integration baseline**

```powershell
$LegacyHits = @(rg -n "SettingsExportData|SettingsExportCodec|SettingsTransferWorkflow|SettingsImportDeduplicator|SettingsImportExecutor" lib test)
$LegacyHits | Out-File -Encoding utf8 logs/settings-transfer-legacy-red.log
if ($LegacyHits.Count -eq 0) { throw '删除前应能观察到旧设置传输事实源' }

dart format test/integration/sync_e2e_integration_test.dart test/integration/sync_multi_category_integration_test.dart
flutter test test/integration/sync_e2e_integration_test.dart test/integration/sync_multi_category_integration_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-integration-before-cleanup.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/settings-transfer-integration-before-cleanup.log
if ($TestExit -ne 0) { exit $TestExit }
```

The grep hits are the cleanup red: the old path still exists. The new v4/v9 integrations must already be green before deleting dead code; do not manufacture a test failure for a pure retirement step.

- [ ] **Step 3: Remove legacy production and test files**

Use `apply_patch` deletions. Do not leave deprecated aliases or a v8 fallback. After deletion, resolve only real remaining imports; do not recreate compatibility wrappers.

- [ ] **Step 4: Run zero-hit legacy and boundary audits**

```powershell
$LegacyHits = @(rg -n "SettingsExportData|SettingsExportCodec|SettingsTransferWorkflow|SettingsImportDeduplicator|SettingsImportExecutor|SyncCategory|SettingsSyncSelection" lib test)
if ($LegacyHits.Count -gt 0) { $LegacyHits; throw '仍存在旧设置传输事实源' }
$ClipboardBoundaryHits = @(rg -n "Clipboard" lib/features/settings/domain lib/features/settings/application lib/features/sync)
if ($ClipboardBoundaryHits.Count -gt 0) { $ClipboardBoundaryHits; throw 'Clipboard 越过 presentation 边界' }
$SyncConcreteSettingsHits = @(rg -n "llmProviderConfigsProvider|presetPromptsProvider|memoryPromptsProvider|templatePromptsProvider|fixedPromptSequencesProvider|customHeadersProvider|outputProcessingSettingsProvider|fontSizeSettingsProvider|autoRetrySettingsProvider" lib/features/sync)
if ($SyncConcreteSettingsHits.Count -gt 0) { $SyncConcreteSettingsHits; throw 'Sync 直接依赖具体 Settings controller' }
$BoxHits = @(rg -n "SettingsTransferParticipantBox|ErasedSettingsTransferParticipant" lib)
$UnexpectedBoxHits = @($BoxHits | Where-Object { $_ -notmatch '^lib[\\/]features[\\/]settings[\\/]application[\\/]transfer[\\/]' })
if ($UnexpectedBoxHits.Count -gt 0) { $UnexpectedBoxHits; throw '类型擦除实现泄漏到 Settings transfer application 之外' }
```

Expected: legacy hits, Clipboard boundary hits, concrete Settings imports under Sync, and unexpected box hits are all empty. Legitimate box hits remain confined to Settings transfer application. The production catalog is the only registration list containing all nine participants.

- [ ] **Step 5: Run final focused transfer/Sync suite**

```powershell
flutter test test/features/settings/domain/models/transfer test/features/settings/application/transfer test/features/settings/presentation/settings_screen_test.dart test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart test/features/sync/domain/models/protocol test/features/sync/application test/app/composition/sync_workspace_screen_test.dart test/integration/sync_e2e_integration_test.dart test/integration/sync_multi_category_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-focused-final.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 200 logs/settings-transfer-focused-final.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 6: Run static gates serially**

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-analyze.log
$AnalyzeExit = $LASTEXITCODE
Write-Host "ANALYZE_EXIT=$AnalyzeExit"
Get-Content -Tail 150 logs/settings-transfer-analyze.log
if ($AnalyzeExit -ne 0) { exit $AnalyzeExit }

dart run tool/check_import_boundaries.dart 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-import-boundaries.log
$BoundaryExit = $LASTEXITCODE
Write-Host "BOUNDARY_EXIT=$BoundaryExit"
Get-Content -Tail 150 logs/settings-transfer-import-boundaries.log
if ($BoundaryExit -ne 0) { exit $BoundaryExit }
```

If analysis stalls after dependency resolution, terminate only that run, execute `flutter analyze --no-pub` once to the same log path, and report the retry accurately.

- [ ] **Step 7: Run the full suite with mandatory redirection**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 logs/fltest.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/fltest.log
if ($TestExit -ne 0) { exit $TestExit }
```

Expected: `EXIT=0`. On failure, use `Select-String -Pattern " -[1-9]" -Path logs/fltest.log` and focused reruns; do not rerun blindly.

- [ ] **Step 8: Format all remaining changed Dart files and verify staged scope**

```powershell
$TransferFiles = @(
  'test/integration/sync_e2e_integration_test.dart',
  'test/integration/sync_multi_category_integration_test.dart'
)
dart format $TransferFiles
$LegacyAndIntegrationFiles = @(
  'lib/features/settings/domain/models/transfer/settings_export_data.dart',
  'lib/features/settings/domain/models/transfer/settings_export_codec.dart',
  'lib/features/settings/application/transfer/settings_transfer_workflow.dart',
  'lib/features/settings/application/transfer/settings_import_deduplicator.dart',
  'lib/features/settings/application/transfer/settings_import_executor.dart',
  'test/features/settings/domain/models/transfer/settings_export_data_test.dart',
  'test/features/settings/domain/models/transfer/settings_export_codec_test.dart',
  'test/features/settings/application/transfer/settings_transfer_workflow_test.dart',
  'test/features/settings/application/transfer/settings_import_deduplicator_test.dart',
  'test/features/settings/application/transfer/settings_import_executor_test.dart',
  'test/integration/sync_e2e_integration_test.dart',
  'test/integration/sync_multi_category_integration_test.dart'
)
git add -A -- $LegacyAndIntegrationFiles
$StagedDartFiles = @(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
if ($StagedDartFiles.Count -gt 0) {
  dart format --output=none --set-exit-if-changed $StagedDartFiles
}
git diff --cached --check
git diff --cached --name-status
git diff --name-only
```

The task-owned path array is explicit so unrelated files are not staged. Expected unstaged output is empty unless it lists documented unrelated user files.

- [ ] **Step 9: Commit legacy retirement and integration coverage**

```powershell
git commit -m "refactor(settings): 移除旧设置传输链路"
git show -s --format='%H%n%s' HEAD
git diff-tree --no-commit-id --name-status -r HEAD
git show HEAD:pubspec.yaml | Select-String '^version:'
git status --short
```

The post-commit hook amends `pubspec.yaml`; report the final hash printed by `git show`, not the pre-hook hash from the initial commit line.

---

## Final Acceptance Checklist

- [ ] Production catalog contains exactly nine registrations and six ordered group descriptors.
- [ ] Adding a fake participant to a test catalog automatically reaches group export, Clipboard-style prepare/summary, Sync facade export/prepare and execute without editing those consumers.
- [ ] No production Clipboard/Sync/summary code enumerates the nine concrete setting fields.
- [ ] Settings current Tab controls export only; Clipboard import recognizes a valid cross-group document globally.
- [ ] Single-preset copy is a standard v9 document and uses the preset participant.
- [ ] Merge collections omit empty sections; replace participants preserve empty clear commands.
- [ ] Sensitive Clipboard export returns no text without application confirmation and performs zero Clipboard writes on cancel.
- [ ] Sensitive Clipboard and Sync imports perform zero writes without application-boundary confirmation.
- [ ] API keys/Header values never appear in summaries, dialog text, error strings or logs.
- [ ] Prepare is write-free; stale preview is write-free; accepted execution is one-shot and serialized.
- [ ] Provider import state changes only after persistence ACK.
- [ ] Partial failure accurately identifies completed, failed and not-attempted safe summaries; retry is idempotent.
- [ ] Sync v4 uses stable group IDs and a structured v9 document with no secondary JSON string.
- [ ] Server independently rejects unknown/sensitive-unconfirmed groups; client rejects unrequested sections.
- [ ] v3/v8 and all future versions are explicitly rejected.
- [ ] Local-only settings do not appear in catalog, document or Sync descriptors.
- [ ] Legacy symbols and files have zero production/test hits.
- [ ] `flutter analyze`, import-boundary gate and full tests all have fresh `EXIT=0` evidence in `logs/`.
- [ ] Final `git status --short` contains no task-owned residue; no push/PR/build/device claim is made.

## Stop Conditions

Stop the current task and return to design/plan review if any of these occurs:

- a participant cannot expose synchronous already-loaded state without adding async first-load behavior;
- raw section maps would need to escape into a controller, Settings presentation or Sync presentation;
- a participant's absent/empty/merge/replace/clear semantics cannot be stated and tested unambiguously;
- the implementation needs a second production registration list for Clipboard or Sync;
- Sync v4 server cannot derive sensitivity from its local facade/catalog descriptors;
- a response subset check would have to trust remote metadata rather than local key-to-group mapping;
- provider or another participant cannot wait for persistence before publishing success state;
- UI would need to describe a cross-store failure as globally rolled back;
- a temporary v8/four-category adapter must survive beyond its named exit task;
- an import-boundary violation requires a broad allowlist;
- work expands into SQLite schema, unrelated controller refactors, code generation, reflection, a universal settings base class, release/push or device behavior.

## Implementation Handoff

Execute tasks in order. Each task ends with a focused green test and an independent Simplified-Chinese conventional commit. At every checkpoint, review the actual staged paths and hook-amended HEAD before starting the next task. Do not combine Tasks 6–8 merely to reduce commit count: their temporary dependency order is what keeps each migration boundary observable and gives the legacy adapter a bounded lifetime.
