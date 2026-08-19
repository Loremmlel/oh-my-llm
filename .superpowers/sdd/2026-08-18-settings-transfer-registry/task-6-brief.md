### Task 6: Migrate Clipboard export/import and single-preset sharing

**Files:**
- Create: `lib/core/widgets/transfer_summary_list.dart`
- Create: `test/features/settings/presentation/settings_screen/settings_screen_transfer_cases.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `lib/features/settings/presentation/widgets/transfer/import_confirm_dialog.dart`
- Modify: `test/features/settings/presentation/settings_screen_test.dart`
- Modify: `test/features/settings/presentation/settings_screen/settings_screen_test_helpers.dart`
- Modify: `test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart`
- Modify: `test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart`
- Keep legacy workflow/executor files temporarily because old Sync still consumes them until Task 7

**Shared view model:**

```dart
final class TransferSummaryViewItem {
  const TransferSummaryViewItem({
    required this.label,
    required this.trailingText,
  });
  final String label;
  final String trailingText;
}

final class TransferSummaryList extends StatelessWidget {
  const TransferSummaryList({required this.items, super.key});
  final List<TransferSummaryViewItem> items;
}
```

It renders layout only and imports no Settings/Sync types. Settings maps `SettingsTransferSummaryItem.label/trailingText`; Sync later maps its port DTO to the same widget.

**Settings screen flow changes:**

- replace `SettingsTransferTab` with a local constant index-to-`SettingsTransferGroup` mapping for the six existing tabs;
- rename import tooltip to `从剪贴板导入设置`; it has no current-tab label;
- export calls `coordinator.exportGroups({_currentTransferGroup})`;
- if export is sensitive, show a non-dismissible confirmation stating that API keys/Header values will enter the system clipboard and may be readable by other apps;
- only call `Clipboard.setData` after `exposeJson(confirmedSensitive: true/false)` returns success;
- import reads Clipboard once, calls `prepareJson(text)` without `allowedGroups`, then displays exact invalid/unsupported/unknown/no-change messages;
- ready import opens `ImportConfirmDialog(batch: batch)`; the dialog renders shared summaries and a sensitive checkbox, then passes that boolean into batch execute;
- stale result replaces the dialog's current batch, clears the checkbox and shows `本地设置已变化，请重新确认` without writing;
- partial failure keeps the dialog open and displays `部分配置已导入` plus safe completed/failed/not-attempted labels;
- full failure keeps the dialog open with the safe reason; success closes true;
- single preset looks up the typed preset participant from the production catalog, calls `exportValue(participant, [source])`, exposes standard JSON with false, then writes Clipboard.

- [ ] **Step 1: Add Clipboard/UI red cases and adapt test harness controls**

`pumpSettingsScreen` gains optional Clipboard text, a set-data recorder and `extraOverrides` so tests control observable platform calls. New cases must prove:

- importing a preset document while currently on providers succeeds without tab-mismatch UI;
- current tab still determines export group;
- provider export opens sensitive confirmation and cancel records zero `Clipboard.setData` calls;
- confirmed provider export records one v9 document whose sections contain only `modelProviders`;
- empty Header and output groups export explicit empty replacement sections;
- malformed, v8 and no-change documents show distinct messages;
- single preset copy contains only `sections.presetPrompts` and round-trips through v9 prepare;
- API key/Header value is absent from dialog text and snackbar text.

Rewrite the dialog test around `SettingsImportBatch` and fake participants rather than `SettingsImportTargets`.

- [ ] **Step 2: Run Settings presentation tests for red**

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-clipboard-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-clipboard-red.log
if ($TestExit -eq 0) { throw '预期 Settings UI 尚未切换 registry，red 却通过' }
```

- [ ] **Step 3: Implement shared summary list and batch-driven import dialog**

Use `PopScope(canPop: !isImporting)` as today. Await batch execution directly; use controlled result types instead of catch-and-stringify. A thrown unexpected error is converted to the fixed safe message `导入未完成，请重试` and the dialog remains open.

- [ ] **Step 4: Switch Settings screen export/import and preset share**

Keep `Clipboard.getData`/`setData` exclusively in `settings_screen.dart`. Remove all imports of `settings_export_data.dart`, legacy workflow and legacy executor from Settings presentation. Do not remove the old classes yet because Sync still compiles against them.

- [ ] **Step 5: Run Settings presentation and coordinator green tests**

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart test/features/settings/application/transfer/settings_transfer_coordinator_test.dart test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-clipboard-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-clipboard-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 6: Verify Clipboard and concrete-field boundaries**

```powershell
rg -n "Clipboard" lib/features/settings/domain lib/features/settings/application
rg -n "SettingsExportData|SettingsTransferWorkflow|SettingsImportExecutor" lib/features/settings/presentation
```

Expected: both commands return no production hits. Clipboard remains only in presentation; Settings presentation no longer knows the legacy field aggregate.

- [ ] **Step 7: Format, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/core/widgets/transfer_summary_list.dart',
  'lib/features/settings/presentation/settings_screen.dart',
  'lib/features/settings/presentation/widgets/transfer/import_confirm_dialog.dart',
  'test/features/settings/presentation/settings_screen_test.dart',
  'test/features/settings/presentation/settings_screen/settings_screen_test_helpers.dart',
  'test/features/settings/presentation/settings_screen/settings_screen_models_and_prompts_cases.dart',
  'test/features/settings/presentation/settings_screen/settings_screen_transfer_cases.dart',
  'test/features/settings/presentation/widgets/transfer/import_confirm_dialog_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 统一剪贴板设置传输入口"
```

---

