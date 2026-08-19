### Task 4: Extract provider merge logic and implement the five collection participants

**Files:**
- Create: `lib/features/settings/application/providers/llm_provider_import_merger.dart`
- Create: `lib/features/settings/application/transfer/participants/model_provider_transfer_participant.dart`
- Create: `lib/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart`
- Create: `test/features/settings/application/transfer/settings_transfer_participants_test.dart`
- Modify: `lib/features/settings/application/providers/llm_model_configs_controller.dart`
- Modify: `test/features/settings/application/providers/llm_model_configs_controller_test.dart`
- Reuse without editing unless a verified contract is missing: existing prompt controllers, repositories, `llm_provider_equivalence.dart`, and template compiler

**Pure provider merge contract:**

```dart
List<LlmProviderConfig> mergeImportedLlmProviders({
  required List<LlmProviderConfig> local,
  required List<LlmProviderConfig> incoming,
});
```

The function exactly preserves current priority:

1. same ID: incoming provider fields replace local provider fields, models merge by `modelName`;
2. no same ID but same normalized protocol + API root + API key: preserve local identity/fields and merge new `modelName` values;
3. no match: add incoming provider;
4. return `sortProviderConfigs` output.

Add a narrow controller method:

```dart
Future<void> replaceAllAfterImport(List<LlmProviderConfig> providers) async {
  final nextState = sortProviderConfigs(providers);
  await _repository.saveProviders(nextState);
  state = nextState;
}
```

Change existing `mergeImportedProviders` to compute via the pure function and delegate to this method. Do not reorder unrelated controller methods. This is the only controller behavior change authorized here.

**Concrete participant keys and types:**

| Key | Type | Group | Order | Sensitivity | Apply |
| --- | --- | --- | --- | --- | --- |
| `modelProviders` | `List<LlmProviderConfig>` | providers | 0 | credential | `replaceAllAfterImport(finalMergedList)` |
| `presetPrompts` | `List<PresetPrompt>` | presets | 0 | standard | `upsertAll(newItems)` |
| `memoryPrompts` | `List<MemoryPrompt>` | prompts | 0 | standard | `upsertAll(newItems)` |
| `templatePrompts` | `List<TemplatePrompt>` | prompts | 1 | standard | `upsertAll(newItems)` |
| `fixedPromptSequences` | `List<FixedPromptSequence>` | prompts | 2 | standard | `upsertAll(newItems)` |

Every list decoder requires a list of maps and invokes the current model `fromJson`. Provider decoder additionally requires non-null `apiProtocol` for every provider. Template decoder compiles every definition with `compileTemplatePromptDefinition`; one invalid template rejects the section before prepare.

Prompt equivalence is moved from the legacy deduplicator into concrete participants without changing contracts: memory by content; preset by ordered message title/role/placement/content; template by content and ordered full variables; fixed sequence by ordered step title/content. Titles/names and IDs remain excluded exactly where the current comparator excludes them.

- [ ] **Step 1: Add red tests for the pure provider merger and persistence ordering**

In `llm_model_configs_controller_test.dart`, add Chinese-named coverage for same-ID replacement, equivalent-key identity preservation, protocol separation and duplicate model suppression through the pure function. Add a test `导入服务商持久化失败时不发布新状态` using a test `SettingsKeyValueStore` whose `setString` returns false; seed initial state through its readable map, invoke `mergeImportedProviders`, expect a `StateError`, and assert controller state still equals the seed.

- [ ] **Step 2: Add red participant tests for five collection types**

Use callback-backed concrete participant constructors so tests do not need Riverpod. Assert each key/group/order/sensitivity, round-trip, empty export omission, content no-op and new-item summary. Add provider cases for final merged list and secret-free summary, plus malformed provider protocol and invalid template compilation rejection.

- [ ] **Step 3: Run the combined red tests**

```powershell
flutter test test/features/settings/application/providers/llm_model_configs_controller_test.dart test/features/settings/application/transfer/settings_transfer_participants_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-collections-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-collections-red.log
if ($TestExit -eq 0) { throw '预期 provider merger/collection participants 尚不存在，red 却通过' }
```

Expected red must include missing merger/participant types or the new persistence-order assertion failing against the old state-before-save method.

- [ ] **Step 4: Extract the pure merger and correct controller ACK order**

Keep repository errors intact for application handling, but never publish `state` until `saveProviders(nextState)` succeeds. Existing normal provider editing methods remain unchanged because this task only promises the import path ordering.

- [ ] **Step 5: Implement provider and prompt collection participants**

Constructor dependencies are synchronous reader and async writer callbacks, plus fixed metadata. The provider participant overrides collection prepare to place the complete merged provider list in `writeValue`; prompt participants place only new incoming items in `writeValue` because their `upsertAll` controller methods atomically merge into current SQLite state. Fingerprints are computed from canonical encoded write values and summary action/count, never from secrets printed as text.

- [ ] **Step 6: Run collection participant green tests and old deduplicator regressions**

```powershell
flutter test test/features/settings/application/providers/llm_model_configs_controller_test.dart test/features/settings/application/transfer/settings_transfer_participants_test.dart test/features/settings/application/transfer/settings_import_deduplicator_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-collections-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-collections-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

The legacy deduplicator test remains a temporary behavior comparison until Task 9 removes it.

- [ ] **Step 7: Format, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/application/providers/llm_provider_import_merger.dart',
  'lib/features/settings/application/providers/llm_model_configs_controller.dart',
  'lib/features/settings/application/transfer/participants/model_provider_transfer_participant.dart',
  'lib/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart',
  'test/features/settings/application/providers/llm_model_configs_controller_test.dart',
  'test/features/settings/application/transfer/settings_transfer_participants_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 注册集合型设置传输项"
```

---

