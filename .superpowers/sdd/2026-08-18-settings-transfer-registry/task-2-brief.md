### Task 2: Build the typed participant primitives and validated catalog

**Files:**
- Create: `lib/features/settings/application/transfer/settings_transfer_types.dart`
- Create: `lib/features/settings/application/transfer/settings_transfer_participant.dart`
- Create: `lib/features/settings/application/transfer/settings_transfer_catalog.dart`
- Create: `test/features/settings/application/transfer/settings_transfer_catalog_test.dart`

**Public contracts:**

```dart
final class SettingsTransferKey extends Equatable {
  const SettingsTransferKey(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

enum SettingsTransferGroup {
  providers('providers', '服务商', 0),
  presets('presets', '预设', 1),
  prompts('prompts', '提示词', 2),
  network('network', '网络', 3),
  outputProcessing('outputProcessing', '输出处理', 4),
  other('other', '其它', 5);

  const SettingsTransferGroup(this.wireKey, this.label, this.order);

  final String wireKey;
  final String label;
  final int order;
}

enum SettingsTransferSensitivity { standard, credentialBearing }
enum SettingsTransferSummaryAction { add, replace, clear }

final class SettingsTransferSummaryItem extends Equatable {
  const SettingsTransferSummaryItem({
    required this.key,
    required this.label,
    required this.action,
    this.count,
  }) : assert(
         action == SettingsTransferSummaryAction.add
             ? count != null && count > 0
             : count == null,
       );
  final SettingsTransferKey key;
  final String label;
  final SettingsTransferSummaryAction action;
  final int? count;
  String get trailingText => switch (action) {
    SettingsTransferSummaryAction.add => '新增 $count 项',
    SettingsTransferSummaryAction.replace => '替换',
    SettingsTransferSummaryAction.clear => '清空',
  };

  @override
  List<Object?> get props => [key, label, action, count];
}

abstract interface class SettingsTransferParticipant<T> {
  SettingsTransferKey get key;
  SettingsTransferGroup get group;
  String get label;
  int get order;
  SettingsTransferSensitivity get sensitivity;

  T readLocal();
  bool shouldExport(T value);
  Object encode(T value);
  T decode(Object? payload);
  SettingsTransferChange<T>? prepareImport({
    required T local,
    required T incoming,
  });
  SettingsTransferSummaryItem summarizeExport(T value);
  Future<void> applyImport(T value);
}

final class SettingsTransferChange<T> {
  const SettingsTransferChange({
    required this.participant,
    required this.incoming,
    required this.writeValue,
    required this.fingerprint,
    required this.summary,
  });
  final SettingsTransferParticipant<T> participant;
  final T incoming;
  final T writeValue;
  final String fingerprint;
  final SettingsTransferSummaryItem summary;
}
```

`ReplacingValueParticipant<T>` compares complete values and produces replace/clear summaries. `MergingCollectionParticipant<T>` implements `SettingsTransferParticipant<List<T>>`, filters content-equivalent existing/incoming elements, omits empty exports, and produces an add summary. Concrete classes still own JSON decoding, equivalence and apply behavior.

The catalog stores one application-internal `SettingsTransferParticipantBox<T>` per participant behind a non-generic `ErasedSettingsTransferParticipant` interface. Because this repository forbids `part` and the catalog/coordinator live in separate Dart libraries, these types cannot use library-private `_Name`s; they have public Dart names but are documented as internal and are never imported outside Settings application. The generic box is the only location allowed to cast erased payload/change values; before apply it verifies both the change type and `identical(change.participant, participant)`. `SettingsTransferCatalog.participant<T>(key)` is the typed lookup used by single-value export and throws a descriptive `StateError` on a wrong requested type.

- [ ] **Step 1: Write failing catalog/base-strategy tests**

Create fake scalar and collection participants with in-memory read/write fields. Assert:

- key ordering is `group.order`, participant `order`, then key value;
- duplicate key and duplicate order within one group are constructor errors;
- blank/invalid key and blank label are constructor errors;
- group descriptors exist for registered groups and aggregate credential sensitivity;
- `participant<int>(key)` succeeds while a wrong generic lookup fails before execution;
- replacing equal value is no-op; empty replacement yields clear summary;
- merging empty local with two unique values yields one add change with count 2; empty collection fails `shouldExport`;
- test-only catalog accepts a fake key without consulting production schema fixtures.

- [ ] **Step 2: Run catalog tests for red**

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-catalog-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-catalog-red.log
if ($TestExit -eq 0) { throw '预期 participant/catalog 类型尚不存在，red 却通过' }
```

Expected red: missing participant, catalog or transfer types.

- [ ] **Step 3: Implement value types and strategy bases**

`SettingsTransferSummaryItem.trailingText` is the sole business-to-display mapping: `add` requires positive `count` and returns `新增 N 项`; `replace` returns `替换`; `clear` returns `清空`. Constructors assert or throw on inconsistent count/action combinations so both Settings and Sync summaries share the same safe wording.

- [ ] **Step 4: Implement catalog and controlled type erasure**

Constructor validation is runtime structural validation only. Do not import a schema fixture or compare `formatVersion` here. Expose:

```dart
List<SettingsTransferGroupDescriptor> get groups;
List<ErasedSettingsTransferParticipant> participantsForGroups(
  Set<SettingsTransferGroup> groups,
);
SettingsTransferParticipant<T> participant<T>(SettingsTransferKey key);
SettingsTransferGroup groupForKey(SettingsTransferKey key);
```

`SettingsTransferParticipantBox` is application-internal and exposes only encoded export, decode/prepare, reprepare comparison and apply methods required by the coordinator; raw casts never appear in presentation or Sync. Add an import-boundary/grep assertion in Task 9 that the box name occurs only under `lib/features/settings/application/transfer/`.

- [ ] **Step 5: Run catalog tests for green**

```powershell
flutter test test/features/settings/application/transfer/settings_transfer_catalog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-catalog-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-catalog-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

- [ ] **Step 6: Format, stage exactly and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/application/transfer/settings_transfer_types.dart',
  'lib/features/settings/application/transfer/settings_transfer_participant.dart',
  'lib/features/settings/application/transfer/settings_transfer_catalog.dart',
  'test/features/settings/application/transfer/settings_transfer_catalog_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 建立设置传输 participant 注册表"
```

---

