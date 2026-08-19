### Task 3: Implement registry-driven export, prepare, revalidation and execution

**Files:**
- Create: `lib/features/settings/application/transfer/settings_transfer_coordinator.dart`
- Create: `test/features/settings/application/transfer/settings_transfer_coordinator_test.dart`
- Modify if the test exposes a missing invariant: the three Task 2 application files only

**Coordinator API:**

`SettingsTransferCoordinator` has a const constructor taking the catalog and exposes exactly four operations: `exportGroups(Set<SettingsTransferGroup>)`, generic `exportValue<T>(SettingsTransferParticipant<T>, T)`, `prepareJson(String?, {Set<SettingsTransferGroup>? allowedGroups})`, and `prepareDocument(SettingsTransferDocument, {Set<SettingsTransferGroup>? allowedGroups})`. The two export methods return `SettingsExportPreparation`; the two prepare methods return `SettingsImportPreparation`.

`SettingsExportPreparation` is either no-content or a `SettingsExportBatch`. The batch contains document/summaries/sensitivity and exposes `SettingsExportExposureResult exposeJson({required bool confirmedSensitive})`; sensitive false returns `SettingsExportSensitiveConfirmationRequired` without text, while standard export succeeds with false.

`SettingsImportPreparation` is sealed into malformed, unsupported version, unknown section, section outside allowed groups, invalid participant payload, no changes, and ready batch. Errors contain safe code/label only, never payload text.

`SettingsImportBatch` owns immutable prepared changes and a coordinator reference, not a closure. Its `execute({required bool confirmedSensitive})` returns:

```dart
sealed class SettingsImportExecutionResult {
  const SettingsImportExecutionResult();
}
final class SettingsImportSuccess extends SettingsImportExecutionResult {
  const SettingsImportSuccess();
}
final class SettingsImportSensitiveConfirmationRequired
    extends SettingsImportExecutionResult {
  const SettingsImportSensitiveConfirmationRequired();
}
final class SettingsImportStalePreview extends SettingsImportExecutionResult {
  const SettingsImportStalePreview(this.refreshedBatch);
  final SettingsImportBatch refreshedBatch;
}
final class SettingsImportFailure extends SettingsImportExecutionResult {
  const SettingsImportFailure({
    required this.failedLabel,
    required this.safeReason,
  });
  final String failedLabel;
  final String safeReason;
}
final class SettingsImportPartialFailure extends SettingsImportExecutionResult {
  const SettingsImportPartialFailure({
    required this.completed,
    required this.failedLabel,
    required this.notAttempted,
    required this.safeReason,
  });
  final List<SettingsTransferSummaryItem> completed;
  final String failedLabel;
  final List<SettingsTransferSummaryItem> notAttempted;
  final String safeReason;
}
final class SettingsImportAlreadyConsumed extends SettingsImportExecutionResult {
  const SettingsImportAlreadyConsumed();
}
```

Missing sensitive confirmation does not consume the batch, because no execution was successfully initiated. Every accepted execution attempt consumes it once. The coordinator serializes accepted attempts with one Future chain. After acquiring the lock it re-runs each participant's prepare against current local state; any fingerprint/action/count change returns `stalePreview` and zero writes with a new batch. Otherwise boxes apply changes in catalog order and report exact partial progress.

- [ ] **Step 1: Write fake-participant coordinator tests first**

Use a test-only catalog and `Completer`-controlled writers. Cover:

- one group, multiple groups, and typed single-value export;
- empty merge participants omitted, empty replace participant retained;
- sensitive export cannot expose JSON until confirmation;
- JSON import is global and routes all known sections without a Tab argument;
- unknown key or one invalid payload rejects the whole document before writes;
- `allowedGroups` rejects a known but unrequested section before participant decode/write;
- prepare performs zero writes; identical local state returns no changes;
- sensitive batch false returns confirmation-required and can later execute true;
- changed local state that changes summary/fingerprint returns stale with zero writes;
- irrelevant local replacement that reproduces the same fingerprint may continue;
- two separately prepared batches started together never overlap writer critical sections;
- failure on first change returns failure; failure after one success returns partial failure with completed/failed/not-attempted summaries;
- repeated successful execute returns already-consumed;
- adding one fake participant requires no coordinator branch and automatically enters group export, prepare summary and execute.

- [ ] **Step 2: Run coordinator tests for red**

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-coordinator-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-coordinator-red.log
if ($TestExit -eq 0) { throw '预期 coordinator/batch 尚不存在，red 却通过' }
```

- [ ] **Step 3: Implement export and decode/prepare paths**

Export iterates catalog boxes once, evaluates `readLocal()` then `shouldExport()`, and constructs sections in catalog order. Import first completes top-level decode, key lookup and every participant decode; it only starts prepare after all sections decode successfully. `allowedGroups` is nullable so Clipboard never accidentally inherits the Sync subset rule.

- [ ] **Step 4: Implement one-shot batch, revalidate and serial execution**

Use a coordinator-owned Future tail; every accepted execution awaits the previous tail and completes its own gate in `finally`. Do not use timers. Convert thrown errors to `safeReason` by a fixed application message such as `写入未完成，请检查本地存储后重试`; never include `error.toString()` because repository exceptions can eventually carry sensitive values.

- [ ] **Step 5: Run coordinator and document/catalog regression tests**

```powershell
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart test/features/settings/application/transfer/settings_transfer_catalog_test.dart test/features/settings/application/transfer/settings_transfer_coordinator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-coordinator-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-coordinator-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 6: Format, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/application/transfer/settings_transfer_types.dart',
  'lib/features/settings/application/transfer/settings_transfer_participant.dart',
  'lib/features/settings/application/transfer/settings_transfer_catalog.dart',
  'lib/features/settings/application/transfer/settings_transfer_coordinator.dart',
  'test/features/settings/application/transfer/settings_transfer_catalog_test.dart',
  'test/features/settings/application/transfer/settings_transfer_coordinator_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 统一设置传输编排与执行"
```

---

