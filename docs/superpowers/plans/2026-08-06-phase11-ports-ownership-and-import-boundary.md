# Phase 11 - Ports 所有权与依赖门禁 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Chat generation、持久化、Favorites 行为和现有跨 Feature facade 的前提下，把被 application 实际消费的 Chat/Favorites 抽象从 `data` 迁到 `application/ports`，把 provider token / concrete / 生产绑定拆开，并用一个纯 Dart、可单测、可独立执行的 import boundary checker 固化分层规则（Settings 的 8 条旧边以精确基线冻结）。

**Architecture:** application-owned port 文件只含 contract、DTO、异常和默认抛 `StateError` 的 Riverpod provider token；`data` 只保留 SQLite/HTTP/background concrete adapter（反向实现 port）；`lib/app/composition/cross_feature_bindings.dart` 是生产环境唯一选择 concrete 的位置，测试在 `appCompositionOverrides()` 之后用 fake 覆盖。checker 解析 `lib/**/*.dart` 的 import/export URI（统一 package/relative 解析），执行 presentation / application / domain / core 四类高信号规则，8 条 Settings 旧边用精确 source→target 对放行。

**Tech Stack:** Flutter、Dart 3.x、Riverpod 3（`NotifierProvider`）、现有 sqlite3/http、Dart SDK `dart:io`。不新增 analyzer/custom_lint/riverpod_lint/path 等依赖。

## Global Constraints

（本节的每一条对后续所有 Task 都生效，违反即 Out Of Scope）

1. **契约冻结**：不修改 `ChatCompletionClient`、`ChatConversationRepository`、`FavoritesRepository`、`CollectionsRepository` 的任何方法签名、返回值、同步/异步语义、DTO 字段、异常字段或中文 doc 措辞（doc 可原样搬移）。`ChatCompletionClient` 保持 `abstract class`（**不得**改为 `abstract interface class`，否则 `FakeChatCompletionClient extends` 会失去默认 `complete()`）。
2. **行为冻结**：不改 SQLite schema / `PRAGMA user_version` / SQL / background worker / debounce / SSE parser / vendor payload adapter / HTTP trust / 日志脱敏 / generation 逻辑 / 消息树 / request builder / Favorites 与 facade 行为。相关文件除 import 外零 body diff。
3. **绑定分离**：四个新 port 的 provider token 默认只抛 `StateError`，不得 import 或构造任何 concrete；`appCompositionOverrides()` 是生产 binding 唯一位置；`lib/bootstrap.dart` 已挂载 `...appCompositionOverrides()`，**只检查不修改**（除非编译证明无法生效，禁止制造无意义 diff）。
4. **依赖零新增**：`pubspec.yaml` / `pubspec.lock` / `analysis_options.yaml` / `dart_test.yaml` 零 diff；checker 只用 `dart:io`。
5. **例外冻结**：Settings 的 8 条 application→data 旧边是唯一 allowlist 条目，精确路径对、reason 非空；禁止通配符、目录豁免、`// ignore`、CI `continue-on-error`。
6. **删除不留 shim**：四个旧 data port 文件删除前必须 `rg` 确认零引用，删除后不留 re-export。
7. **import 风格**：跨 feature 用 `package:oh_my_llm/...` 根路径；同 feature 用相对路径（`ports/...`、`../application/ports/...`、`../../domain/...`）；不为迁移新增 barrel export。
8. **测试约定**：`FakeChatCompletionClient` 继续 `extends ChatCompletionClient` 且只 override `streamCompletion()`；`pumpTestApp` 的 `extraOverrides` 保持在 `appCompositionOverrides()` 之后（现有顺序，不得反转）。
9. **提交纪律**：每个 Task 单独 commit（共 5 个），commit message 在 **Bash** 中执行（禁用 PowerShell here-string）；提交前对全部改动 Dart 文件 `dart format`，暂存后跑 `dart format --output=none --set-exit-if-changed`，非零不得提交；post-commit hook 自动 bump 版本，**禁止手工改 `pubspec.yaml`**。
10. **测试输出重定向（强制）**：所有 `flutter test` 必须重定向到日志文件再 tail，禁止裸跑、禁止 `tee`。
11. **注释规范**：production 注释只写「为什么」，不写 Phase/TD 等临时编号；`///` doc、`//` 行间注释均简体中文。
12. **架构 fixture 不入 `lib`**：checker 的非法 fixture 只存在于内存 source map 或 `test/` 临时目录，禁止在真实 `lib` 写临时违规文件。

---

## 任务前必读：迁移前的符号/引用快照（所有 Task 的共同起点）

```powershell
rg -n "chat_completion_client\.dart|chat_conversation_repository\.dart|chatCompletionClientProvider|chatConversationRepositoryProvider|ChatCompletionClient|ChatConversationRepository" lib test
rg -n "favorites_repository\.dart|collections_repository\.dart|favoritesRepositoryProvider|collectionsRepositoryProvider|FavoritesRepository|CollectionsRepository" lib test
```

把输出按「contract / provider token / concrete 构造」三类核对。本计划中的文件清单基于 2026-08-06 实测（`rg` 命中 59 个文件），执行时以 `rg -l` 重新生成清单为准，发现清单外的引用按「使用符号」判断归属（只用 contract/DTO/provider → port import；直接构造 concrete → 保留 data import 另加 port import）。

**当前四个待迁移文件的实测内容**（迁移前后对照基准）：

| 旧文件 | 内容 | provider token 位置 |
|---|---|---|
| `lib/features/chat/data/chat_completion_client.dart` | `ChatCompletionException` + `abstract class ChatCompletionClient`（含默认 `complete()`）+ `ChatCompletionChunk` / `ChatCompletionResult` / `ChatCompletionRequestMessage` | **不在本文件**，在 `openai_compatible_chat_client.dart` 顶部 |
| `lib/features/chat/data/chat_conversation_repository.dart` | `abstract interface class ChatConversationRepository`（9 方法）+ `chatConversationRepositoryProvider` factory（watch `appDatabaseProvider` → Sqlite → Background） | 本文件顶部 |
| `lib/features/favorites/data/favorites_repository.dart` | `abstract interface class FavoritesRepository`（6 方法）+ `favoritesRepositoryProvider` factory | 本文件顶部 |
| `lib/features/favorites/data/collections_repository.dart` | `abstract interface class CollectionsRepository`（3 方法）+ `collectionsRepositoryProvider` factory | 本文件顶部 |

参考模式：`lib/features/sync/application/ports/sync_client_transport.dart` 的 provider 写法——`Provider<SyncClientTransport>((ref) { throw StateError('SyncClientTransport 尚未由应用组合层绑定'); });`。

---

### Task 1: 迁移 Chat completion/conversation ports，并建立 production binding

**Commit：** `refactor(chat): 将聊天端口归属 application`

**Files:**
- Create: `lib/features/chat/application/ports/chat_completion_client.dart`、`lib/features/chat/application/ports/chat_conversation_repository.dart`
- Delete: `lib/features/chat/data/chat_completion_client.dart`、`lib/features/chat/data/chat_conversation_repository.dart`（Step 6 零引用后）
- Modify: `lib/features/chat/data/openai_compatible_chat_client.dart`、`chat_chunk_parser.dart`、`sqlite_chat_conversation_repository.dart`、`background_chat_repository.dart`；9 个 application consumer；`lib/app/composition/cross_feature_bindings.dart`；`test/integration/bootstrap_integration_test.dart`；6 个 shared test helper；`test/features/chat/application/**`、`test/features/chat/chat_screen/*`、`test/features/history/history_screen/history_screen_pagination_bar_cases.dart`、`test/integration/{chat_lifecycle,chat_multi_conversation,preset_prompt_request,vendor_payload}_integration_test.dart` 的 import

**Interfaces:**
- Produces: `chatCompletionClientProvider`（`Provider<ChatCompletionClient>`，默认抛 `StateError`）、`chatConversationRepositoryProvider`（`Provider<ChatConversationRepository>`，默认抛 `StateError`）；port 文件内类型与原 data 文件完全同名同签名，后续 Task 直接消费。

- [ ] **Step 1: 迁移前快照**

运行「任务前必读」第一条 rg 命令，确认当前基线（把输出存档，Step 6 对照）。特别注意：`chat_sessions_controller.dart` 第 19-21 行有三个 import（`chat_completion_client.dart`、`chat_conversation_repository.dart`、`openai_compatible_chat_client.dart`——第三个只是为了 provider token）。

- [ ] **Step 2: 创建两个 Chat port 文件 + 写红灯测试**

**Step 2a. 创建 `lib/features/chat/application/ports/chat_completion_client.dart`**（完整内容，contract/DTO/异常从旧 data 文件原样搬入，仅新增 provider token）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oh_my_llm/features/settings/domain/models/llm_model_config.dart';
import '../../domain/models/chat_message.dart';

/// 流式补全请求失败时抛出的业务异常。
///
/// 面向开发者：尽量携带原始诊断信息（HTTP 状态码、响应体、源异常与堆栈），
/// 由上层格式化为可复制的错误详情，而非「傻瓜友好」文案。
class ChatCompletionException implements Exception {
  const ChatCompletionException(
    this.message, {
    this.statusCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });

  final String message;

  /// HTTP 状态码（非 2xx 响应时可用）。
  final int? statusCode;

  /// 原始响应体（HTTP 错误或 SSE 解析失败时的原文）。
  final String? responseBody;

  /// 被包装的源异常（连接中断、TLS 握手失败等）。
  final Object? cause;

  /// 源异常对应的堆栈。
  final StackTrace? causeStackTrace;

  @override
  String toString() => message;
}

/// 聊天补全客户端抽象。
abstract class ChatCompletionClient {
  /// 以流式方式拉取模型回复增量。
  ///
  /// [streamIdleTimeout] 非空时，若 SSE 流在该时长内没有任何新数据，
  /// 则抛出 [ChatCompletionException] 并关闭流。
  Stream<ChatCompletionChunk> streamCompletion({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
    Duration? streamIdleTimeout,
  });

  /// 以一次性方式获取完整回复。
  Future<ChatCompletionResult> complete({
    required LlmModelConfig modelConfig,
    required List<ChatCompletionRequestMessage> messages,
    ReasoningEffort? reasoningEffort,
  }) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    String? finishReason;
    await for (final chunk in streamCompletion(
      modelConfig: modelConfig,
      messages: messages,
      reasoningEffort: reasoningEffort,
    )) {
      contentBuffer.write(chunk.contentDelta);
      reasoningBuffer.write(chunk.reasoningDelta);
      if (chunk.finishReason != null) {
        finishReason = chunk.finishReason;
      }
    }
    return ChatCompletionResult(
      content: contentBuffer.toString(),
      reasoningContent: reasoningBuffer.toString(),
      finishReason: finishReason,
    );
  }
}

/// 流式返回的一段补全增量。
class ChatCompletionChunk {
  const ChatCompletionChunk({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.finishReason,
  });

  final String contentDelta;
  final String reasoningDelta;

  /// 模型返回的停止原因（如 "stop"、"length"），仅最后一个 chunk 非空。
  final String? finishReason;

  /// 当内容增量和推理增量都为空时，说明这段 chunk 没有有效内容。
  bool get isEmpty => contentDelta.isEmpty && reasoningDelta.isEmpty;
}

/// 一次性请求返回的完整结果。
class ChatCompletionResult {
  const ChatCompletionResult({
    this.content = '',
    this.reasoningContent = '',
    this.finishReason,
  });

  final String content;
  final String reasoningContent;

  /// 模型返回的停止原因（如 "stop"、"length"）。
  final String? finishReason;
}

/// 发给模型 API 的单条请求消息。
class ChatCompletionRequestMessage {
  const ChatCompletionRequestMessage({
    required this.role,
    required this.content,
  });

  final ChatMessageRole role;
  final String content;

  /// 转换为 API 所需的 JSON 结构。
  Map<String, dynamic> toJson() {
    return {'role': role.apiValue, 'content': content};
  }
}

/// 必须由 app composition 或测试显式绑定的聊天补全客户端。
final chatCompletionClientProvider = Provider<ChatCompletionClient>((ref) {
  throw StateError('ChatCompletionClient 尚未由应用组合层绑定');
});
```

> 注意 import 顺序：跨 feature 的 settings domain 用 `package:oh_my_llm/...` 根路径（与旧 data 文件一致）；同 feature 的 chat domain 用 `../../domain/models/chat_message.dart`（从 `application/ports/` 向上两级）。

**Step 2b. 创建 `lib/features/chat/application/ports/chat_conversation_repository.dart`**（完整内容）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_conversation_summary.dart';

/// 必须由 app composition 或测试显式绑定的会话持久化仓库。
final chatConversationRepositoryProvider =
    Provider<ChatConversationRepository>((ref) {
  throw StateError('ChatConversationRepository 尚未由应用组合层绑定');
});

/// 聊天会话持久化仓库接口。
abstract interface class ChatConversationRepository {
  /// 读取全部会话；空存储会返回空列表。
  List<ChatConversation> loadAll();

  /// 读取单个会话的完整数据（消息树、分支选择、检查点）。
  /// 找不到时返回 `null`。
  ChatConversation? loadConversation(String id);

  /// 按历史页需求读取会话摘要，并支持按标题和用户消息搜索。
  ///
  /// 传入 [limit] 时分页返回；不传时返回全部数据。
  List<ChatConversationSummary> loadHistorySummaries({
    String keyword = '',
    int? limit,
    int? offset,
  });

  /// 返回满足 [keyword] 条件的会话总数（与 [loadHistorySummaries] 的
  /// 过滤语义一致：标题 + 用户消息，忽略无消息/无 checkpoint 的空会话）。
  int countHistorySummaries({String keyword = ''});

  /// 将指定会话列表增量写回持久层（不存在则插入，存在则更新）。
  Future<void> saveConversations(List<ChatConversation> conversations);

  /// 保存单条会话，空会话（无消息、无检查点、无标题）将被跳过。
  Future<void> saveConversation(ChatConversation conversation);

  /// 从持久层删除指定 ID 的会话及其所有关联数据。
  Future<void> deleteConversations(List<String> ids);

  /// 等待所有已排队的写入耐久落盘。
  ///
  /// 调用 [saveConversation] 后若需确保数据已写入 SQLite，可 await 此方法。
  Future<void> flush();

  /// 排空所有待写入并关闭后台 Isolate。
  ///
  /// 应在应用退出或 repository 销毁前调用。调用后不应再调用 save* 方法。
  Future<void> close();
}
```

**Step 2c. 扩展 `test/integration/bootstrap_integration_test.dart`，形成红灯。**

在第三个用例 `'启动后 ProviderScope override 正确注入'` 的 `logger` 断言之后追加（Task 2 会继续追加 favorites 断言）：

```dart
    final completion = container.read(chatCompletionClientProvider);
    expect(completion, isA<OpenAiCompatibleChatClient>());

    final conversation = container.read(chatConversationRepositoryProvider);
    expect(conversation, isA<BackgroundChatConversationRepository>());
```

并新增 imports：

```dart
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
```

**Step 2d. 运行 bootstrap 集成测试确认红灯**（此时 composition 尚未绑定，`chatCompletionClientProvider` 抛 `StateError`，断言失败是预期）：

```powershell
flutter test test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-bootstrap-red.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-bootstrap-red.log
```

Expected: `EXIT=1`，日志中出现 `StateError` 或测试失败摘要。**不要提交红灯状态。**

- [ ] **Step 3: 迁移 9 个 Chat application consumer 的 import**

对以下文件执行 import 替换（同 feature 相对路径）：

| 文件 | 原 import | 新 import |
|---|---|---|
| `lib/features/chat/application/chat_generation_coordinator.dart` | `'../data/chat_completion_client.dart'` | `'ports/chat_completion_client.dart'` |
| `lib/features/chat/application/chat_generation_lifecycle.dart` | 同上 | 同上 |
| `lib/features/chat/application/chat_generation_run.dart` | 同上 | 同上 |
| `lib/features/chat/application/chat_request_message_builder.dart` | 同上 | 同上 |
| `lib/features/chat/application/chat_sessions_controller_streaming.dart` | 同上 | 同上 |
| `lib/features/chat/application/checkpoint_request_context.dart` | 同上 | 同上 |
| `lib/features/chat/application/chat_sessions_controller_support.dart` | `'../data/chat_conversation_repository.dart'` | `'ports/chat_conversation_repository.dart'` |
| `lib/features/chat/application/history_pagination_controller.dart` | 同上 | 同上 |
| `lib/features/chat/application/chat_sessions_controller.dart` | 19 行 `'../data/chat_completion_client.dart'`、20 行 `'../data/chat_conversation_repository.dart'`、21 行 `'../data/openai_compatible_chat_client.dart'` | 19 行 → `'ports/chat_completion_client.dart'`，20 行 → `'ports/chat_conversation_repository.dart'`，**21 行整行删除**（provider token 已由 port 提供） |

逐文件 `git diff` 检查：**只允许 import 行变化与因 import 排序产生的格式变化**；禁止改方法签名、状态字段、switch 分支、错误字符串、timeout。

- [ ] **Step 4: 迁移 data adapters，移出 concrete factory，绑定 composition**

**Step 4a. `lib/features/chat/data/openai_compatible_chat_client.dart`：**

- 删除 import：`package:flutter_riverpod/flutter_riverpod.dart`、`package:oh_my_llm/core/http/custom_headers_provider.dart`、`package:oh_my_llm/core/http/http_client_provider.dart`、`package:oh_my_llm/core/logging/app_network_logger_provider.dart`（均为顶部 factory 专用）。
- 修改 import：`import 'chat_completion_client.dart';` → `import '../application/ports/chat_completion_client.dart';`
- 保留 import：`dart:convert`、`dart:async`、`package:http/http.dart`、`package:oh_my_llm/core/logging/network_logger.dart`（`NetworkLogger`/`NoopNetworkLogger` 是构造参数类型）、settings domain、chat domain、`chat_chunk_parser.dart`、`vendor_payload_adapters.dart`。
- 删除文件顶部第 17-29 行整块 provider factory（`/// OpenAI 兼容接口的 HTTP 流式客户端提供者。` + `final chatCompletionClientProvider = Provider<ChatCompletionClient>(...)`）。
- 其余 body 一字不动。

**Step 4b. `lib/features/chat/data/chat_chunk_parser.dart`：**

- `import 'chat_completion_client.dart';` → `import '../application/ports/chat_completion_client.dart';`

**Step 4c. `lib/features/chat/data/sqlite_chat_conversation_repository.dart`：**

- `import 'chat_conversation_repository.dart';` → `import '../application/ports/chat_conversation_repository.dart';`

**Step 4d. `lib/features/chat/data/background_chat_repository.dart`：**

- `import 'chat_conversation_repository.dart';` → `import '../application/ports/chat_conversation_repository.dart';`
- doc 中 `[ChatConversationRepository]` 链接自动指向新 contract，措辞不改。

**Step 4e. `lib/app/composition/cross_feature_bindings.dart`：**

新增 imports（插入现有 import 块，保持字母序风格）：

```dart
import 'package:oh_my_llm/core/http/custom_headers_provider.dart';
import 'package:oh_my_llm/core/http/http_client_provider.dart';
import 'package:oh_my_llm/core/logging/app_network_logger_provider.dart';
import 'package:oh_my_llm/core/persistence/app_database_provider.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
import 'package:oh_my_llm/features/chat/application/ports/chat_conversation_repository.dart';
import 'package:oh_my_llm/features/chat/data/background_chat_repository.dart';
import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
```

在 `appCompositionOverrides()` 的返回列表**末尾**（`favoriteSourceConversationCommandProvider.overrideWith` 之后）追加两个 override。保持现有 `List<dynamic>` 签名和既有 override 顺序不动；read/watch/factory 语义与旧 factory 完全一致：

```dart
    // Chat completion：生产环境绑定 OpenAI 兼容 HTTP 流式客户端。
    chatCompletionClientProvider.overrideWith(
      (ref) => OpenAiCompatibleChatClient(
        httpClient: ref.read(httpClientProvider),
        logger: ref.watch(appNetworkLoggerProvider),
        // 在请求构建阶段读取自定义 header，确保 logRequest 之前已附加到请求上。
        extraHeadersFactory: () => ref.read(customHeadersMapProvider),
      ),
    ),
    // Chat conversation：SQLite inner + 后台 Isolate 写入代理，
    // 与迁移前的 data-owned factory 保持相同装配语义。
    chatConversationRepositoryProvider.overrideWith(
      (ref) {
        final database = ref.watch(appDatabaseProvider);
        return BackgroundChatConversationRepository(
          SqliteChatConversationRepository(database),
          database.path,
        );
      },
    ),
```

**Step 4f. 重新运行 bootstrap 集成测试，红灯转绿：**

```powershell
flutter test test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-bootstrap.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-bootstrap.log
```

Expected: `EXIT=0`。`BackgroundChatConversationRepository` 对内存库（`:memory:`）不会 spawn Isolate，测试安全。

- [ ] **Step 5: 迁移 tests/helpers，显式处理默认 binding 消失**

**5a. 纯 contract import 替换**（`data/...` → `application/ports/...`，下表中「保留」指该文件原有其他 data/concrete import 不动）：

| 文件 | import 变化 |
|---|---|
| `test/helpers/fake_chat_completion_client.dart:3` | `features/chat/data/chat_completion_client.dart` → `features/chat/application/ports/chat_completion_client.dart` |
| `test/helpers/controllable_chat_conversation_repository.dart:4` | `.../data/chat_conversation_repository.dart` → `.../application/ports/chat_conversation_repository.dart`（:5 `sqlite_chat_conversation_repository.dart` 保留——直接构造 concrete） |
| `test/helpers/flaky_chat_conversation_repository.dart:1` | 同上（:2 `sqlite_chat_conversation_repository.dart` 保留） |
| `test/helpers/fake_history_repository.dart:1` | `.../data/chat_conversation_repository.dart` → `.../application/ports/chat_conversation_repository.dart` |
| `test/helpers/fixtures.dart:7` | `.../data/chat_completion_client.dart` → `.../application/ports/chat_completion_client.dart`（:8 `sqlite_chat_conversation_repository.dart` 保留——seed 数据直接构造） |
| `test/helpers/integration_test_helpers.dart:9` | `.../data/chat_completion_client.dart` → `.../application/ports/chat_completion_client.dart` |

**5b. `test/helpers/integration_test_helpers.dart` 的 `createTestContainer`：**

- 删除 :10 `import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';`（provider token 已从 port 获取）。
- 新增 `import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';`。
- `createTestContainer` 的 overrides 改为（标准 composition 在前、fake completion 最后，保证 fake 优先级）：

```dart
ProviderContainer createTestContainer({
  required AppDatabase database,
  required SharedPreferences preferences,
  required ChatCompletionClient fakeClient,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...appCompositionOverrides(useInMemorySyncSecureStore: true),
      chatCompletionClientProvider.overrideWithValue(fakeClient),
    ],
  );
}
```

> 依赖 `createTestContainer` 的 `chat_lifecycle_integration_test.dart` 与 `chat_message_version_persistence_integration_test.dart`（后者不在本清单内，因它只间接使用）由此自动获得 repository 生产绑定，无需改这两个文件的 repository import。

**5c. `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart`（`ControllerTestHarness`）：**

- :13 `import 'package:oh_my_llm/features/chat/data/chat_completion_client.dart';` → `.../application/ports/chat_completion_client.dart`
- :14 `import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';` **保留**（`realIdleTimeoutStream` 直接构造 `OpenAiCompatibleChatClient`）。
- 新增 `import 'package:oh_my_llm/app/composition/cross_feature_bindings.dart';`
- `init()` 中 `ProviderContainer` 的 overrides 改为（composition 提供 repository 生产绑定，fake completion 最后覆盖）：

```dart
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
        ...appCompositionOverrides(useInMemorySyncSecureStore: true),
        chatCompletionClientProvider.overrideWithValue(fakeClient),
      ],
    );
```

**5d. 其余测试文件的 import 批量替换**（先 `rg -l` 重新生成清单，以下为 2026-08-06 实测基线；规则：只用 contract/DTO/provider → 只改 port import；直接构造 concrete 的测试保留 data import）：

| 目录/文件 | import 变化 |
|---|---|
| `test/features/chat/application/chat_generation_coordinator_test.dart:9`、`chat_generation_run_test.dart:8`、`chat_generation_lifecycle_test.dart:4`、`chat_generation_race_contract_test.dart:13-14`、`chat_sessions_controller_persistence_test.dart:12-13`、`chat_composer_command_test.dart:12`、`chat_workspace_view_state_test.dart:13`、`history_pagination_controller_test.dart:9`、`chat_sessions_controller/chat_sessions_controller_{branching,checkpoint,crud,generation,retry,stop}_cases.dart`、`chat_sessions_controller/chat_sessions_controller_test_helpers.dart:13` | `features/chat/data/chat_completion_client.dart` → `features/chat/application/ports/chat_completion_client.dart`；`features/chat/data/chat_conversation_repository.dart` → `features/chat/application/ports/chat_conversation_repository.dart`（若该文件同时 import 了 `data/sqlite_chat_conversation_repository.dart` 且直接构造 concrete，保留它） |
| `test/features/chat/chat_screen/chat_screen_branching_cases.dart:6`、`chat_screen_streaming_cases.dart:7`、`chat_screen_test_helpers.dart` | completion import → port |
| `test/features/history/history_screen/history_screen_pagination_bar_cases.dart:8` | repository import → port |
| `test/features/chat/data/openai_compatible_chat_client_test.dart:7`、`chat_chunk_parser_test.dart:4` | completion import → port（concrete 本体测试，直接构造的路径 import 不受影响） |
| `test/integration/chat_lifecycle_integration_test.dart:17-18`、`chat_multi_conversation_integration_test.dart`、`preset_prompt_request_integration_test.dart`、`vendor_payload_integration_test.dart:13` | 同上两条规则（integration 测试若直接构造 concrete 则保留对应 data import） |
| `test/features/chat/chat_conversation_repository_test.dart`、`test/features/chat/data/background_chat_repository_test.dart`、`background_chat_repository_lifecycle_test.dart` | **不改**（只 import concrete，无 interface/port 引用） |

5d 完成后运行 `flutter analyze` 检查遗漏（此时旧 data port 文件仍在，analyze 应 `EXIT=0`）：

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase11-task1.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase11-task1.log
```

- [ ] **Step 6: 确认零旧引用后删除两个旧 data port 文件**

```powershell
rg -n 'data/(chat_completion_client|chat_conversation_repository)\.dart' lib test
rg -n '^import .(chat_completion_client|chat_conversation_repository)\.dart.;' lib/features
```

- 第一条：若还有残留引用，先按 5d 规则修正（不能保留 re-export）。
- 第二条：新 `application/ports` 文件名相同但不含 `data/` 且路径不以 `./` 裸 import 形式命中，删除后预期两条均为零结果。
- 确认后执行 `Remove-Item` 删除两个旧文件（或 `git rm`）。

```powershell
git rm lib/features/chat/data/chat_completion_client.dart lib/features/chat/data/chat_conversation_repository.dart
```

- [ ] **Step 7: 运行 Chat 定向回归**（每条命令都必须重定向；若当前 Flutter 版本不接受多文件参数，把 integration 命令拆成四条同格式命令，不改变测试集）

```powershell
flutter test test/features/chat/application --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-chat-application.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-chat-application.log
flutter test test/features/chat/data --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-chat-data.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-chat-data.log
flutter test test/features/chat/chat_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-chat-screen.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-chat-screen.log
flutter test test/features/history/history_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-history.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-history.log
flutter test test/integration/chat_lifecycle_integration_test.dart test/integration/chat_multi_conversation_integration_test.dart test/integration/preset_prompt_request_integration_test.dart test/integration/vendor_payload_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-chat-integration.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-chat-integration.log
flutter test test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-bootstrap.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-bootstrap.log
```

每条均要求 `EXIT=0`。

- [ ] **Step 8: 格式化、检查并提交**

```powershell
dart format lib/features/chat/application/ports lib/features/chat/application lib/features/chat/data lib/app/composition test/helpers test/integration/bootstrap_integration_test.dart test/features/chat test/features/history
```

暂存（只含本 Task 改动，不得混入 Favorites port 或架构 checker）：

```bash
git add lib/features/chat test/helpers test/integration/bootstrap_integration_test.dart test/integration/chat_lifecycle_integration_test.dart test/integration/chat_multi_conversation_integration_test.dart test/integration/preset_prompt_request_integration_test.dart test/integration/vendor_payload_integration_test.dart test/features/history/history_screen/history_screen_pagination_bar_cases.dart lib/app/composition/cross_feature_bindings.dart
```

```powershell
$dartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($dartFiles) { dart format --output=none --set-exit-if-changed $dartFiles }
git diff --check
```

三项均通过后提交（Bash）：

```bash
git commit -m "refactor(chat): 将聊天端口归属 application" \
           -m "Chat application 不再通过 data 取得 completion/repository 抽象；provider token 移入 application/ports，生产 concrete 由 app composition 统一绑定，fake 可在其后覆盖。"
```

提交后 post-commit hook 会自动 bump 版本，**不要手工改 pubspec.yaml**。

---

### Task 2: 迁移 Favorites/Collections repository ports

**Commit：** `refactor(favorites): 将收藏仓库端口归属 application`

**Files:**
- Create: `lib/features/favorites/application/ports/favorites_repository.dart`、`lib/features/favorites/application/ports/collections_repository.dart`
- Delete: `lib/features/favorites/data/favorites_repository.dart`、`lib/features/favorites/data/collections_repository.dart`（Step 5 零引用后）
- Modify: `lib/features/favorites/application/favorites_controller.dart`、`collections_controller.dart`；`lib/features/favorites/data/sqlite_favorites_repository.dart`、`sqlite_collections_repository.dart`；`lib/app/composition/cross_feature_bindings.dart`；`test/features/favorites/application/favorites_controller_test.dart`；`test/integration/chat_favorites_integration_test.dart`、`collections_cascade_integration_test.dart`；`test/integration/bootstrap_integration_test.dart`

**Interfaces:**
- Consumes: Task 1 的 composition 模式（`appCompositionOverrides()` 列表 + 末尾追加 override）。
- Produces: `favoritesRepositoryProvider` / `collectionsRepositoryProvider`（默认抛 `StateError`）；类型与原 data 文件同名同签名。

- [ ] **Step 1: 新增两个 application port 与默认失败 provider**

**`lib/features/favorites/application/ports/favorites_repository.dart`**（完整内容）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/favorite.dart';

/// 必须由 app composition 或测试显式绑定的收藏记录仓库。
final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  throw StateError('FavoritesRepository 尚未由应用组合层绑定');
});

/// 收藏记录的读写仓库接口。
abstract interface class FavoritesRepository {
  /// 按收藏时间降序返回全部收藏记录，可选按收藏夹筛选。
  List<Favorite> loadAll({String? collectionId});

  /// 保存单条收藏（INSERT OR REPLACE）。
  void save(Favorite favorite);

  /// 删除指定收藏记录。
  void delete(String favoriteId);

  /// 将指定收藏移动到另一个收藏夹（null 表示未分类）。
  void moveToCollection(String favoriteId, String? collectionId);

  /// 更新指定收藏的自定义标题（null 表示清除自定义标题）。
  void updateTitle(String favoriteId, String? title);

  /// 检查指定助手消息内容是否已存在收藏。
  bool existsByAssistantContent(String assistantContent);
}
```

**`lib/features/favorites/application/ports/collections_repository.dart`**（完整内容）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/collection.dart';

/// 必须由 app composition 或测试显式绑定的收藏夹仓库。
final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  throw StateError('CollectionsRepository 尚未由应用组合层绑定');
});

/// 收藏夹的读写仓库接口。
abstract interface class CollectionsRepository {
  /// 按创建时间升序返回全部收藏夹。
  List<FavoriteCollection> loadAll();

  /// 保存单个收藏夹（INSERT OR REPLACE）。
  void save(FavoriteCollection collection);

  /// 删除指定收藏夹。
  void delete(String collectionId);
}
```

> 不要把 Phase 7 的 `ChatFavoritesFacade` 合并进 repository port：facade 是跨 Feature intent，repository 是 Favorites 内部持久化 port，职责不同。

- [ ] **Step 2: 更新 controller 与 SQLite adapter 的 import**

| 文件 | 原 import | 新 import |
|---|---|---|
| `lib/features/favorites/application/favorites_controller.dart:4` | `'../data/favorites_repository.dart'` | `'ports/favorites_repository.dart'` |
| `lib/features/favorites/application/collections_controller.dart:4` | `'../data/collections_repository.dart'` | `'ports/collections_repository.dart'` |
| `lib/features/favorites/data/sqlite_favorites_repository.dart:3` | `'favorites_repository.dart'` | `'../application/ports/favorites_repository.dart'` |
| `lib/features/favorites/data/sqlite_collections_repository.dart:3` | `'collections_repository.dart'` | `'../application/ports/collections_repository.dart'` |

除 import 外零 diff（controllers 的 body、SQL 一字不动）。

- [ ] **Step 3: 把两个 SQLite factory 放入 app composition**

`lib/app/composition/cross_feature_bindings.dart` 新增 imports：

```dart
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
```

在 Task 1 的两个 Chat override 之后追加（同一 `appCompositionOverrides()` 列表末尾）：

```dart
    favoritesRepositoryProvider.overrideWith(
      (ref) => SqliteFavoritesRepository(ref.watch(appDatabaseProvider)),
    ),
    collectionsRepositoryProvider.overrideWith(
      (ref) => SqliteCollectionsRepository(ref.watch(appDatabaseProvider)),
    ),
```

> `chatFavoritesFacadeProvider.overrideWith` 继续 watch `favoritesProvider` / `collectionsProvider`（controller provider），不直接读 repository，现有代码不用改。

- [ ] **Step 4: 更新测试 binding**

**4a. `test/features/favorites/application/favorites_controller_test.dart`：**

新增 imports：

```dart
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
```

`setUp` 中 `ProviderContainer` 的 overrides 改为（该测试不加载整套 app composition，只显式绑定两个 port provider 为内存 SQLite concrete，保持 controller 测试聚焦）：

```dart
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        favoritesRepositoryProvider.overrideWith(
          (ref) => SqliteFavoritesRepository(database),
        ),
        collectionsRepositoryProvider.overrideWith(
          (ref) => SqliteCollectionsRepository(database),
        ),
      ],
    );
```

测试用例 body 一律不改。

**4b. `test/integration/chat_favorites_integration_test.dart:19-20`、`test/integration/collections_cascade_integration_test.dart:16-17`：**

`features/favorites/data/favorites_repository.dart` → `features/favorites/application/ports/favorites_repository.dart`；`features/favorites/data/collections_repository.dart` → `features/favorites/application/ports/collections_repository.dart`。若文件直接构造 `Sqlite*Repository`（单独 import 了 `data/sqlite_*_repository.dart`），保留该 concrete import。

**4c. `test/integration/bootstrap_integration_test.dart`：**

在 Task 1 的 `conversation` 断言后追加：

```dart
    final favorites = container.read(favoritesRepositoryProvider);
    expect(favorites, isA<SqliteFavoritesRepository>());

    final collections = container.read(collectionsRepositoryProvider);
    expect(collections, isA<SqliteCollectionsRepository>());
```

新增 imports：

```dart
import 'package:oh_my_llm/features/favorites/application/ports/collections_repository.dart';
import 'package:oh_my_llm/features/favorites/application/ports/favorites_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_collections_repository.dart';
import 'package:oh_my_llm/features/favorites/data/sqlite_favorites_repository.dart';
```

- [ ] **Step 5: 零引用后删除旧 data port 文件**

```powershell
rg -n "features/favorites/data/(favorites_repository|collections_repository)\.dart|\.\./data/(favorites_repository|collections_repository)\.dart" lib test
```

预期零结果；不留 re-export。确认后：

```powershell
git rm lib/features/favorites/data/favorites_repository.dart lib/features/favorites/data/collections_repository.dart
```

- [ ] **Step 6: 运行 Favorites 与跨 Feature 回归**

```powershell
flutter test test/features/favorites/application/favorites_controller_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-favorites-application.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-favorites-application.log
flutter test test/features/favorites/data --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-favorites-data.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-favorites-data.log
flutter test test/features/favorites/favorites_screen_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-favorites-screen.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-favorites-screen.log
flutter test test/integration/chat_favorites_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-chat-favorites.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-chat-favorites.log
flutter test test/integration/collections_cascade_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-collections-cascade.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-collections-cascade.log
flutter test test/integration/bootstrap_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-bootstrap-favorites.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-bootstrap-favorites.log
```

每条均要求 `EXIT=0`。

- [ ] **Step 7: 格式化并提交**

```powershell
dart format lib/features/favorites lib/app/composition/cross_feature_bindings.dart test/features/favorites test/integration/chat_favorites_integration_test.dart test/integration/collections_cascade_integration_test.dart test/integration/bootstrap_integration_test.dart
```

```bash
git add lib/features/favorites lib/app/composition/cross_feature_bindings.dart test/features/favorites test/integration/chat_favorites_integration_test.dart test/integration/collections_cascade_integration_test.dart test/integration/bootstrap_integration_test.dart
```

```powershell
$dartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($dartFiles) { dart format --output=none --set-exit-if-changed $dartFiles }
git diff --check
```

通过后提交（Bash；暂存只含 Task 2，不得把架构 tooling 提前混入）：

```bash
git commit -m "refactor(favorites): 将收藏仓库端口归属 application" \
           -m "Favorites/Collections repository 抽象与 provider token 迁入 application/ports，SQLite concrete 反向实现 port，生产绑定集中于 app composition。"
```

---

### Task 3: 实现并验证 import boundary checker

**Commit：** `test(architecture): 增加依赖边界检查器`

**Files:**
- Create: `tool/architecture/import_boundary_checker.dart`、`tool/check_import_boundaries.dart`、`test/architecture/import_boundary_checker_test.dart`
- 不修改 `pubspec.yaml` / `analysis_options.yaml` / `lib/**`

**Interfaces:**
- Consumes: Task 1/2 迁移完成后的仓库状态（lib 内 application→data 只剩 8 条 Settings 旧边）。
- Produces: `ImportBoundaryChecker.checkSources(Map<String, String>, {bool verifyAllowlistUsage})`、`checkDirectory(Directory, {bool verifyAllowlistUsage})`、`ArchitecturePolicy`、`ArchitectureViolation`、`ImportEdge`、`architecturePolicy`（8 条例外常量）。

- [ ] **Step 1: 先写 fixture 测试（TDD 红灯）**

创建 `test/architecture/import_boundary_checker_test.dart`（完整内容；checker 文件可以先只建一个抛出 `UnimplementedError` 的 API 骨架，让本文件明确失败）：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/architecture/import_boundary_checker.dart';

ImportBoundaryChecker _checker([ArchitecturePolicy? policy]) =>
    ImportBoundaryChecker(policy: policy ?? const ArchitecturePolicy());

ArchitecturePolicy get _settingsAllowance => ArchitecturePolicy(
  legacyApplicationDataEdges: {
    ImportEdge(
      sourcePath: 'lib/features/settings/application/chat_defaults_controller.dart',
      targetPath: 'lib/features/settings/data/chat_defaults_repository.dart',
    ): '存量债务',
  },
);

void main() {
  group('合法输入', () {
    test('同 feature 分层引用零违规', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "import '../application/chat_sessions_controller.dart';\n"
                "import '../../domain/models/chat_conversation.dart';",
        'lib/features/chat/application/chat_sessions_controller.dart':
            "import '../domain/models/chat_conversation.dart';",
        'lib/features/chat/data/sqlite_chat_conversation_repository.dart':
            "import '../application/ports/chat_conversation_repository.dart';",
      });
      expect(violations, isEmpty);
    });

    test('app composition 组合 port 与 data concrete 零违规', () {
      final violations = _checker().checkSources({
        'lib/app/composition/cross_feature_bindings.dart': """
          import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';
          import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart';
        """,
      });
      expect(violations, isEmpty);
    });

    test('domain 只依赖 dart 与纯值库零违规', () {
      final violations = _checker().checkSources({
        'lib/features/chat/domain/models/chat_message.dart':
            "import 'package:equatable/equatable.dart';\nimport 'dart:async';",
      });
      expect(violations, isEmpty);
    });

    test('精确 allowlist 边放行', () {
      final violations = ImportBoundaryChecker(
        policy: _settingsAllowance,
      ).checkSources({
        'lib/features/settings/application/chat_defaults_controller.dart':
            "import '../data/chat_defaults_repository.dart';",
      });
      expect(violations, isEmpty);
    });
  });

  group('非法输入', () {
    test('presentation 直达 data（package URI）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_DATA');
    });

    test('presentation 直达 data（相对 URI 解析一致）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/screens/chat_screen.dart':
            "import '../../data/sqlite_chat_conversation_repository.dart';",
      });
      final v = violations.single;
      expect(v.ruleId, 'PRESENTATION_TO_DATA');
      expect(
        v.resolvedTarget,
        'lib/features/chat/data/sqlite_chat_conversation_repository.dart',
      );
    });

    test('presentation 直达 core persistence', () {
      final violations = _checker().checkSources({
        'lib/features/history/presentation/history_screen.dart':
            "import 'package:oh_my_llm/core/persistence/app_database.dart';",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_CORE_PERSISTENCE');
    });

    test('core 依赖 feature', () {
      final violations = _checker().checkSources({
        'lib/core/widgets/example_widget.dart':
            "import 'package:oh_my_llm/features/chat/application/ports/chat_completion_client.dart';",
      });
      expect(violations.single.ruleId, 'CORE_TO_FEATURE');
    });

    test('domain 依赖框架包', () {
      for (final pkg in ['flutter', 'flutter_riverpod', 'riverpod', 'riverpod_annotation', 'sqlite3']) {
        final violations = _checker().checkSources({
          'lib/features/chat/domain/models/chat_message.dart':
              "import 'package:$pkg/whatever.dart';",
        });
        expect(
          violations.single.ruleId,
          'DOMAIN_FRAMEWORK_DEPENDENCY',
          reason: 'package:$pkg 应被禁止',
        );
      }
    });

    test('application 直达 data（非 allowlist）', () {
      final violations = _checker().checkSources({
        'lib/features/chat/application/chat_sessions_controller.dart':
            "import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';",
      });
      expect(violations.single.ruleId, 'APPLICATION_TO_DATA');
    });

    test('allowlist 不放行同一 source 的其他 target', () {
      final violations = ImportBoundaryChecker(
        policy: _settingsAllowance,
      ).checkSources({
        'lib/features/settings/application/chat_defaults_controller.dart':
            "import '../data/other_repository.dart';",
      });
      expect(violations.single.ruleId, 'APPLICATION_TO_DATA');
    });

    test('export 不能绕过边界', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart':
            "export 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart' show ChatConversation;",
      });
      expect(violations.single.ruleId, 'PRESENTATION_TO_DATA');
    });
  });

  group('allowlist 生命周期', () {
    test('stale allowlist 条目报 STALE_ALLOWANCE', () {
      final violations = ImportBoundaryChecker(
        policy: _settingsAllowance,
      ).checkSources({}, verifyAllowlistUsage: true);
      expect(violations.single.ruleId, 'STALE_ALLOWANCE');
    });
  });

  group('扫描细节', () {
    test('注释中的伪 import 忽略；conditional 每个分支都检查', () {
      final violations = _checker().checkSources({
        'lib/features/chat/presentation/chat_screen.dart': """
          // import 'package:oh_my_llm/features/chat/data/sqlite_chat_conversation_repository.dart';
          import 'package:oh_my_llm/features/chat/data/openai_compatible_chat_client.dart'
              if (dart.library.io) 'package:oh_my_llm/features/chat/data/vendor_payload_adapters.dart';
        """,
      });
      expect(violations, hasLength(2));
      expect(violations.every((v) => v.ruleId == 'PRESENTATION_TO_DATA'), isTrue);
    });

    test('输出排序与输入顺序无关', () {
      final sourcesA = {
        'lib/features/b/presentation/b_screen.dart':
            "import 'package:oh_my_llm/features/b/data/b_repository.dart';",
        'lib/features/a/presentation/a_screen.dart':
            "import '../data/a_repository.dart';",
      };
      final sourcesB = Map<String, String>.of(sourcesA);
      final keys = sourcesB.keys.toList().reversed.toList();
      final sourcesBReordered = <String, String>{
        for (final key in keys) key: sourcesB[key]!,
      };
      final violationsA = _checker().checkSources(sourcesA);
      final violationsB = _checker().checkSources(sourcesBReordered);
      final keyOf = (ArchitectureViolation v) =>
          (v.sourcePath, v.line, v.ruleId, v.resolvedTarget);
      expect(violationsA.map(keyOf).toList(), violationsB.map(keyOf).toList());
      final sources = violationsA.map((v) => v.sourcePath).toList();
      expect(sources, List<String>.of(sources)..sort());
    });

    test('当前仓库零违规且 8 条例外均被消费', () {
      final checker = ImportBoundaryChecker(policy: architecturePolicy);
      final violations = checker.checkDirectory(
        Directory('lib'),
        verifyAllowlistUsage: true,
      );
      expect(violations, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
flutter test test/architecture/import_boundary_checker_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-architecture-red.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-architecture-red.log
```

Expected: `EXIT=1`（API 骨架抛 `UnimplementedError` 或编译失败）。

- [ ] **Step 3: 实现 `tool/architecture/import_boundary_checker.dart`**（完整内容）

```dart
import 'dart:io';

/// 一条解析后的 import/export 依赖边（source 与 target 均为仓库相对路径）。
class ImportEdge {
  const ImportEdge({required this.sourcePath, required this.targetPath});

  final String sourcePath;
  final String targetPath;

  @override
  bool operator ==(Object other) =>
      other is ImportEdge &&
      other.sourcePath == sourcePath &&
      other.targetPath == targetPath;

  @override
  int get hashCode => Object.hash(sourcePath, targetPath);

  @override
  String toString() => '$sourcePath -> $targetPath';
}

/// 架构策略：只承载存量债务的精确例外。
class ArchitecturePolicy {
  const ArchitecturePolicy({this.legacyApplicationDataEdges = const {}});

  /// application → data 的精确放行边（key 是完整规范化路径对，value 是保留原因）。
  final Map<ImportEdge, String> legacyApplicationDataEdges;
}

/// 一条架构违规。
class ArchitectureViolation {
  const ArchitectureViolation({
    required this.ruleId,
    required this.sourcePath,
    required this.line,
    required this.importUri,
    required this.resolvedTarget,
    required this.message,
  });

  final String ruleId;
  final String sourcePath;

  /// 1-based 行号；stale allowance 条目为 0。
  final int line;
  final String importUri;
  final String? resolvedTarget;
  final String message;
}

/// 生产架构策略：Settings 的 8 条存量 application→data 旧边。
///
/// 新增例外必须同步修改本常量、补 reason、补测试并经过 review；
/// 不允许从配置文件读取任意通配符。
const architecturePolicy = ArchitecturePolicy(
  legacyApplicationDataEdges: {
    ImportEdge(
      sourcePath:
          'lib/features/settings/application/chat_defaults_controller.dart',
      targetPath: 'lib/features/settings/data/chat_defaults_repository.dart',
    ): '现有 concrete SharedPreferences repository；不属于已迁移的 port 闭环。',
    ImportEdge(
      sourcePath:
          'lib/features/settings/application/fixed_prompt_sequences_controller.dart',
      targetPath: 'lib/features/settings/data/fixed_prompt_sequence_repository.dart',
    ): '现有 concrete/top-level SQLite repository；保持既有行为。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/llm_model_configs_controller.dart',
      targetPath: 'lib/features/settings/data/llm_model_config_repository.dart',
    ): '现有 concrete repository；Settings 全组不在本次迁移范围。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/memory_prompts_controller.dart',
      targetPath: 'lib/features/settings/data/sqlite_memory_prompt_repository.dart',
    ): '现有 SQLite repository object；metadata/persistence ownership 另行处理。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/model_catalog_workflow.dart',
      targetPath: 'lib/features/settings/data/model_list_client.dart',
    ): '现有 concrete HTTP client；没有 application-owned port。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/model_catalog_workflow.dart',
      targetPath: 'lib/features/settings/data/model_list_url.dart',
    ): 'data helper；不为迁移创建无收益 port。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/preset_prompts_controller.dart',
      targetPath: 'lib/features/settings/data/preset_prompt_repository.dart',
    ): '现有 concrete/top-level SQLite repository。',
    ImportEdge(
      sourcePath: 'lib/features/settings/application/template_prompts_controller.dart',
      targetPath: 'lib/features/settings/data/template_prompt_repository.dart',
    ): '现有 concrete/top-level SQLite repository。',
  },
);

/// 扫描 lib/**/*.dart 的 import/export 依赖方向，判定分层违规。
class ImportBoundaryChecker {
  ImportBoundaryChecker({required this.policy});

  final ArchitecturePolicy policy;

  /// 最近一次扫描的文件数。
  int fileCount = 0;

  static const _frameworkPackages = {
    'flutter',
    'flutter_riverpod',
    'riverpod',
    'riverpod_annotation',
    'sqlite3',
  };

  static final _directivePattern = RegExp(r'^(import|export)\s+(.+);\s*$');
  static final _uriPattern = RegExp(r"'([^']+)'|\"([^\"]+)\"");

  /// 用内存 source map 检查（fixture 测试用）。key 是 `lib/...` 仓库相对路径。
  List<ArchitectureViolation> checkSources(
    Map<String, String> sources, {
    bool verifyAllowlistUsage = false,
  }) {
    fileCount = sources.length;
    final violations = <ArchitectureViolation>[];
    final consumedAllowances = <ImportEdge>{};

    final sortedPaths = sources.keys.toList()..sort();
    for (final sourcePath in sortedPaths) {
      final lines = sources[sourcePath]!.split('\n');
      var inBlockComment = false;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (inBlockComment) {
          if (line.contains('*/')) inBlockComment = false;
          continue;
        }
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (trimmed.contains('/*')) {
          // import/export 行不会同时携带块注释，含块注释的行保守跳过。
          if (!line.contains('*/')) inBlockComment = true;
          continue;
        }
        final directive = _directivePattern.firstMatch(trimmed);
        if (directive == null) continue;
        final body = directive.group(2)!;
        // conditional directive 的所有 URI literal 都要检查；
        // show/hide 子句不携带引号字符串，不会产生伪 URI。
        for (final uriMatch in _uriPattern.allMatches(body)) {
          final uri = uriMatch.group(1) ?? uriMatch.group(2)!;
          final resolved = _resolveImport(sourcePath, uri);
          final violation = _checkEdge(
            sourcePath: sourcePath,
            line: i + 1,
            importUri: uri,
            resolvedTarget: resolved,
            consumedAllowances: consumedAllowances,
          );
          if (violation != null) violations.add(violation);
        }
      }
    }

    if (verifyAllowlistUsage) {
      for (final edge in policy.legacyApplicationDataEdges.keys) {
        if (!consumedAllowances.contains(edge)) {
          violations.add(
            ArchitectureViolation(
              ruleId: 'STALE_ALLOWANCE',
              sourcePath: edge.sourcePath,
              line: 0,
              importUri: edge.targetPath,
              resolvedTarget: edge.targetPath,
              message: 'allowlist 例外已不再被消费，请删除对应条目',
            ),
          );
        }
      }
    }

    violations.sort(_compareViolations);
    return violations;
  }

  /// 扫描真实 lib 目录（conformance 测试与 CLI 用）。
  List<ArchitectureViolation> checkDirectory(
    Directory libDirectory, {
    bool verifyAllowlistUsage = false,
  }) {
    final sources = <String, String>{};
    final libRoot = libDirectory.absolute.path;
    for (final entity in libDirectory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relative = entity.absolute.path
            .substring(libRoot.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        sources['lib/$relative'] = entity.readAsStringSync();
      }
    }
    return checkSources(sources, verifyAllowlistUsage: verifyAllowlistUsage);
  }

  ArchitectureViolation? _checkEdge({
    required String sourcePath,
    required int line,
    required String importUri,
    required String? resolvedTarget,
    required Set<ImportEdge> consumedAllowances,
  }) {
    final sourceLayer = _featureLayer(sourcePath);
    final targetLayer =
        resolvedTarget == null ? null : _featureLayer(resolvedTarget);

    if (sourceLayer == 'presentation' && targetLayer == 'data') {
      return _violation(
        'PRESENTATION_TO_DATA',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'presentation 不得导入 data',
      );
    }
    if (sourceLayer == 'presentation' &&
        resolvedTarget != null &&
        resolvedTarget.startsWith('lib/core/persistence/')) {
      return _violation(
        'PRESENTATION_TO_CORE_PERSISTENCE',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'presentation 不得导入 core/persistence',
      );
    }
    if (sourcePath.startsWith('lib/core/') &&
        resolvedTarget != null &&
        resolvedTarget.startsWith('lib/features/')) {
      return _violation(
        'CORE_TO_FEATURE',
        sourcePath,
        line,
        importUri,
        resolvedTarget,
        'core 不得导入 feature',
      );
    }
    if (sourcePath.contains('/domain/')) {
      final pkg = _packageName(importUri);
      if (pkg != null && _frameworkPackages.contains(pkg)) {
        return _violation(
          'DOMAIN_FRAMEWORK_DEPENDENCY',
          sourcePath,
          line,
          importUri,
          resolvedTarget,
          'domain 不得依赖框架包 package:$pkg',
        );
      }
    }
    if (sourceLayer == 'application' && targetLayer == 'data') {
      final edge = ImportEdge(sourcePath: sourcePath, targetPath: resolvedTarget!);
      if (policy.legacyApplicationDataEdges.containsKey(edge)) {
        consumedAllowances.add(edge);
      } else {
        return _violation(
          'APPLICATION_TO_DATA',
          sourcePath,
          line,
          importUri,
          resolvedTarget,
          'application 不得导入 data（存量例外见 architecturePolicy）',
        );
      }
    }
    return null;
  }

  /// 解析 import URI：本包 package → `lib/...`；外部 package/dart: 保留 null；
  /// 相对 URI 按 source 目录解析 `.`/`..`。
  String? _resolveImport(String sourcePath, String uri) {
    if (uri.startsWith('package:oh_my_llm/')) {
      return 'lib/${uri.substring('package:oh_my_llm/'.length)}';
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) {
      return null;
    }
    final sourceDir = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
    return _normalizePath('$sourceDir/$uri');
  }

  String _normalizePath(String path) {
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(part);
    }
    return out.join('/');
  }

  /// 返回 `features/<feature>/<layer>` 中的 layer；非 feature 路径返回 null。
  String? _featureLayer(String path) {
    final segments = path.split('/');
    final featureIndex = segments.indexOf('features');
    if (featureIndex < 0 || featureIndex + 2 >= segments.length) return null;
    return segments[featureIndex + 2];
  }

  String? _packageName(String uri) {
    if (!uri.startsWith('package:')) return null;
    return uri.substring('package:'.length).split('/').first;
  }

  ArchitectureViolation _violation(
    String ruleId,
    String sourcePath,
    int line,
    String importUri,
    String? resolvedTarget,
    String message,
  ) => ArchitectureViolation(
    ruleId: ruleId,
    sourcePath: sourcePath,
    line: line,
    importUri: importUri,
    resolvedTarget: resolvedTarget,
    message: message,
  );

  /// 结果按 sourcePath → line → ruleId → resolvedTarget 排序，
  /// 保证 Windows/Linux 输出一致。
  int _compareViolations(ArchitectureViolation a, ArchitectureViolation b) {
    final bySource = a.sourcePath.compareTo(b.sourcePath);
    if (bySource != 0) return bySource;
    if (a.line != b.line) return a.line - b.line;
    final byRule = a.ruleId.compareTo(b.ruleId);
    if (byRule != 0) return byRule;
    return (a.resolvedTarget ?? '').compareTo(b.resolvedTarget ?? '');
  }
}
```

- [ ] **Step 4: 运行 checker 测试确认通过**

```powershell
flutter test test/architecture/import_boundary_checker_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 fltest-phase11-architecture.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest-phase11-architecture.log
```

Expected: `EXIT=0`。若 conformance 用例（当前仓库扫描）失败，说明 Task 1/2 迁移有遗漏——只修 lib 的 import，**不得扩大 allowlist 掩盖**。

- [ ] **Step 5: 实现 CLI `tool/check_import_boundaries.dart`**（完整内容）

```dart
import 'dart:io';

import 'architecture/import_boundary_checker.dart';

/// 依赖边界 CLI：从仓库根运行 `dart run tool/check_import_boundaries.dart`。
///
/// 退出码：0 = 零违规；1 = 存在违规或 stale allowance；2 = 运行目录错误。
Future<void> main() async {
  final libDirectory = Directory('lib');
  if (!libDirectory.existsSync()) {
    stderr.writeln(
      '错误：找不到 lib/ 目录，请在仓库根目录运行本工具。',
    );
    exitCode = 2;
    return;
  }
  final checker = ImportBoundaryChecker(policy: architecturePolicy);
  final violations = checker.checkDirectory(
    libDirectory,
    verifyAllowlistUsage: true,
  );
  for (final violation in violations) {
    final location = violation.line > 0
        ? '${violation.sourcePath}:${violation.line}'
        : violation.sourcePath;
    stdout.writeln(
      '$location [${violation.ruleId}] ${violation.message}',
    );
  }
  stdout.writeln(
    '检查 ${checker.fileCount} 个文件，${violations.length} 条违规',
  );
  if (violations.isNotEmpty) {
    exitCode = 1;
  }
}
```

- [ ] **Step 6: 运行 CLI 验证**

```powershell
dart run tool/check_import_boundaries.dart
```

Expected: 退出码 0，输出形如 `检查 N 个文件，0 条违规`。

手工验证负例（可选但推荐，**在 test fixture 上改，不要动 production `lib`**）：临时把 Step 1 测试中某 fixture 的非法 import 恢复运行，确认报 `[APPLICATION_TO_DATA]`，然后恢复原状；或直接信任 Step 1-4 的单元测试。

- [ ] **Step 7: 格式化并提交**

```powershell
dart format tool test/architecture
dart format --output=none --set-exit-if-changed tool test/architecture
git diff --check
```

```bash
git add tool test/architecture
git commit -m "test(architecture): 增加依赖边界检查器" \
           -m "纯 Dart 扫描 lib 的 import/export，执行 presentation/application/domain/core 四类规则；Settings 8 条旧边以精确 source→target 对冻结。"
```

---

### Task 4: 接入 Phase 1 CI 门禁

**Commit：** `ci: 执行架构依赖门禁`

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: 扩展 format 门禁覆盖 `tool`**

`.github/workflows/ci.yml` 中：

```yaml
      # 1) format 门禁：代码必须已按 dart format 规范化
      - name: format check
        run: dart format --set-exit-if-changed lib test
```

改为：

```yaml
      # 1) format 门禁：代码必须已按 dart format 规范化
      - name: format check
        run: dart format --set-exit-if-changed lib test tool
```

- [ ] **Step 2: 新增独立 architecture step**

放在 format 之后、analyze 之前：

```yaml
      # 2) architecture 门禁：分层依赖规则（独立于 analyze/test 快速失败）
      - name: architecture boundaries
        run: dart run tool/check_import_boundaries.dart
```

该 step **不使用** `continue-on-error`，不重定向吞掉输出。

- [ ] **Step 3: 顺延后续注释编号**

把 analyze / version hook / test / upload test log / coverage report / upload coverage 的注释编号 `2)` `3)` `4)` `5)` 顺延为 `3)` `4)` `5)` `6)` `7)` `8)`，命令内容一律不变（UDP 排除、日志上传、coverage 逻辑保持）。

- [ ] **Step 4: 本地复现 CI 前半段并提交**

```powershell
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_import_boundaries.dart
flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase11-ci.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase11-ci.log
```

三项均 `EXIT=0` 后提交（Bash；CI 的 hosted runner 最终成功只能在 push/PR 后观察）：

```bash
git add .github/workflows/ci.yml
git commit -m "ci: 执行架构依赖门禁" \
           -m "format 覆盖 tool/，analyze 前新增独立 architecture boundaries step。"
```

---

### Task 5: 全量验证、范围审计与仅必要修复

**Commit（仅发现直接回归时）：** `fix(architecture): 修复端口迁移门禁回归`。没有回归时不创建空提交。

- [ ] **Step 1: 旧 ownership 零引用审计**

```powershell
rg -n 'data/(chat_completion_client|chat_conversation_repository|favorites_repository|collections_repository)\.dart' lib test
rg -n '^import .(chat_completion_client|chat_conversation_repository|favorites_repository|collections_repository)\.dart.;' lib/features
rg -n "chatCompletionClientProvider|chatConversationRepositoryProvider|favoritesRepositoryProvider|collectionsRepositoryProvider" lib/features lib/app
```

前两条必须零结果；第三条预期：provider 声明只出现在 `application/ports/`，production concrete factory 只出现在 `app/composition/cross_feature_bindings.dart`，consumers 只读 token。

- [ ] **Step 2: 依赖边与 allowlist 审计**

```powershell
dart run tool/check_import_boundaries.dart
rg -n '^import .*data/' lib/features -g '**/application/**/*.dart'
rg -n '^import .*core/persistence/' lib/features -g '**/presentation/**/*.dart'
rg -n '^import .*features/' lib/core
rg -n '^import .*package:(flutter|flutter_riverpod|riverpod|riverpod_annotation|sqlite3)' lib -g '**/domain/**/*.dart'
```

- application→data 搜索结果**只能**是 3.4 的 8 条 Settings 边；
- 其余三条搜索零结果。rg 无匹配返回 1 是预期的「零结果」，不是命令失败。

- [ ] **Step 3: composition 与 fake override 审计**

手工确认（可对照 Task 1/2 的 diff）：
- 四个 port provider 默认不构造 concrete（各文件仅 `throw StateError`）。
- `appCompositionOverrides()` 是 `OpenAiCompatibleChatClient`、`BackgroundChatConversationRepository`+`SqliteChatConversationRepository`、`SqliteFavoritesRepository`、`SqliteCollectionsRepository` 的唯一生产 selection 点。
- `bootstrap_integration_test.dart` 的 4 个 concrete 类型断言全部存在并通过。
- `FakeChatCompletionClient` 仍只 override `streamCompletion()`；controllable/flaky/history fake 实现 application repository port。
- `pumpTestApp` 的 `extraOverrides` 位于 `appCompositionOverrides()` 之后（`test/helpers/test_harness.dart` 现状，未被改动）。

- [ ] **Step 4: 反范围 diff 审计**

```powershell
git diff -- analysis_options.yaml pubspec.yaml pubspec.lock dart_test.yaml
git diff -- lib/features/chat/domain lib/features/favorites/domain lib/core/persistence
git diff --stat
git diff --check
git status --short
```

前两条预期空；production diff 除 port 文件、imports、composition factory 外不得有业务 body 变化。不得把测试日志（`fltest*.log`、`flanalyze*.log`）、coverage、临时 fixture 或无关文件暂存。

- [ ] **Step 5: 执行 `flutter analyze`**

```powershell
flutter analyze 2>&1 | Out-File -Encoding utf8 flanalyze-phase11.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 flanalyze-phase11.log
```

要求 `EXIT=0` 和 `No issues found!`。

- [ ] **Step 6: 按仓库强制格式执行全量测试**

```powershell
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log; $E = $LASTEXITCODE; Write-Host "EXIT=$E"; Get-Content -Tail 150 fltest.log
```

要求 `EXIT=0` 和末尾 `All tests passed!`。失败时只从日志定位：

```powershell
Select-String -Pattern " -[1-9]" -Path fltest.log
Select-String -Pattern "失败测试名" -Path fltest.log -Context 0,30
```

修复后先重跑失败文件，再重跑 `dart run tool/check_import_boundaries.dart`、analyze 和全量测试。禁止不重定向直接跑全量 `flutter test`，禁止用 `tee`。若有直接回归，单独提交 `fix(architecture): 修复端口迁移门禁回归`（Bash，格式校验同前）。

- [ ] **Step 7: 验证 hosted CI**

push/PR 后确认流水线 `format check → architecture boundaries → analyze → version hook → test → coverage` 全绿，且 architecture step 在 full test 前单独可见。若没有 push 权限，交付中明确写明「CI 配置已本地复现，hosted run 待有权限者验证」，不得宣称已完成远端验证。若 Linux 上 path 解析失败，只修 checker 的跨平台 path normalization（`Platform.pathSeparator` 分支），不放宽规则。

---

## 提交序列总览

| 顺序 | Commit message | 独立价值 | 提交前必须通过 |
|---|---|---|---|
| 1 | `refactor(chat): 将聊天端口归属 application` | Chat application 不再经 data 取得抽象；生产/fake binding 闭环 | Task 1 Step 7 全部定向测试 |
| 2 | `refactor(favorites): 将收藏仓库端口归属 application` | Favorites/Collections 闭环，不留下半迁移 | Task 2 Step 6 全部定向测试 |
| 3 | `test(architecture): 增加依赖边界检查器` | 五条规则 + 负例 + 精确债务基线本地可执行 | architecture test + CLI（均 `EXIT=0`） |
| 4 | `ci: 执行架构依赖门禁` | CI 在 analyze/full test 前快速阻断新穿透；tool 格式受控 | format + CLI + analyze |
| 5（仅必要） | `fix(architecture): 修复端口迁移门禁回归` | 只含门禁暴露的最小直接回归 | 失败定向测试 + 全部门禁 |

每个 commit 都会触发 post-commit 版本自动 bump；禁止手工预改 `pubspec.yaml`。提交前对该 commit 全部 Dart 文件执行 `dart format`，精确暂存后执行 `dart format --output=none --set-exit-if-changed`（非零不得提交），并 `git diff --check`。Commit message 一律在 Bash 中执行。

## 完成定义（对照 Phase 11 验收映射）

- 四个旧 data port 文件已删除（`rg` 零引用）；Chat/Favorites application 只依赖 `application/ports`。
- 四个 production override 在 `appCompositionOverrides()` 解析；`bootstrap_integration_test` 证明 concrete 类型。
- 8 条 Settings 旧边是唯一 application→data 例外，checker 真实仓库扫描 0 violation、0 stale。
- `flutter analyze` 与强制重定向的全量测试均 `EXIT=0`；CI 显式执行 `dart run tool/check_import_boundaries.dart`。
- 最终 diff 不含任何 Out Of Scope 项（见 Phase 11 文档第九节：不改 Settings 旧边、不加 use case/DI、不改业务 body、不加 wildcard/ignore/continue-on-error、不引入 lint 依赖、不修改 Phase 12-17 内容）。
