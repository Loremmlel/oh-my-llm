# Unified Settings Transfer Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把设置页分组剪贴板导出、全局剪贴板导入、单条预设分享和设备 Sync 收敛到同一套显式注册的 Settings transfer registry；设置默认仅本地，新增设置只有在注册 participant 后才自动进入所有标准入口。

**Architecture:** Settings domain 只定义 v9 `SettingsTransferDocument` 及严格顶层 codec；Settings application 以类型化 `SettingsTransferParticipant<T>`、受控类型擦除的 catalog 和统一 coordinator 负责读取、编解码、prepare、摘要、敏感确认、revalidate、串行执行与部分失败。九个首批 participant 复用两种基础策略并保留服务商专用合并器。Settings presentation 只负责 Clipboard 与对话框，Sync 通过 consumer-owned facade DTO 投影 catalog，并将协议提升到 v4 的稳定 group ID 与结构化 document。

**Tech Stack:** Flutter 3.44.x stable（CI 固定 3.44.6；计划编写机为 3.44.8）/ Dart `^3.11.5`（计划编写机为 3.12.2）/ Riverpod 3 `NotifierProvider` / Equatable / 原始 sqlite3 / SharedPreferences / typed Sync v4 / Flutter Widget tests。

**Spec:** `docs/specs/2026-08-18-settings-transfer-registry-design.md`

## Global Constraints

- 权威设计是上面的已批准规格；若实现需要改变缺失/空 section 语义、敏感确认边界、跨存储失败语义、Sync group 或版本策略，立即停止并回到规格评审。
- 当前基线为 `f7c378d9efd8c5cb52d11b0d1cb3ff7552922c21`、`pubspec.yaml` 版本 `3.55.14+0`；执行前必须重新读取，不能把它们视为长期事实。
- 默认仅本地。只有显式注册为 `SettingsTransferParticipant<T>` 的设置才可传输；不得扫描 Provider、SharedPreferences key、SQLite table、controller 继承关系或 Dart 类型来自动注册。
- 首批仅注册九项：服务商、预设、记忆提示词、模板提示词、固定顺序提示词、自定义 Header、输出处理、字号、自动重试。`ChatDefaults`、设置当前 Tab、媒体根目录、媒体密度和派生模型目录继续仅本地。
- 不建立“所有设置项”的统一基类。只实现 participant 层的 `ReplacingValueParticipant<T>` 与 `MergingCollectionParticipant<T>`；标量 controller 基类继续保持 out of scope。
- Settings transfer v9 是唯一支持格式；v8、更旧版本和未来版本均显式拒绝。Sync v4 是唯一支持协议；v3、更旧版本和未来版本均显式拒绝。
- 不引入 participant `schemaRevision`。生产 key 集合与 canonical fixtures 只在契约测试中绑定顶层 `formatVersion`；测试 catalog 不受生产快照约束。
- `readLocal()` 必须同步返回已经加载的状态。不得在单个 participant 内启动异步首载；若现有数据不满足，按规格停止而不是偷偷把返回类型改成 `Future`。
- 合并型集合只有非空时形成 section；缺失 section 表示不参与且不改本地。替换型 section 只要选中就形成，空 Header/空输出规则是明确的清空命令。
- 全局剪贴板导入不依赖当前 Settings Tab；当前 Tab 只决定导出 group。单条预设分享必须生成标准 v9 document，不能保留专用 JSON 旁路。
- API Key、Header value、完整 Clipboard 文本和完整 transfer document 不得写日志、摘要或错误文案。敏感导出在返回可写剪贴板文本前确认；敏感导入在 application 执行边界再次确认。
- 不宣称 SQLite 与 SharedPreferences 跨 participant 原子。执行按 catalog 顺序串行；结果必须区分成功、stale preview、失败和部分失败，且重试保持幂等。
- 单 participant 必须等待真实持久化 Future 成功后才发布 Riverpod state 或报告成功。服务商导入是本计划必须修复和测试的已知例外。
- 不修改 SQLite schema、`PRAGMA user_version`、既有本地 SharedPreferences key 或本地 JSON schema。
- Settings domain/application 不导入 Flutter Clipboard；Sync presentation/data 不导入九个具体 Settings controller；跨 feature 只经 Sync-owned port 和 app composition 绑定。
- 不增加宽泛 import-boundary allowlist；任何需要新 allowlist 才能通过的设计应停止实施。
- 所有新增注释与测试标题使用简体中文；不得新增 `part` / `part of`。
- 跨 feature、跨 `core/`、跨 `app/` 使用 `package:oh_my_llm/` 根路径；同一 feature 内部使用相对 import。
- 测试只等待 Provider 状态、受控 stream、`Completer`、存储 ACK 或有限动画；不得新增任意固定延迟、`Future.delayed(Duration.zero)` 或无条件 `pumpAndSettle()`。
- 所有测试、分析与诊断输出写入 ignored 的 `logs/`；全量测试固定写 `logs/fltest.log`。
- 每个提交前格式化本任务所有改动 Dart 文件，暂存后再次运行 `dart format --output=none --set-exit-if-changed`。
- 每个任务只暂存该任务列出的文件；发现用户的无关改动时保留并绕开，重叠改动无法安全分离时停止请求用户处理。
- 每项 red 证据必须因预期缺失类型、缺失行为或新断言失败；若失败来自环境、旧用例或不相关编译错误，先诊断，不能把它当作有效 red。
- 本计划不授权 push、PR、发布、Windows/Android 构建或设备手测；最终只报告实际运行的自动化验证。

### Review dispositions carried into implementation

| 审查点 | 实施约束 |
| --- | --- |
| 空服务商示例与 presence 规则冲突 | v9 fixture 不生成空合并 section；替换型空 section 另测清空。 |
| runtime catalog 与 schema snapshot 职责混淆 | constructor 只做结构校验；生产 snapshot 只在 contract test 比较；fake catalog 使用自己的 fixture。 |
| 双重版本号无独立价值 | 不实现 `schemaRevision`；任一 canonical section 变化提升顶层 `formatVersion`。 |
| facade 同步 prepare 缺少前提 | participant `readLocal()` 明确同步；新异步首载需求触发停止条件。 |
| Change 的“受控操作”含糊 | change 保存输入、最终写入值、摘要与类型化 participant 引用，不保存闭包、不序列化。 |
| 通用 decode 混入 Sync 校验 | document/participant decode 保持通用；requested group subset 只在 Sync facade 的 prepare 路径执行。 |

---

## 0. File Structure and Dependency Lock

### New Settings domain and application files

| File | Responsibility |
| --- | --- |
| `lib/features/settings/domain/models/transfer/settings_transfer_document.dart` | v9 identifier、formatVersion、深度不可变 JSON-safe sections。 |
| `lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart` | JSON/string 顶层严格编解码与 malformed/unsupported 分类；不认识具体 participant。 |
| `lib/features/settings/application/transfer/settings_transfer_types.dart` | key、group、sensitivity、摘要、export/import batch 与 sealed 结果类型。 |
| `lib/features/settings/application/transfer/settings_transfer_participant.dart` | 泛型 participant 契约、替换/合并策略基类、内部类型擦除 box。 |
| `lib/features/settings/application/transfer/settings_transfer_catalog.dart` | 注册、结构校验、有序检索、group/sensitivity 投影与 typed lookup。 |
| `lib/features/settings/application/transfer/settings_transfer_coordinator.dart` | export、decode/prepare、Sync subset、revalidate、串行 execute 与部分失败。 |
| `lib/features/settings/application/transfer/settings_transfer_catalog_provider.dart` | 九个 participant 的唯一生产装配和 coordinator Provider。 |
| `lib/features/settings/application/transfer/participants/model_provider_transfer_participant.dart` | 服务商严格 codec、专用 merge、摘要和持久化写入。 |
| `lib/features/settings/application/transfer/participants/prompt_collection_transfer_participants.dart` | 四类提示词的 codec、内容去重、模板编译校验和 SQLite upsert。 |
| `lib/features/settings/application/transfer/participants/preference_transfer_participants.dart` | Header、输出处理、字号、自动重试的替换/清空策略。 |
| `lib/features/settings/application/providers/llm_provider_import_merger.dart` | 服务商 ID/等价键/modelName 合并纯函数，供 controller 与 participant 共用。 |

### New shared presentation and tests

| File | Responsibility |
| --- | --- |
| `lib/core/widgets/transfer_summary_list.dart` | 不依赖 feature 的 label/trailingText 摘要列表布局，供 Settings 与 Sync 对话框共用。 |
| `test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart` | v9 document round-trip、严格版本和顶层结构。 |
| `test/features/settings/application/transfer/settings_transfer_catalog_test.dart` | constructor 结构校验、group 顺序/敏感性、typed lookup 与 test-only catalog。 |
| `test/features/settings/application/transfer/settings_transfer_coordinator_test.dart` | fake participants 驱动所有通用 export/prepare/execute/并发契约。 |
| `test/features/settings/application/transfer/settings_transfer_participants_test.dart` | 九个 concrete participant 的 codec、merge/replace/clear/no-op/ACK。 |
| `test/features/settings/application/transfer/settings_transfer_catalog_contract_test.dart` | 生产 key + v9 + canonical fixtures 快照和本地-only 排除。 |
| `test/features/settings/presentation/settings_screen/settings_screen_transfer_cases.dart` | 全局导入、当前 group 导出、敏感确认、单预设标准文档。 |

### Existing files intentionally changed

- Provider persistence: `lib/features/settings/application/providers/llm_model_configs_controller.dart`, `test/features/settings/application/providers/llm_model_configs_controller_test.dart`.
- Settings facade/UI: `lib/features/settings/application/transfer/settings_sync_facade.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/settings/presentation/widgets/transfer/import_confirm_dialog.dart` and their existing tests/helpers/case entrypoint.
- Sync port/domain/application: `lib/features/sync/application/ports/settings_sync_facade.dart`, `sync_client_protocol.dart`, `sync_client_protocol_coordinator.dart`, `sync_server_protocol_coordinator.dart`, `sync_client_controller.dart`, `domain/models/protocol/sync_types.dart`, `sync_protocol_message.dart`, `sync_protocol_version.dart`.
- Sync UI/composition tests: `lib/features/sync/presentation/widgets/sync_operation_tab.dart`, `sync_import_confirm_dialog.dart`, `test/features/sync/**`, `test/app/composition/sync_workspace_screen/**`, `test/integration/sync_e2e_integration_test.dart`, `test/integration/sync_multi_category_integration_test.dart`.
- Composition binding stays at `lib/app/composition/cross_feature_bindings.dart`; only the facade implementation behind the existing override changes.

### Legacy files removed only after both entry families migrate

| Remove in Task 9 | Replacement |
| --- | --- |
| `settings_export_data.dart` / `settings_export_codec.dart` | v9 document + document codec + participant codecs |
| `settings_transfer_workflow.dart` | coordinator export/prepare |
| `settings_import_deduplicator.dart` | participant `prepareImport` |
| `settings_import_executor.dart` | batch execute through participant box |
| corresponding five legacy unit-test files | new document/catalog/coordinator/participant/facade tests |
| `SyncCategory` and four-boolean `SettingsSyncSelection` | stable `SettingsSyncGroupId` set and dynamic descriptors |

No legacy file is deleted while a production import still references it. Any temporary adapter added for intermediate compilation must contain a removal comment naming Task 8 or Task 9 and must be absent from the final grep audit.

### Final dependency direction

```text
Settings domain document/codec
          ↑
participant<T> ← concrete participant ← existing controller/repository
          ↑
catalog → coordinator → Settings presentation (Clipboard only here)
                    ↘ Settings-owned implementation of Sync-owned facade
                         ↘ Sync controller/protocol → Sync presentation
```

Sync domain may import the Settings domain document for the typed structured payload. It must not import Settings application or presentation. The Sync facade implementation is the only cross-feature adapter that sees both the Settings coordinator and Sync port DTOs.

## 1. Execution Preflight

- [ ] **Step 1: Confirm workspace, branch, hooks, baseline and unrelated state**

Run from `E:\Code\oh-my-llm`:

```powershell
git rev-parse --show-toplevel
git rev-parse HEAD
git branch --show-current
git config --get core.hooksPath
Select-String -Path pubspec.yaml -Pattern '^version:'
git status --short
New-Item -ItemType Directory -Force logs | Out-Null
```

Expected: repository root is `E:/Code/oh-my-llm`, hook path ends in `.githooks`, and all existing changes are understood. The recorded baseline may be newer than this plan because the version hook and plan commit can move HEAD. If any overlapping transfer/Sync files are already modified, stop and reconcile ownership before editing.

- [ ] **Step 2: Confirm toolchain without upgrading it**

```powershell
flutter --version
dart --version
```

Expected: Flutter remains 3.44.x stable and Dart satisfies `^3.11.5`. Do not run `flutter upgrade`. If the executor changed Flutter, run `flutter clean` before tests as required by `AGENTS.md`.

- [ ] **Step 3: Capture import graph and old-path inventory before migration**

```powershell
rg -n "SettingsExportData|SettingsExportCodec|SettingsTransferWorkflow|SettingsImportDeduplicator|SettingsImportExecutor|SyncCategory|SettingsSyncSelection" lib test | Out-File -Encoding utf8 logs/settings-transfer-legacy-inventory.log
Get-Content -Tail 160 logs/settings-transfer-legacy-inventory.log
```

Expected: hits are limited to the legacy files and consumers enumerated above. Save this inventory for the Task 9 zero-hit comparison; do not mechanically replace unrelated historical prose in docs.

- [ ] **Step 4: Run the focused baseline serially**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer test/features/settings/application/transfer test/features/sync/domain/models/protocol/sync_protocol_message_test.dart test/features/sync/application/sync_client_controller_test.dart test/integration/sync_e2e_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-baseline.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 150 logs/settings-transfer-baseline.log
if ($TestExit -ne 0) { exit $TestExit }
```

Expected: `EXIT=0`. If startup stalls before a test begins, run `.\scripts\kill-stale-test-processes.ps1` and retry once. If it still fails, diagnose the baseline before adding code.

---

### Task 1: Define the canonical Settings transfer v9 document

**Files:**
- Create: `lib/features/settings/domain/models/transfer/settings_transfer_document.dart`
- Create: `lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart`
- Create: `test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart`
- Keep unchanged for now: `settings_export_data.dart`, `settings_export_codec.dart` and their tests

**Interfaces:**

```dart
final class SettingsTransferDocument extends Equatable {
  SettingsTransferDocument({required Map<String, Object?> sections})
    : sections = _freezeJsonObject(sections);

  static const identifier = 'shikiyuzu-oh-my-llm';
  static const formatVersion = 9;

  final Map<String, Object?> sections;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'identifier': identifier,
    'formatVersion': formatVersion,
    'sections': sections,
  });

  @override
  List<Object?> get props => [jsonEncode(toJson())];
}

sealed class SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeResult();
}
final class SettingsTransferDocumentDecodeSuccess
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentDecodeSuccess(this.document);
  final SettingsTransferDocument document;
}
final class SettingsTransferDocumentUnsupportedVersion
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentUnsupportedVersion(this.version);
  final int version;
}
final class SettingsTransferDocumentMalformed
    extends SettingsTransferDocumentDecodeResult {
  const SettingsTransferDocumentMalformed();
}

```

`SettingsTransferDocumentCodec` has exactly three public static members: `decodeJson(String?)`, `decodeObject(Map<String, Object?>)` and `encodeJson(SettingsTransferDocument)`. The first two return `SettingsTransferDocumentDecodeResult`; the last returns `String`.

The constructor/codec copies nested maps/lists into unmodifiable values and accepts only JSON-safe `null/bool/num/String/List/Map<String, Object?>`. Top level must contain exactly `identifier`, `formatVersion`, and `sections`; wrong identifier or wrong types are malformed, integer versions other than 9 are unsupported. The codec validates section key syntax and payload JSON safety but does not know whether a key is registered or how its payload decodes.

- [ ] **Step 1: Write failing v9 document tests**

Cover all of these in Chinese-named tests:

- round-trip preserves a non-empty ordered sections map;
- empty sections is structurally valid;
- v8 and v10 return `UnsupportedVersion` with their exact version;
- null, blank, invalid JSON, wrong identifier, missing/float version, missing/non-map sections and unexpected top-level keys return `Malformed`;
- non-string nested map keys and non-JSON-safe objects are rejected;
- mutating the source map/list after construction cannot change the document;
- `toJson()` returns a defensive structure that callers cannot mutate.

- [ ] **Step 2: Run the new test and record the expected red**

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-red.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-red.log
if ($TestExit -eq 0) { throw '预期 v9 document 类型尚不存在，red 却通过' }
```

Expected red: imports/types for `SettingsTransferDocument` or its codec are missing. Any native-assets or unrelated compilation failure is not valid evidence.

- [ ] **Step 3: Implement the immutable document and strict top-level codec**

Use recursive copy/validation helpers private to `settings_transfer_document.dart`; preserve insertion order with ordinary `LinkedHashMap` behavior wrapped by `Map.unmodifiable`. `props` may use `jsonEncode(toJson())` so nested value equality is structural and deterministic. Do not add participant imports.

- [ ] **Step 4: Run the focused green test**

```powershell
flutter test test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 logs/settings-transfer-document-green.log
$TestExit = $LASTEXITCODE
Write-Host "EXIT=$TestExit"
Get-Content -Tail 120 logs/settings-transfer-document-green.log
if ($TestExit -ne 0) { exit $TestExit }
```

Expected: `EXIT=0`, including v8/v10 rejection and defensive-copy assertions.

- [ ] **Step 5: Format, stage exactly and commit**

```powershell
$TransferFiles = @(
  'lib/features/settings/domain/models/transfer/settings_transfer_document.dart',
  'lib/features/settings/domain/models/transfer/settings_transfer_document_codec.dart',
  'test/features/settings/domain/models/transfer/settings_transfer_document_codec_test.dart'
)
dart format $TransferFiles
git add -- $TransferFiles
dart format --output=none --set-exit-if-changed $TransferFiles
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(settings): 建立设置传输 v9 文档"
```

Expected staged paths are exactly the three listed files. After the hook, record actual `git rev-parse HEAD` and version.

---

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
