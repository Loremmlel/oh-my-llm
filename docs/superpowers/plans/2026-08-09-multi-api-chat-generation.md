# Multi-API Chat Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前仅支持 OpenAI Chat Completions 兼容格式的普通聊天网络链路，重构为显式支持 Chat Completions、OpenAI Responses、Anthropic Messages 三种官方协议的可维护实现，同时保持既有消息树、生成生命周期、reasoning/content 分离、inline 错误与本地上下文语义不变。

**Architecture:** 服务商保存显式 `LlmApiProtocol`；application 只依赖中立 `ChatGenerationClient`；组合根绑定按协议路由的唯一 client；三个 data client 独立编码和解析各自协议；`core/llm` 统一解析端点，`core/http` 统一负责 HTTP/SSE/timeout/取消/日志。普通聊天只回放可见文本，不回放 reasoning、signature、response ID 或工具项。

**Tech Stack:** Flutter 3.44.x / Dart 3.11+、Riverpod 3 `Provider`/`NotifierProvider`、`package:http`、原生 `dart:convert`、SSE、Equatable、SharedPreferences 版本化 JSON。

## Global Constraints

- 本计划以 [已通过的设计规格](../specs/2026-08-09-multi-api-chat-generation-design.md) 为唯一产品与架构依据；不重新解释厂商能力，也不恢复以 host 猜测厂商的旧方案。
- 保持 `ChatGenerationCoordinator` / `ChatGenerationRun` 对 prepare、stream、stop、retry、finalize、durable terminal 的唯一所有权；不得新增第二套 generation 状态机。
- 保持请求消息五段顺序：检查点记忆 -> before 预设 -> 活动对话路径 -> beforeLatestInput 预设 -> after 预设。
- 三种协议的历史 assistant 消息只发送 `content`；`reasoningContent` 继续持久化和展示，但普通聊天永不回放。
- 错误继续写入 inline assistant 消息；不得新增用于网络错误的 SnackBar 或 Dialog。
- 外部 LLM 只使用 `httpClientProvider`；Sync/Media peer 继续只使用 `peerHttpClientProvider`，不得共享 API key、Cookie 或自定义 Header。
- 自定义 Header 继续最后覆盖协议默认 Header。日志只记录脱敏后的最终 Header，请求正文默认关闭。
- 不引入 OpenAI/Anthropic SDK；继续使用原始 `package:http`。
- 不新增 SQLite migration，不修改会话 schema，不改变 `reasoning_content` 与 `finish_reason` 的持久化结构。
- 不实现 tools、MCP、Agent、图片/音频/文件、多模态、Responses 服务端状态、`previous_response_id`、`conversation`、encrypted reasoning、Anthropic signature 回放、手动 thinking budget、显式缓存断点/TTL/统计 UI、输出 token 设置、结构化输出、协议自动回退或厂商专用补丁。
- 代码注释使用简体中文，且不得写入临时计划编号；跨 `core/`、`app/`、feature 的 import 使用 `package:oh_my_llm/...`。
- 每个任务先写失败测试，再写最小实现；每个提交独立可编译、可测试、可回滚。

---

## 0. Planning Baseline and Scope Evidence

### 0.1 当前快照

- 计划编写前 HEAD：`dac542f`（`docs: 将docs/superpowers重新纳入仓库`）。
- 计划编写前 `git status --short`：无输出。
- 本机工具：Flutter 3.44.8、Dart 3.12.2；仓库/CI 固定 Flutter 3.44.6、Dart 约束 `^3.11.5`。实施者不得因该本机差异修改 CI 版本。
- 已执行相关基线：220 个测试通过，`EXIT=0`，日志为仓库根目录被忽略的 `multi-api-plan-baseline.log`。
- 基线覆盖：现有 chat data、`ChatGenerationRun`、provider/导出/模型列表/去重、core HTTP/redaction 与 vendor payload integration。
- 本计划编写阶段未运行 `flutter analyze`、架构门禁或全量测试；这些属于实现完成后的门禁，不得把计划基线误写为实现通过。

基线复现命令：

```powershell
flutter test test/features/chat/data test/features/chat/application/chat_generation_run_test.dart test/features/settings/domain/models/llm_provider_config_test.dart test/features/settings/domain/models/settings_export_codec_test.dart test/features/settings/data/llm_model_config_repository_test.dart test/features/settings/data/model_list_url_test.dart test/features/settings/data/model_list_client_test.dart test/features/settings/application/settings_import_deduplicator_test.dart test/features/settings/application/model_catalog_workflow_test.dart test/core/http test/core/logging/network_log_redactor_test.dart test/integration/vendor_payload_integration_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 multi-api-plan-baseline.log
$multiApiBaselineExit = $LASTEXITCODE
Write-Host "EXIT=$multiApiBaselineExit"
Get-Content -Tail 150 multi-api-plan-baseline.log
```

### 0.2 最终数据流

```text
LlmProviderConfig.apiProtocol
  -> LlmProviderModelConfig.resolveForProvider()
  -> LlmModelConfig.apiProtocol
  -> ChatGenerationTarget(protocol/raw endpoint/key/model)
  -> ProtocolRoutingChatGenerationClient
       -> ChatCompletionsClient
       -> ResponsesClient
       -> AnthropicMessagesClient
  -> LlmEndpointResolver.resolveGenerationEndpoint()
  -> LlmHttpStreamTransport
  -> SseEventDecoder
  -> protocol parser
  -> ChatGenerationChunk(content/reasoning/finishReason/usage)
  -> existing ChatGenerationRun
  -> existing message tree + persistence + inline error UI
```

### 0.3 目标文件结构

计划新增：

```text
lib/core/llm/
  llm_api_protocol.dart
  llm_endpoint_resolver.dart
lib/core/http/
  llm_http_stream_transport.dart
  sse_event_decoder.dart
lib/features/chat/application/ports/
  chat_generation_client.dart
lib/features/chat/data/
  protocol_routing_chat_generation_client.dart
  chat_completions/
    chat_completions_client.dart
    chat_completions_parser.dart
    inline_reasoning_tag_splitter.dart
  responses/
    responses_client.dart
    responses_parser.dart
  anthropic/
    anthropic_messages_client.dart
    anthropic_message_transformer.dart
    anthropic_parser.dart

lib/features/settings/application/
  llm_provider_equivalence.dart
```

计划删除：

```text
lib/features/chat/application/ports/chat_completion_client.dart
lib/features/chat/data/openai_compatible_chat_client.dart
lib/features/chat/data/chat_chunk_parser.dart
lib/features/chat/data/chunk_parse_strategy.dart
lib/features/chat/data/vendor_payload_adapters.dart
lib/features/settings/data/model_list_url.dart
test/features/chat/data/openai_compatible_chat_client_test.dart
test/features/chat/data/chat_chunk_parser_test.dart
test/features/chat/data/vendor_payload_adapters_test.dart
test/features/settings/data/model_list_url_test.dart
test/integration/vendor_payload_integration_test.dart
```

旧测试不是简单丢弃：其仍有效的 URL、SSE、timeout、取消、日志、错误和 Chat 行为分别迁入新 resolver/transport/protocol 测试；只删除 Google、DeepSeek、Volcengine host patch 与 Gemini List parts/`reasoning` 别名这些已明确撤销的行为断言。

---

## 1. Exact Contracts

### 1.1 协议枚举

`lib/core/llm/llm_api_protocol.dart` 的公开接口固定为：

```dart
enum LlmApiProtocol {
  chatCompletions('chatCompletions', 'Chat Completions'),
  responses('responses', 'Responses'),
  anthropic('anthropic', 'Anthropic');

  const LlmApiProtocol(this.storageValue, this.displayName);

  final String storageValue;
  final String displayName;

  static LlmApiProtocol fromStorageValue(String value) {
    return LlmApiProtocol.values.firstWhere(
      (protocol) => protocol.storageValue == value,
      orElse: () => throw FormatException('未知 LLM API 协议：$value'),
    );
  }
}
```

兼容默认值只放在 `LlmProviderConfig.fromJson()` 对“字段缺失”的处理里；枚举解析未知字符串必须失败，不能把拼写错误或未来协议静默降级为 Chat Completions。

### 1.2 Endpoint resolver

`lib/core/llm/llm_endpoint_resolver.dart` 的公开接口固定为：

```dart
final class LlmEndpointResolver {
  const LlmEndpointResolver();

  Uri resolveGenerationEndpoint({
    required String rawUrl,
    required LlmApiProtocol protocol,
  });

  Uri resolveModelsEndpoint(String rawUrl);

  Uri resolveApiRoot(String rawUrl);
}
```

共同验证：trim 后必须为绝对 `http`/`https` URI，host 非空，fragment 为空；保留 port 与 query。`resolveApiRoot()` 将域名/代理前缀统一到以 `/v1` 结尾的根，用于端点生成和导入等价键。三种已知生成后缀与 `/v1/models` 都先剥离到 API root；未知 path 视为代理前缀并追加 `/v1`，不猜测 Azure deployment 或其他厂商语义。

Settings 的共享等价键接口固定为：

```dart
typedef LlmProviderEquivalenceKey = ({
  LlmApiProtocol apiProtocol,
  String apiRoot,
  String apiKey,
});

LlmProviderEquivalenceKey buildLlmProviderEquivalenceKey(
  LlmProviderConfig provider, {
  LlmEndpointResolver resolver = const LlmEndpointResolver(),
});
```

合法 URL 的 `apiRoot` 使用 resolver；非法历史/导入 URL 使用 `provider.apiUrl.trim()` 作为不可归一化的稳定回退值，使导入不崩溃且不会错误合并。

### 1.3 中立应用端口

`lib/features/chat/application/ports/chat_generation_client.dart` 替代旧 port，公开接口固定为：

```dart
final class ChatGenerationException implements Exception {
  const ChatGenerationException(
    this.message, {
    required this.protocol,
    this.uri,
    this.statusCode,
    this.apiErrorCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });

  final String message;
  final LlmApiProtocol protocol;
  final Uri? uri;
  final int? statusCode;
  final String? apiErrorCode;
  final String? responseBody;
  final Object? cause;
  final StackTrace? causeStackTrace;
}

final class ChatGenerationTarget {
  const ChatGenerationTarget({
    required this.protocol,
    required this.endpoint,
    required this.apiKey,
    required this.model,
  });

  final LlmApiProtocol protocol;
  /// 服务商保存的原始 endpoint 输入；协议 client 在发送前统一解析。
  final String endpoint;
  final String apiKey;
  final String model;
}

final class ChatRequestMessage {
  const ChatRequestMessage({required this.role, required this.content});

  final ChatMessageRole role;
  final String content;
}

final class ChatGenerationRequest {
  const ChatGenerationRequest({
    required this.target,
    required this.messages,
    this.reasoningEffort,
    this.streamIdleTimeout,
  });

  final ChatGenerationTarget target;
  final List<ChatRequestMessage> messages;
  final ReasoningEffort? reasoningEffort;
  final Duration? streamIdleTimeout;
}

final class ChatGenerationUsage {
  const ChatGenerationUsage({
    this.inputTokens,
    this.outputTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;

  ChatGenerationUsage merge(ChatGenerationUsage newer);
}

final class ChatGenerationChunk {
  const ChatGenerationChunk({
    this.contentDelta = '',
    this.reasoningDelta = '',
    this.finishReason,
    this.usage,
  });

  final String contentDelta;
  final String reasoningDelta;
  final String? finishReason;
  final ChatGenerationUsage? usage;
  bool get isEmpty;
}

final class ChatGenerationResult {
  const ChatGenerationResult({
    this.content = '',
    this.reasoningContent = '',
    this.finishReason,
    this.usage,
  });

  final String content;
  final String reasoningContent;
  final String? finishReason;
  final ChatGenerationUsage? usage;
}

abstract class ChatGenerationClient {
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request);

  Future<ChatGenerationResult> complete(ChatGenerationRequest request) async {
    // 只折叠 streamCompletion；不得增加第二条非流式 HTTP 路径。
  }
}

final chatGenerationClientProvider = Provider<ChatGenerationClient>((ref) {
  throw StateError('ChatGenerationClient 尚未由应用组合层绑定');
});
```

`ChatGenerationTarget.endpoint` 保留服务商 trim 后的原始 URL，不在 application 层解析或重写；具体协议 client 使用共享 resolver 生成最终 URI。这样无效 URL 仍作为正常 stream error 进入现有 inline/durable failure 生命周期。`ChatGenerationException.uri` 只在原始 URL 无法形成 URI 时允许为 null；所有已发出的请求异常必须带最终 URI。`complete()` 使用最后一个非空 finish reason，并用 `ChatGenerationUsage.merge()` 合并分散在不同事件中的 usage；Fake 仍只覆写 `streamCompletion()`。

`ChatGenerationChunk.isEmpty` 只表示正文与 reasoning 增量都为空，不代表 finish reason/usage 不重要。协议 client 必须 yield 带 finish reason 或 usage 的 metadata-only chunk；“空响应”判断只累计正文/reasoning 是否出现过。

当前 `chat_generation_lifecycle.dart` 内同名 `ChatGenerationRequest` 删除。它的 `conversationId`、`assistantMessageId`、`parentMessageId` 已由 `ChatPrepareSuccess`/assistant/streaming snapshot 持有，`retryPolicy`/`retryDelay` 已由 `ChatGenerationCommand` 持有，不能复制到网络请求中。

### 1.4 SSE 与 transport

`lib/core/http/sse_event_decoder.dart`：

```dart
final class SseEvent {
  const SseEvent({this.eventName, required this.data, required this.rawData});

  final String? eventName;
  final String data;
  final String rawData;
}

final class SseIdleTimeoutException implements Exception {
  const SseIdleTimeoutException(this.timeout);
  final Duration timeout;
}

final class SseEventDecoder {
  const SseEventDecoder();

  Stream<SseEvent> decode(
    Stream<List<int>> byteStream, {
    Duration? idleTimeout,
  });
}
```

Decoder 自己处理 UTF-8 跨 byte chunk、CRLF/LF、`event:`、多个 `data:`、注释与尾事件；只有读取到 `data:` 行时重置 idle timer。取消输出订阅必须 cancel 输入订阅并取消 timer。

`lib/core/http/llm_http_stream_transport.dart`：

```dart
final class LlmHttpTransportException implements Exception {
  const LlmHttpTransportException(
    this.message, {
    required this.uri,
    this.statusCode,
    this.responseBody,
    this.cause,
    this.causeStackTrace,
  });
  // fields 与参数同名。
}

final class LlmHttpStreamTransport {
  LlmHttpStreamTransport({
    required http.Client httpClient,
    NetworkLogger logger = const NoopNetworkLogger(),
    Map<String, String> Function()? extraHeadersFactory,
    SseEventDecoder decoder = const SseEventDecoder(),
  });

  Stream<SseEvent> postSse({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> payload,
    Duration? idleTimeout,
  });
}
```

core 不得 import chat feature，所以 transport 只抛内部 `LlmHttpTransportException`/`SseIdleTimeoutException`；每个协议 client 捕获并转换为带 protocol 的 `ChatGenerationException`。非 2xx 时 transport 读完并保留原始错误体；协议 client 再提取官方 error message/code。`logRequest(..., logBody: false)` 是固定要求。

### 1.5 协议 parser 返回约定

三个 parser 的单事件方法统一使用结构相同的 Dart record：

```dart
({ChatGenerationChunk? chunk, bool isDone, bool recognized}) parse(
  SseEvent event,
);
```

- `recognized=false` 只用于未知且与文本无关的事件，由 client 写脱敏诊断后忽略。
- 明确的 error/failed/incomplete/tool 事件必须抛异常，不能返回 unknown。
- `isDone=true` 时 client yield 非空 `chunk` 后立即停止消费。
- Chat parser 另有 `ChatGenerationChunk? finish()`，只刷新 inline tag splitter 尾部。
- 每次请求创建一个 parser；parser 状态不得跨请求复用。

---

## Task 1: Add the protocol value to provider configuration

**Files**

- Create: `lib/core/llm/llm_api_protocol.dart`
- Create: `test/core/llm/llm_api_protocol_test.dart`
- Modify: `lib/features/settings/domain/models/llm_provider_config.dart`
- Modify: `lib/features/settings/domain/models/llm_model_config.dart`
- Modify: `test/features/settings/domain/models/llm_provider_config_test.dart`
- Modify: `test/features/settings/domain/models/llm_model_config_test.dart`
- Modify: `test/helpers/fixtures.dart`
- Modify every existing direct `LlmProviderConfig(...)` call listed in section 8.1.
- Modify every existing direct `LlmModelConfig(...)` call listed in section 8.1.

**Consumes:** existing provider JSON, `LlmProviderModelConfig.resolveForProvider()`.

**Produces:** required provider/model `apiProtocol`; missing legacy JSON field -> Chat Completions; unknown explicit value -> `FormatException`.

- [ ] Add failing enum tests for the three stable storage strings/display names and rejection of an unknown storage value.
- [ ] Run `flutter test test/core/llm/llm_api_protocol_test.dart --reporter compact` with redirected output; confirm compile/test failure because the enum does not exist.
- [ ] Implement `LlmApiProtocol` exactly as section 1.1.
- [ ] Add failing provider tests proving: constructor/copyWith/props include protocol; `toJson()` writes `apiProtocol`; `fromJson()` defaults only a missing field to `chatCompletions`; all three values round-trip; an unknown explicit value throws.
- [ ] Add a failing resolved-model test proving `resolveForProvider()` copies the provider protocol into `LlmModelConfig`.
- [ ] Add `required this.apiProtocol` to both `LlmProviderConfig` and `LlmModelConfig`; update `copyWith()`, `toJson()`, `fromJson()`, `props`, comments and `resolveForProvider()`.
- [ ] Update `TestFixtures.model()` and provider builders to accept `apiProtocol` with a fixture-level default of `chatCompletions`; do not make the production constructor optional.
- [ ] Update direct test constructors to pass `LlmApiProtocol.chatCompletions` unless the test intentionally covers another protocol. Add the new core import using package paths.
- [ ] Run the two model tests and repository test; confirm legacy stored provider JSON still loads without user action.
- [ ] Run `dart format` on touched Dart files and the staged format check.
- [ ] Commit: `refactor(settings): 在服务商配置中显式保存 API 协议`

Expected focused command:

```powershell
flutter test test/core/llm/llm_api_protocol_test.dart test/features/settings/domain/models/llm_provider_config_test.dart test/features/settings/domain/models/llm_model_config_test.dart test/features/settings/data/llm_model_config_repository_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 task1-provider-protocol.log
$task1Exit = $LASTEXITCODE
Write-Host "EXIT=$task1Exit"
Get-Content -Tail 150 task1-provider-protocol.log
```

Stop condition: if requiring the new field reveals a production provider constructor outside the section 8.1 audit, add that path to the audit before editing it. Do not hide the missed call site by adding a production default.

## Task 2: Upgrade Settings export and Sync snapshots from v6 to v7

**Files**

- Modify: `lib/features/settings/domain/models/settings_export_data.dart`
- Modify: `lib/features/settings/domain/models/settings_export_codec.dart`
- Modify: `lib/features/settings/application/settings_import_deduplicator.dart`
- Modify: `lib/features/settings/application/llm_model_configs_controller.dart`
- Modify: `test/features/settings/domain/models/settings_export_data_test.dart`
- Modify: `test/features/settings/domain/models/settings_export_codec_test.dart`
- Modify: `test/features/settings/application/settings_import_deduplicator_test.dart`
- Modify: `test/features/settings/application/llm_model_configs_controller_test.dart`
- Modify: `test/features/settings/application/settings_import_executor_test.dart`
- Modify: `test/features/settings/application/settings_sync_facade_test.dart`
- Modify: `test/features/settings/application/settings_transfer_workflow_test.dart`
- Modify: `test/features/sync/domain/models/sync_protocol_message_test.dart`
- Modify: `test/integration/sync_e2e_integration_test.dart`

**Consumes:** current v5/v6 codec and typed Sync snapshot.

**Produces:** v7 write format, sequential v5->v6->v7 migration, strict future/malformed rejection, protocol-aware import equivalence.

Use sequential migrators; do not change the old migrator to jump directly to the current constant:

```dart
final class SettingsExportFormatMigratorV5ToV6 {
  Map<String, Object?> migrate(Map<String, Object?> source) {
    return {...source, 'formatVersion': 6}..remove('version');
  }
}

final class SettingsExportFormatMigratorV6ToV7 {
  Map<String, Object?> migrate(Map<String, Object?> source) {
    // Deep-copy modelProviders and add apiProtocol=chatCompletions to each map.
  }
}
```

- [ ] Add failing codec tests for `formatVersion == 7`, v6 provider migration to Chat Completions, v5 sequential migration, v7 three-protocol round-trip, v4/v8 rejection, malformed v7 missing/unknown `apiProtocol`, and untouched non-provider categories.
- [ ] Run codec/data tests; confirm failures show version 6 and missing migrator behavior.
- [ ] Change `SettingsExportData.formatVersion` and JSON example to 7.
- [ ] Implement the v6->v7 migrator with defensive Map/List type checks. Preserve `sourceVersion` as the original input version and set `migrated` whenever it is not 7.
- [ ] Make current-format decoding require a valid `apiProtocol` in every provider map. The repository-level `LlmProviderConfig.fromJson()` remains missing-field compatible; export v7 must be strict because it advertises the new schema.
- [ ] Add failing dedupe/controller tests proving same URL/key/model but different protocols are not deduplicated or merged when IDs differ; normalized API-root behavior is deferred to Task 3, so use identical raw URLs in this task.
- [ ] Add protocol to `hasProviderChanges`; add protocol to the no-ID fallback key in both `SettingsImportDeduplicator` and `LlmProviderConfigsController.mergeImportedProviders()`.
- [ ] Preserve same-ID semantics: incoming provider fields, including protocol, replace local provider fields; models merge by `modelName` under the resulting provider identity.
- [ ] Extend typed Sync codec tests with a `SettingsSnapshotPayload` containing a Responses provider; assert encoded snapshot has format 7 and `apiProtocol`, decoded snapshot preserves it, and mismatched outer/inner `formatVersion` is rejected.
- [ ] Extend loopback Sync integration for a selected providers snapshot carrying an Anthropic provider; assert the client receives `apiProtocol == anthropic`. Do not change Sync wire protocol version 3.
- [ ] Run all listed settings/sync tests with redirection.
- [ ] Format, stage-check, and commit: `feat(settings): 将服务商协议纳入导出与同步格式`

Stop condition: if Sync needs a wire protocol bump merely because the nested Settings snapshot moved from v6 to v7, stop and diagnose. The approved contract is that typed Sync carries the Settings codec’s own version; Sync protocol v3 does not change.

## Task 3: Centralize API root and endpoint resolution

This task intentionally brings the design’s shared resolver one position earlier than the prose migration list so the settings import equivalence key can be completed in the same commit as endpoint semantics. The neutral application target still stores the raw URL; protocol clients resolve it immediately before transport.

**Files**

- Create: `lib/core/llm/llm_endpoint_resolver.dart`
- Create: `test/core/llm/llm_endpoint_resolver_test.dart`
- Create: `lib/features/settings/application/llm_provider_equivalence.dart`
- Create: `test/features/settings/application/llm_provider_equivalence_test.dart`
- Modify: `lib/features/settings/application/settings_import_deduplicator.dart`
- Modify: `lib/features/settings/application/llm_model_configs_controller.dart`
- Modify: `test/features/settings/application/settings_import_deduplicator_test.dart`
- Modify: `test/features/settings/application/llm_model_configs_controller_test.dart`

**Consumes:** raw provider URL plus explicit protocol.

**Produces:** deterministic API root, generation endpoint, models endpoint and normalized import key.

- [ ] Write a table-driven failing resolver test covering all three protocols for: bare domain, domain with trailing slash, `/v1`, `/v1/`, each complete known generation endpoint, conversion from each known endpoint to each other protocol, `/v1/models`, proxy prefix, proxy prefix ending `/v1`, explicit port, query preservation, uppercase HTTP scheme, relative URL, `ftp`, missing host and fragment.
- [ ] Include exact acceptance examples from the design, including `https://host/proxy/openai/v1` -> Responses `/v1/responses`.
- [ ] Assert `resolveApiRoot('https://api.openai.com')` and resolving the three full endpoints all produce `https://api.openai.com/v1`.
- [ ] Assert an unknown path such as `/gateway/team-a` is treated as a prefix and becomes `/gateway/team-a/v1`; do not scan path segments for vendor names.
- [ ] Run the new test and confirm failure because the resolver does not exist.
- [ ] Implement URI validation and path normalization in private helpers. Match only complete suffix segments, so `/v1/messages-extra` is not mistaken for `/v1/messages`.
- [ ] Keep query during path replacement and reject fragment before any mutation.
- [ ] Implement `LlmProviderEquivalenceKey` as a named record typedef and `buildLlmProviderEquivalenceKey(LlmProviderConfig provider, {LlmEndpointResolver resolver = const LlmEndpointResolver()})` in `llm_provider_equivalence.dart`; the value must be `(apiProtocol: ..., apiRoot: ..., apiKey: ...)`.
- [ ] Add direct helper tests for same/different protocol, root, query and key. Use this one helper from both `SettingsImportDeduplicator` and `LlmProviderConfigsController`; do not duplicate normalization logic.
- [ ] Add dedupe tests proving domain, `/v1`, and a full endpoint normalize to the same root for the same protocol; different query values remain distinct; invalid imported URLs are not silently merged. Let malformed URLs remain separate and be rejected when used, rather than crashing import.
- [ ] For invalid URL comparison, catch resolver failure only inside equivalence matching and fall back to the trimmed raw URL; do not rewrite stored configuration.
- [ ] Run resolver, dedupe and controller tests.
- [ ] Format, stage-check, and commit: `refactor(llm): 统一解析生成与模型端点`

## Task 4: Replace the Chat Completion port with the neutral generation port

**Files**

- Create: `lib/features/chat/application/ports/chat_generation_client.dart`
- Create: `test/features/chat/application/chat_generation_client_test.dart`
- Delete at task end: `lib/features/chat/application/ports/chat_completion_client.dart`
- Modify: `lib/features/chat/application/chat_generation_lifecycle.dart`
- Modify: `lib/features/chat/application/chat_generation_run.dart`
- Modify: `lib/features/chat/application/chat_generation_coordinator.dart`
- Modify: `lib/features/chat/application/chat_request_message_builder.dart`
- Modify: `lib/features/chat/application/checkpoint_request_context.dart`
- Modify: `lib/features/chat/application/chat_sessions_controller.dart`
- Modify: `lib/features/chat/application/chat_sessions_controller_streaming.dart`
- Modify: `lib/features/chat/data/openai_compatible_chat_client.dart` as a temporary thin implementation of the new port; it must reject non-Chat protocols until replaced in Task 7.
- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Rename: `test/helpers/fake_chat_completion_client.dart` -> `test/helpers/fake_chat_generation_client.dart`
- Modify: `test/helpers/fixtures.dart`
- Modify: `test/helpers/test_harness.dart`
- Modify: `test/helpers/integration_test_helpers.dart`
- Modify all port symbol/import call sites listed in section 8.2.
- Modify: `test/architecture/import_boundary_checker_test.dart`

**Consumes:** existing lifecycle and resolved `LlmModelConfig`.

**Produces:** one neutral client port/provider/request/chunk/result/exception vocabulary; no duplicate lifecycle state.

- [ ] Add failing port tests in `test/features/chat/application/chat_generation_client_test.dart` for `complete()` folding content/reasoning/latest finish reason and merging split usage fields; prove a Fake only implements `streamCompletion(ChatGenerationRequest)`.
- [ ] Add failing request-builder assertions that assistant `reasoningContent` never appears in `ChatRequestMessage.content`; preserve the exact five-segment ordering.
- [ ] Implement the types in section 1.3 and `ChatGenerationUsage.merge()` with “new non-null field wins, otherwise keep old” semantics.
- [ ] Move the name `ChatGenerationRequest` out of lifecycle into the port and remove lifecycle-only fields. Keep retry policy/delay on `ChatGenerationCommand`; keep assistant/conversation ownership in `ChatPrepareSuccess` and snapshots.
- [ ] Add a private controller helper that converts `LlmModelConfig` to `ChatGenerationTarget(protocol: modelConfig.apiProtocol, endpoint: modelConfig.apiUrl, apiKey: modelConfig.apiKey, model: modelConfig.modelName)` without resolving or rewriting the URL.
- [ ] In `prepare()`, build exactly one neutral request from target/messages/reasoning/idle timeout after durable pending save. URL resolution remains in the concrete protocol stream, so invalid configuration follows the same partial/inline error path as other network failures.
- [ ] Change checkpoint summary generation to call `chatClient.complete(ChatGenerationRequest(...))`; it now uses the same stream-folding path as normal chat.
- [ ] Change `ChatGenerationRun._startStream()` to pass the request object directly. Keep chunk accumulation, throttling, stop, retry and finalization code otherwise unchanged; ignore usage because this phase has no usage UI/persistence.
- [ ] Rename the exception formatter branch to `ChatGenerationException` and include protocol/URI/API error code when present without dropping existing status/body/cause/stack diagnostics.
- [ ] Rename provider/getter/bind flag: `chatGenerationClientProvider`, `chatClient: ChatGenerationClient`, `bindChatGenerationClient`. Update composition comments.
- [ ] Adapt the legacy concrete client only enough to implement the new signature and consume `request.target`; add an explicit protocol guard for non-Chat requests. Do not refactor its parser/transport yet and do not add Responses/Anthropic fields here.
- [ ] Rename test Fake types to `FakeChatGenerationClient`, `ControlledChatGenerationStream`, and `ChatGenerationChunk`; keep queue/listened/cancel behavior and request history, now recording whole `ChatGenerationRequest` values.
- [ ] Mechanically migrate all tests/imports and update architecture examples to the new port/concrete path. Do not alter their behavioral assertions except for the new request wrapper and removal of obsolete lifecycle fields.
- [ ] Run `rg -n "ChatCompletion(Client|Chunk|Result|RequestMessage|Exception)|chatCompletionClientProvider|bindChatCompletionClient" lib test --glob "*.dart"`; expected no output after this task. `OpenAiCompatibleChatClient` may remain by class name only until Task 7.
- [ ] Run request-builder, lifecycle, coordinator, run, controller, chat screen and integration suites listed in section 9.2.
- [ ] Run the architecture boundary test and CLI gate.
- [ ] Format, stage-check, and commit: `refactor(chat): 泛化普通聊天生成端口`

Stop condition: if any code attempts to keep both old and new provider bindings, stop. The task may use a temporary concrete client, but it must not leave two application ports or two Riverpod providers.

## Task 5: Implement the byte-safe SSE decoder

**Files**

- Create: `lib/core/http/sse_event_decoder.dart`
- Create: `test/core/http/sse_event_decoder_test.dart`

**Consumes:** arbitrary `Stream<List<int>>` network byte chunks.

**Produces:** protocol-neutral `SseEvent` values with correct boundaries, timeout and cancellation.

- [ ] Add a test helper that splits one UTF-8 SSE document at every byte boundary, including inside a Chinese multi-byte code point; do not assume network chunks align with lines or characters.
- [ ] Add failing parameterized tests for LF and CRLF, `event:`, multiple `data:` lines joined with `\n`, ignored `:` comments, ignored unknown fields, empty events, blank `data:`, and a final event without a trailing empty line.
- [ ] Assert `rawData` is the joined untrimmed `data:` field payload used for diagnostic logging, while `data` follows SSE field parsing rules. Do not retain API headers or keys in this object.
- [ ] Add a cancellation test using a source `StreamController<List<int>>(onCancel: ...)`; cancel the decoded subscription and await an explicit cancellation completer.
- [ ] Add timeout tests with a controlled stream: comment lines do not reset the timer; a `data:` line does reset it; cancellation cancels the outstanding timer. Await the emitted error/completion instead of inserting `Future.delayed` into the test.
- [ ] Run the test and confirm it fails because the decoder is absent.
- [ ] Implement the decoder using `utf8.decoder` plus line accumulation. Treat both `\n` and `\r\n` correctly and flush a final unterminated line/event on source completion.
- [ ] Own exactly one input subscription and one idle `Timer`. Forward pause/resume, cancel both on output cancellation, and guard all timer callbacks after close.
- [ ] Start the idle timer when listening if timeout is non-null; reset it only after a syntactically valid `data:` line is observed, including Anthropic ping data.
- [ ] Run the test repeatedly 10 times to expose byte-boundary or cancel races; do not fix failures by widening arbitrary sleeps.
- [ ] Format, stage-check, and commit: `refactor(http): 增加协议无关的 SSE 事件解码器`

Expected repeated command:

```powershell
1..10 | ForEach-Object {
  $task5Round = $_
  $task5Log = "task5-sse-$task5Round.log"
  flutter test test/core/http/sse_event_decoder_test.dart --reporter compact 2>&1 | Out-File -Encoding utf8 $task5Log
  $task5Exit = $LASTEXITCODE
  if ($task5Exit -ne 0) {
    Get-Content -Tail 150 $task5Log
    throw "SSE decoder round $task5Round failed, EXIT=$task5Exit"
  }
}
```

## Task 6: Extract the shared LLM HTTP streaming transport

**Files**

- Create: `lib/core/http/llm_http_stream_transport.dart`
- Create: `test/core/http/llm_http_stream_transport_test.dart`
- Create: `test/helpers/fake_streaming_http_client.dart`

**Consumes:** final URI/default headers/JSON payload, `httpClientProvider`-compatible client, logger and SSE decoder.

**Produces:** logged, cancellable, timeout-aware `Stream<SseEvent>`; no protocol JSON knowledge.

- [ ] Add reusable `test/helpers/fake_streaming_http_client.dart`. Its API enqueues `http.StreamedResponse`, records `http.BaseRequest`, and exposes cancellation completers; it must not know chat protocols. Reuse it in all three protocol client tests and the final integration harness.
- [ ] Write failing tests for POST method, JSON UTF-8 body, caller-provided headers, 2xx response, SSE forwarding, network exception cause/stack, non-2xx status/body, empty non-2xx body, request/response/SSE/error logging and cancellation propagation.
- [ ] Compose `CustomHeadersHttpClient` around the fake client and pass an `extraHeadersFactory`; prove a custom `Authorization` or `x-api-key` overrides the protocol default both on the actual request and in the logger input.
- [ ] Assert request logging receives `logBody == false` even though the transport has the payload object. This is a hard privacy regression test.
- [ ] Assert non-2xx body is not emitted to the SSE decoder and is attached to `LlmHttpTransportException`.
- [ ] Run the new test and confirm it fails because the transport does not exist.
- [ ] Implement `postSse()` with `http.Request`, `jsonEncode`, `_httpClient.send()`, response status validation and `SseEventDecoder.decode()`.
- [ ] Log the merged `{...defaultHeaders, ...extraHeadersFactory()}` map so diagnostics reflect the final user override. Let `CustomHeadersHttpClient.send()` remain the sole actual injection point; do not inject the same map twice into the outgoing request.
- [ ] Use `unawaited` only for non-critical request/response/SSE logs. Await error logs on caught failures where preserving ordering aids diagnostics.
- [ ] Wrap transport/network/SSE timeout errors in `LlmHttpTransportException`, retaining URI, status/body and source stack. Do not create `ChatGenerationException` in core.
- [ ] Run transport, decoder, custom-header and redactor tests.
- [ ] Run `dart run tool/check_import_boundaries.dart`; core must have zero feature imports.
- [ ] Format, stage-check, and commit: `refactor(http): 抽取 LLM 流式请求传输层`

## Task 7: Replace the legacy client with the official Chat Completions implementation

**Files**

- Create: `lib/features/chat/data/chat_completions/chat_completions_client.dart`
- Create: `lib/features/chat/data/chat_completions/chat_completions_parser.dart`
- Create: `lib/features/chat/data/chat_completions/inline_reasoning_tag_splitter.dart`
- Create: `test/features/chat/data/chat_completions/chat_completions_client_test.dart`
- Create: `test/features/chat/data/chat_completions/chat_completions_parser_test.dart`
- Create: `test/features/chat/data/chat_completions/inline_reasoning_tag_splitter_test.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart` to bind the new Chat client temporarily until router wiring in Task 10.
- Modify: timeout helper references in `test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart`.
- Delete: `lib/features/chat/data/openai_compatible_chat_client.dart`
- Delete: `lib/features/chat/data/chat_chunk_parser.dart`
- Delete: `lib/features/chat/data/chunk_parse_strategy.dart`
- Delete: `lib/features/chat/data/vendor_payload_adapters.dart`
- Delete/replace: their three unit tests and `test/integration/vendor_payload_integration_test.dart`.
- Modify: `test/integration/bootstrap_integration_test.dart`

**Consumes:** neutral request, shared transport/SSE.

**Produces:** official Chat Completions request/stream behavior plus the explicitly retained `reasoning_content` and three inline tags; no vendor host logic.

Request encoding must be exactly:

```dart
final payload = <String, Object?>{
  'model': request.target.model,
  'stream': true,
  'messages': [
    for (final message in request.messages)
      {'role': message.role.apiValue, 'content': message.content},
  ],
  if (request.reasoningEffort case final effort?)
    'reasoning_effort': effort.apiValue,
};
```

Headers: `Content-Type: application/json`, `Accept: text/event-stream`, `Authorization: Bearer <key>`.

- [ ] Port the still-valid legacy client tests into the three new test files before deleting the old test: content, `reasoning_content`, `finish_reason`, `[DONE]`, `message` envelope, HTTP/SSE error, malformed JSON, empty response, logging, timeout and cancellation.
- [ ] Add negative tests proving `delta.reasoning` no longer becomes reasoning, List-valued `delta.content` no longer produces text, and DeepSeek/Ark/Google hosts do not add `thinking`, `extra_body`, or suppress official `reasoning_effort`.
- [ ] Add request tests for all current effort values. Chat sends their `apiValue` unchanged, including `xhigh` and `max`; null omits the field.
- [ ] Write splitter tests for exactly singular `<thought>`, `<thinking>`, `<think>` tags. Add case-insensitive names, opening whitespace/attributes, closing whitespace, multiple tags, arbitrary chunk splits, explicit reasoning followed by inline reasoning, unclosed opening tag, incomplete tag at stream end and unmatched closing tag.
- [ ] Explicitly assert plural `<thoughts>`/`<thinkings>` are ordinary content; the approved retained set contains only the three singular tags.
- [ ] Run the new tests and confirm they fail before implementation.
- [ ] Implement `InlineReasoningTagSplitter` as a request-scoped state machine. Opening regex may accept attributes; closing regex must not accept attributes. When flushing an incomplete candidate tag, emit it through the current channel.
- [ ] Implement `ChatCompletionsParser.parse()` using only `choices[0].delta ?? choices[0].message`, string `content`, string `reasoning_content`, finish reason and official error envelope. Return `[DONE]` as `isDone=true`.
- [ ] When one envelope has both explicit and inline reasoning, form `reasoningDelta` as explicit text first, then extracted inline text.
- [ ] Map Chat usage when naturally present: `prompt_tokens`, `completion_tokens`, `completion_tokens_details.reasoning_tokens`, `prompt_tokens_details.cached_tokens`. Missing/non-int values remain null.
- [ ] Implement `ChatCompletionsClient` with a protocol guard, official headers/payload, shared transport loop, unknown-event diagnostic logging, parser finish flush and the common empty-response rule.
- [ ] Resolve `request.target.endpoint` with `resolveGenerationEndpoint(..., chatCompletions)` immediately before transport. Convert resolver failures into `ChatGenerationException` without attempting HTTP.
- [ ] Catch `LlmHttpTransportException`, decode `{error:{message,code}}` or string error when possible, and throw `ChatGenerationException` with protocol/endpoint/status/body/cause.
- [ ] Switch composition and bootstrap type assertion to `ChatCompletionsClient`; inject one shared transport and logger. Do not add the protocol router until Task 10.
- [ ] Update the controller timeout helper to build a neutral Chat request through the new client. Preserve its observable retry-timeout contract.
- [ ] Delete all four legacy production files and obsolete tests only after their valid cases are present in the new tests.
- [ ] Run the removal audits in section 9.4; there must be no host comparisons or vendor patch symbols.
- [ ] Run Chat parser/client, controller retry, bootstrap integration and core transport tests.
- [ ] Format, stage-check, and commit: `refactor(chat): 以官方模式实现 Chat Completions`

Stop condition: if a compatibility endpoint requires List parts or `reasoning` alias for an existing test, keep the new negative test and report the compatibility loss as intentional. Do not reintroduce the removed fallback without a new product decision.

## Task 8: Implement stateless OpenAI Responses

**Files**

- Create: `lib/features/chat/data/responses/responses_client.dart`
- Create: `lib/features/chat/data/responses/responses_parser.dart`
- Create: `test/features/chat/data/responses/responses_client_test.dart`
- Create: `test/features/chat/data/responses/responses_parser_test.dart`

**Consumes:** neutral text messages, reasoning effort and Responses SSE events.

**Produces:** `store:false` stateless text/reasoning/refusal stream with normalized completion.

Request encoding must be exactly:

```dart
final payload = <String, Object?>{
  'model': request.target.model,
  'stream': true,
  'store': false,
  'input': [
    for (final message in request.messages)
      {'role': message.role.apiValue, 'content': message.content},
  ],
  if (request.reasoningEffort case final effort?)
    'reasoning': {
      'effort': effort.apiValue,
      'summary': 'auto',
      'context': 'current_turn',
    },
};
```

- [ ] Add failing request tests for URL/header/body and all efforts; null omits `reasoning`.
- [ ] Assert every request has `store:false` and lacks `previous_response_id`, `conversation`, `include`, encrypted reasoning and response IDs.
- [ ] Add parser tests for `response.output_text.delta`, `response.reasoning_summary_text.delta`, `response.reasoning_text.delta`, `response.refusal.delta`, `response.completed`, `response.incomplete`, `response.failed`, `error`, unknown bookkeeping events and malformed JSON.
- [ ] Include both `event:` names and JSON `type`; if both exist and disagree, use the JSON `type` as the authoritative event payload type and record the envelope mismatch as an unknown diagnostic, not duplicate content.
- [ ] Add `.done` tests carrying full text/summary and prove they do not append content or reasoning a second time.
- [ ] Normalize completed -> `stop`; incomplete reason `max_output_tokens` -> `length`; other incomplete reasons remain their raw string after throwing only when the event represents failure rather than a normal incomplete terminal.
- [ ] Clarify terminal behavior in tests: `response.incomplete` is a terminal chunk with normalized finish reason, not an exception; `response.failed`/`error` are exceptions.
- [ ] Map natural usage from completed/incomplete response objects: input/output tokens, output reasoning tokens and cached input tokens. Do not request extra usage fields.
- [ ] Implement parser and client with the same transport-error translation and common empty-response rule as Chat.
- [ ] Resolve `request.target.endpoint` with the Responses protocol immediately before transport; never reuse an endpoint URI previously resolved for Chat.
- [ ] Test refusal as user-visible `contentDelta`, so it persists and renders through the normal assistant body.
- [ ] Test partial output followed by failed/error: emitted partial chunks remain observable before the stream error; the existing run is responsible for durable failure handling.
- [ ] Run Responses tests plus neutral port folding tests.
- [ ] Format, stage-check, and commit: `feat(chat): 增加无状态 Responses 协议客户端`

## Task 9: Implement Anthropic message transformation and streaming

**Files**

- Create: `lib/features/chat/data/anthropic/anthropic_message_transformer.dart`
- Create: `lib/features/chat/data/anthropic/anthropic_messages_client.dart`
- Create: `lib/features/chat/data/anthropic/anthropic_parser.dart`
- Create: `test/features/chat/data/anthropic/anthropic_message_transformer_test.dart`
- Create: `test/features/chat/data/anthropic/anthropic_messages_client_test.dart`
- Create: `test/features/chat/data/anthropic/anthropic_parser_test.dart`

**Consumes:** neutral messages and Anthropic Messages SSE.

**Produces:** leading-system transformation, automatic cache request, adaptive thinking and text/reasoning chunks.

Transformer interface:

```dart
final class AnthropicMessageTransform {
  const AnthropicMessageTransform({required this.system, required this.messages});
  final String? system;
  final List<Map<String, String>> messages;
}

final class AnthropicMessageTransformer {
  const AnthropicMessageTransformer();
  AnthropicMessageTransform transform(List<ChatRequestMessage> source);
}
```

- [ ] Write failing transformer table tests for: no system; one leading system; multiple contiguous leading systems joined by one newline; a later system converted to user; several later systems; consecutive user/assistant roles merged by one newline after conversion; leading system followed by later system; input order preserved; source list unchanged.
- [ ] Do not trim or discard message content inside the transformer. The request builders already decide which template messages are empty; preserving exact text avoids protocol-specific prompt rewriting.
- [ ] Implement the single-pass algorithm: consume the maximal leading System prefix, join it; convert every remaining System to User; then merge adjacent equal roles.
- [ ] Add failing client body tests for `model`, `stream:true`, `max_tokens:8192`, top-level `cache_control:{type:ephemeral}`, optional top-level `system`, transformed messages and protocol headers.
- [ ] Assert headers are exactly the defaults `Content-Type`, `Accept`, `x-api-key`, `anthropic-version: 2023-06-01`; custom Header override remains transport-level.
- [ ] Add effort mapping tests: low->low, medium->medium, high->high, xhigh->max, max->max. When reasoning is enabled, send `thinking:{type:adaptive,display:summarized}` and `output_config:{effort:...}`. Null omits both.
- [ ] Add parser tests for `content_block_delta/text_delta`, `thinking_delta`, ignored `signature_delta`, `message_delta.delta.stop_reason`, `message_stop`, ping, error, malformed JSON and unknown lifecycle events.
- [ ] Add explicit failure tests for `content_block_start` declaring `tool_use`, `server_tool_use` or another tool content block. The error message must state that ordinary chat does not support that response type.
- [ ] Normalize `end_turn`/`stop_sequence` -> stop, `max_tokens`/`model_context_window_exceeded` -> length, `refusal` -> refusal, and preserve unknown stop strings.
- [ ] Map input/cache usage from `message_start.message.usage` and output usage from `message_delta.usage`; emit cumulative merged usage so base `complete()` can retain both halves. Ignore signature data completely.
- [ ] Implement client error extraction from Anthropic `{type:'error', error:{type,message}}`, storing `error.type` as `apiErrorCode`.
- [ ] Resolve `request.target.endpoint` with the Anthropic protocol immediately before transport; a full Chat/Responses suffix must be replaced with `/v1/messages`.
- [ ] Verify ping’s `data:` line resets shared idle timeout even though the parser yields no chunk; the decoder, not the parser, owns that rule.
- [ ] Apply the common empty-response rule: reasoning-only succeeds; text/reasoning both empty fails; message_stop alone is not content.
- [ ] Run all Anthropic tests and the SSE/transport tests.
- [ ] Format, stage-check, and commit: `feat(chat): 增加 Anthropic Messages 协议客户端`

## Task 10: Bind one protocol router in the composition root

**Files**

- Create: `lib/features/chat/data/protocol_routing_chat_generation_client.dart`
- Create: `test/features/chat/data/protocol_routing_chat_generation_client_test.dart`
- Modify: `lib/app/composition/cross_feature_bindings.dart`
- Modify: `test/integration/bootstrap_integration_test.dart`
- Modify: `test/helpers/test_harness.dart`

**Consumes:** one neutral request and three concrete clients.

**Produces:** the only production `chatGenerationClientProvider` binding.

Router interface:

```dart
final class ProtocolRoutingChatGenerationClient implements ChatGenerationClient {
  const ProtocolRoutingChatGenerationClient({
    required ChatGenerationClient chatCompletionsClient,
    required ChatGenerationClient responsesClient,
    required ChatGenerationClient anthropicClient,
  });

  @override
  Stream<ChatGenerationChunk> streamCompletion(ChatGenerationRequest request);
}
```

- [ ] Write failing parameterized tests with three recording clients; for each protocol assert exactly the matching delegate receives the identical request object and the other two receive zero calls.
- [ ] Add propagation tests proving delegate chunks/errors/cancellation are not transformed, swallowed or retried by the router.
- [ ] Implement a total `switch` on `request.target.protocol`; no host/model-name checks, JSON parsing or request copying.
- [ ] In composition, construct one `LlmHttpStreamTransport` from `httpClientProvider`, `appNetworkLoggerProvider` and `customHeadersMapProvider`; inject it into all three clients.
- [ ] Bind only `ProtocolRoutingChatGenerationClient` to `chatGenerationClientProvider`. Remove the temporary direct Chat binding.
- [ ] Update bootstrap integration to assert router type, not a concrete protocol client. Do not expose router internals merely for the assertion.
- [ ] Keep the test harness opt-out flag `bindChatGenerationClient`; fake overrides remain at the neutral provider.
- [ ] Run router, bootstrap, application generation and chat screen tests.
- [ ] Run `rg -n "chatGenerationClientProvider\.overrideWith" lib --glob "*.dart"`; expected one production binding in `cross_feature_bindings.dart`.
- [ ] Format, stage-check, and commit: `refactor(chat): 按服务商协议路由聊天请求`

## Task 11: Expose protocol selection in provider settings

**Files**

- Modify: `lib/features/settings/presentation/widgets/form/model_provider_form_dialog.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `lib/features/settings/presentation/widgets/list/provider_info_body.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_test_helpers.dart`

**Consumes:** `LlmApiProtocol` and provider add/edit flow.

**Produces:** visible add/edit selection, Chat default, persisted protocol and list label.

- [ ] Add widget tests that open “新增服务商”, find a labeled `API 模式` field, and observe Chat Completions selected by default.
- [ ] Add a test selecting Responses, entering a bare domain URL, saving, and asserting provider state has Responses while the stored `apiUrl` remains the trimmed raw domain rather than an auto-expanded endpoint.
- [ ] Add an edit test changing an existing provider from Chat to Anthropic; assert its existing model IDs remain and every resolved model now inherits Anthropic.
- [ ] Add a visible-behavior assertion that the provider card displays exactly `API 模式：Anthropic`.
- [ ] Run the settings widget entry and confirm failures.
- [ ] Add `apiProtocol` to `ModelProviderFormData`; initialize from existing provider or Chat default.
- [ ] Add `DropdownButtonFormField<LlmApiProtocol>` with label `API 模式` and exactly three options. Do not infer protocol from URL or model name.
- [ ] Update URL hint/help to state domain, `/v1`, or a full generation endpoint are accepted. Update form validation to require absolute HTTP(S), non-empty host and no fragment, matching the resolver; old imported/stored invalid values still receive the same resolver error when used.
- [ ] Update SettingsScreen provider construction to save `formData.apiProtocol` and preserve existing models on edit.
- [ ] Add a protocol `ProviderMetaChip` before endpoint/key metadata. Keep API key masking unchanged.
- [ ] Run settings screen/model form/provider domain tests at both default and compact viewports already used by the suite.
- [ ] Format, stage-check, and commit: `feat(settings): 允许服务商选择聊天 API 协议`

## Task 12: Make model catalog resolution and authentication protocol-aware

**Files**

- Modify: `lib/features/settings/application/model_catalog_workflow.dart`
- Modify: `lib/features/settings/data/model_list_client.dart`
- Modify: `lib/features/settings/presentation/widgets/form/model_fetch_section.dart`
- Delete: `lib/features/settings/data/model_list_url.dart`
- Modify: `test/features/settings/application/model_catalog_workflow_test.dart`
- Modify: `test/features/settings/data/model_list_client_test.dart`
- Delete: `test/features/settings/data/model_list_url_test.dart`
- Modify: `test/features/settings/presentation/model_config_form_dialog_test.dart`
- Modify: `test/features/settings/settings_screen/settings_screen_models_and_prompts_cases.dart`

**Consumes:** provider protocol/raw URL/key and optional explicit models URL.

**Produces:** shared resolver `/v1/models` endpoint and protocol-correct authentication.

Use these exact application/data inputs:

```dart
final class ModelCatalogRequest {
  const ModelCatalogRequest({
    required this.apiProtocol,
    required this.apiUrl,
    required this.apiKey,
    this.modelsUrlOverride,
  });
  // fields match parameters
}

Future<List<ModelCatalogEntry>> fetchModels({
  required Uri modelsEndpoint,
  required LlmApiProtocol apiProtocol,
  required String apiKey,
});
```

- [ ] Add failing workflow tests proving automatic URL uses `LlmEndpointResolver.resolveModelsEndpoint()` for bare domain, `/v1`, any full generation endpoint and proxy prefix.
- [ ] Assert a non-empty manual override is trimmed, validated as an absolute HTTP(S) URI with no fragment, and used exactly; it is not passed through generation suffix replacement.
- [ ] Add client tests for Chat/Responses Bearer auth and Anthropic `x-api-key` plus fixed `anthropic-version`; all use `Accept: application/json`.
- [ ] Add custom-header precedence/logging tests parallel to generation transport. Extend `ModelListClient` with `extraHeadersFactory` because current logging otherwise cannot reflect final injected headers.
- [ ] Keep model list response support at official `{data:[{id, owned_by}]}` shape. Malformed list items remain skipped; whole invalid envelopes still fail.
- [ ] Add UI tests proving the advanced endpoint label shows the derived `/v1/models` URL for each protocol and the workflow request contains provider protocol.
- [ ] Run tests and confirm old `deriveModelsUrl` and hard-coded Bearer behavior fail the new cases.
- [ ] Replace `resolveModelsUrl()` with a `Uri`-returning function backed by `LlmEndpointResolver`; pass protocol through workflow fetch typedef.
- [ ] Update `ModelFetchSection` to construct `ModelCatalogRequest(apiProtocol: provider.apiProtocol, ...)` both for preview and fetch.
- [ ] Update `ModelListClient` provider to read `customHeadersMapProvider` for logging, while actual override still occurs in `httpClientProvider`.
- [ ] Delete the old URL helper and its test after every valid case is represented in resolver/workflow tests.
- [ ] Verify model-list failure never mutates the saved provider and never switches protocol/auth automatically.
- [ ] Run model catalog, model dialog, settings screen, resolver, custom-header and redactor tests.
- [ ] Format, stage-check, and commit: `feat(settings): 按协议拉取服务商模型列表`

## Task 13: Add cross-protocol integration coverage and perform final cleanup

**Files**

- Create: `test/integration/multi_protocol_chat_generation_integration_test.dart`
- Modify: `test/integration/preset_prompt_request_integration_test.dart`
- Modify: `test/integration/chat_lifecycle_integration_test.dart`
- Modify: `test/features/chat/application/chat_request_message_builder_test.dart`
- Modify: `test/features/chat/application/chat_generation_run_test.dart`
- Modify: `test/features/chat/application/chat_sessions_controller_test.dart` and its registered case files only where neutral request assertions need updates.
- Modify: `test/architecture/import_boundary_checker_test.dart` to replace the transitional legacy concrete example with `chat_completions/chat_completions_client.dart` and the final neutral port path.
- Delete any remaining obsolete files listed in section 0.3.

**Consumes:** final composition, three protocol clients, existing chat lifecycle/persistence.

**Produces:** end-to-end evidence that protocol differences end at the neutral chunk boundary and no legacy compatibility machinery remains.

- [ ] Build a parameterized integration harness with a fake streaming HTTP client and real resolver/transport/router/protocol client for each protocol. Return equivalent “思考” + “正文” + terminal events in each native SSE shape.
- [ ] For each protocol, start a real controller generation against an in-memory conversation repository and assert the final assistant message has identical `content`, `reasoningContent`, normalized `finishReason`, `isStreaming=false`, and durable persisted state.
- [ ] Capture each outgoing request and assert protocol-specific endpoint/header/body, including Responses stateless fields and Anthropic system/cache/thinking transformation.
- [ ] Seed prior assistant `reasoningContent='不得回放的历史思考'`; assert the serialized outgoing request body for all three protocols does not contain that sentinel while the prior assistant visible content is present.
- [ ] Parameterize an error response for all three protocols and assert the existing inline assistant error path receives `ChatGenerationException`; no SnackBar/Dialog assertion should be added.
- [ ] Keep existing message-tree edit/branch/retry tests on the neutral Fake. Assert request messages correspond only to the selected active path and still omit reasoning.
- [ ] Replace the old vendor integration test with this file; do not keep tests for removed host behavior.
- [ ] Run the exact symbol/path/host audits in section 9.4 and remove stale imports, comments, helper names and ignored dead code.
- [ ] Run formatter, staged formatter check, architecture CLI, analyze, targeted tests and full suite in section 9.
- [ ] Inspect `git diff --check` and `git status --short`; only plan-scoped production/tests plus the automatic `pubspec.yaml` version bump from commits may remain.
- [ ] Commit integration/cleanup: `test(chat): 覆盖三种协议的普通聊天生成链路`

Stop condition: if a protocol can only pass by adding tool items, server-side response state, encrypted reasoning replay, model-name inference, request fallback or a vendor host branch, stop and report that the approved ordinary-chat scope is insufficient. Do not expand it inside cleanup.

---

## 8. Exhaustive Migration Audit

### 8.1 Existing direct provider/model constructors

Task 1 must inspect and compile-migrate every existing `LlmProviderConfig(...)` call in these paths. Production constructors must pass the form/provider value explicitly; test fixtures may default at the fixture API only.

```text
lib/features/settings/domain/models/llm_provider_config.dart
lib/features/settings/presentation/settings_screen.dart
test/features/chat/application/chat_composer_command_test.dart
test/features/chat/application/chat_generation_race_contract_test.dart
test/features/chat/application/chat_sessions_controller_persistence_test.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart
test/features/chat/application/chat_workspace_view_state_test.dart
test/features/settings/application/llm_model_configs_controller_test.dart
test/features/settings/application/settings_import_deduplicator_test.dart
test/features/settings/application/settings_import_executor_test.dart
test/features/settings/application/settings_sync_facade_test.dart
test/features/settings/application/settings_transfer_workflow_test.dart
test/features/settings/data/llm_model_config_repository_test.dart
test/features/settings/domain/models/llm_provider_config_test.dart
test/features/settings/domain/models/settings_export_data_test.dart
test/features/settings/presentation/import_confirm_dialog_test.dart
test/features/settings/presentation/model_config_form_dialog_test.dart
test/features/sync/application/sync_client_controller_execute_test.dart
test/features/sync/application/sync_server_controller_test.dart
test/features/sync/sync_screen/sync_screen_import_dialog_cases.dart
test/helpers/fixtures.dart
test/helpers/integration_test_helpers.dart
test/integration/chat_favorites_integration_test.dart
test/integration/preset_prompt_request_integration_test.dart
```

Recount before implementation:

```powershell
rg -l "LlmProviderConfig\(" lib test --glob "*.dart" | Sort-Object
```

If the output differs, update this audit list in the implementation commit before changing the extra file.

Direct `LlmModelConfig(...)` construction must also be migrated in:

```text
lib/features/settings/domain/models/llm_model_config.dart
lib/features/settings/domain/models/llm_provider_config.dart
test/features/chat/application/chat_generation_coordinator_test.dart
test/features/chat/application/chat_generation_lifecycle_test.dart
test/features/chat/application/chat_generation_race_contract_test.dart
test/features/chat/application/chat_generation_run_test.dart
test/features/chat/application/chat_sessions_controller_persistence_test.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart
test/features/chat/data/openai_compatible_chat_client_test.dart
test/features/settings/domain/models/llm_model_config_test.dart
test/helpers/fixtures.dart
test/helpers/integration_test_helpers.dart
test/integration/vendor_payload_integration_test.dart
```

The final two legacy data/integration tests still receive explicit Chat protocol in Task 1 so its commit compiles; Task 7 later replaces/deletes them.

```powershell
rg -l "LlmModelConfig\(" lib test --glob "*.dart" | Sort-Object
```

### 8.2 Old chat port and symbols

The following existing production files import or use the old port and must end on the neutral vocabulary:

```text
lib/app/composition/cross_feature_bindings.dart
lib/features/chat/application/chat_generation_coordinator.dart
lib/features/chat/application/chat_generation_lifecycle.dart
lib/features/chat/application/chat_generation_run.dart
lib/features/chat/application/chat_request_message_builder.dart
lib/features/chat/application/chat_sessions_controller.dart
lib/features/chat/application/chat_sessions_controller_streaming.dart
lib/features/chat/application/checkpoint_request_context.dart
```

The following existing tests/helpers must be migrated or explicitly deleted/replaced by Tasks 4/7/13:

```text
test/architecture/import_boundary_checker_test.dart
test/features/chat/application/chat_composer_command_test.dart
test/features/chat/application/chat_generation_coordinator_test.dart
test/features/chat/application/chat_generation_lifecycle_test.dart
test/features/chat/application/chat_generation_race_contract_test.dart
test/features/chat/application/chat_generation_run_test.dart
test/features/chat/application/chat_sessions_controller_persistence_test.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_branching_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_checkpoint_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_crud_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_generation_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_retry_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_stop_cases.dart
test/features/chat/application/chat_sessions_controller/chat_sessions_controller_test_helpers.dart
test/features/chat/application/chat_workspace_view_state_test.dart
test/features/chat/chat_screen/chat_screen_basics_cases.dart
test/features/chat/chat_screen/chat_screen_branching_cases.dart
test/features/chat/chat_screen/chat_screen_favorites_cases.dart
test/features/chat/chat_screen/chat_screen_responsive_cases.dart
test/features/chat/chat_screen/chat_screen_streaming_cases.dart
test/features/chat/chat_screen/chat_screen_test_helpers.dart
test/features/chat/chat_screen/chat_screen_workspace_ownership_cases.dart
test/helpers/fake_chat_completion_client.dart
test/helpers/fixtures.dart
test/helpers/integration_test_helpers.dart
test/helpers/test_harness.dart
test/integration/bootstrap_integration_test.dart
test/integration/chat_favorites_integration_test.dart
test/integration/chat_lifecycle_integration_test.dart
test/integration/chat_message_version_persistence_integration_test.dart
test/integration/chat_multi_conversation_integration_test.dart
test/integration/preset_prompt_request_integration_test.dart
```

The old data tests and vendor integration are not in this migration list because Task 7 replaces/deletes them as named artifacts.

### 8.3 File-by-file behavior matrix

| Area | Current behavior | Final required behavior | Explicit non-edit |
|---|---|---|---|
| Provider domain | URL/key/models only | required provider protocol, model inherits | no per-model protocol |
| Provider storage | missing protocol impossible | missing old field -> Chat; unknown explicit value fails | no `VersionedJsonStorage` wrapper bump |
| Settings export | format 6 | format 7, v5/v6 sequential migration | no Sync protocol v3 bump |
| Import merge | ID, then raw URL+key | ID, then protocol+normalized root+key | no cross-protocol merge |
| Request builder | Chat-specific message type | neutral text message type | no reasoning replay |
| Generation lifecycle | old client vocabulary | neutral request/chunk/exception only | no phase/flag rewrite |
| URL handling | configured URL used directly | domain/root/full endpoint accepted | stored raw URL not rewritten |
| SSE | mixed into legacy client | byte-safe neutral event decoder | no protocol JSON in core |
| HTTP | mixed into legacy client | shared POST/log/error/timeout/cancel | no peer client reuse |
| Chat protocol | vendor strategy chain | official request + `reasoning_content` + three singular tags | no host patches/List parts/alias |
| Responses | absent | stateless `store:false`, current-turn reasoning | no response ID/server state |
| Anthropic | absent | leading System transform, auto cache, adaptive thinking | no signature/tool/budget replay |
| Router | absent | switch only on explicit protocol | no host/model inference/fallback |
| Model catalog | Chat URL derivation + Bearer | shared models resolver + protocol auth | no protocol switching on failure |
| UI | no protocol field | add/edit selector and visible chip | no model-level override |
| Usage | absent | neutral transient field when naturally supplied | no persistence/UI/request expansion |

### 8.4 Explicitly unchanged files and subsystems

Do not modify these unless a compilation error proves a direct dependency, in which case stop and document why before editing:

- `lib/features/chat/domain/models/chat_message.dart` persistence fields and message-tree meaning. `ReasoningEffort` remains where it is; this plan only maps its values per protocol.
- `lib/features/chat/data/chat_sql_codec.dart`, SQLite repositories and `lib/core/persistence/` migrations.
- `lib/features/chat/presentation/widgets/reasoning_panel.dart`, inline error/empty cards and message bubble layout.
- `lib/features/sync/data/` trust/auth transport, peer client provider and Sync protocol version.
- `lib/features/media/` and all media HTTP routes.
- `dart_test.yaml`, `.github/workflows/`, Flutter/Dart version constraints and package dependencies.

---

## 9. Verification Strategy

### 9.1 Per-commit mandatory format and static checks

Before every commit:

```powershell
$taskDartFiles = git diff --name-only -- '*.dart'
if ($taskDartFiles) {
  dart format $taskDartFiles
}
dart run tool/check_import_boundaries.dart
flutter analyze
```

After staging, verify only staged Dart paths:

```powershell
$stagedDartFiles = git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
if ($stagedDartFiles) {
  dart format --output=none --set-exit-if-changed $stagedDartFiles
}
```

Any non-zero result blocks the commit. If `dart format` receives no paths, skip it instead of formatting the whole repository.

### 9.2 Application regression set after Task 4 and final integration

```powershell
$multiApiApplicationTests = @(
  'test/features/chat/application/chat_generation_client_test.dart',
  'test/features/chat/application/chat_request_message_builder_test.dart',
  'test/features/chat/application/checkpoint_request_context_test.dart',
  'test/features/chat/application/chat_generation_lifecycle_test.dart',
  'test/features/chat/application/chat_generation_coordinator_test.dart',
  'test/features/chat/application/chat_generation_run_test.dart',
  'test/features/chat/application/chat_generation_race_contract_test.dart',
  'test/features/chat/application/chat_sessions_controller_test.dart',
  'test/features/chat/application/chat_sessions_controller_persistence_test.dart',
  'test/features/chat/chat_screen_test.dart',
  'test/integration/chat_lifecycle_integration_test.dart',
  'test/integration/chat_multi_conversation_integration_test.dart',
  'test/integration/preset_prompt_request_integration_test.dart'
)
flutter test $multiApiApplicationTests --reporter compact 2>&1 | Out-File -Encoding utf8 multi-api-application.log
$multiApiApplicationExit = $LASTEXITCODE
Write-Host "EXIT=$multiApiApplicationExit"
Get-Content -Tail 150 multi-api-application.log
```

Task 4 runs the subset whose new files exist at that point; the final run uses the complete array.

### 9.3 Final protocol/settings targeted set

```powershell
$multiApiTargetedTests = @(
  'test/core/llm',
  'test/core/http',
  'test/core/logging/network_log_redactor_test.dart',
  'test/features/chat/data',
  'test/features/settings/domain/models/llm_provider_config_test.dart',
  'test/features/settings/domain/models/llm_model_config_test.dart',
  'test/features/settings/domain/models/settings_export_data_test.dart',
  'test/features/settings/domain/models/settings_export_codec_test.dart',
  'test/features/settings/data/llm_model_config_repository_test.dart',
  'test/features/settings/data/model_list_client_test.dart',
  'test/features/settings/application/model_catalog_workflow_test.dart',
  'test/features/settings/application/settings_import_deduplicator_test.dart',
  'test/features/settings/application/llm_model_configs_controller_test.dart',
  'test/features/settings/presentation/model_config_form_dialog_test.dart',
  'test/features/settings/settings_screen_test.dart',
  'test/features/sync/domain/models/sync_protocol_message_test.dart',
  'test/integration/bootstrap_integration_test.dart',
  'test/integration/sync_e2e_integration_test.dart',
  'test/integration/multi_protocol_chat_generation_integration_test.dart'
)
flutter test $multiApiTargetedTests --reporter compact 2>&1 | Out-File -Encoding utf8 multi-api-targeted.log
$multiApiTargetedExit = $LASTEXITCODE
Write-Host "EXIT=$multiApiTargetedExit"
Get-Content -Tail 150 multi-api-targeted.log
```

Expected: `EXIT=0`. Diagnose failures from the log; do not trust truncated live output.

### 9.4 Final source audits

```powershell
rg -n "ChatCompletion(Client|Chunk|Result|RequestMessage|Exception)|chatCompletionClientProvider|bindChatCompletionClient" lib test --glob "*.dart"
rg -n "OpenAiCompatibleChatClient|VendorPayloadAdapter|ChunkParseStrategy|GeminiPartsChunkStrategy|DeepSeekChunkStrategy" lib test --glob "*.dart"
rg -n "api\.deepseek\.com|ark\.cn-beijing\.volces\.com|generativelanguage\.googleapis\.com|extra_body|thinking_config" lib test --glob "*.dart"
rg -n "reasoning_content.*\?\?.*reasoning|delta\['reasoning'\]" lib/features/chat/data --glob "*.dart"
rg -n "previous_response_id|encrypted_content|include.*reasoning|conversation" lib/features/chat/data/responses --glob "*.dart"
rg -n "tool_use|server_tool_use" lib/features/chat/data/anthropic test/features/chat/data/anthropic --glob "*.dart"
rg -n "peerHttpClientProvider" lib/features/chat lib/core/http/llm_http_stream_transport.dart --glob "*.dart"
```

Expected results:

- First four commands: no output.
- Responses audit: no output. Tests may mention forbidden fields only outside the production-only path in this command.
- Anthropic tool audit: output must be limited to explicit unsupported-response detection and its tests; there must be no tool request encoding.
- Peer client audit: no output.

Also verify deleted paths are gone and planned paths exist:

```powershell
$removedPaths = @(
  'lib/features/chat/application/ports/chat_completion_client.dart',
  'lib/features/chat/data/openai_compatible_chat_client.dart',
  'lib/features/chat/data/chat_chunk_parser.dart',
  'lib/features/chat/data/chunk_parse_strategy.dart',
  'lib/features/chat/data/vendor_payload_adapters.dart',
  'lib/features/settings/data/model_list_url.dart',
  'test/features/chat/data/openai_compatible_chat_client_test.dart',
  'test/features/chat/data/chat_chunk_parser_test.dart',
  'test/features/chat/data/vendor_payload_adapters_test.dart',
  'test/features/settings/data/model_list_url_test.dart',
  'test/integration/vendor_payload_integration_test.dart'
)
$removedPaths | Where-Object { Test-Path -LiteralPath $_ }
```

Expected: no output.

### 9.5 Final architecture/analyze/full suite

```powershell
dart format --output=none --set-exit-if-changed <all changed Dart files>
dart run tool/check_import_boundaries.dart
flutter analyze
git diff --check
flutter test --reporter compact 2>&1 | Out-File -Encoding utf8 fltest.log
$multiApiFullExit = $LASTEXITCODE
Write-Host "EXIT=$multiApiFullExit"
Get-Content -Tail 150 fltest.log
```

Only `EXIT=0`, zero analyzer issues, zero architecture violations and a clean `git diff --check` constitute implementation verification. If the local full suite is blocked by a native-assets DLL lock, run `./scripts/kill-stale-test-processes.ps1` and retry; do not claim success from the targeted set alone.

---

## 10. Failure Diagnosis and Stop Rules

1. **Old provider cannot load:** inspect whether the failure is repository JSON (missing field must default) or Settings export v7 (field must be strict). Do not make all enum parsing permissive.
2. **v5/v6 export loses fields:** inspect each sequential migrator’s deep copy and version increment. Never mutate the caller’s source map or set v5 directly to the current constant.
3. **Different protocols merge:** inspect both deduplicator and controller fallback keys; same-ID and no-ID branches have deliberately different semantics.
4. **Wrong endpoint under proxy prefix:** inspect complete suffix matching and `/v1` segment handling. Do not use string `replaceAll` or remove an interior `/v1`.
5. **Query disappears:** all resolver mutations must use `Uri.replace(path: ...)` without replacing query parameters.
6. **Generation hangs during invalid URL:** each protocol client must convert resolver failure into a `ChatGenerationException` stream error. Do not resolve in controller `_prepare`, where an escaping synchronous exception could leave ownership ambiguous.
7. **SSE corrupts Chinese text:** byte decoding happened after per-chunk string conversion. UTF-8 must be decoded as a stream before line splitting.
8. **Keepalive prevents timeout:** only `data:` resets idle time; `:` comments and `event:` do not. Anthropic ping is a JSON data event and therefore does reset it.
9. **Cancel still receives chunks:** output cancellation did not cancel the decoder input or HTTP response stream subscription. Fix ownership; do not add token guards in protocol parsers as a substitute.
10. **Custom Header works but log is wrong:** actual injection and log merge are separate. Keep `CustomHeadersHttpClient` as injector and use the same current map only to describe final effective headers to the logger.
11. **Request body appears in network log:** transport must call `logRequest` with `logBody:false`; do not special-case by protocol.
12. **Chat duplicates reasoning:** ensure explicit `reasoning_content` is appended once and inline extraction runs only over string content. Never treat `reasoning` alias as a second source.
13. **Inline tag leaks at chunk boundary:** retain a candidate tail beginning at `<` until it can be accepted/rejected. On stream finish, flush through the current channel.
14. **Responses duplicates final text:** `.done` payload is validation-only. Only `.delta` events append.
15. **Responses retries internally:** remove it. Protocol clients do not retry or delete unsupported fields; existing generation lifecycle owns configured retries.
16. **Anthropic rejects message roles:** first verify leading contiguous System extraction, later System->User conversion and adjacent-role merge. Do not invent placeholder turns or reorder messages.
17. **Anthropic `max` switch is non-exhaustive:** both application `xhigh` and existing `max` map to Anthropic `max`; do not remove an existing UI effort value in this refactor.
18. **Tool event produces empty reply:** tool declarations are explicit unsupported errors, not unknown events and not empty content.
19. **Partial reply disappears after error:** protocol client should emit deltas before the error; existing `ChatGenerationRun` and host own partial durable handling. Do not persist from the client.
20. **Architecture gate fails core-to-feature:** replace feature exceptions/types in core with transport-local types. Protocol clients perform the translation.
21. **A required change reaches Agent/multimodal/server-state code:** stop. That is a scope contradiction, not a reason to add placeholder abstractions.

---

## 11. Independent Commit Sequence

| Order | Commit | Scope |
|---:|---|---|
| 1 | `refactor(settings): 在服务商配置中显式保存 API 协议` | enum, provider/model storage compatibility |
| 2 | `feat(settings): 将服务商协议纳入导出与同步格式` | export v7, Sync snapshot, import protocol key |
| 3 | `refactor(llm): 统一解析生成与模型端点` | API root/generation/models resolver, normalized key |
| 4 | `refactor(chat): 泛化普通聊天生成端口` | neutral port/request/Fake and lifecycle call sites |
| 5 | `refactor(http): 增加协议无关的 SSE 事件解码器` | byte/event/timeout/cancel semantics |
| 6 | `refactor(http): 抽取 LLM 流式请求传输层` | POST/log/status/error/stream ownership |
| 7 | `refactor(chat): 以官方模式实现 Chat Completions` | official Chat parser/client; remove vendor stack |
| 8 | `feat(chat): 增加无状态 Responses 协议客户端` | Responses encoder/parser/client |
| 9 | `feat(chat): 增加 Anthropic Messages 协议客户端` | transformer/adaptive thinking/cache/parser |
| 10 | `refactor(chat): 按服务商协议路由聊天请求` | router and single composition binding |
| 11 | `feat(settings): 允许服务商选择聊天 API 协议` | add/edit/list UI |
| 12 | `feat(settings): 按协议拉取服务商模型列表` | models resolver/auth/logging; remove old URL helper |
| 13 | `test(chat): 覆盖三种协议的普通聊天生成链路` | cross-protocol integration, audit, cleanup |

Each commit must pass its focused tests and `flutter analyze`; do not squash unrelated feature work into this sequence. The repository post-commit hook may amend `pubspec.yaml` for each commit according to its message prefix; treat those hook edits as expected and do not manually pre-bump versions.

---

## 12. Definition of Done

- [ ] Existing provider JSON without `apiProtocol` loads as Chat Completions with no user action.
- [ ] Unknown explicit protocol strings fail rather than silently falling back.
- [ ] Settings export writes format 7; v5/v6 migrate; future/malformed versions reject.
- [ ] Typed Settings Sync preserves protocol without changing Sync protocol v3.
- [ ] Same URL/key under different protocols does not deduplicate; equivalent domain/root/full endpoints do deduplicate within the same protocol.
- [ ] Provider add/edit offers exactly Chat Completions, Responses and Anthropic; default is Chat Completions; editing protocol preserves models.
- [ ] Provider list visibly identifies protocol.
- [ ] Raw configured URL is preserved; resolver accepts domain, `/v1`, full known endpoint, proxy prefix, port and query.
- [ ] Model catalog always resolves `/v1/models` and uses Bearer for Chat/Responses, `x-api-key` + fixed version for Anthropic.
- [ ] Only `ChatGenerationClient`/`chatGenerationClientProvider` exists at the application boundary.
- [ ] `ChatGenerationRequest` contains only target/messages/reasoning/idle timeout; lifecycle/retry fields are not duplicated.
- [ ] Fake clients only override the streaming method.
- [ ] Shared SSE decoder survives arbitrary byte/UTF-8/line splits, joins multi-data events, flushes tail events, ignores comments, resets timeout only on data and propagates cancellation.
- [ ] Shared transport has no feature or protocol JSON imports, logs body off, retains non-2xx/network diagnostics and reflects custom Header overrides after redaction.
- [ ] Chat sends official `reasoning_effort`, parses `reasoning_content`, and recognizes only singular `<thought>`, `<thinking>`, `<think>` tags with the approved boundary rules.
- [ ] Chat contains no Google/DeepSeek/Volcengine host patches, Gemini List parts parser or `reasoning` alias fallback.
- [ ] Responses always sends `store:false`, current-turn reasoning when enabled, and no server-state/response-replay fields.
- [ ] Responses parses output, reasoning summary/text and refusal without `.done` duplication; terminal/error semantics are covered.
- [ ] Anthropic joins only the leading contiguous System prefix, converts later System to User and merges adjacent equal roles.
- [ ] Anthropic sends automatic ephemeral cache, fixed 8192 max tokens, adaptive summarized thinking and correct effort mapping; null reasoning omits thinking/output config.
- [ ] Anthropic ignores signature, handles ping/stop/errors and explicitly rejects tool content blocks.
- [ ] Finish reasons normalize to existing stop/length behavior; unknown strings remain diagnosable.
- [ ] Text/reasoning empty fails; reasoning-only remains representable; partial output before failure reaches the existing durable lifecycle.
- [ ] Three protocols persist identical neutral assistant outcomes in integration tests.
- [ ] Historical `reasoningContent` sentinel is absent from all three serialized requests.
- [ ] Existing stop/cancel/retry/finalize/message-tree/inline-error tests remain green.
- [ ] No SDK, Agent, tools, multimodal, server-state, signature replay, output-token setting, structured-output, protocol-fallback or vendor-special-case code was added.
- [ ] Every changed Dart file is formatted and staged format check passes.
- [ ] Import-boundary CLI reports zero violations.
- [ ] `flutter analyze` reports zero issues.
- [ ] Targeted protocol/settings/application suites pass with `EXIT=0`.
- [ ] Full redirected test suite passes with `EXIT=0`.
- [ ] Final legacy symbol/host/path audits match section 9.4.
- [ ] `git diff --check` is clean and `git status --short` contains only intended work.

## 13. Final Scope Audit

Before declaring implementation complete, answer each question from the final diff:

- Does any ordinary chat request contain persisted reasoning, signature, response ID, tool call/result or encrypted item? Expected: no.
- Does any client decide behavior from host or model name? Expected: no.
- Can the router do anything except select one delegate? Expected: no.
- Can core HTTP/SSE import a feature or inspect protocol JSON? Expected: no.
- Is there any second generation phase/flag owner or any persistence call inside protocol clients? Expected: no.
- Did any task change SQLite schema, peer HTTP trust, Sync protocol v3, CI/toolchain, or package dependencies? Expected: no.
- Did UI expose a per-model protocol, manual cache budget, response state, output tokens, tools or Agent toggle? Expected: no.
- Are all old compatibility files and tests removed only after their valid generic/Chat cases were relocated? Expected: yes.

Any unexpected answer blocks completion and requires either reverting the out-of-scope change or obtaining a new explicit product decision.
