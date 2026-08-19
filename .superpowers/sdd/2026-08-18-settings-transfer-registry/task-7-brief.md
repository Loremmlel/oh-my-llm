### Task 7: Project the catalog through the Sync port and migrate wire protocol to v4

**Files:**
- Rewrite: `lib/features/settings/application/transfer/settings_sync_facade.dart`
- Rewrite: `test/features/settings/application/transfer/settings_sync_facade_test.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Modify: `lib/features/sync/application/ports/settings_sync_facade.dart`
- Modify: `lib/features/sync/application/ports/sync_client_protocol.dart`
- Modify: `lib/features/sync/application/sync_client_protocol_coordinator.dart`
- Modify: `lib/features/sync/application/sync_server_protocol_coordinator.dart`
- Modify: `lib/features/sync/application/sync_client_controller.dart`
- Modify: `lib/features/sync/domain/models/protocol/sync_types.dart`
- Modify: `lib/features/sync/domain/models/protocol/sync_protocol_message.dart`
- Modify: `lib/features/sync/domain/models/protocol/sync_protocol_version.dart`
- Modify temporarily for the new prepared-import state: `lib/features/sync/presentation/widgets/sync_operation_tab.dart`
- Modify temporarily for the new prepared-import state: `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`
- Modify: `test/features/sync/domain/models/protocol/sync_protocol_message_test.dart`
- Modify: `test/features/sync/domain/models/protocol/sync_protocol_version_test.dart`
- Modify: `test/features/sync/application/sync_test_fakes.dart`
- Modify: `test/features/sync/application/sync_client_controller_test.dart`
- Modify: `test/features/sync/application/sync_client_controller_execute_test.dart`
- Modify: `test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart`

**Sync-owned port DTOs:**

`SettingsSyncGroupId` lives in `lib/features/sync/domain/models/protocol/sync_types.dart` because the typed wire payload needs it. `SettingsSyncGroupDescriptor`, sensitivity, summaries, prepared command and execution results live in the Sync-owned application port; Sync domain never imports its application layer.

```dart
final class SettingsSyncGroupId extends Equatable {
  const SettingsSyncGroupId(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

enum SettingsSyncSensitivity { standard, credentialBearing }

final class SettingsSyncGroupDescriptor extends Equatable {
  const SettingsSyncGroupDescriptor({
    required this.id,
    required this.label,
    required this.order,
    required this.sensitivity,
  });
  final SettingsSyncGroupId id;
  final String label;
  final int order;
  final SettingsSyncSensitivity sensitivity;

  @override
  List<Object?> get props => [id, label, order, sensitivity];
}

final class SettingsSyncSummaryItem extends Equatable {
  const SettingsSyncSummaryItem({
    required this.label,
    required this.trailingText,
  });
  final String label;
  final String trailingText;

  @override
  List<Object?> get props => [label, trailingText];
}

abstract interface class SettingsSyncPreparedImport {
  List<SettingsSyncSummaryItem> get summaries;
  bool get containsSensitive;
  Future<SettingsSyncImportExecutionResult> execute({
    required bool confirmedSensitive,
  });
}

abstract interface class SettingsSyncFacade {
  List<SettingsSyncGroupDescriptor> get availableGroups;
  SettingsTransferDocument exportGroups(Set<SettingsSyncGroupId> groups);
  SettingsSyncPreparedImport prepareIncoming(
    SettingsTransferDocument document, {
    required Set<SettingsSyncGroupId> requestedGroups,
  });
}
```

Port-owned execution results mirror success, sensitive-confirmation-required, stale with refreshed prepared command, failure, partial failure and already-consumed. They contain safe labels/messages only. The Settings implementation mechanically maps catalog descriptors/groups, calls coordinator export/prepare with allowed groups, wraps the one-shot batch and maps results; it contains no nine-field switch.

**Sync v4 payloads:**

```dart
final class SettingsSyncRequestPayload extends EncryptedSyncPayload {
  SettingsSyncRequestPayload(
    Set<SettingsSyncGroupId> groups, {
    required this.confirmedSensitive,
  }) : groups = Set.unmodifiable(groups);

  final Set<SettingsSyncGroupId> groups;
  final bool confirmedSensitive;

  @override
  String get kind => 'settingsSyncRequest';

  @override
  List<Object?> get props => [
    groups.map((group) => group.value).toList()..sort(),
    confirmedSensitive,
  ];
}

final class SettingsSyncResponsePayload extends EncryptedSyncPayload {
  const SettingsSyncResponsePayload(this.document);

  final SettingsTransferDocument document;

  @override
  String get kind => 'settingsSyncResponse';

  @override
  List<Object?> get props => [document];
}
```

Wire JSON is:

```json
{
  "kind": "settingsSyncRequest",
  "groups": ["providers", "prompts"],
  "confirmedSensitive": true
}
```

and:

```json
{
  "kind": "settingsSyncResponse",
  "document": {
    "identifier": "shikiyuzu-oh-my-llm",
    "formatVersion": 9,
    "sections": {}
  }
}
```

There is no redundant snapshot `formatVersion` and no JSON string inside `document`. The protocol codec validates non-empty, syntactically valid, unique group IDs but deliberately leaves “known group” and sensitivity decisions to the receiving server facade/catalog.

**Server security path:**

1. decrypt/strictly decode request;
2. compare requested IDs to `availableGroups`; unknown ID returns the existing public `malformedMessage` failure before export;
3. recompute sensitivity from local descriptors; credential group without confirmation returns `sensitiveConfirmationRequired`;
4. call facade `exportGroups` and encrypt the structured document.

The client controller calls `prepareIncoming(document, requestedGroups: exactRequestSet)` before entering received state. A response containing a known but unrequested section is rejected before any write. The protocol version constants become current/min/max 4, and both client/server HKDF info strings become `oh-my-llm-sync-v4-session`.

**One-commit UI compatibility adapter:**

To keep this task compiling before the dynamic UI rewrite, retain `SyncCategory` only as a deprecated presentation adapter. Map `providers→{providers}`, `presets→{presets}`, `prompts→{prompts}`, `other→{network, outputProcessing, other}` in `SyncClientController`; it is not used by wire codec or server security. Replace `deduplicatedData` with `SettingsSyncPreparedImport? preparedImport` and minimally update the operation tab/dialog to render port summaries and call `execute(confirmedSensitive: confirmed)`. Task 8 must remove this adapter and its four-value UI; do not extend its lifetime.

- [ ] **Step 1: Rewrite facade tests for catalog projection and automatic adaptation**

Assert production facade returns six ordered descriptors with providers/network credential-bearing. With a separate fake catalog containing one extra participant in an existing group, construct the same facade adapter and prove the fake automatically enters `exportGroups`, `prepareIncoming.summaries` and final execute without changing facade code. Add rejection for unknown requested ID and known section outside requested groups.

- [ ] **Step 2: Add Sync v4 protocol red tests**

Update protocol tests to demand version 4, `groups`, structured `document`, v3 rejection, future-version rejection, duplicate group rejection, malformed document rejection and absence of `snapshot.data`/secondary JSON. Tests must also prove an unknown but syntactically valid group survives codec decode so the server—not the transport parser—rejects it against local catalog.

- [ ] **Step 3: Add server/client red tests for local sensitivity and requested subset**

Fakes expose configurable group descriptors and document. Assert:

- client sends exact stable IDs and confirmation bit;
- server refuses an unknown ID without invoking export;
- server refuses locally credential-bearing group when false, even if client UI would have called it standard;
- server exports after true;
- controller rejects response containing a section from an unrequested group;
- prepared import no-change enters `noNewData`; otherwise enters `received` with the one-shot command;
- execute forwards the import-time sensitive confirmation and maps stale/partial/success states.

- [ ] **Step 4: Run the v4/facade red suite**

```powershell
flutter test test/features/settings/application/transfer/settings_sync_facade_test.dart test/features/sync/domain/models/protocol/sync_protocol_version_test.dart test/features/sync/domain/models/protocol/sync_protocol_message_test.dart test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-v4-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/settings-sync-v4-red.log
if ($TestExit -eq 0) { throw '预期 Sync port/v4 协议尚未实现，red 却通过' }
```

- [ ] **Step 5: Implement the Settings-owned Sync facade adapter**

The adapter constructor accepts `SettingsTransferCatalog` and `SettingsTransferCoordinator`; the Riverpod production binding reads the two providers once. Map group IDs by exact `group.wireKey`. Unknown IDs fail before coordinator calls. `prepareIncoming` passes the resolved group set as `allowedGroups` and wraps only a ready batch; map no-change/invalid/unsupported/subset errors to typed, safe Sync preparation failures handled by the controller.

- [ ] **Step 6: Implement Sync v4 domain codec and protocol coordinators**

Remove protocol imports of `settings_export_data.dart`/old codec. Use `SettingsTransferDocumentCodec.decodeObject` for response payload. Change protocol range to 4 only, KDF info on both sides, request group encoding, server local catalog validation and structured response.

- [ ] **Step 7: Migrate controller to prepared import with the bounded category adapter**

Store the exact requested group set used for the in-flight response. Reset it with session state. Do not infer subset from current checkboxes after an async round trip. The import dialog's checkbox is independent from the request-time confirmation; application execution still receives its own boolean.

- [ ] **Step 8: Run v4/facade/controller green tests**

```powershell
flutter test test/features/settings/application/transfer/settings_sync_facade_test.dart test/features/sync/domain/models/protocol/sync_protocol_version_test.dart test/features/sync/domain/models/protocol/sync_protocol_message_test.dart test/features/sync/application/sync_client_controller_test.dart test/features/sync/application/sync_client_controller_execute_test.dart test/app/composition/sync_workspace_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-sync-v4-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 180 logs/settings-sync-v4-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 9: Format all task files, stage exact scope and commit**

```powershell
$TransferFiles = @(
  'lib/app/composition/cross_feature_bindings.dart',
  'lib/features/settings/application/transfer/settings_sync_facade.dart',
  'lib/features/sync/application/ports/settings_sync_facade.dart',
  'lib/features/sync/application/ports/sync_client_protocol.dart',
  'lib/features/sync/application/sync_client_protocol_coordinator.dart',
  'lib/features/sync/application/sync_server_protocol_coordinator.dart',
  'lib/features/sync/application/sync_client_controller.dart',
  'lib/features/sync/domain/models/protocol/sync_types.dart',
  'lib/features/sync/domain/models/protocol/sync_protocol_message.dart',
  'lib/features/sync/domain/models/protocol/sync_protocol_version.dart',
  'lib/features/sync/presentation/widgets/sync_operation_tab.dart',
  'lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart',
  'test/features/settings/application/transfer/settings_sync_facade_test.dart',
  'test/features/sync/domain/models/protocol/sync_protocol_message_test.dart',
  'test/features/sync/domain/models/protocol/sync_protocol_version_test.dart',
  'test/features/sync/application/sync_test_fakes.dart',
  'test/features/sync/application/sync_client_controller_test.dart',
  'test/features/sync/application/sync_client_controller_execute_test.dart',
  'test/app/composition/sync_workspace_screen/sync_workspace_screen_import_dialog_cases.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(sync): 迁移设置同步 v4 协议"
```

---

