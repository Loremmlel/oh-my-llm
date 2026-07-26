# Phase 5 - Settings 工作流与持久化契约 Implement Plan

> 本 Plan 仅基于 `Phase 5 - Settings 工作流与持久化契约.md` 细化；不重新解释 Architecture Review Report，也不改变 Phase 的结论或技术选型。
> 严格遵守本 Phase 的 Refactor Scope / Out Of Scope / Dependencies：只收敛 settings feature 内部的 application、轻量持久化和 presentation 边界；不创建 Phase 7 的跨 feature facade / snapshot，不实现 Phase 8 的同步协议或认证，不提前开展 Phase 11 的全局 ports 搬迁。

## 一、现状验证结论（2026-07-26）

| 验证项 | 实测结果 | 对应计划动作 |
|---|---|---|
| 静态分析 | `flutter analyze`：`EXIT=0`，`No issues found` | 以干净基线开始；每个逻辑提交后运行定向测试，最终重跑 analyze。 |
| 全量测试 | 按项目规定重定向执行：`EXIT=0`，`1309 All tests passed!` | 最终仍须按同一重定向命令验收。 |
| TD-03 | `SettingsImportExecutor.executeImport(dynamic ref, ...)` 逐项 `ref.read(...)`；测试需 `_ExecutorHarness` 捕获真实 `Ref` 才能调用 | 用显式、类型化的写入目标对象和 provider 装配替换 `dynamic`。 |
| TD-22 | `AutoRetrySettingsController`、`CustomHeadersController`、`FontSizeSettingsController`、`OutputProcessingSettingsController` 各自直接 `jsonEncode/jsonDecode + SharedPreferences`；`ChatDefaultsRepository` 也是无版本裸 JSON；模型列表虽有版本包装，但未统一写入失败处理 | 增加轻量泛型 versioned JSON store，保留小设置 Controller，按实际触碰范围渐进迁移。 |
| TD-23 | `SettingsEntityController.upsert/upsertAll/deleteById` 调用了 `_commit()` 却不 `return/await`；`PresetPromptsController.toggleMessageEnabled` 也丢弃 `upsert` Future | 公开 mutation 必须把实际 SQLite commit 的成功/异常传回调用方；保留小集合 replace-all。 |
| TD-26 | `SettingsScreen` 直接读取 `sharedPreferencesProvider`、维护 tab schema 迁移、解析/构造/去重 `SettingsExportData`，并把 `modelListClientProvider.fetchModels` 传进 dialog | 将 tab preference、transfer workflow 和 model catalog workflow 移到 application；Screen 只保留 TabController、Clipboard、dialog 与提示组合。 |
| 现有测试缺口 | 已有导入、去重、Controller、模型客户端与 widget 测试；没有类型化导入依赖测试、提交失败后 Future 异常测试、旧标量 JSON→版本包装兼容测试、Screen 不直连 persistence/data 的回归门禁 | 在各变更提交中先补这些行为测试，避免通过实现细节断言替代契约测试。 |

**无需回查 Review Report。** Phase 5 文档自身的债务、边界、依赖、风险和验收条件完整一致；上述只是对 File Scope 当前工作树的核对。

## 二、实施后的边界与关键决策

### 2.1 持久化：轻量泛型 store，不制造 settings God Service

新增 core 层 `SettingsKeyValueStore` 和 `VersionedJsonStore<T>`。前者只适配当前 settings 实际需要的 string/int key-value 读写；后者只负责一个 string key 的版本包装/解包、损坏或不支持版本时返回调用者给定 fallback、以及确认 `setString` 返回 `true` 后才视为 commit 成功。两者都不认识任何 settings 业务模型、不聚合多个 key、不做导入导出。

```dart
typedef JsonObjectDecoder<T> = T Function(JsonMap json);
typedef JsonObjectEncoder<T> = JsonMap Function(T value);

final class VersionedJsonStore<T> {
  const VersionedJsonStore({
    required SettingsKeyValueStore storage,
    required this.key,
    required this.subject,
    required this.fallback,
    required this.fromJson,
    required this.toJson,
  }) : _storage = storage;

  final SettingsKeyValueStore _storage;
  final String key;
  final String subject;
  final T Function() fallback;
  final JsonObjectDecoder<T> fromJson;
  final JsonObjectEncoder<T> toJson;

  T load();
  Future<void> save(T value);
}
```

`SettingsKeyValueStore` 仅抽象 `getString` / `setString` / `getInt` / `setInt`，生产 adapter 委托已有 `SharedPreferences`，测试可用内存 fake 控制写入的成功、失败和异常。它是为持久化完成语义与 tab preference 服务的 core adapter，不是 Phase 11 所说的跨 feature application port。

`VersionedJsonStorage` 扩展对象（非列表）包装：新写入为 `{ "version": 1, "value": { ... } }`；读到无 `value` 包装的旧 JSON object 时按 **legacy v0** 交给模型 `fromJson`，因此现有 `settings.auto_retry` / `settings.custom_headers` / `settings.font_size` / `settings.output_processing` / `settings.chat_defaults` 不会因升级丢失。解析失败、`version` 非整数、或未来版本均不抛给启动 UI，而是由 store 返回显式 fallback；写入失败绝不吞掉。

`LlmModelConfigRepository` 已使用列表版本包装，保留该合理设计，仅通过同一写入 adapter 将 `false` 返回值提升为异常。SQLite 的 memory/preset/template/fixed-sequence 仍是小集合 replace-all；本 Phase 不把它们形式化迁为增量 CRUD。

所有持久化 mutation 的统一顺序是：计算 next value → `await` 实际 write → 更新 Riverpod state。这样调用方的 Future 表示 durable commit 已成功；失败时 Future 以原异常完成且 state 保持旧值。`FontSizeSettingsController.updateLocal` 是刻意不落盘的拖拽预览 API，保持同步 `void` 并在文档中明确不是 mutation commit。

### 2.2 导入/导出：settings 内部 workflow，不暴露给 sync

`SettingsImportExecutor` 改为构造时接收显式 `SettingsImportTargets`；目标中每个字段都是对应的强类型 Future callback。application provider 是唯一使用 Riverpod notifier 的装配点，UI 和 future sync 消费者都不再传 `Ref`，更不传 `dynamic`。

```dart
final class SettingsImportTargets {
  const SettingsImportTargets({
    required this.mergeImportedProviders,
    required this.upsertMemoryPrompts,
    required this.upsertPresetPrompts,
    required this.upsertTemplatePrompts,
    required this.upsertFixedPromptSequences,
    required this.saveAutoRetrySettings,
    required this.saveCustomHeaders,
    required this.saveFontSize,
    required this.saveOutputProcessing,
  });

  final Future<void> Function(List<LlmProviderConfig>) mergeImportedProviders;
  final Future<void> Function(List<MemoryPrompt>) upsertMemoryPrompts;
  // 其余字段使用相同的、对应模型的强类型签名。
}

final settingsImportExecutorProvider = Provider<SettingsImportExecutor>((ref) {
  return SettingsImportExecutor(
    targets: SettingsImportTargets(
      mergeImportedProviders:
          ref.read(llmProviderConfigsProvider.notifier).mergeImportedProviders,
      // 每一个目标在这里显式绑定到对应 notifier mutation。
    ),
  );
});
```

新增 `SettingsTransferWorkflow` 只在 settings 内部组织以下稳定输入输出：`SettingsTransferTab`、`SettingsExportData? buildExportData(tab)`、以及 `SettingsImportPreparation prepareImport(tab, clipboardText)`。`prepareImport` 依次做 parse、当前 tab 匹配和现有 `SettingsImportDeduplicator` 去重，返回 `invalidClipboard`、`tabMismatch`、`noNewItems` 或携带 deduped data 的 `ready`。它不会读取 Clipboard、显示 dialog、写入任何 sync 协议对象，也不命名为 `SettingsSnapshot`。

### 2.3 Tab 与模型目录：Screen 发 intent，application 编排依赖

`SettingsTabPreferences` 负责 tab key、版本迁移、初始 index 读取和 index commit；`SettingsScreen` 继续拥有 Flutter `TabController` 与六个标签的视觉 label，但不再 import/读取 `SharedPreferences`。

`ModelCatalogWorkflow` 是 `ModelListClient` 的 application 边界。它接受 `ModelCatalogRequest(apiUrl, apiKey, modelsUrlOverride)`，在 application 内使用现有 `deriveModelsUrl` 处理未覆盖 URL，再委托 client。稳定的 UI 输入/输出类型移动到 settings domain/application：`ModelCatalogEntry` 和 `ModelCatalogFailure`。workflow 将 data 层 `ModelListException` 映射为 `ModelCatalogFailure(message, responseBody)`；`ModelFetchSection` 只处理该 application failure，不再 import data client 或 data URL helper。HTTP、日志和 30 秒 timeout 仍由 `ModelListClient` 保持，符合 Phase 3 已建立的观测边界。

### 2.4 错误与完成语义

- save/import 失败不得被当作成功：`await` 的 Future 原样失败；Import confirm dialog 保持打开、恢复可点击状态，并使用现有 `showSettingsSnackbar` 提示失败，不能显示“已成功导入”。
- 取消仍不写入；空剪贴板、tab 不匹配、全重复的现有文案和用户路径不变。
- model fetch 的 loading、重试、错误 body 展示、已存在标识、选择状态保持均不变；仅把数据 client 依赖替换为 workflow callback。
- 不修改聊天 feature 的 inline error 规范；这里沿用 Settings 已有的通知辅助方法，不引入新的 Dialog/SnackBar 错误机制。

## 三、文件修改清单

### 新增

| 文件 | 职责 |
|---|---|
| `lib/core/persistence/settings_key_value_store.dart` | 极小 string/int key-value adapter：`SharedPreferencesSettingsKeyValueStore` 生产实现与可控 fake 所需接口。 |
| `lib/core/persistence/versioned_json_store.dart` | 单 key 泛型 settings store：版本化对象、legacy v0 兼容、fallback、写入成功确认。 |
| `lib/features/settings/application/settings_import_targets.dart` | 所有导入写入目标的类型化 callback 契约。 |
| `lib/features/settings/application/settings_transfer_workflow.dart` | tab 内 export、parse/tab-match/deduplicate import preparation 与 provider 装配。 |
| `lib/features/settings/application/settings_tab_preferences.dart` | tab index/version key、纯迁移函数、读取与 durable save。 |
| `lib/features/settings/application/model_catalog_workflow.dart` | model catalog request、failure、workflow provider；屏蔽 `ModelListClient`。 |
| `lib/features/settings/domain/models/model_catalog_entry.dart` | 不依赖 HTTP 的模型目录显示项。 |
| `test/core/persistence/versioned_json_store_test.dart` | 新包装、legacy、future schema、损坏输入、`false`/throw 写入失败的契约测试。 |
| `test/features/settings/application/settings_entity_controller_test.dart` | replace-all commit Future 成功/失败完成语义。 |
| `test/features/settings/application/settings_transfer_workflow_test.dart` | export、tab 匹配、去重和 preparation 状态的纯 application 测试。 |
| `test/features/settings/application/settings_tab_preferences_test.dart` | tab schema 迁移、clamp、持久化完成/失败测试。 |
| `test/features/settings/application/model_catalog_workflow_test.dart` | URL 推导/覆盖、data failure 映射、成功列表传递测试。 |

### 修改

| 文件 | 改动 |
|---|---|
| `lib/core/persistence/versioned_json_storage.dart` | 增加 versioned **object** encode/decode 和 legacy object 识别；既有 object-list API 与 schema version 不变。 |
| `lib/core/persistence/shared_preferences_provider.dart` | 提供从 bootstrap 已注入 `SharedPreferences` 创建 `SettingsKeyValueStore` 的轻量 provider；不改变 bootstrap override 机制。 |
| `lib/features/settings/application/auto_retry_settings_controller.dart` | 改用 typed store provider；先 commit 后置 state。 |
| `lib/features/settings/application/custom_headers_controller.dart` | 改用 typed store provider；保留 add/remove/update API，全部 await save。 |
| `lib/features/settings/application/font_size_settings_controller.dart` | 改用 typed store；保留 `updateLocal`，`save` durable-first。 |
| `lib/features/settings/application/output_processing_settings_controller.dart` | 改用 typed store；移除各自 JSON parsing/fallback。 |
| `lib/features/settings/application/chat_defaults_controller.dart` | 继续经 repository 访问，但由 repository 提供版本化 fallback 和真实 commit Future。 |
| `lib/features/settings/application/llm_model_configs_controller.dart` | 各 mutation 保持 await repository；仅对写入 adapter 的异常/false 结果透明传播，不改 merge、排序或小集合策略。 |
| `lib/features/settings/application/settings_entity_controller.dart` | `return _commit(...)`；`_commit` 先完成 `saveAll` 再发布 immutable state。 |
| `lib/features/settings/application/preset_prompts_controller.dart` | `toggleMessageEnabled` 返回 `Future<void>` 并 `return upsert(...)`。 |
| `lib/features/settings/application/settings_import_executor.dart` | 删除 `dynamic ref`、所有 Riverpod imports 与 service locator 读取；改用 `SettingsImportTargets`。 |
| `lib/features/settings/data/chat_defaults_repository.dart` | 迁移到 `VersionedJsonStore<ChatDefaults>`，支持 legacy raw JSON 和统一 fallback/commit policy。 |
| `lib/features/settings/data/llm_model_config_repository.dart` | 通过 string-store adapter 确认 `setString == true`；现有 list 包装、排序逻辑不变。 |
| `lib/features/settings/data/model_list_client.dart` | 使用 domain `ModelCatalogEntry`；保留作为 data HTTP client，`ModelListException` 只被 workflow 消费。 |
| `lib/features/settings/presentation/settings_screen.dart` | 移除 direct SharedPreferences、ModelListClient、deduplicator、`SettingsExportData` 业务编排；改调用 tab/transfer/catalog application providers。保留 Clipboard、dialog、TabController、表单构造及成功/失败提示。 |
| `lib/features/settings/presentation/widgets/import_confirm_dialog.dart` | 使用 executor provider；失败时复位 loading、保持 dialog、提示失败；成功才 `pop(true)`。 |
| `lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart` | callback 类型改为 model catalog application request/entry，保留手输/拉取两种 UI。 |
| `lib/features/settings/presentation/widgets/form/model_fetch_section.dart` | 移除 data imports；使用 application/domain catalog 类型与 failure。 |
| `lib/features/settings/presentation/widgets/list/preset_prompts_list.dart` | await `toggleMessageEnabled`，失败时沿用现有 settings 提示辅助方法，避免未处理 Future。 |
| `test/core/persistence/versioned_json_storage_test.dart` | 增加 object envelope 与 legacy-object decode，不改变列表测试。 |
| `test/features/settings/application/settings_import_executor_test.dart` | 删除 `_ExecutorHarness`/真实 `Ref`；以 recording targets 直接测试类型化依赖、顺序和异常停止。 |
| `test/features/settings/application/custom_headers_controller_test.dart`、`font_size_settings_controller_test.dart`、`output_processing_settings_controller_test.dart`、`../auto_retry_settings_controller_test.dart` | 保留可观察的恢复/保存行为，补 legacy→versioned migration、写入失败 state 不变/Future 失败；共享测试 helper，避免重复 JSON setup。 |
| `test/features/settings/data/chat_defaults_repository_test.dart`、`llm_model_config_repository_test.dart` | 更新为 versioned envelope、legacy fallback 与 commit 失败契约。 |
| `test/features/settings/data/model_list_client_test.dart` | import 新 domain entry 类型；继续只验证 HTTP parsing/headers/error，不测试 workflow。 |
| `test/features/settings/presentation/import_confirm_dialog_test.dart` | 覆盖成功、取消和写入失败不关闭；不再把 controller 装配细节当 dialog 行为。 |
| `test/features/settings/presentation/model_config_form_dialog_test.dart` | 用 application catalog callback fake，保留加载、错误、选择和 batch add 用户行为。 |
| `test/features/settings/settings_screen/settings_screen_test_helpers.dart` | 为 workflow/catalog provider 注入 fake 或 application overrides；移除测试对 Screen 内 SharedPreferences/HTTP client 的假设。 |
| `test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart`、`settings_screen_models_and_prompts_cases.dart`、`settings_screen_fixed_prompt_sequences_cases.dart` | 保留既有用户交互；新增 tab 记忆、导入准备结果及 catalog callback 的行为断言，不读取 Screen 私有实现。 |

### 明确不修改

- `lib/features/sync/**`、sync importer/snapshot/protocol/auth：属于 Phase 7 / Phase 8。
- `lib/bootstrap.dart`：仍注入 `sharedPreferencesProvider`，新增 core adapter 从该既有注入派生，无启动顺序调整。
- `lib/core/http/**`、`lib/core/logging/**`：Phase 3 的 HTTP 信任域和日志边界不回退、不扩展。
- SQLite schema、迁移、`SqliteEntityRepository` replace-all 算法：不为小集合预先做增量 CRUD。
- Riverpod 3、`SharedPreferences`、sqlite3、`package:http`、go_router 以及任何代码生成/新状态管理方案。
- `SettingsExportData` 的 identifier、`formatVersion`、JSON 对外格式：本 Phase 仅消费其已有格式，不引入 sync snapshot 格式。

## 四、实施任务、测试策略与提交节点

> 每项先写失败测试，再写最小实现，再跑该项定向测试。命令在 PowerShell 执行时始终遵循项目重定向规则；提交在 **Bash** 执行，使用 Conventional Commit 第一行。post-commit hook 的正常 version bump 会 amend 回本提交。

### Task 1：建立可验证的版本化对象 store

**Files:**

- Create: `lib/core/persistence/settings_key_value_store.dart`
- Create: `lib/core/persistence/versioned_json_store.dart`
- Modify: `lib/core/persistence/versioned_json_storage.dart`
- Modify: `lib/core/persistence/shared_preferences_provider.dart`
- Create: `test/core/persistence/versioned_json_store_test.dart`
- Modify: `test/core/persistence/versioned_json_storage_test.dart`

- [ ] **Step 1: 写 object envelope 与 commit 失败的失败测试。**

  使用 `_FakeSettingsKeyValueStore`（`stringValues`、`intValues`、`nextWriteResult`、`writeError`）验证以下外部契约：

  ```dart
  test('loads legacy object then saves a versioned object envelope', () async {
    final storage = _FakeSettingsKeyValueStore(
      stringValues: {'settings.font_size': '{"bodyFontSize":18}'},
    );
    final store = VersionedJsonStore<FontSizeSettings>(
      storage: storage,
      key: 'settings.font_size',
      subject: 'font size settings',
      fallback: () => const FontSizeSettings(),
      fromJson: FontSizeSettings.fromJson,
      toJson: (value) => value.toJson(),
    );

    expect(store.load().bodyFontSize, 18);
    await store.save(const FontSizeSettings(bodyFontSize: 20));
    expect(jsonDecode(storage.values['settings.font_size']!), {
      'version': VersionedJsonStorage.currentSchemaVersion,
      'value': {'bodyFontSize': 20},
    });
  });

  test('save completes with an error when preferences rejects the write', () async {
    final storage = _FakeSettingsKeyValueStore(nextWriteResult: false);
    final store = /* same typed store */;

    await expectLater(
      store.save(const FontSizeSettings(bodyFontSize: 20)),
      throwsA(isA<StateError>()),
    );
  });
  ```

  同一文件用参数化数据覆盖：缺 key → fallback、损坏 JSON → fallback、`version: current + 1` → fallback、`version` 字符串 → fallback、底层 write 抛异常 → 原异常传播。`versioned_json_storage_test.dart` 只补 `encodeObject/decodeObject`、legacy map 与 future version；既有 `encodeObjectList/decodeObjectList` 断言不改。

- [ ] **Step 2: 运行新测试并确认当前缺少 API。**

  ```powershell
  flutter test test/core/persistence/versioned_json_store_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-store.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-store.log
  ```

  预期：`EXIT≠0`，报缺少 `SettingsKeyValueStore` / `VersionedJsonStore` / object codec；不是测试环境或 Flutter framework 失败。

- [ ] **Step 3: 实现最小 core contract。**

  `settings_key_value_store.dart` 只包含：

  ```dart
  abstract interface class SettingsKeyValueStore {
    String? getString(String key);
    Future<bool> setString(String key, String value);
    int? getInt(String key);
    Future<bool> setInt(String key, int value);
  }

  final class SharedPreferencesSettingsKeyValueStore
      implements SettingsKeyValueStore {
    const SharedPreferencesSettingsKeyValueStore(this._preferences);
    final SharedPreferences _preferences;

    @override
    String? getString(String key) => _preferences.getString(key);

    @override
    Future<bool> setString(String key, String value) =>
        _preferences.setString(key, value);

    @override
    int? getInt(String key) => _preferences.getInt(key);

    @override
    Future<bool> setInt(String key, int value) => _preferences.setInt(key, value);
  }
  ```

  `VersionedJsonStorage.encodeObject` 写 `version/value`；`decodeObject` 对存在 `value` 的 wrapper 校验 version 与 map value，对没有 `value` 的 map 返回 legacy map。`VersionedJsonStore.load` 捕获 decode/fromJson 的 `FormatException`、`TypeError` 与 JSON format failure 后调用 `fallback`；`save` 在 `await setString` 为 `false` 时抛 `StateError('Failed to persist $subject.')`。不要捕获 write 异常。

  在 `shared_preferences_provider.dart` 新增：

  ```dart
  final settingsKeyValueStoreProvider = Provider<SettingsKeyValueStore>((ref) {
    return SharedPreferencesSettingsKeyValueStore(
      ref.watch(sharedPreferencesProvider),
    );
  });
  ```

- [ ] **Step 4: 运行 core 测试。**

  ```powershell
  flutter test test/core/persistence/versioned_json_storage_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-storage-codec.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-storage-codec.log
  flutter test test/core/persistence/versioned_json_store_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-store.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-store.log
  ```

  预期：两条均 `EXIT=0`。

- [ ] **Step 5: 提交 core 持久化契约。**

  ```bash
  git add lib/core/persistence/settings_key_value_store.dart \
          lib/core/persistence/versioned_json_store.dart \
          lib/core/persistence/versioned_json_storage.dart \
          lib/core/persistence/shared_preferences_provider.dart \
          test/core/persistence/versioned_json_store_test.dart \
          test/core/persistence/versioned_json_storage_test.dart
  git commit -m "refactor(settings): 建立版本化 JSON 存储契约"
  ```

### Task 2：迁移小型 SharedPreferences 设置并统一 durable commit

**Files:**

- Modify: `lib/features/settings/application/auto_retry_settings_controller.dart`
- Modify: `lib/features/settings/application/custom_headers_controller.dart`
- Modify: `lib/features/settings/application/font_size_settings_controller.dart`
- Modify: `lib/features/settings/application/output_processing_settings_controller.dart`
- Modify: `lib/features/settings/data/chat_defaults_repository.dart`
- Modify: `lib/features/settings/data/llm_model_config_repository.dart`
- Modify: `lib/features/settings/application/chat_defaults_controller.dart`
- Modify: `lib/features/settings/application/llm_model_configs_controller.dart`
- Modify: `test/features/settings/auto_retry_settings_controller_test.dart`
- Modify: `test/features/settings/application/custom_headers_controller_test.dart`
- Modify: `test/features/settings/application/font_size_settings_controller_test.dart`
- Modify: `test/features/settings/application/output_processing_settings_controller_test.dart`
- Modify: `test/features/settings/data/chat_defaults_repository_test.dart`
- Modify: `test/features/settings/data/llm_model_config_repository_test.dart`

- [ ] **Step 1: 为四个 scalar controller 与 chat defaults 写失败测试。**

  每个 scalar controller 用 `keyValueStringStoreProvider` override 注入同一个 fake，验证以下表驱动场景，而非复制四套 JSON 断言：

  | 情况 | 预期 |
  |---|---|
  | 旧裸 JSON | build 恢复原设置；下一次成功 save 写 `version/value`。 |
  | 空、损坏、future version | build 返回该模型现有默认值。 |
  | store 返回 false / throw | `save` Future 失败，provider state 等于保存前值。 |
  | 成功 save | Future 完成后 state 更新；新 container 恢复相同值。 |

  对 `FontSizeSettingsController` 单独保留 `updateLocal` 测试：它更新 state 且不写 fake；随后失败的 `save` 不应把失败目标值伪装成 durable state。

  `ChatDefaultsRepository` 测试改为：legacy 裸 JSON 能读取、损坏/future version 回到 `const ChatDefaults()`、`save` 在 false 时抛异常。`LlmModelConfigRepository` 补 `setString == false` 时 `saveProviders` Future 异常；不改变 provider/model 排序测试。

- [ ] **Step 2: 运行设置持久化测试并确认它们在迁移前失败。**

  ```powershell
  flutter test test/features/settings/auto_retry_settings_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-auto-retry.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-auto-retry.log
  flutter test test/features/settings/application/custom_headers_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-headers.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-headers.log
  flutter test test/features/settings/data/chat_defaults_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-chat-defaults.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-chat-defaults.log
  ```

  预期：新增 legacy-envelope/失败 state 测试失败；现有行为测试仍可通过。

- [ ] **Step 3: 将 controller/repository 改为 store 依赖。**

  每个 scalar controller 建一个类型化 store provider（key、subject、默认值、`fromJson`、`toJson` 都在该模型附近声明），并将实现压缩为以下模式：

  ```dart
  @override
  AutoRetrySettings build() => ref.read(autoRetrySettingsStoreProvider).load();

  Future<void> save(AutoRetrySettings settings) async {
    await ref.read(autoRetrySettingsStoreProvider).save(settings);
    state = settings;
  }
  ```

  `CustomHeadersController.addHeader/removeHeader/updateHeader` 保持原 public API，只继续 `await save(next)`。`ChatDefaultsRepository` 持有 typed store 而非裸 `SharedPreferences`，其 `load` 不再因本地损坏 JSON 抛出。`LlmModelConfigRepository` 不迁移 list wrapper 格式，但经 `SettingsKeyValueStore` 保存并检查 `true`；Controller 的现有 `await _repository.save...` 继续传播 commit failure。不得将五个模型合并到一个按 key 分支的 settings manager。

- [ ] **Step 4: 跑所有受影响测试。**

  ```powershell
  flutter test test/features/settings/auto_retry_settings_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-auto-retry.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-auto-retry.log
  flutter test test/features/settings/application/custom_headers_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-headers.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-headers.log
  flutter test test/features/settings/application/font_size_settings_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-font-size.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-font-size.log
  flutter test test/features/settings/application/output_processing_settings_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-output-processing.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-output-processing.log
  flutter test test/features/settings/data/chat_defaults_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-chat-defaults.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-chat-defaults.log
  flutter test test/features/settings/data/llm_model_config_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-model-repository.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-model-repository.log
  ```

  预期：所有命令 `EXIT=0`。

- [ ] **Step 5: 提交小设置迁移。**

  ```bash
  git add lib/features/settings/application/auto_retry_settings_controller.dart \
          lib/features/settings/application/custom_headers_controller.dart \
          lib/features/settings/application/font_size_settings_controller.dart \
          lib/features/settings/application/output_processing_settings_controller.dart \
          lib/features/settings/application/chat_defaults_controller.dart \
          lib/features/settings/application/llm_model_configs_controller.dart \
          lib/features/settings/data/chat_defaults_repository.dart \
          lib/features/settings/data/llm_model_config_repository.dart \
          test/features/settings/auto_retry_settings_controller_test.dart \
          test/features/settings/application/custom_headers_controller_test.dart \
          test/features/settings/application/font_size_settings_controller_test.dart \
          test/features/settings/application/output_processing_settings_controller_test.dart \
          test/features/settings/data/chat_defaults_repository_test.dart \
          test/features/settings/data/llm_model_config_repository_test.dart
  git commit -m "refactor(settings): 统一小设置持久化完成语义"
  ```

### Task 3：修复 SQLite settings mutation 的 Future 契约

**Files:**

- Modify: `lib/features/settings/application/settings_entity_controller.dart`
- Modify: `lib/features/settings/application/preset_prompts_controller.dart`
- Modify: `lib/features/settings/presentation/widgets/list/preset_prompts_list.dart`
- Create: `test/features/settings/application/settings_entity_controller_test.dart`
- Modify: `test/features/settings/application/settings_import_executor_test.dart`（仅为后续 executor 改造前的现有 await 断言做准备）

- [ ] **Step 1: 写成功与失败 completion 测试。**

  使用真实 `AppDatabase.inMemory()` 和 `memoryPromptsProvider`：成功路径 `await controller.upsert(memory)` 后用 repository/新 container 验证已落库；失败路径先读取 provider 使 build 完成，再关闭该精确 in-memory database，调用 `controller.upsert(memory)` 并断言：

  ```dart
  await expectLater(
    controller.upsert(memory),
    throwsA(isA<Object>()),
  );
  ```

  失败断言的重点是 Future **不应在实际 `saveAll` 抛出前成功完成**，不锁定 sqlite 的具体 exception class。另测 `preset.toggleMessageEnabled(...)` 返回 `Future<void>`，await 后再查持久化的 message enabled 值；找不到 preset 时是成功的 no-op Future。

- [ ] **Step 2: 运行测试确认 `_commit()` 未传递导致失败用例红灯。**

  ```powershell
  flutter test test/features/settings/application/settings_entity_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-entity-commit.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-entity-commit.log
  ```

  预期：关闭 DB 的 mutation 当前会过早成功，新增 `throwsA` 失败。

- [ ] **Step 3: 返回真实 commit Future，并在成功后发布 state。**

  将三个方法改成 return 形式，不能保留未 await 的调用：

  ```dart
  Future<void> upsert(T item) {
    final items = [...state];
    // 保留既有按 id 合并逻辑。
    return _commit(items);
  }

  Future<void> _commit(List<T> items) async {
    items.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final nextState = List<T>.unmodifiable(items);
    await repository.saveAll(ref.read(appDatabaseProvider), nextState);
    state = nextState;
  }
  ```

  `upsertAll/deleteById` 同样 `return _commit(...)`。`toggleMessageEnabled` 改成 `Future<void>` 并将 `upsert` Future 返回；list widget 的 callback 显式 `await`，catch 后走已有 `showSettingsSnackbar`，不要 fire-and-forget。不要替换 `SqliteEntityRepository.saveAll` 的 transaction 或 replace-all。

- [ ] **Step 4: 运行定向测试。**

  ```powershell
  flutter test test/features/settings/application/settings_entity_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-entity-commit.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-entity-commit.log
  flutter test test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-screen-existing.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-screen-existing.log
  ```

  预期：均 `EXIT=0`；第二条确保现有编辑、删除和切换行为未因 completion 时机回归。

- [ ] **Step 5: 提交 Future 修复。**

  ```bash
  git add lib/features/settings/application/settings_entity_controller.dart \
          lib/features/settings/application/preset_prompts_controller.dart \
          lib/features/settings/presentation/widgets/list/preset_prompts_list.dart \
          test/features/settings/application/settings_entity_controller_test.dart \
          test/features/settings/application/settings_import_executor_test.dart
  git commit -m "fix(settings): 传递实体设置提交的完成结果"
  ```

### Task 4：建立类型化导入与 transfer workflow

**Files:**

- Create: `lib/features/settings/application/settings_import_targets.dart`
- Modify: `lib/features/settings/application/settings_import_executor.dart`
- Create: `lib/features/settings/application/settings_transfer_workflow.dart`
- Modify: `lib/features/settings/presentation/widgets/import_confirm_dialog.dart`
- Modify: `test/features/settings/application/settings_import_executor_test.dart`
- Create: `test/features/settings/application/settings_transfer_workflow_test.dart`
- Modify: `test/features/settings/presentation/import_confirm_dialog_test.dart`

- [ ] **Step 1: 将 executor 测试替换为无 Riverpod/dynamic 的 recording targets。**

  删除 `_ExecutorHarness`，以纯 Dart `_RecordingTargets` 收集每类 payload。直接构造：

  ```dart
  final executor = SettingsImportExecutor(
    targets: SettingsImportTargets(
      mergeImportedProviders: targets.recordProviders,
      upsertMemoryPrompts: targets.recordMemoryPrompts,
      // 显式填完九个目标；没有 optional/dynamic fallback。
    ),
  );
  ```

  覆盖：(1) full payload 每类恰好收到一次；(2) 空 payload 返回 false 且零 callback；(3) 任一 callback 抛出时 `executeImport` Future 抛出并停止后续写入；(4) 所有 callback 成功时 Future 完成后 assertions 才成立。测试源码不 import `flutter_riverpod`、`ProviderContainer`、`Ref`。

  `SettingsTransferWorkflow` 测试以显式 state getter 注入 fixtures，验证：每个 tab 只创建原来相同字段的 `SettingsExportData`；空 tab 返回 null；无效 text、tab mismatch、全部重复分别得到三个准备状态；ready 中保留 deduped items 与 scalar settings。它不调用 executor，也不触碰 Clipboard。

- [ ] **Step 2: 运行新 application 测试并确认当前 API 不存在。**

  ```powershell
  flutter test test/features/settings/application/settings_import_executor_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-import-executor.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-import-executor.log
  flutter test test/features/settings/application/settings_transfer_workflow_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-transfer.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-transfer.log
  ```

  预期：第一个因构造签名仍是 `dynamic ref`，第二个因 workflow 缺失而失败。

- [ ] **Step 3: 实现 type-safe targets 与 workflow provider。**

  `SettingsImportExecutor` 只遍历数据并 `await targets.<typed callback>(...)`；不 import Riverpod。`settingsImportExecutorProvider` 放在 application 层，逐一绑定现有 notifier 的 `mergeImportedProviders/upsertAll/save`，让编译器验证九个依赖。

  `SettingsTransferWorkflow` 采用 constructor-injected typed read callbacks；其 provider 从 settings providers 构造这些 callbacks。`SettingsImportPreparation` 为 sealed/enum + data object，Screen 仅 switch 状态映射已有中文文案。不得在此层调用 `Clipboard`、`showDialog` 或 sync API。

  `ImportConfirmDialog._handleImport` 改为：

  ```dart
  Future<void> _handleImport() async {
    setState(() => _isImporting = true);
    try {
      await ref.read(settingsImportExecutorProvider).executeImport(
        data: widget.exportData,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      showSettingsSnackbar(context, '导入失败：$error');
    }
  }
  ```

  只在成功时关闭；取消行为不变。

- [ ] **Step 4: 运行 application 与 dialog 测试。**

  ```powershell
  flutter test test/features/settings/application/settings_import_executor_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-import-executor.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-import-executor.log
  flutter test test/features/settings/application/settings_transfer_workflow_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-transfer.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-transfer.log
  flutter test test/features/settings/presentation/import_confirm_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-import-dialog.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-import-dialog.log
  ```

  预期：均 `EXIT=0`。失败 dialog 测试断言 dialog 仍存在、导入按钮重新可点、无成功回传，而不是检查其 private `_isImporting` 字段。

- [ ] **Step 5: 提交导入工作流边界。**

  ```bash
  git add lib/features/settings/application/settings_import_targets.dart \
          lib/features/settings/application/settings_import_executor.dart \
          lib/features/settings/application/settings_transfer_workflow.dart \
          lib/features/settings/presentation/widgets/import_confirm_dialog.dart \
          test/features/settings/application/settings_import_executor_test.dart \
          test/features/settings/application/settings_transfer_workflow_test.dart \
          test/features/settings/presentation/import_confirm_dialog_test.dart
  git commit -m "refactor(settings): 类型化导入与传输工作流"
  ```

### Task 5：迁移 tab preference 与 model catalog workflow

**Files:**

- Create: `lib/features/settings/application/settings_tab_preferences.dart`
- Create: `lib/features/settings/application/model_catalog_workflow.dart`
- Create: `lib/features/settings/domain/models/model_catalog_entry.dart`
- Modify: `lib/features/settings/data/model_list_client.dart`
- Modify: `lib/features/settings/presentation/widgets/form/model_fetch_section.dart`
- Modify: `lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart`
- Create: `test/features/settings/application/settings_tab_preferences_test.dart`
- Create: `test/features/settings/application/model_catalog_workflow_test.dart`
- Modify: `test/features/settings/data/model_list_client_test.dart`
- Modify: `test/features/settings/presentation/model_config_form_dialog_test.dart`

- [ ] **Step 1: 写 tab preference 及 model catalog workflow 的失败测试。**

  `SettingsTabPreferences` 用 fake key-value store 验证旧 schema 的 index 迁移保持当前 mapping（v1 3↔4，v3 4↔5）、初始值 clamp 到 `0..5`、迁移后的 index/version 一起写入、tab change 的 Future 要等 `setInt` 的 durable adapter 成功。不要测试 `TabController` 内部动画。

  `ModelCatalogWorkflow` 以 fake fetcher 验证：

  ```dart
  final result = await workflow.fetch(
    const ModelCatalogRequest(
      apiUrl: 'https://api.example.com/v1/chat/completions',
      apiKey: 'sk-test',
    ),
  );
  expect(capturedUrl, 'https://api.example.com/v1/models');
  expect(result, [const ModelCatalogEntry(id: 'gpt-4o')]);
  ```

  再覆盖非空 override 不被重推导、`ModelListException` 转为 `ModelCatalogFailure` 并保持 message/responseBody。UI dialog 测试的 fetch fake 改为 request → `ModelCatalogEntry` 列表或 `ModelCatalogFailure`，原有 loading/error/selection/batch-add 行为断言保持。

- [ ] **Step 2: 运行测试确认 application contract 未实现。**

  ```powershell
  flutter test test/features/settings/application/settings_tab_preferences_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-tab-preferences.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-tab-preferences.log
  flutter test test/features/settings/application/model_catalog_workflow_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-catalog.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-catalog.log
  ```

  预期：均因新 contract 缺失失败。

- [ ] **Step 3: 实现 workflow，保持 data HTTP 行为不变。**

  将现有 `_migrateTabIndex`、key 和 current version 移进 `SettingsTabPreferences`；`loadInitialIndex(tabCount: 6)` 负责 migration 和 clamp，`saveIndex` 负责 durable write。Screen 不再保留这些 persistence constants 或 import core persistence。

  把无 HTTP 依赖的 `RemoteModelInfo` 更名/移动为 domain `ModelCatalogEntry`。`ModelListClient.fetchModels` 的返回类型改为 `Future<List<ModelCatalogEntry>>`，URL、header、日志、timeout、response parsing 与 `ModelListException` 均不变。workflow 内部处理 default/override URL，并只将 `ModelListException` 映射为 application `ModelCatalogFailure`；未知异常也归一为有 message 的 failure。presentation 只 import `model_catalog_workflow.dart` 和 domain entry，绝不 import `data/model_list_client.dart` 或 `data/model_list_url.dart`。

- [ ] **Step 4: 运行迁移相关测试。**

  ```powershell
  flutter test test/features/settings/application/settings_tab_preferences_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-tab-preferences.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-tab-preferences.log
  flutter test test/features/settings/application/model_catalog_workflow_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-catalog.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-catalog.log
  flutter test test/features/settings/data/model_list_client_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-model-client.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-model-client.log
  flutter test test/features/settings/presentation/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-model-dialog.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-model-dialog.log
  ```

  预期：均 `EXIT=0`。

- [ ] **Step 5: 提交 tab/catalog application 边界。**

  ```bash
  git add lib/features/settings/application/settings_tab_preferences.dart \
          lib/features/settings/application/model_catalog_workflow.dart \
          lib/features/settings/domain/models/model_catalog_entry.dart \
          lib/features/settings/data/model_list_client.dart \
          lib/features/settings/presentation/widgets/form/model_fetch_section.dart \
          lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart \
          test/features/settings/application/settings_tab_preferences_test.dart \
          test/features/settings/application/model_catalog_workflow_test.dart \
          test/features/settings/data/model_list_client_test.dart \
          test/features/settings/presentation/model_config_form_dialog_test.dart
  git commit -m "refactor(settings): 提取标签与模型目录工作流"
  ```

### Task 6：让 SettingsScreen 回到 UI 组合职责并完成回归

**Files:**

- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart`
- Modify: `test/features/settings/settings_screen_test.dart`（仅入口 import/register 有需要时）

- [ ] **Step 1: 写 Screen 层用户行为回归测试。**

  用 `pumpTestApp()`/现有 helper 装配真实 settings application providers 和 fake catalog workflow。新增场景：

  1. 以迁移过的 tab index 启动时显示对应 tab 内容，并在点击另一 tab 后重新挂载仍从 application preference 读取该 index；
  2. 导出当前 providers tab 时 Clipboard 得到既有 `SettingsExportData.toJsonString()` 格式；空数据仍显示原提示；
  3. 导入无效文本、tab 不匹配、全重复分别显示既有提示，ready 才打开 confirm dialog；取消不改状态；
  4. 从 API 拉取模型经 fake catalog workflow 返回 entry 后，选择并提交仍创建相同模型。

  测试只断言文本、dialog、Clipboard payload 和 provider 可观察状态；不以 `find.byKey`、Screen 私有字段、像素位置或 widget 属性验证 implementation detail。核心 dedup/parse/callback 顺序继续由 application tests 覆盖，Screen 测试不重复它们。

- [ ] **Step 2: 将 Screen 改为 application consumer。**

  - 删除 `shared_preferences_provider.dart`、`model_list_client.dart`、`settings_import_deduplicator.dart` 与 `settings_export_data.dart` 的 direct business imports。
  - `initState` 调用 `settingsTabPreferencesProvider.loadInitialIndex(tabCount: 6)`；tab listener 调用并处理 `saveIndex` Future，Screen 只维持 controller 与 `setState`。
  - `_exportCurrentTab` 通过 `settingsTransferWorkflowProvider.buildExportData(SettingsTransferTab.values[index])` 获取 data；Clipboard 写入和现有成功/空通知留在 Screen。
  - `_importToCurrentTab` 只取 Clipboard text，调用 workflow `prepareImport`，按 result 展示已有文案或 `showDialog(ImportConfirmDialog)`；不再直接 read 十余个 providers 或调用 deduplicator。
  - `_showModelConfigDialog` 传 `ref.read(modelCatalogWorkflowProvider).fetch`；表单不再拿 data client method tear-off。

  现有新增/编辑/复制 prompt、form dialog 和 tab 视觉树不重构。不要将 Clipboard 移到 application（它是 Flutter presentation platform interaction），不要从 Screen 创建任何 sync facade。

- [ ] **Step 3: 运行 Settings widget 回归。**

  ```powershell
  flutter test test/features/settings/settings_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-settings-screen.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase5-settings-screen.log
  flutter test test/features/settings/presentation/import_confirm_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-import-dialog-final.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-import-dialog-final.log
  flutter test test/features/settings/presentation/model_config_form_dialog_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase5-model-dialog-final.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 120 fltest-phase5-model-dialog-final.log
  ```

  预期：三条均 `EXIT=0`。

- [ ] **Step 4: 做静态边界检查。**

  ```powershell
  rg -n "sharedPreferencesProvider|SharedPreferences|modelListClientProvider|ModelListClient|SettingsImportDeduplicator" lib/features/settings/presentation/settings_screen.dart lib/features/settings/presentation/widgets/import_confirm_dialog.dart lib/features/settings/presentation/widgets/form/model_fetch_section.dart lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart
  rg -n "dynamic ref|executeImport\(dynamic" lib/features/settings test/features/settings
  ```

  预期：两条均无输出。`Clipboard` 命中允许保留在 `settings_screen.dart`；它不是 persistence/data client。

- [ ] **Step 5: 提交 Screen 边界收敛。**

  ```bash
  git add lib/features/settings/presentation/settings_screen.dart \
          test/features/settings/settings_screen/settings_screen_test_helpers.dart \
          test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart \
          test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart \
          test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart \
          test/features/settings/settings_screen_test.dart
  git commit -m "refactor(settings): 收敛设置页工作流边界"
  ```

### Task 7：最终质量门禁与范围复核

**Files:**

- Modify only if prior verification发现格式、分析或测试问题；不趁机加入任何范围外清理。

- [ ] **Step 1: 格式化本 Phase 触及的 Dart 文件。**

  ```powershell
  dart format lib/core/persistence/settings_key_value_store.dart lib/core/persistence/versioned_json_store.dart lib/core/persistence/versioned_json_storage.dart lib/core/persistence/shared_preferences_provider.dart lib/features/settings/application lib/features/settings/data/chat_defaults_repository.dart lib/features/settings/data/llm_model_config_repository.dart lib/features/settings/data/model_list_client.dart lib/features/settings/domain/models/model_catalog_entry.dart lib/features/settings/presentation/settings_screen.dart lib/features/settings/presentation/widgets/import_confirm_dialog.dart lib/features/settings/presentation/widgets/form/model_fetch_section.dart lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart test/core/persistence/versioned_json_store_test.dart test/core/persistence/versioned_json_storage_test.dart test/features/settings
  ```

- [ ] **Step 2: 运行 analyze。**

  ```powershell
  flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase5-final.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase5-final.log
  ```

  预期：`EXIT=0`、`No issues found!`。

- [ ] **Step 3: 按项目强制方式运行全量测试。**

  ```powershell
  flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
  ```

  预期：`EXIT=0`、末尾 `All tests passed!`。若失败，使用 `Select-String -Pattern "失败测试名" -Path fltest.log -Context 0,30` 定位，修复仅限造成失败的本 Phase 文件后重跑。

- [ ] **Step 4: 进行 completion/range 审计。**

  ```powershell
  rg -n "Future<.*> (upsert|upsertAll|deleteById|toggleMessageEnabled)|_commit\(" lib/features/settings/application
  rg -n "dynamic ref|executeImport\(dynamic" lib/features/settings test/features/settings
  git diff --check
  git diff --name-only HEAD~6..HEAD
  ```

  审计标准：公开 durable mutation 都 return/await实际 commit；只剩 `updateLocal` 这类文档明确的内存预览方法可为同步；无 `dynamic ref`；无空白错误；变更不包含 `features/sync`、协议/auth、全局 port 搬迁或 SQLite incremental CRUD。

- [ ] **Step 5: 处理最终门禁发现的问题。**

  仅修复由 Step 2–4 直接暴露、且位于本 Phase File Scope 内的问题；对每个修复重复对应的定向测试、`flutter analyze` 与全量测试。将这类确有必要的修复作为独立 `fix(settings):` 或 `test(settings):` 提交，提交文件清单必须等于该失败的最小修复集；没有失败时不创建空提交。

## 五、提交序列总览

| 节点 | Commit message | 独立价值 |
|---|---|---|
| 1 | `refactor(settings): 建立版本化 JSON 存储契约` | core 可测试的 key/value、object version 与 commit 成功确认。 |
| 2 | `refactor(settings): 统一小设置持久化完成语义` | 标量设置与 chat defaults 的兼容读取、fallback、durable commit 一致。 |
| 3 | `fix(settings): 传递实体设置提交的完成结果` | SQLite replace-all mutation 不再过早完成。 |
| 4 | `refactor(settings): 类型化导入与传输工作流` | 消除 dynamic service locator，形成 settings 内部可测试导入/export preparation。 |
| 5 | `refactor(settings): 提取标签与模型目录工作流` | presentation 不再直接使用 persistence/data client。 |
| 6 | `refactor(settings): 收敛设置页工作流边界` | SettingsScreen 回归 UI composition。 |
| 7（可选） | `test(settings): 补齐工作流契约回归` | 仅用于最终门禁暴露的、本 Phase 内的精确修复。 |

## 六、验收矩阵与范围护栏

| Phase 5 验收项 | 对应任务/证据 |
|---|---|
| Import 不再接受 `dynamic ref`，依赖可由编译器检查 | Task 4 的 `SettingsImportTargets`、无 `dynamic ref` rg 审计、无 Riverpod 的 executor 测试。 |
| 小设置持久化/版本/fallback/提交语义一致，且无无收益 repository 化 | Task 1–2；每个 scalar 使用泛型 store，保留 Controller；model list 继续合理的 versioned list repository。 |
| 公共 async mutation 的 Future 表示实际 commit 成功或失败 | Task 2 fake false/throw、Task 3 closed-DB test、Task 4 executor callback failure。 |
| 小集合保持 replace-all，仅明确边界 | Task 3 只改 Future/state 发布顺序；不改 `SqliteEntityRepository` 和 schema。 |
| Screen 不再直接读 persistence 或编排 ModelListClient/transfer | Task 5–6 import 扫描与 widget tests；Clipboard/dialog 仍留 presentation。 |
| 导入、去重、取消、失败、成功均覆盖 | Task 4 application + dialog tests，Task 6 Screen path tests。 |
| 旧版本、坏 JSON、fallback 回归保护 | Task 1 core tests，Task 2 legacy scalar/chat-defaults tests。 |
| 不提前 Phase 7/8/11 | diff name 审计；不新增 sync facade/protocol/auth，不将全项目 repository 接口 port 化。 |

## 七、计划自检

- **Phase 覆盖：** TD-03 对应 Task 4；TD-22 对应 Task 1–2；TD-23 对应 Task 3；TD-26 对应 Task 5–6。每一项 Verification Requirement 都在第六节映射到可运行命令和测试。
- **类型一致性：** `SettingsImportTargets` 是 executor 唯一写入依赖；`SettingsImportPreparation` 是 transfer 到 Screen 的唯一准备结果；`ModelCatalogRequest/Entry/Failure` 是 catalog workflow 到 presentation 的唯一合同；没有把未来 `SettingsSnapshot` 作为本 Phase 类型。
- **占位检查：** 实施步骤没有 TBD/TODO 或需要工程师自行补齐的实现内容；前六个正常提交均列出精确文件，最终门禁仅在确有失败时创建最小修复提交。
- **范围检查：** 没有变更 sync、HTTP/logging、schema/迁移、vendor、导航、响应式或可访问性主题；没有改既有技术选型。
