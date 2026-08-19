### Task 5: Register the four replacing participants and lock the production schema

**Files:**
- Create: `lib/features/settings/application/transfer/participants/preference_transfer_participants.dart`
- Create: `lib/features/settings/application/transfer/settings_transfer_catalog_provider.dart`
- Create: `test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart`
- Modify: `test/features/settings/application/transfer/settings_transfer_participants_test.dart`
- Modify only if a persistence failure is untested: `test/features/settings/application/preferences/persisted_settings_controllers_test.dart`

**Replacing participant table:**

| Key | Type | Group | Order | Sensitivity | Empty meaning |
| --- | --- | --- | --- | --- | --- |
| `customHeaders` | `CustomHeadersConfig` | network | 0 | credential | clear all headers |
| `outputProcessing` | `OutputProcessingSettings` | outputProcessing | 0 | standard | clear all rules |
| `fontSizeSettings` | `FontSizeSettings` | other | 0 | standard | not applicable; complete value required |
| `autoRetrySettings` | `AutoRetrySettings` | other | 1 | standard | not applicable; complete value required |

All four return `shouldExport == true` when their group is selected, including empty Header/output values. Their decoders require maps and delegate to current model `fromJson`; apply callbacks call existing `save` methods, which already await store ACK before state.

**Production providers:**

```dart
final settingsTransferCatalogProvider =
    Provider<SettingsTransferCatalog>(_buildSettingsTransferCatalog);

final settingsTransferCoordinatorProvider =
    Provider<SettingsTransferCoordinator>((ref) {
      return SettingsTransferCoordinator(
        catalog: ref.watch(settingsTransferCatalogProvider),
      );
    });
```

The catalog provider is the one and only production registration list. It passes synchronous `ref.read(xxxProvider)` readers and async notifier methods to participant constructors. Presentation and Sync must consume the coordinator/catalog providers and must not construct a second list.

**Schema snapshot test shape:**

```dart
const expectedFormatVersion = 9;
const expectedParticipantKeys = <String>[
  'modelProviders',
  'presetPrompts',
  'memoryPrompts',
  'templatePrompts',
  'fixedPromptSequences',
  'customHeaders',
  'outputProcessing',
  'fontSizeSettings',
  'autoRetrySettings',
];

const expectedCanonicalSections = <String, Object?>{
  // Each key has one complete, secret-safe fixture with fixed IDs/timestamps.
};
```

The actual test must spell out all nine fixture payloads; it must not derive expected JSON by calling the same production encoder. Provider/Header fixtures use obvious test-only secrets and assertions must never print the full fixture on failure; compare key paths and sanitized maps separately where needed.

- [ ] **Step 1: Add red tests for replace/clear semantics and production registration**

Extend participant tests for:

- identical value no-op;
- non-empty Header/rules replace;
- incoming empty Header/rules produces `clear`, not no-op;
- font/retry replace complete values;
- rejected storage Future leaves controller state unchanged.

Create contract tests for exact ordered keys, all six groups, providers/network sensitivity, nine encode/decode round-trips, v9 fixture snapshot, and absence of local-only storage keys/types.

- [ ] **Step 2: Run replacement and contract tests for red**

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_participants_test.dart test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart test/features/settings/application/preferences/persisted_settings_controllers_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-production-catalog-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-production-catalog-red.log
if ($TestExit -eq 0) { throw '预期 replacing participants/生产 catalog 尚不存在，red 却通过' }
```

- [ ] **Step 3: Implement four replacing participants**

For `customHeaders` and `outputProcessing`, derive summary action from incoming collection emptiness. The summary exposes only counts; it never includes header keys, values, regex patterns or replacement strings.

- [ ] **Step 4: Assemble the nine production participants once**

Use exact catalog order from the tables. For single preset export, callers later retrieve `participant<List<PresetPrompt>>(const SettingsTransferKey('presetPrompts'))`; do not publish nine separate globally mutable registries.

- [ ] **Step 5: Implement the explicit production schema fixture**

The contract test builds a real `ProviderContainer` with in-memory DB and SharedPreferences, reads the production catalog, feeds stable typed fixtures to each typed participant, and compares sanitized canonical payloads to the literal snapshot. Add one test-only fake participant to a separate catalog and assert constructor acceptance without modifying the production snapshot.

- [ ] **Step 6: Run all Settings transfer application tests for green**

```powershell
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart test/features/settings/application/transfer/settings_transfer_catalog_test.dart test/features/settings/application/transfer/settings_transfer_coordinator_test.dart test/features/settings/application/transfer/settings_transfer_participants_test.dart test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart test/features/settings/application/preferences/persisted_settings_controllers_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-production-catalog-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-production-catalog-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 7: Format, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/application/transfer/participants/preference_transfer_participants.dart',
  'lib/features/settings/application/transfer/settings_transfer_catalog_provider.dart',
  'test/features/settings/application/transfer/settings_transfer_participants_test.dart',
  'test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart',
  'test/features/settings/application/preferences/persisted_settings_controllers_test.dart'
)
$TransferFiles = $TransferFiles | Where-Object { Test-Path $_ }
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 注册替换型设置传输项"
```

If `persisted_settings_controllers_test.dart` did not change, it is filtered out before formatting/staging; verify the printed staged list still contains only the four transfer files.

---

