# 脆弱测试反模式修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复测试中 6 类脆弱反模式，使测试在 CI 慢运行、布局微调、常量变更时不再误报。

**Architecture:** 按严重度分 8 个 Task 顺序执行。每个 Task 是原子改动——可独立运行测试验证。高优先（时间依赖、冗余 setup、参数化）先做，中低优先随后。

**Tech Stack:** Flutter 3.11.5+, Dart 3.x, flutter_test, package:flutter_riverpod

## Global Constraints

- 所有命令使用 PowerShell 语法
- 测试运行必须使用：`flutter test --reporter compact 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log`
- 提交粒度：每个 Task 完成后单独提交
- Commit message 使用 Bash 语法（不使用 PowerShell here-string）
- 注释使用简体中文
- 禁止 `part` / `part of`
- 禁止在 widget 测试中写 raw SQL

---

### Task 1: 导出 debounce 常量 + 修复时间依赖测试

**Files:**
- Modify: `lib/features/settings/presentation/widgets/form/template_prompt_form_dialog.dart:42-46`
- Modify: `lib/features/history/presentation/history_screen.dart:31`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart:350,396-411`
- Modify: `test/features/history/history_screen/history_screen_search_cases.dart:13,20,27,39`
- Modify: `test/features/chat/chat_screen/chat_screen_streaming_cases.dart:17-33,165-166`

**Interfaces:**
- Produces: `TemplatePromptFormDialog.variableReconcileDebounce` (public static const Duration), `TemplatePromptFormDialog.variableReconcileDebounceForLargeContent` (public static const Duration), `HistoryScreen.searchDebounce` (public static const Duration)

- [ ] **Step 1: 导出 template_prompt_form_dialog.dart 的 debounce 常量**

将 `_variableReconcileDebounce` 和 `_variableReconcileDebounceForLargeContent` 从 private 改为 public：

```dart
// 改前
static const _variableReconcileDebounce = Duration(milliseconds: 220);
static const _variableReconcileDebounceForLargeContent = Duration(
  milliseconds: 320,
);

// 改后
static const variableReconcileDebounce = Duration(milliseconds: 220);
static const variableReconcileDebounceForLargeContent = Duration(
  milliseconds: 320,
);
```

同步修改文件内所有引用（`_resolveDebounceWindow` 中的 `_variableReconcileDebounce` → `variableReconcileDebounce`，`_variableReconcileDebounceForLargeContent` → `variableReconcileDebounceForLargeContent`）。

- [ ] **Step 2: 导出 history_screen.dart 的 searchDebounce 常量**

将 `_searchDebounce` 从 private 改为 public：

```dart
// 改前
static const _searchDebounce = Duration(milliseconds: 300);

// 改后
static const searchDebounce = Duration(milliseconds: 300);
```

同步修改文件内所有引用（`_searchDebounceTimer = Timer(_searchDebounce, ...)` → `Timer(searchDebounce, ...)`）。

- [ ] **Step 3: 修复 settings_screen_models_and_prompts_cases.dart 的时间硬编码**

在文件顶部添加 import：
```dart
import 'package:oh_my_llm/features/settings/presentation/widgets/form/template_prompt_form_dialog.dart';
```

替换 3 处硬编码 pump：

```dart
// 改前（line 350）
await tester.pump(const Duration(milliseconds: 250));
// 改后
await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce + const Duration(milliseconds: 50));

// 改前（line 400）
await tester.pump(const Duration(milliseconds: 250));
// 改后
await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce + const Duration(milliseconds: 50));

// 改前（line 405）
await tester.pump(const Duration(milliseconds: 50));
// 改后 — 50ms 仍在 debounce 窗口内，无需引用常量
await tester.pump(const Duration(milliseconds: 50));

// 改前（line 410）
await tester.pump(const Duration(milliseconds: 250));
// 改后
await tester.pump(TemplatePromptFormDialog.variableReconcileDebounce + const Duration(milliseconds: 50));
```

- [ ] **Step 4: 修复 history_screen_search_cases.dart 的时间硬编码**

在文件顶部添加 import：
```dart
import 'package:oh_my_llm/features/history/presentation/history_screen.dart';
```

替换 4 处 `pump(const Duration(milliseconds: 300))`：

```dart
// 改后
await tester.pump(HistoryScreen.searchDebounce + const Duration(milliseconds: 50));
```

共 4 处（line 13, 20, 27, 39）。

- [ ] **Step 5: 修复 streaming_cases.dart 的 chunkDelay 时间竞争**

用 `StreamController` 替代 `chunkDelay` 模式，消除 10ms/12ms 的微秒级依赖：

```dart
// 改前（line 16-33）
final fakeClient = FakeChatCompletionClient();
fakeClient.enqueueChunks([
  '第一段 ',
  '第二段',
], chunkDelay: const Duration(milliseconds: 10));
// ...
await tester.pump(const Duration(milliseconds: 12));

// 改后
final fakeClient = FakeChatCompletionClient();
final streamController = StreamController<ChatCompletionChunk>();
addTearDown(streamController.close);
fakeClient.enqueueStream(streamController.stream);
// ...
await tester.tap(sendButton);
await tester.pump();

streamController.add(const ChatCompletionChunk(contentDelta: '第一段 '));
await tester.pump();
streamController.add(const ChatCompletionChunk(contentDelta: '第二段'));
await tester.pump();
```

需添加 import：`import 'dart:async';`（已有则忽略）。

同时修复 line 165-166 的 `pump(16ms)`：

```dart
// 改前
streamController.add(const ChatCompletionChunk(contentDelta: '已生成部分'));
await tester.pump(const Duration(milliseconds: 16));

// 改后
streamController.add(const ChatCompletionChunk(contentDelta: '已生成部分'));
await tester.pump();
```

- [ ] **Step 6: 运行受影响的测试验证通过**

```powershell
flutter test --reporter compact test/features/settings/settings_screen/ test/features/history/ test/features/chat/chat_screen/ 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 7: 提交**

```bash
git add lib/features/settings/presentation/widgets/form/template_prompt_form_dialog.dart lib/features/history/presentation/history_screen.dart test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart test/features/history/history_screen/history_screen_search_cases.dart test/features/chat/chat_screen/chat_screen_streaming_cases.dart
git commit -m "fix: eliminate hardcoded debounce timing in tests by exporting constants" -m "TemplatePromptFormDialog.variableReconcileDebounce and HistoryScreen.searchDebounce are now public; tests reference them instead of hardcoded milliseconds. streaming_cases uses StreamController instead of chunkDelay."
```

---

### Task 2: 提取冗余 setUp（app_log_store_test.dart）

**Files:**
- Modify: `test/core/logging/app_log_store_test.dart`

**Interfaces:**
- None (internal to test file)

- [ ] **Step 1: 将重复的临时目录创建提取到 setUp**

当前 8 个测试各自重复以下 5-6 行：
```dart
final directory = await Directory.systemTemp.createTemp('...');
addTearDown(() async {
  if (await directory.exists()) { await directory.delete(recursive: true); }
});
final file = File('${directory.path}${Platform.pathSeparator}network.log');
```

提取为 `late` 变量 + `setUp`：

```dart
late Directory _directory;
late File _logFile;

setUp(() async {
  _directory = await Directory.systemTemp.createTemp('log-store-test-');
  addTearDown(() async {
    if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  });
  _logFile = File('${_directory.path}${Platform.pathSeparator}network.log');
});
```

然后删除 8 个测试中的重复代码，将 `directory` 替换为 `_directory`，`file` 替换为 `_logFile`。

注意：
- 第 1 个测试（`rotates file when size exceeds max bytes`）使用 `AppLogStore.open` 而非 `AppNetworkLogger`，目录前缀改为统一前缀即可
- 第 2 个测试（`keeps request logs across relaunches`）创建了两次 logger，目录仍使用 `_directory`

- [ ] **Step 2: 运行测试验证**

```powershell
flutter test --reporter compact test/core/logging/ 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 3: 提交**

```bash
git add test/core/logging/app_log_store_test.dart
git commit -m "refactor: extract shared temp directory setup in app_log_store_test" -m "8 tests shared identical directory/file creation boilerplate; extracted to setUp()."
```

---

### Task 3: 提取冗余 setUp（background_sqlite_writer_test.dart）

**Files:**
- Modify: `test/core/persistence/background_sqlite_writer_test.dart`

**Interfaces:**
- None (internal to test file)

- [ ] **Step 1: 将重复的 AppDatabase.inMemory() + DateTime.now() 提取到 setUp**

当前 9 个测试各自重复：
```dart
final appDb = AppDatabase.inMemory();
addTearDown(appDb.close);
final db = appDb.connection;
final now = DateTime.now();
```

提取为 `late` 变量 + `setUp`：

```dart
late AppDatabase _appDb;
late Database _db;
late DateTime _now;

setUp(() {
  _appDb = AppDatabase.inMemory();
  addTearDown(_appDb.close);
  _db = _appDb.connection;
  _now = DateTime.now();
});
```

注意：`Database` 类型需确认 `AppDatabase.connection` 的返回类型（从现有 import 推断应为 `sqlite3` 的 `Database`）。

- [ ] **Step 2: 运行测试验证**

```powershell
flutter test --reporter compact test/core/persistence/background_sqlite_writer_test.dart 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 3: 提交**

```bash
git add test/core/persistence/background_sqlite_writer_test.dart
git commit -m "refactor: extract shared database setup in background_sqlite_writer_test" -m "9 tests shared identical AppDatabase.inMemory() + DateTime.now() boilerplate; extracted to setUp()."
```

---

### Task 4: 提取集成测试 ProviderContainer 辅助函数

**Files:**
- Modify: `test/helpers/integration_test_helpers.dart`
- Modify: `test/integration/chat_lifecycle_integration_test.dart`
- Modify: `test/integration/chat_message_version_persistence_integration_test.dart`

**Interfaces:**
- Produces: `createTestContainer({required AppDatabase database, required SharedPreferences preferences, required ChatCompletionClient fakeClient})` → `ProviderContainer`

- [ ] **Step 1: 在 integration_test_helpers.dart 中新增 createTestContainer 辅助函数**

在文件末尾添加：

```dart
/// 创建带有标准 override 的 ProviderContainer。
///
/// 自动注入 [appDatabaseProvider]、[sharedPreferencesProvider]、
/// [chatCompletionClientProvider] 三个 override。
/// 调用方需自行 dispose 或在 addTearDown 中 dispose。
ProviderContainer createTestContainer({
  required AppDatabase database,
  required SharedPreferences preferences,
  required ChatCompletionClient fakeClient,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      chatCompletionClientProvider.overrideWithValue(fakeClient),
    ],
  );
}
```

需添加 import：
- `import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';`
- `import 'package:flutter_riverpod/flutter_riverpod.dart';`
- `import 'package:oh_my_llm/core/persistence/app_database_provider.dart';`
- `import 'package:oh_my_llm/core/persistence/shared_preferences_provider.dart';`

（部分 import 可能已存在，检查后添加缺失的。）

- [ ] **Step 2: 重构 chat_lifecycle_integration_test.dart**

4 个测试中，containerA 和 containerB 的创建替换为：

```dart
// 改前
final containerA = ProviderContainer(
  overrides: [
    appDatabaseProvider.overrideWithValue(database),
    sharedPreferencesProvider.overrideWithValue(preferences),
    chatCompletionClientProvider.overrideWithValue(fakeClientA),
  ],
);

// 改后
final containerA = createTestContainer(
  database: database,
  preferences: preferences,
  fakeClient: fakeClientA,
);
```

containerB 同理（使用 `FakeChatCompletionClient()` 作为 fakeClient）。

注意保留 `addTearDown(database.close)` 和 `addTearDown(() { containerB.dispose(); })`，这些属于测试特定的生命周期管理，不纳入辅助函数。

- [ ] **Step 3: 重构 chat_message_version_persistence_integration_test.dart**

同 Step 2 的模式，将 containerA 和 containerB 创建替换为 `createTestContainer` 调用。

- [ ] **Step 4: 运行集成测试验证**

```powershell
flutter test --reporter compact test/integration/chat_lifecycle_integration_test.dart test/integration/chat_message_version_persistence_integration_test.dart 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 5: 提交**

```bash
git add test/helpers/integration_test_helpers.dart test/integration/chat_lifecycle_integration_test.dart test/integration/chat_message_version_persistence_integration_test.dart
git commit -m "refactor: extract createTestContainer helper for integration tests" -m "6 ProviderContainer creations across 2 files now use shared helper."
```

---

### Task 5: 参数化 versioned_json_storage_test 的 rejection 测试

**Files:**
- Modify: `test/core/persistence/versioned_json_storage_test.dart:35-117`

**Interfaces:**
- None (internal to test file)

- [ ] **Step 1: 将 6 个 rejection 测试合并为参数化循环**

将 line 35-117 的 6 个独立 test 替换为：

```dart
test('rejects unsupported future versions', () {
  expect(
    () => VersionedJsonStorage.decodeObjectList(
      rawJson: jsonEncode({
        'version': VersionedJsonStorage.currentSchemaVersion + 1,
        'items': const <dynamic>[],
      }),
      subject: 'test items',
    ),
    throwsFormatException,
  );
});

const _rejectionCases = <(String, Object)>[
  ('non-integer version', {'version': 'v1', 'items': <dynamic>[]}),
  ('non-list items', {'version': 1, 'items': 'not-a-list'}),
  ('items containing non-map entries', {'version': 1, 'items': [null]}),
  ('non-object JSON', 'plain string'),
  ('plain array JSON', [{'id': 'item-1'}]),
];

for (final (name, payload) in _rejectionCases) {
  test('rejects $name', () {
    expect(
      () => VersionedJsonStorage.decodeObjectList(
        rawJson: jsonEncode(payload),
        subject: 'test items',
      ),
      throwsFormatException,
    );
  });
}
```

注意：`'unsupported future version'` case 需要 `currentSchemaVersion + 1`，不能放入 `const` 列表，单独提取为第一个 test。

- [ ] **Step 2: 运行测试验证**

```powershell
flutter test --reporter compact test/core/persistence/versioned_json_storage_test.dart 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 3: 提交**

```bash
git add test/core/persistence/versioned_json_storage_test.dart
git commit -m "refactor: parameterize rejection tests in versioned_json_storage_test" -m "6 structurally identical tests collapsed into a for loop; future version case kept separate for dynamic constant."
```

---

### Task 6: Anchor Rail 像素断言替换为语义断言

**Files:**
- Modify: `test/features/chat/widgets/message_anchor_rail_test.dart:146-324`

**Interfaces:**
- None (internal to test file)

- [ ] **Step 1: 替换「鼠标进入时展开锚点条宽度」测试**

改前（line 146-164）：用 `getSize().width` 比较

改后：用预览文本可见性断言展开行为

```dart
testWidgets('鼠标进入时展开并显示消息预览文本', (tester) async {
  final messages = List.generate(
    5,
    (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
  );
  await pumpAnchorRail(tester, userMessages: messages);

  // 紧凑模式下不显示预览文本
  expect(find.text('消息1'), findsNothing);

  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer();
  await gesture.moveTo(tester.getCenter(railContainerFinder));
  await tester.pumpAndSettle();

  // 展开后显示预览文本
  expect(find.text('消息1'), findsOneWidget);

  await gesture.removePointer();
});
```

- [ ] **Step 2: 替换「鼠标离开时折叠回原宽度」测试**

改前（line 166-189）：3 次 `getSize().width`

改后：用预览文本消失断言折叠行为

```dart
testWidgets('鼠标离开时折叠并隐藏预览文本', (tester) async {
  final messages = List.generate(
    5,
    (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
  );
  await pumpAnchorRail(tester, userMessages: messages);

  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer();
  await gesture.moveTo(tester.getCenter(railContainerFinder));
  await tester.pumpAndSettle();

  expect(find.text('消息1'), findsOneWidget);

  await gesture.moveTo(const Offset(0, 0));
  await tester.pumpAndSettle();

  expect(find.text('消息1'), findsNothing);

  await gesture.removePointer();
});
```

- [ ] **Step 3: 替换「长按展开锚点条宽度」测试**

改前（line 217-231）：用 `getSize().width` 比较

改后：用预览文本可见性断言

```dart
testWidgets('长按展开并显示消息预览文本', (tester) async {
  final messages = List.generate(
    5,
    (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
  );
  await pumpAnchorRail(tester, userMessages: messages);

  expect(find.text('消息1'), findsNothing);

  await tester.longPress(railContainerFinder);
  await tester.pumpAndSettle();

  expect(find.text('消息1'), findsOneWidget);
});
```

- [ ] **Step 4: 保留「≤3 条不展开」的宽度断言，添加注释**

line 250-269 的测试断言 `equals(widthBefore)`，这是唯一无预览文本可断言的场景（3 条消息时 rail 不会展开，因此无预览文本）。保留 `getSize().width` 断言但添加注释说明原因：

```dart
testWidgets('消息数 ≤3 时鼠标悬停不展开', (tester) async {
  // ... setup 不变 ...

  // ≤3 条时无预览文本可断言，宽度不变是唯一可验证"不展开"的方式
  final widthBefore = tester.getSize(railContainerFinder).width;

  // ... gesture 不变 ...

  final widthAfter = tester.getSize(railContainerFinder).width;
  expect(widthAfter, equals(widthBefore));

  await gesture.removePointer();
});
```

- [ ] **Step 5: 替换「父级重建时折叠展开状态」测试中的宽度断言**

改前（line 279-324）：3 次 `getSize().width`

改后：用预览文本可见性断言

```dart
testWidgets('父级重建时折叠展开状态', (tester) async {
  final messages = List.generate(
    5,
    (i) => _userMessage(id: 'msg-${i + 1}', content: '消息${i + 1}，测试'),
  );
  // ... _ScrollWrapper setup 不变 ...

  // 紧凑模式：无预览
  expect(find.text('消息1'), findsNothing);

  await tester.longPress(railContainerFinder);
  await tester.pumpAndSettle();

  // 展开：预览可见
  expect(find.text('消息1'), findsOneWidget);

  // 父级 setState 触发 didUpdateWidget → 折叠
  wrapperKey.currentState!.triggerRebuild();
  await tester.pumpAndSettle();

  // 折叠：预览消失
  expect(find.text('消息1'), findsNothing);
});
```

- [ ] **Step 6: 替换「空消息列表不渲染任何锚点条目」的 findsNothing on InkWell**

改前（line 109）：`expect(find.byType(InkWell), findsNothing);`
改后：`expect(find.byType(InkWell), findsNAnchorItems(0));`

- [ ] **Step 7: 运行测试验证**

```powershell
flutter test --reporter compact test/features/chat/widgets/message_anchor_rail_test.dart 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 8: 提交**

```bash
git add test/features/chat/widgets/message_anchor_rail_test.dart
git commit -m "refactor: replace pixel width assertions with semantic text visibility in anchor rail tests" -m "Most getSize().width comparisons replaced with find.text() assertions. Width comparison retained only for the ≤3 guard case where no preview text exists. findsNothing on InkWell replaced with findsNAnchorItems(0)."
```

---

### Task 7: 长线性 CRUD 测试拆分

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart:14-86`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart:225-329`
- Modify: `test/features/settings/settings_screen/settings_screen_fixed_prompt_sequences_cases.dart:11-104`
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart` (新增 helper)

**Interfaces:**
- Produces: `createTestProvider(WidgetTester tester)` helper in settings_screen_test_helpers.dart

- [ ] **Step 1: 在 settings_screen_test_helpers.dart 中添加 createTestProvider helper**

在文件末尾添加：

```dart
/// 通过 UI 快速创建一个测试用服务商。
Future<void> createTestProvider(WidgetTester tester) async {
  await tester.tap(find.text('新增服务商'));
  await tester.pumpAndSettle();
  await tester.enterText(providerNameField(), 'OpenAI 官方');
  await tester.enterText(
    providerApiUrlField(),
    'https://api.example.com/v1/chat/completions',
  );
  await tester.enterText(providerApiKeyField(), 'sk-test-12345678');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}
```

需添加 import：`import 'package:flutter_test/flutter_test.dart';`（已存在则忽略）。

- [ ] **Step 2: 拆分 provider+model CRUD 测试（72 行 → 4 个独立测试）**

将 `settings screen supports provider and model CRUD flows`（line 14-86）拆为 4 个测试。

**Test 1: creates a provider and verifies persistence**
```dart
testWidgets('settings screen creates a provider and verifies persistence', (tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createEmptyPreferences(database);
  final repository = LlmModelConfigRepository(preferences);

  await pumpSettingsScreen(tester, preferences: preferences, database: database);
  expect(repository.loadProviders(), isEmpty);

  await createTestProvider(tester);

  final createdProvider = repository.loadProviders().single;
  expect(createdProvider.name, 'OpenAI 官方');
  expect(find.text('OpenAI 官方'), findsWidgets);
});
```

**Test 2: creates a model under a provider**
```dart
testWidgets('settings screen creates a model under a provider', (tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createEmptyPreferences(database);
  final repository = LlmModelConfigRepository(preferences);

  await pumpSettingsScreen(tester, preferences: preferences, database: database);
  await createTestProvider(tester);

  await tester.tap(find.text('新增模型'));
  await tester.pumpAndSettle();
  await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
  await tester.enterText(modelApiNameField(), 'gpt-4.1');
  await tester.tap(modelSupportsReasoningField());
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  final createdModel = repository.loadAll().single;
  expect(createdModel.displayName, 'OpenAI 4.1');
  expect(createdModel.modelName, 'gpt-4.1');
  expect(createdModel.supportsReasoning, isTrue);
});
```

**Test 3: edits provider and model names**
```dart
testWidgets('settings screen edits provider and model names', (tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createEmptyPreferences(database);
  final repository = LlmModelConfigRepository(preferences);

  await pumpSettingsScreen(tester, preferences: preferences, database: database);
  await createTestProvider(tester);

  // 添加模型
  await tester.tap(find.text('新增模型'));
  await tester.pumpAndSettle();
  await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
  await tester.enterText(modelApiNameField(), 'gpt-4.1');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  // 编辑服务商
  await tester.tap(find.text('编辑服务商'));
  await tester.pumpAndSettle();
  await tester.enterText(providerNameField(), 'OpenAI 官方 v2');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  expect(repository.loadProviders().single.name, 'OpenAI 官方 v2');

  // 编辑模型
  await tester.tap(find.widgetWithText(OutlinedButton, '编辑').last);
  await tester.pumpAndSettle();
  await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1 Turbo');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  expect(repository.loadAll().single.displayName, 'OpenAI 4.1 Turbo');
});
```

**Test 4: deletes model then provider**
```dart
testWidgets('settings screen deletes model then provider', (tester) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final preferences = await createEmptyPreferences(database);
  final repository = LlmModelConfigRepository(preferences);

  await pumpSettingsScreen(tester, preferences: preferences, database: database);
  await createTestProvider(tester);

  // 添加模型
  await tester.tap(find.text('新增模型'));
  await tester.pumpAndSettle();
  await tester.enterText(modelDisplayNameField(), 'OpenAI 4.1');
  await tester.enterText(modelApiNameField(), 'gpt-4.1');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  // 删除模型
  await tester.tap(find.widgetWithText(OutlinedButton, '删除').last);
  await tester.pumpAndSettle();
  expect(repository.loadAll(), isEmpty);

  // 删除服务商
  await tester.tap(find.text('删除服务商'));
  await tester.pumpAndSettle();
  expect(repository.loadProviders(), isEmpty);
});
```

- [ ] **Step 3: 拆分模板插入排序测试（100+ 行 → 2 个独立测试）**

将 `prompt template dialog inserts a new item below selection and keeps groups ordered`（line 225-329）拆为：

**Test 1: inserts a new item below the selected item**
- 创建模板 → 添加 2 个条目（前置1、后置1）→ 选中前置1 → 插入新条目 → 验证前置1.5 出现在前置1和后置1之间

**Test 2: keeps items ordered after inserting below the last item**
- 在 Test 1 基础上 → 选中后置1 → 插入新条目 → 验证后置1.5 出现在后置1之后

两个测试各自独立 setup（不依赖前一个测试的状态）。

- [ ] **Step 4: 拆分序列 CRUD 测试（93 行 → 3 个独立测试）**

将 `settings screen supports fixed prompt sequence CRUD flows`（line 11-104）拆为：

**Test 1: creates a sequence with two steps**
```dart
testWidgets('settings screen creates a fixed prompt sequence with steps', (tester) async {
  final database = await setUpSettingsScreen(
    tester,
    size: const Size(1440, 2200),
    initialTabIndex: 2,
  );
  final repository = fixedPromptSequenceRepository;
  expect(repository.loadAll(database), isEmpty);

  await tester.tap(find.text('新增序列'));
  await tester.pumpAndSettle();
  await tester.enterText(fixedPromptSequenceNameField(), '对比测试流程');
  await tester.enterText(fixedStepTitleField(), '标题1');
  await tester.enterText(fixedStepContentField(), '请先总结这个需求的核心目标。');
  await tester.tap(find.text('新增步骤'));
  await tester.pumpAndSettle();
  await tester.enterText(fixedStepTitleField(), '标题2');
  await tester.enterText(fixedStepContentField(), '请列出三个可执行方案，并说明权衡。');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  final createdSequence = repository.loadAll(database).single;
  expect(createdSequence.name, '对比测试流程');
  expect(createdSequence.steps, hasLength(2));
});
```

**Test 2: edits sequence name** — 先创建序列，再编辑名称

**Test 3: deletes sequence** — 先创建序列，再删除

- [ ] **Step 5: 运行全部 settings 测试验证**

```powershell
flutter test --reporter compact test/features/settings/ 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 6: 提交**

```bash
git add test/features/settings/
git commit -m "refactor: split long linear CRUD tests into focused independent tests" -m "Provider+Model CRUD (72 lines) -> 4 tests; template insert (100+ lines) -> 2 tests; sequence CRUD (93 lines) -> 3 tests. Added createTestProvider helper."
```

---

### Task 8: 低优先修补

**Files:**
- Modify: `test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart:6-14`
- Modify: `lib/features/settings/presentation/widgets/form/model_provider_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/model_config_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/preset_prompt_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/fixed_prompt_sequence_form_dialog.dart`
- Modify: `lib/features/settings/presentation/widgets/form/memory_prompt_form_dialog.dart`
- Modify: `lib/features/chat/presentation/widgets/composer/composer_message_field.dart`
- Modify: `lib/features/chat/presentation/widgets/message_anchor_rail.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`

**Interfaces:**
- None

- [ ] **Step 1: 删除多余的 tab 存在性测试**

删除 `settings_screen_tab_navigation_cases.dart` 中的 `settings screen shows tab bar with five tabs` 测试（line 6-14），因为 `switching tabs updates the visible content`（line 24-43）已通过交互覆盖了所有 tab 的存在性。

- [ ] **Step 2: 为源码中的 ValueKey 添加 // test-key 注释**

在每个 `ValueKey(...)` 声明旁添加 `// test-key` 注释，标明这是测试契约的一部分：

示例（model_provider_form_dialog.dart:70）：
```dart
// 改前
key: const ValueKey('model-provider-name-field'),
// 改后
key: const ValueKey('model-provider-name-field'), // test-key
```

涉及文件和行：
- `model_provider_form_dialog.dart:70,80,91`
- `model_config_form_dialog.dart:70,80,90`
- `preset_prompt_form_dialog.dart:76,83,87,103,293,316,325,352,389`
- `fixed_prompt_sequence_form_dialog.dart:93,101,117,143,291,314,338`
- `memory_prompt_form_dialog.dart:61,71`
- `composer_message_field.dart:37`
- `message_anchor_rail.dart:134`

- [ ] **Step 3: 在 settings_screen_test_helpers.dart 的 Finder 工厂区域添加契约注释**

在 `// ── Finder 工厂 ──` 注释后添加：

```dart
// ── Finder 工厂 ────────────────────────────────────────────
//
// 以下 finder 依赖源码中显式声明的 ValueKey（标注 // test-key）。
// 重命名 key 时需同步更新此处及对应源码。
```

- [ ] **Step 4: 运行全量测试验证**

```powershell
flutter test --reporter compact 2>&1 > fltest.log; $E=$LASTEXITCODE; echo "EXIT=$E"; tail -150 fltest.log
```

Expected: EXIT=0

- [ ] **Step 5: 提交**

```bash
git add test/features/settings/settings_screen/settings_screen_tab_navigation_cases.dart lib/features/settings/presentation/widgets/form/ lib/features/chat/presentation/widgets/composer/composer_message_field.dart lib/features/chat/presentation/widgets/message_anchor_rail.dart test/features/settings/settings_screen/settings_screen_test_helpers.dart
git commit -m "refactor: remove redundant tab existence test and annotate ValueKey test contracts" -m "Removed 'shows tab bar with five tabs' test (covered by switching tabs test). Added // test-key comments to all ValueKey declarations used by tests."
```
