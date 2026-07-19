# 同步去重修复 + 收藏页增强 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复同步时标量型设置不去重的 Bug，并为收藏页增加重命名和移动收藏项功能。

**Architecture:** 在 `SettingsImportDeduplicator.deduplicate()` 中增加标量型配置的相等性比较，两端一致时置 null。在 `Favorite` 模型新增 `title` 字段并做 DB V10 迁移，详情页增加重命名和移动收藏夹入口。

**Tech Stack:** Flutter, Riverpod, SQLite (sqlite3), Equatable

## Global Constraints

- 注释使用简体中文，`///` 用于 doc 注释，`//` 用于行间注释
- 禁止 `part` / `part of`
- 测试命令：`flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
- Lint 命令：`flutter analyze`
- DB schema 版本用 `>=` 断言，不用 `==`

---

### Task 1: 修复 SettingsImportDeduplicator 标量型配置去重

**Files:**
- Modify: `lib/features/settings/application/settings_import_deduplicator.dart`
- Test: `test/features/settings/application/settings_import_deduplicator_test.dart`

**Interfaces:**
- Produces: `deduplicate()` 新增 3 个可选参数 `existingAutoRetrySettings`、`existingCustomHeadersConfig`、`existingFontSizeSettings`，类型均为可空标量类型

- [ ] **Step 1: 修改测试文件中的 `export()` 工厂和现有透传测试**

在 `test/features/settings/application/settings_import_deduplicator_test.dart` 中：

1. 在 `export()` 工厂函数中加入 `customHeadersConfig` 参数：

```dart
  SettingsExportData export({
    List<LlmProviderConfig> modelProviders = const [],
    List<MemoryPrompt> memoryPrompts = const [],
    List<PresetPrompt> presetPrompts = const [],
    List<TemplatePrompt> templatePrompts = const [],
    List<FixedPromptSequence> fixedPromptSequences = const [],
    AutoRetrySettings? autoRetrySettings,
    FontSizeSettings? fontSizeSettings,
    CustomHeadersConfig? customHeadersConfig,
  }) {
    return SettingsExportData(
      modelProviders: modelProviders,
      memoryPrompts: memoryPrompts,
      presetPrompts: presetPrompts,
      templatePrompts: templatePrompts,
      fixedPromptSequences: fixedPromptSequences,
      autoRetrySettings: autoRetrySettings,
      fontSizeSettings: fontSizeSettings,
      customHeadersConfig: customHeadersConfig,
    );
  }
```

2. 在文件顶部加入 import：

```dart
import 'package:oh_my_llm/features/settings/domain/models/custom_headers_config.dart';
```

3. 将现有两个透传测试改为传入 `existingAutoRetrySettings` 参数（保持旧行为：不传 existing 时仍透传）。将"保留 autoRetrySettings（透传，不做去重）"测试改为：

```dart
    test('不传 existingAutoRetrySettings 时 autoRetrySettings 透传', () {
      const autoRetry = AutoRetrySettings(maxJitterSeconds: 20, maxRetryCount: 5);
      final data = export(
        memoryPrompts: [mem(content: '新记忆')],
        autoRetrySettings: autoRetry,
      );

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      expect(result.autoRetrySettings, isNotNull);
      expect(result.autoRetrySettings!.maxJitterSeconds, 20);
      expect(result.autoRetrySettings!.maxRetryCount, 5);
      expect(result.memoryPrompts.length, 1);
    });
```

将"在 data 仅含 autoRetry 时 hasContent 为 true"测试改为：

```dart
    test('不传 existingAutoRetrySettings 时 data 仅含 autoRetry 则 hasContent 为 true', () {
      final data = export(
        autoRetrySettings: const AutoRetrySettings(),
      );

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );

      expect(result.hasContent, isTrue);
      expect(result.autoRetrySettings, isNotNull);
    });
```

将"保留 fontSizeSettings（透传，不做去重）"测试改为：

```dart
    test('不传 existingFontSizeSettings 时 fontSizeSettings 透传', () {
      final data = export(
        fontSizeSettings: const FontSizeSettings(bodyFontSize: 18),
      );
      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
      );
      expect(result.fontSizeSettings?.bodyFontSize, 18);
    });
```

- [ ] **Step 2: 添加新的标量配置去重测试**

在 `SettingsImportDeduplicator.deduplicate()` group 末尾添加以下测试：

```dart
    // ── 标量型配置去重 ──────────────────────────────────────────────

    test('autoRetrySettings 与本地一致时去重后为 null', () {
      const autoRetry = AutoRetrySettings(maxJitterSeconds: 20, maxRetryCount: 5);
      final data = export(autoRetrySettings: autoRetry);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingAutoRetrySettings: autoRetry,
      );

      expect(result.autoRetrySettings, isNull);
    });

    test('autoRetrySettings 与本地不同时保留远端值', () {
      const existing = AutoRetrySettings(maxJitterSeconds: 15, maxRetryCount: 0);
      const incoming = AutoRetrySettings(maxJitterSeconds: 30, maxRetryCount: 5);
      final data = export(autoRetrySettings: incoming);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingAutoRetrySettings: existing,
      );

      expect(result.autoRetrySettings, isNotNull);
      expect(result.autoRetrySettings!.maxJitterSeconds, 30);
      expect(result.autoRetrySettings!.maxRetryCount, 5);
    });

    test('customHeadersConfig 与本地一致时去重后为 null', () {
      const config = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-Custom', value: 'test'),
      ]);
      final data = export(customHeadersConfig: config);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingCustomHeadersConfig: config,
      );

      expect(result.customHeadersConfig, isNull);
    });

    test('customHeadersConfig 与本地不同时保留远端值', () {
      const existing = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-Old', value: 'old'),
      ]);
      const incoming = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-New', value: 'new'),
      ]);
      final data = export(customHeadersConfig: incoming);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingCustomHeadersConfig: existing,
      );

      expect(result.customHeadersConfig, isNotNull);
      expect(result.customHeadersConfig!.headers.first.key, 'X-New');
    });

    test('customHeadersConfig 远端为空列表时去重后为 null（与 hasContent 联动）', () {
      const incoming = CustomHeadersConfig(headers: []);
      final data = export(customHeadersConfig: incoming);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingCustomHeadersConfig: const CustomHeadersConfig(),
      );

      expect(result.customHeadersConfig, isNull);
    });

    test('fontSizeSettings 与本地一致时去重后为 null', () {
      const fontSize = FontSizeSettings(bodyFontSize: 18);
      final data = export(fontSizeSettings: fontSize);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingFontSizeSettings: fontSize,
      );

      expect(result.fontSizeSettings, isNull);
    });

    test('fontSizeSettings 与本地不同时保留远端值', () {
      const existing = FontSizeSettings(bodyFontSize: 14);
      const incoming = FontSizeSettings(bodyFontSize: 20);
      final data = export(fontSizeSettings: incoming);

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingFontSizeSettings: existing,
      );

      expect(result.fontSizeSettings, isNotNull);
      expect(result.fontSizeSettings!.bodyFontSize, 20);
    });

    test('全部标量配置与本地一致时 hasContent 为 false', () {
      const autoRetry = AutoRetrySettings(maxJitterSeconds: 20, maxRetryCount: 5);
      const customHeaders = CustomHeadersConfig(headers: [
        CustomHeaderEntry(key: 'X-Custom', value: 'test'),
      ]);
      const fontSize = FontSizeSettings(bodyFontSize: 18);
      final data = export(
        autoRetrySettings: autoRetry,
        customHeadersConfig: customHeaders,
        fontSizeSettings: fontSize,
      );

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingAutoRetrySettings: autoRetry,
        existingCustomHeadersConfig: customHeaders,
        existingFontSizeSettings: fontSize,
      );

      expect(result.hasContent, isFalse);
    });

    test('混合场景：部分一致部分不一致', () {
      const existingAutoRetry = AutoRetrySettings(maxJitterSeconds: 15);
      const incomingAutoRetry = AutoRetrySettings(maxJitterSeconds: 15); // 一致
      const existingFontSize = FontSizeSettings(bodyFontSize: 14);
      const incomingFontSize = FontSizeSettings(bodyFontSize: 20); // 不一致
      final data = export(
        autoRetrySettings: incomingAutoRetry,
        fontSizeSettings: incomingFontSize,
      );

      final result = deduplicator.deduplicate(
        data: data,
        existingProviders: const [],
        existingMemoryPrompts: const [],
        existingPresetPrompts: const [],
        existingTemplatePrompts: const [],
        existingSequences: const [],
        existingAutoRetrySettings: existingAutoRetry,
        existingFontSizeSettings: existingFontSize,
      );

      expect(result.autoRetrySettings, isNull);
      expect(result.fontSizeSettings, isNotNull);
      expect(result.fontSizeSettings!.bodyFontSize, 20);
      expect(result.hasContent, isTrue);
    });
```

- [ ] **Step 3: 运行测试验证新测试失败**

Run: `flutter test --reporter compact test/features/settings/application/settings_import_deduplicator_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: FAIL - 新增的"一致时为 null"测试失败（因为当前透传不比较），旧测试通过

- [ ] **Step 4: 修改 deduplicator 实现加入标量配置去重**

在 `lib/features/settings/application/settings_import_deduplicator.dart` 中：

1. 在文件顶部加入 import：

```dart
import '../domain/models/auto_retry_settings.dart';
import '../domain/models/custom_headers_config.dart';
import '../domain/models/font_size_settings.dart';
```

2. 在 `deduplicate()` 方法签名中加入 3 个可选参数，并在返回时做相等性比较：

将 `deduplicate` 方法签名改为：

```dart
  SettingsExportData deduplicate({
    required SettingsExportData data,
    required List<LlmProviderConfig> existingProviders,
    required List<MemoryPrompt> existingMemoryPrompts,
    required List<PresetPrompt> existingPresetPrompts,
    required List<TemplatePrompt> existingTemplatePrompts,
    required List<FixedPromptSequence> existingSequences,
    AutoRetrySettings? existingAutoRetrySettings,
    CustomHeadersConfig? existingCustomHeadersConfig,
    FontSizeSettings? existingFontSizeSettings,
  }) {
```

3. 在方法体末尾的 `return SettingsExportData(...)` 之前加入标量配置比较逻辑：

```dart
    // ── 标量型配置去重：两端一致时置 null ──────────────────────────
    final dedupAutoRetry = (data.autoRetrySettings != null &&
            data.autoRetrySettings == existingAutoRetrySettings)
        ? null
        : data.autoRetrySettings;

    final dedupCustomHeaders = (data.customHeadersConfig != null &&
            data.customHeadersConfig == existingCustomHeadersConfig)
        ? null
        : data.customHeadersConfig;

    final dedupFontSize = (data.fontSizeSettings != null &&
            data.fontSizeSettings == existingFontSizeSettings)
        ? null
        : data.fontSizeSettings;
```

4. 修改返回值：

```dart
    return SettingsExportData(
      modelProviders: newProviders,
      memoryPrompts: newMemoryPrompts,
      presetPrompts: newTemplates,
      templatePrompts: newTemplatePrompts,
      fixedPromptSequences: newSequences,
      autoRetrySettings: dedupAutoRetry,
      customHeadersConfig: dedupCustomHeaders,
      fontSizeSettings: dedupFontSize,
    );
```

- [ ] **Step 5: 运行测试验证全部通过**

Run: `flutter test --reporter compact test/features/settings/application/settings_import_deduplicator_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/application/settings_import_deduplicator.dart test/features/settings/application/settings_import_deduplicator_test.dart
git commit -m "fix: 同步去重时比较标量型配置，两端一致则跳过"
```

---

### Task 2: 更新同步和剪贴板导入的调用方

**Files:**
- Modify: `lib/features/sync/application/sync_client_controller.dart:246-256`
- Modify: `lib/features/settings/presentation/settings_screen.dart:425-433`

**Interfaces:**
- Consumes: Task 1 产出的 `deduplicate()` 新签名（3 个可选参数）
- Produces: 无

- [ ] **Step 1: 修改 SyncClientController._deduplicate()**

在 `lib/features/sync/application/sync_client_controller.dart` 顶部加入 import：

```dart
import '../../settings/application/auto_retry_settings_controller.dart';
import '../../settings/application/custom_headers_controller.dart';
import '../../settings/application/font_size_settings_controller.dart';
```

将 `_deduplicate` 方法改为：

```dart
  SettingsExportData _deduplicate(SettingsExportData data) {
    const deduplicator = SettingsImportDeduplicator();
    return deduplicator.deduplicate(
      data: data,
      existingProviders: ref.read(llmProviderConfigsProvider),
      existingMemoryPrompts: ref.read(memoryPromptsProvider),
      existingPresetPrompts: ref.read(presetPromptsProvider),
      existingTemplatePrompts: ref.read(templatePromptsProvider),
      existingSequences: ref.read(fixedPromptSequencesProvider),
      existingAutoRetrySettings: ref.read(autoRetrySettingsProvider),
      existingCustomHeadersConfig: ref.read(customHeadersProvider),
      existingFontSizeSettings: ref.read(fontSizeSettingsProvider),
    );
  }
```

- [ ] **Step 2: 修改 settings_screen.dart 剪贴板导入路径**

在 `lib/features/settings/presentation/settings_screen.dart` 中，将 `_importDeduplicator.deduplicate()` 调用（约 426 行）改为：

```dart
    final dedupedData = _importDeduplicator.deduplicate(
      data: exportData,
      existingProviders: ref.read(llmProviderConfigsProvider),
      existingMemoryPrompts: ref.read(memoryPromptsProvider),
      existingPresetPrompts: ref.read(presetPromptsProvider),
      existingTemplatePrompts: ref.read(templatePromptsProvider),
      existingSequences: ref.read(fixedPromptSequencesProvider),
      existingAutoRetrySettings: ref.read(autoRetrySettingsProvider),
      existingCustomHeadersConfig: ref.read(customHeadersProvider),
      existingFontSizeSettings: ref.read(fontSizeSettingsProvider),
    );
```

确保文件顶部已 import `auto_retry_settings_controller.dart`、`custom_headers_controller.dart`、`font_size_settings_controller.dart`（如果尚未 import）。检查现有 import 并按需添加。

- [ ] **Step 3: 删除 settings_screen.dart 中的过时注释**

删除约 425 行的注释：
```
// 去重（autoRetrySettings 不需要去重，deduplicator 会直接透传）。
```

- [ ] **Step 4: 运行 analyze 确保无编译错误**

Run: `flutter analyze lib/features/sync/application/sync_client_controller.dart lib/features/settings/presentation/settings_screen.dart`
Expected: 无 error

- [ ] **Step 5: Commit**

```bash
git add lib/features/sync/application/sync_client_controller.dart lib/features/settings/presentation/settings_screen.dart
git commit -m "fix: 同步和剪贴板导入传入本地标量配置用于去重比较"
```

---

### Task 3: 修复同步服务端导出和导入对话框展示

**Files:**
- Modify: `lib/features/sync/application/sync_server_controller.dart:236-260`
- Modify: `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart`

- [ ] **Step 1: 在 SyncServerController._buildExportData() 中补充 fontSizeSettings 导出**

在 `lib/features/sync/application/sync_server_controller.dart` 顶部加入 import：

```dart
import '../../settings/application/font_size_settings_controller.dart';
```

在 `_buildExportData()` 方法的返回 `SettingsExportData(...)` 中，在 `customHeadersConfig` 之后添加 `fontSizeSettings`：

```dart
    return SettingsExportData(
      modelProviders: categories.contains(SyncCategory.providers.payloadKey)
          ? ref.read(llmProviderConfigsProvider)
          : const [],
      presetPrompts: categories.contains(SyncCategory.presets.payloadKey)
          ? ref.read(presetPromptsProvider)
          : const [],
      memoryPrompts: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(memoryPromptsProvider)
          : const [],
      templatePrompts: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(templatePromptsProvider)
          : const [],
      fixedPromptSequences: categories.contains(SyncCategory.prompts.payloadKey)
          ? ref.read(fixedPromptSequencesProvider)
          : const [],
      autoRetrySettings: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(autoRetrySettingsProvider)
          : null,
      customHeadersConfig: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(customHeadersProvider)
          : null,
      fontSizeSettings: categories.contains(SyncCategory.other.payloadKey)
          ? ref.read(fontSizeSettingsProvider)
          : null,
    );
```

- [ ] **Step 2: 在 SyncImportConfirmDialog 中补充 customHeadersConfig 和 fontSizeSettings 展示行**

在 `lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart` 中，在 `autoRetrySettings` 展示行之后（约 88 行之后）添加：

```dart
          if (data.customHeadersConfig != null &&
              data.customHeadersConfig!.headers.isNotEmpty)
            _buildCountRow(
              context,
              icon: Icons.http_outlined,
              label: '自定义请求头',
              count: data.customHeadersConfig!.headers.length,
            ),
          if (data.fontSizeSettings != null)
            _buildCountRow(
              context,
              icon: Icons.format_size_rounded,
              label: '正文字号设置',
              count: 1,
            ),
```

- [ ] **Step 3: 运行 analyze 确保无编译错误**

Run: `flutter analyze lib/features/sync/`
Expected: 无 error

- [ ] **Step 4: 运行同步相关测试**

Run: `flutter test --reporter compact test/features/sync/ test/integration/sync_multi_category_integration_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0（如有因新增 fontSizeSettings 导出导致的集成测试变化，修复断言）

- [ ] **Step 5: Commit**

```bash
git add lib/features/sync/application/sync_server_controller.dart lib/features/sync/presentation/widgets/sync_import_confirm_dialog.dart
git commit -m "fix: 同步服务端补充 fontSizeSettings 导出，导入对话框补充展示行"
```

---

### Task 4: 数据库 V10 迁移 - favorites 表新增 title 列

**Files:**
- Modify: `lib/core/persistence/app_database.dart`
- Test: `test/core/persistence/app_database_migration_test.dart`

- [ ] **Step 1: 添加 V10 迁移测试**

在 `test/core/persistence/app_database_migration_test.dart` 中添加测试组：

```dart
    group('V10 迁移', () {
      test('迁移后 favorites 表包含 title 列', () {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        final columns = db.connection.select('PRAGMA table_info(favorites);');
        final columnNames = columns.map((row) => row['name'] as String).toList();

        expect(columnNames, contains('title'));
      });

      test('迁移后 user_version >= 10', () {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        final version =
            db.connection.select('PRAGMA user_version;').single['user_version']
                as int;
        expect(version, greaterThanOrEqualTo(10));
      });

      test('全新安装 favorites 表含 title 列且默认为 NULL', () {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        db.connection.execute(
          "INSERT INTO favorites (id, user_message_content, assistant_content, created_at) "
          "VALUES ('fav-1', 'hello', 'world', '2025-01-01T00:00:00.000');",
        );

        final rows = db.connection.select('SELECT title FROM favorites WHERE id = ?;', ['fav-1']);
        expect(rows.length, 1);
        expect(rows.first['title'], isNull);
      });
    });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `flutter test --reporter compact test/core/persistence/app_database_migration_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: FAIL - V10 测试组失败（title 列不存在，user_version 仍为 9）

- [ ] **Step 3: 实现 V10 迁移**

在 `lib/core/persistence/app_database.dart` 中：

1. 修改 `_migrate()` 方法：

```dart
  void _migrate() {
    final currentVersion =
        _connection.select('PRAGMA user_version;').single['user_version']
            as int;
    if (currentVersion < 9) {
      _migrateV9(currentVersion);
    }
    if (currentVersion < 10) {
      _migrateV10(currentVersion);
    }
  }
```

2. 添加 `_migrateV10()` 方法：

```dart
  /// V10：favorites 表新增 title 列，用于自定义收藏标题。
  void _migrateV10(int fromVersion) {
    if (fromVersion == 0) {
      // 全新安装，_createSchema 已包含 title 列
    } else {
      _connection.execute(
        'ALTER TABLE favorites ADD COLUMN title TEXT;',
      );
    }
    _connection.execute('PRAGMA user_version = 10;');
  }
```

3. 在 `_createSchema()` 中的 `CREATE TABLE IF NOT EXISTS favorites` 语句中添加 `title TEXT` 列：

```sql
      CREATE TABLE IF NOT EXISTS favorites (
        id TEXT PRIMARY KEY,
        collection_id TEXT,
        user_message_content TEXT NOT NULL,
        assistant_content TEXT NOT NULL,
        assistant_reasoning_content TEXT NOT NULL DEFAULT '',
        source_conversation_id TEXT,
        source_conversation_title TEXT,
        created_at TEXT NOT NULL,
        assistant_model_display_name TEXT NOT NULL DEFAULT '匿名模型',
        title TEXT,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE SET NULL
      );
```

- [ ] **Step 4: 运行测试验证通过**

Run: `flutter test --reporter compact test/core/persistence/app_database_migration_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0

- [ ] **Step 5: Commit**

```bash
git add lib/core/persistence/app_database.dart test/core/persistence/app_database_migration_test.dart
git commit -m "feat: 数据库 V10 迁移，favorites 表新增 title 列"
```

---

### Task 5: Favorite 模型 + Repository + Controller 增加 title 支持

**Files:**
- Modify: `lib/features/favorites/domain/models/favorite.dart`
- Modify: `lib/features/favorites/data/favorites_repository.dart`
- Modify: `lib/features/favorites/data/sqlite_favorites_repository.dart`
- Modify: `lib/features/favorites/application/favorites_controller.dart`
- Test: `test/features/favorites/domain/favorite_test.dart`
- Test: `test/features/favorites/data/sqlite_favorites_repository_test.dart`
- Test: `test/features/favorites/application/favorites_controller_test.dart`

**Interfaces:**
- Produces: `Favorite.title` 字段、`Favorite.displayTitle` getter、`FavoritesRepository.updateTitle()` 方法、`FavoritesController.rename()` 方法

- [ ] **Step 1: 修改 Favorite 模型测试**

在 `test/features/favorites/domain/favorite_test.dart` 中添加测试：

```dart
    test('displayTitle 使用自定义标题', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '这是一段很长的用户消息内容',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
        title: '我的自定义标题',
      );

      expect(favorite.displayTitle, '我的自定义标题');
    });

    test('displayTitle 在无自定义标题时 fallback 到 userMessageContent', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '用户消息原文',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
      );

      expect(favorite.displayTitle, '用户消息原文');
    });

    test('copyWith 更新 title', () {
      final favorite = Favorite(
        id: 'fav-1',
        userMessageContent: '消息',
        assistantContent: '回复',
        createdAt: DateTime(2025, 1, 1),
      );

      final updated = favorite.copyWith(title: '新标题');
      expect(updated.title, '新标题');
      expect(updated.userMessageContent, '消息');
    });
```

- [ ] **Step 2: 修改 Favorite 模型**

在 `lib/features/favorites/domain/models/favorite.dart` 中：

1. 在构造函数中添加 `this.title` 参数（放在 `sourceConversationTitle` 之后、`createdAt` 之前）：

```dart
  const Favorite({
    required this.id,
    required this.userMessageContent,
    required this.assistantContent,
    required this.createdAt,
    this.collectionId,
    this.assistantReasoningContent = '',
    this.assistantModelDisplayName = anonymousAssistantModelDisplayName,
    this.sourceConversationId,
    this.sourceConversationTitle,
    this.title,
  });
```

2. 添加字段声明和 getter（在 `sourceConversationTitle` 字段之后）：

```dart
  /// 自定义标题；为 null 时列表展示用 [userMessageContent] 前缀。
  final String? title;

  /// 列表展示用标题：有自定义标题则用，否则取 [userMessageContent]。
  String get displayTitle => title ?? userMessageContent;
```

3. 在 `copyWith` 中添加 `title` 参数：

```dart
  Favorite copyWith({
    String? id,
    String? collectionId,
    String? userMessageContent,
    String? assistantContent,
    String? assistantReasoningContent,
    String? assistantModelDisplayName,
    String? sourceConversationId,
    String? sourceConversationTitle,
    String? title,
    DateTime? createdAt,
    bool clearCollectionId = false,
    bool clearTitle = false,
  }) {
    return Favorite(
      id: id ?? this.id,
      collectionId: clearCollectionId
          ? null
          : collectionId ?? this.collectionId,
      userMessageContent: userMessageContent ?? this.userMessageContent,
      assistantContent: assistantContent ?? this.assistantContent,
      assistantReasoningContent:
          assistantReasoningContent ?? this.assistantReasoningContent,
      assistantModelDisplayName:
          assistantModelDisplayName ?? this.assistantModelDisplayName,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      sourceConversationTitle:
          sourceConversationTitle ?? this.sourceConversationTitle,
      title: clearTitle ? null : title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
    );
  }
```

4. 在 `props` 中添加 `title`：

```dart
  @override
  List<Object?> get props => [
    id,
    collectionId,
    userMessageContent,
    assistantContent,
    assistantReasoningContent,
    assistantModelDisplayName,
    sourceConversationId,
    sourceConversationTitle,
    title,
    createdAt,
  ];
```

- [ ] **Step 3: 运行 Favorite 模型测试**

Run: `flutter test --reporter compact test/features/favorites/domain/favorite_test.dart 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0

- [ ] **Step 4: 修改 FavoritesRepository 接口**

在 `lib/features/favorites/data/favorites_repository.dart` 中，在 `moveToCollection` 方法后添加：

```dart
  /// 更新指定收藏的自定义标题（null 表示清除自定义标题）。
  void updateTitle(String favoriteId, String? title);
```

- [ ] **Step 5: 修改 SqliteFavoritesRepository 实现**

在 `lib/features/favorites/data/sqlite_favorites_repository.dart` 中：

1. 修改 `save()` 方法的 SQL，加入 `title` 列：

```dart
  @override
  void save(Favorite favorite) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO favorites '
      '(id, collection_id, user_message_content, assistant_content, '
      'assistant_reasoning_content, assistant_model_display_name, source_conversation_id, '
      'source_conversation_title, title, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        favorite.id,
        favorite.collectionId,
        favorite.userMessageContent,
        favorite.assistantContent,
        favorite.assistantReasoningContent,
        favorite.assistantModelDisplayName,
        favorite.sourceConversationId,
        favorite.sourceConversationTitle,
        favorite.title,
        favorite.createdAt.toIso8601String(),
      ],
    );
  }
```

2. 修改 `_rowToFavorite()` 方法，读取 `title` 列：

```dart
  Favorite _rowToFavorite(Map<String, dynamic> row) {
    return Favorite(
      id: row['id'] as String,
      collectionId: row['collection_id'] as String?,
      userMessageContent: row['user_message_content'] as String,
      assistantContent: row['assistant_content'] as String,
      assistantReasoningContent:
          row['assistant_reasoning_content'] as String,
      assistantModelDisplayName:
          row['assistant_model_display_name'] as String,
      sourceConversationId: row['source_conversation_id'] as String?,
      sourceConversationTitle: row['source_conversation_title'] as String?,
      title: row['title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
```

3. 添加 `updateTitle()` 方法：

```dart
  @override
  void updateTitle(String favoriteId, String? title) {
    _database.connection.execute(
      'UPDATE favorites SET title = ? WHERE id = ?;',
      [title, favoriteId],
    );
  }
```

- [ ] **Step 6: 修改 FavoritesController 添加 rename 方法**

在 `lib/features/favorites/application/favorites_controller.dart` 中，在 `moveTo` 方法后添加：

```dart
  /// 重命名指定收藏的标题（null 或空字符串表示清除自定义标题）。
  void rename(String favoriteId, String? title) {
    _repo.updateTitle(favoriteId, title);
    _refresh();
  }
```

- [ ] **Step 7: 添加 Repository 和 Controller 测试**

在 `test/features/favorites/data/sqlite_favorites_repository_test.dart` 中添加测试组：

```dart
    group('updateTitle', () {
      test('设置自定义标题后 loadAll 返回的记录包含 title', () {
        final fav = _makeFavorite(id: 'fav-1');
        repo.save(fav);

        repo.updateTitle('fav-1', '我的标题');

        final loaded = repo.loadAll();
        expect(loaded.single.title, '我的标题');
      });

      test('清除自定义标题后 title 为 null', () {
        final fav = _makeFavorite(id: 'fav-1')..copyWith(title: '旧标题');
        repo.save(fav.copyWith(title: '旧标题'));

        repo.updateTitle('fav-1', null);

        final loaded = repo.loadAll();
        expect(loaded.single.title, isNull);
      });

      test('save 保留 title 字段 round-trip', () {
        final fav = _makeFavorite(id: 'fav-1').copyWith(title: '持久化标题');
        repo.save(fav);

        final loaded = repo.loadAll();
        expect(loaded.single.title, '持久化标题');
      });
    });
```

在 `test/features/favorites/application/favorites_controller_test.dart` 中，在 `FavoritesController` group 中添加：

```dart
    test('rename 更新收藏标题', () {
      final id = container.read(favoritesProvider.notifier).add(
        userMessageContent: '用户消息',
        assistantContent: '回复',
      );

      container.read(favoritesProvider.notifier).rename(id, '新标题');

      final favorites = container.read(favoritesProvider);
      final fav = favorites.firstWhere((f) => f.id == id);
      expect(fav.title, '新标题');
    });

    test('rename 传 null 清除自定义标题', () {
      final id = container.read(favoritesProvider.notifier).add(
        userMessageContent: '用户消息',
        assistantContent: '回复',
      );
      container.read(favoritesProvider.notifier).rename(id, '临时标题');
      container.read(favoritesProvider.notifier).rename(id, null);

      final favorites = container.read(favoritesProvider);
      final fav = favorites.firstWhere((f) => f.id == id);
      expect(fav.title, isNull);
    });
```

- [ ] **Step 8: 运行全部收藏相关测试**

Run: `flutter test --reporter compact test/features/favorites/ 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0

- [ ] **Step 9: Commit**

```bash
git add lib/features/favorites/domain/models/favorite.dart lib/features/favorites/data/favorites_repository.dart lib/features/favorites/data/sqlite_favorites_repository.dart lib/features/favorites/application/favorites_controller.dart test/features/favorites/domain/favorite_test.dart test/features/favorites/data/sqlite_favorites_repository_test.dart test/features/favorites/application/favorites_controller_test.dart
git commit -m "feat: Favorite 模型新增 title 字段，支持自定义收藏标题"
```

---

### Task 6: 收藏列表项展示自定义标题

**Files:**
- Modify: `lib/features/favorites/presentation/widgets/favorite_list_item.dart`

- [ ] **Step 1: 修改 FavoriteListItem 使用 displayTitle**

在 `lib/features/favorites/presentation/widgets/favorite_list_item.dart` 中，将 `build` 方法中的 `userSnippet` 计算改为优先使用自定义标题：

将第 29 行：
```dart
    final userSnippet = _snippet(favorite.userMessageContent);
```

改为：
```dart
    final userSnippet = favorite.title != null
        ? favorite.title!
        : _snippet(favorite.userMessageContent);
```

- [ ] **Step 2: 运行 analyze**

Run: `flutter analyze lib/features/favorites/presentation/widgets/favorite_list_item.dart`
Expected: 无 error

- [ ] **Step 3: Commit**

```bash
git add lib/features/favorites/presentation/widgets/favorite_list_item.dart
git commit -m "feat: 收藏列表项优先展示自定义标题"
```

---

### Task 7: 收藏详情页增加重命名和移动收藏夹功能

**Files:**
- Modify: `lib/features/favorites/presentation/favorite_detail_screen.dart`
- Modify: `lib/features/favorites/presentation/widgets/favorite_card.dart`

**Interfaces:**
- Consumes: Task 5 的 `FavoritesController.rename()` 和 `moveTo()` 方法

- [ ] **Step 1: 修改 FavoriteCard 增加 onMoveToCollection 回调**

在 `lib/features/favorites/presentation/widgets/favorite_card.dart` 中：

1. 在构造函数中添加 `onMoveToCollection` 参数：

```dart
  const FavoriteCard({
    required this.favorite,
    required this.collectionName,
    required this.onDeletePressed,
    required this.onGoToConversation,
    this.onMoveToCollection,
    super.key,
  });
```

2. 添加字段声明：

```dart
  /// 移动到其它收藏夹；为 null 时不显示移动按钮。
  final VoidCallback? onMoveToCollection;
```

3. 在元信息行中，收藏夹名称之后添加移动按钮。找到 `if (collectionName != null) ...[` 块末尾的 `const SizedBox(width: 8)` 之后，添加：

```dart
                      if (onMoveToCollection != null) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: onMoveToCollection,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: Icon(
                              Icons.drive_file_move_outline,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
```

- [ ] **Step 2: 修改 FavoriteDetailScreen 为 ConsumerStatefulWidget 并添加重命名 + 移动 UI**

将 `lib/features/favorites/presentation/favorite_detail_screen.dart` 整体替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_destination.dart';
import '../../chat/application/chat_sessions_controller.dart';
import '../application/favorites_controller.dart';
import '../application/collections_controller.dart';
import '../domain/models/collection.dart';
import '../domain/models/favorite.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import 'widgets/favorite_card.dart';

/// 单条收藏的详情页，展示完整对话内容。
///
/// 通过 GoRouter extra 接收 [Favorite] 对象，读取 collectionsProvider
/// 获取收藏夹名称。支持重命名收藏标题和移动到其它收藏夹。
class FavoriteDetailScreen extends ConsumerStatefulWidget {
  const FavoriteDetailScreen({required this.favorite, super.key});

  final Favorite favorite;

  @override
  ConsumerState<FavoriteDetailScreen> createState() =>
      _FavoriteDetailScreenState();
}

class _FavoriteDetailScreenState extends ConsumerState<FavoriteDetailScreen> {
  late Favorite _favorite = widget.favorite;

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);
    final collectionById = {for (final c in collections) c.id: c};
    final collection = _favorite.collectionId != null
        ? collectionById[_favorite.collectionId]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_favorite.title ?? '收藏详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: '重命名',
            onPressed: () => _showRenameDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除收藏',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: FavoriteCard(
          favorite: _favorite,
          collectionName: collection?.name,
          onDeletePressed: () => _confirmDelete(context),
          onMoveToCollection: () => _showMoveDialog(context, collections),
          onGoToConversation: _favorite.sourceConversationId != null
              ? () => _goToConversation(context)
              : null,
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: _favorite.title ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名收藏'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '自定义标题',
            hintText: '留空则使用消息摘要',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final trimmed = result.trim();
    ref.read(favoritesProvider.notifier).rename(
          _favorite.id,
          trimmed.isEmpty ? null : trimmed,
        );
    _refreshFavorite();
  }

  Future<void> _showMoveDialog(
    BuildContext context,
    List<FavoriteCollection> collections,
  ) async {
    String? selectedCollectionId = _favorite.collectionId;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('移动到收藏夹'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoveCollectionTile(
                  label: '未分类',
                  icon: Icons.folder_off_outlined,
                  selected: selectedCollectionId == null,
                  onTap: () =>
                      setState(() => selectedCollectionId = null),
                ),
                if (collections.isNotEmpty) ...[
                  const Divider(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: collections.length,
                      itemBuilder: (context, index) {
                        final collection = collections[index];
                        return _MoveCollectionTile(
                          label: collection.name,
                          icon: Icons.folder_outlined,
                          selected: selectedCollectionId == collection.id,
                          onTap: () => setState(
                            () => selectedCollectionId = collection.id,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(selectedCollectionId),
              child: const Text('移动'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    // 仅当目标收藏夹与当前不同时才执行移动
    if (result != _favorite.collectionId) {
      ref
          .read(favoritesProvider.notifier)
          .moveTo(_favorite.id, result.isEmpty ? null : result);
      _refreshFavorite();
    }
  }

  void _refreshFavorite() {
    final favorites = ref.read(favoritesProvider);
    final updated = favorites.where((f) => f.id == _favorite.id).firstOrNull;
    if (updated != null) {
      setState(() => _favorite = updated);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const AppConfirmDialog(
        title: '删除收藏',
        message: '确定要删除这条收藏记录吗？',
        confirmLabel: '删除',
      ),
    );

    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).remove(_favorite.id);
      if (context.mounted) context.pop();
    }
  }

  void _goToConversation(BuildContext context) {
    ref
        .read(chatSessionsProvider.notifier)
        .selectConversation(_favorite.sourceConversationId!);
    context.go(AppDestination.chat.path);
  }
}

/// 移动收藏夹对话框中的选项行。
class _MoveCollectionTile extends StatelessWidget {
  const _MoveCollectionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.onSecondaryContainer
                        : null,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 analyze**

Run: `flutter analyze lib/features/favorites/presentation/`
Expected: 无 error

- [ ] **Step 3: 运行收藏相关 Widget 测试**

Run: `flutter test --reporter compact test/features/favorites/ 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0（如有因详情页改为 StatefulWidget 导致的测试失败，修复断言）

- [ ] **Step 4: Commit**

```bash
git add lib/features/favorites/presentation/favorite_detail_screen.dart lib/features/favorites/presentation/widgets/favorite_card.dart
git commit -m "feat: 收藏详情页增加重命名标题和移动收藏夹功能"
```

---

### Task 8: 全量测试 + Lint 验证

- [ ] **Step 1: 运行全量测试**

Run: `flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log`
Expected: EXIT=0

- [ ] **Step 2: 运行 flutter analyze**

Run: `flutter analyze`
Expected: 无 error

- [ ] **Step 3: 如有失败，修复并重新运行**

检查 `fltest.log` 中的失败项，用 `Select-String -Pattern " -[1-9]" -Path fltest.log` 查找失败测试名，修复后重新运行。

- [ ] **Step 4: 最终 Commit（如有修复）**

```bash
git add -A
git commit -m "fix: 修复全量测试中的兼容性问题"
```
