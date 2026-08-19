### Task 8: Replace the four-category Sync UI with dynamic catalog groups

**Files:**
- Modify: `lib/features/sync/application/sync_client_controller.dart`
- Modify: `lib/features/sync/domain/models/protocol/sync_types.dart`
- Modify: `lib/features/sync/presentation/widgets/sync_operation_tab.dart`
- Modify: `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`
- Modify: `test/features/sync/application/sync_test_fakes.dart`
- Modify: `test/features/sync/application/sync_client_controller_test.dart`
- Modify: `test/features/sync/application/sync_client_controller_execute_test.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_test_helpers.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart`
- Modify if assertions are affected: `test/app/composition/sync_workspace_screen_test.dart`

**Final controller state:**

```dart
final List<SettingsSyncGroupDescriptor> availableGroups;
final Set<SettingsSyncGroupId> selectedGroups;
final SettingsSyncPreparedImport? preparedImport;
```

`build()` reads facade descriptors and stores an immutable ordered list. `toggleGroup(id)` only accepts an available ID. `selectAllGroups()` copies every descriptor ID. Any selection change clears request-time sensitive confirmation, prepared import and transient errors. Remove `SyncCategory`, its sensitivity extension, `selectedCategories`, `toggleCategory`, `selectAllCategories` and all category-to-group mapping.

`SyncOperationTab` iterates `state.availableGroups`; label sensitivity comes from descriptor, not a static enum. “全选” compares selected IDs with descriptor IDs. Request-time warning appears if any selected descriptor is credential-bearing. The import dialog uses `TransferSummaryList`, never inspects Settings payload/domain types, and reacts to port results:

- sensitive confirmation required: keep open and re-enable checkbox;
- stale: replace summaries through updated controller state, reset checkbox, show reconfirm message;
- partial failure: keep open with explicit partial message and safe labels;
- success: close true;
- failure/already-consumed: keep open or close only according to explicit result, never report success.

- [ ] **Step 1: Add dynamic group/controller red tests**

Configure a fake facade with six descriptors plus one test-only descriptor. Assert build preserves descriptor order, select-all includes all seven without code changes, toggle works by stable ID, and sensitivity is computed from descriptors. Assert removing/changing selection clears confirmation/prepared state.

- [ ] **Step 2: Add Sync Widget red cases**

Verify all six production labels render (`服务商`, `预设`, `提示词`, `网络`, `输出处理`, `其它`), fake seventh descriptor renders through the same loop, all-select selects the exact list, only credential descriptors show the warning suffix, and the dialog summary renders replacement/clear rows from port DTOs without importing Settings concrete models.

- [ ] **Step 3: Run dynamic UI tests for red**

```powershell
flutter test test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/app/composition/sync_workspace_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-dynamic-groups-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/settings-sync-dynamic-groups-red.log
if ($TestExit -eq 0) { throw '预期 Sync UI 仍是四分类，red 却通过' }
```

- [ ] **Step 4: Replace controller category adapter with descriptor IDs**

The exact requested set is captured before the async call and passed unchanged to both protocol and incoming preparation. Equatable props sort by `id.value`, not object identity. Unknown toggle IDs are ignored or rejected consistently and covered by the new test.

- [ ] **Step 5: Make operation tab and import dialog fully data-driven**

Remove all concrete Settings model imports and count branches from Sync presentation. Map `SettingsSyncSummaryItem` to `TransferSummaryViewItem` in one expression. Keep existing PopScope/busy behavior and observable animation helpers.

- [ ] **Step 6: Prove legacy category adapter is gone**

```powershell
rg -n "SyncCategory|selectedCategories|toggleCategory|selectAllCategories" lib/features/sync test/features/sync test/app/composition
```

Expected: zero hits. If a historical test title alone remains, rename it to the final group vocabulary in the same task.

- [ ] **Step 7: Run dynamic UI/controller green suite**

```powershell
flutter test test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/app/composition/sync_workspace_screen_test.dart test/features/settings/application/transfer/settings_sync_facade_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-dynamic-groups-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/settings-sync-dynamic-groups-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 8: Format, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/features/sync/application/sync_client_controller.dart',
  'lib/features/sync/domain/models/protocol/sync_types.dart',
  'lib/features/sync/presentation/widgets/sync_operation_tab.dart',
  'lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart',
  'test/features/sync/application/sync_test_fakes.dart',
  'test/features/sync/application/sync_client_controller_test.dart',
  'test/features/sync/application/sync_client_controller_execute_test.dart',
  'test/app/composition/sync_workspace_screen/sync_workspace_screen_test_helpers.dart',
  'test/app/composition/sync_workspace_screen/sync_workspace_screen_render_cases.dart',
  'test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart',
  'test/app/composition/sync_workspace_screen_test.dart'
)
$TransferFiles = $TransferFiles | Where-Object { Test-Path $_ }
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(sync): 按注册表动态生成设置同步项"
```

---

