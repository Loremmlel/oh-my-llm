# Phase 3 - HTTP 信任域与日志边界 Implement Plan

> 本 Plan 基于 `Phase 3 - HTTP 信任域与日志边界.md` 细化，不改变 Phase 的结论或技术选型。
> 遵守 Refactor Scope / Out Of Scope / Phase 依赖，不提前实现其他 Phase。
> 所有现状结论已对当前工作树源码实测；实施已完成，验证结论记录于第十节。

## 一、现状验证结论（已实测）

| 验证项 | 结果 | 判定 |
|---|---|---|
| 静态分析 | `flutter analyze` EXIT=0，No issues found | 干净 |
| 全量测试 | `flutter test --reporter compact` 重定向后 EXIT=0 | 基线通过 |
| `test/core/http/` | 目录不存在，零 CustomHeadersHttpClient 单元测试 | **P0 缺口** |
| 信任域分离 | 5 个消费者共用 `httpClientProvider`，3 个 LAN peer 错误接收自定义 Header | TD-01 确认 |
| Redactor 覆盖 | 仅识别 `authorization` 和 `apikey`/`api_key` | TD-16 确认 |
| SSE 日志 | 每行 `appendLine` + `flush: true`，无批量/有界/排空机制 | TD-16 确认 |
| ModelListClient | `elapsed: Duration.zero`，`await` 日志（阻塞），独立 `_truncateBody` | TD-19 确认 |
| ChatClient | `_fireAndForget` 日志，真实 `DateTime.now().difference()` 计时 | TD-19 对比基线 |
| AppLogStore 轮转 | `_rotateIfExceeded` 仅写标记不真正轮转，文件持续增长 | 已知限制，本 Phase 不改轮转语义 |

## 二、关键实现决策（不改变 Phase 结论）

1. **信任域 = 分离 Provider，不改 CustomHeadersHttpClient 类本身**。新增 `peerHttpClientProvider` 返回纯 `http.Client`（无 header 注入），三个 LAN peer 消费者迁移至它；现有 `httpClientProvider`（`CustomHeadersHttpClient`）仅保留给外部 LLM 消费者。这是最小侵入方案——不改 `CustomHeadersHttpClient` 的 `send()` 逻辑，仅让不该走它的消费者不再走它。

2. **`customHeadersSyncProvider` 不变**。它仍然监听 `customHeadersMapProvider` 并同步到 `httpClientProvider` 的 `CustomHeadersHttpClient`。peer 客户端与它无关。

3. **App 根 watch 不变**。`OhMyLlmApp.build()` 中的 `ref.watch(customHeadersSyncProvider)` 仍确保冷启动时外部 LLM 客户端的 header 同步。

4. **Redactor 扩展为安全默认集合**。新增 `Cookie`、`X-API-Key`、`Token`/`Access-Token`/`Auth-Token`、`Secret`/`Client-Secret`、`Proxy-Authorization` 到 `_sensitiveHeaderKeys`，以及 JSON body 中的 `token`/`secret`/`password`/`credential` 字段。保持 `const` 构造与纯函数风格，新增 `isSensitiveHeader()` 公开方法供测试断言。

5. **SSE 日志引入有界缓冲区**。新增 `SseLogBuffer`：固定容量（默认 128 条），溢出时丢弃最旧条目并写入 `[sse-dropped]` 标记；`flush()` 批量写磁盘；`drain()` 用于生命周期结束前排空。`AppNetworkLogger.logSseLine()` 不再直接 `_writeLog`，而是入队 buffer；buffer 内部定时（每 500ms 或满 64 条）批量 flush。`NetworkLogger` 新增 `drain()` 方法。

6. **body 日志改为显式选择**。`logRequest` / `logResponseBody` 新增 `bool logBody` 参数（默认 `false`）。`OpenAiCompatibleChatClient` 在 `logRequest` 传 `logBody: true`（完整请求日志对 LLM 调试必要）；`ModelListClient` 的 `logRequest` 传 `logBody: false`（GET 请求无 body）。`logResponseBody` 在 chat client 非 SSE 完整响应时传 `logBody: true`。

7. **ModelListClient 观测对齐 ChatClient**。修正 `elapsed: Duration.zero` 为真实计时；统一使用 `_fireAndForget` 日志模式；使用 `truncateJsonValues` 替代独立 `_truncateBody`；保留 `await` 日志在错误路径（错误日志应阻塞以确保持久化）。

8. **不改 AppLogStore 轮转语义**。`_rotateIfExceeded` 的"仅标记不轮转"行为是已知限制，本 Phase 不改（属性能优化，非 TD-16 安全范畴）。

9. **不改 vendor adapter / SSE parser / streaming 逻辑**。Out Of Scope 明确排除。

10. **`NetworkLogger` 接口新增 `drain()`**。用于应用退出前确保 SSE buffer 排空。`NoopNetworkLogger` 的 `drain()` 是 no-op。`AppNetworkLogger.drain()` 调用 `_sseBuffer.drain()` 后 `_writeLog('[drain] SSE buffer flushed.')`。

## 三、文件修改清单

### 新增

| 文件 | 用途 |
|---|---|
| `lib/core/http/peer_http_client_provider.dart` | LAN peer 信任域 HTTP Client Provider，返回纯 `http.Client`（无 header 注入） |
| `lib/core/logging/sse_log_buffer.dart` | SSE 日志有界缓冲区：固定容量、溢出丢弃+标记、批量 flush、drain 契约 |
| `test/core/http/custom_headers_http_client_test.dart` | `CustomHeadersHttpClient` 单元测试：header 注入、updateHeaders、close 后抛异常 |
| `test/core/http/peer_http_client_provider_test.dart` | peer Provider 测试：返回纯 `http.Client`、不携带自定义 Header |
| `test/core/http/http_client_provider_test.dart` | 两个 Provider 的信任域分离集成测试 |
| `test/core/logging/sse_log_buffer_test.dart` | 缓冲区边界、溢出丢弃、批量 flush、drain 契约 |

### 修改

| 文件 | 改动 |
|---|---|
| `lib/core/http/http_client_provider.dart` | `httpClientProvider` 注释更新为"外部 LLM 信任域"；`customHeadersSyncProvider` 不变 |
| `lib/core/logging/network_log_redactor.dart` | 扩展 `_sensitiveHeaderKeys` 集合（Cookie/X-API-Key/Token/Secret 等）；扩展 `_looksLikeApiKeyField` 匹配 `token`/`secret`/`password`/`credential`；新增 `isSensitiveHeader(String)` 公开方法 |
| `lib/core/logging/network_logger.dart` | `NetworkLogger` mixin 新增 `Future<void> drain() async {}`；`logRequest` 新增 `bool logBody = false` 参数；`logResponseBody` 新增 `bool logBody = false` 参数 |
| `lib/core/logging/app_network_logger.dart` | 注入 `SseLogBuffer`；`logSseLine` 改为入队 buffer；`logRequest`/`logResponseBody` 根据 `logBody` 参数决定是否记录 body；实现 `drain()`；`onAppDetached` 调用 `drain()` |
| `lib/core/logging/app_log_store.dart` | 新增 `appendLines(List<String> lines)` 批量写入方法（单次文件 open + 多行 + 单次 flush） |
| `lib/features/chat/data/openai_compatible_chat_client.dart` | `logRequest` 传 `logBody: true`；`logResponseBody` 传 `logBody: true` |
| `lib/features/settings/data/model_list_client.dart` | 修正 `elapsed: Duration.zero` 为真实计时；`logRequest` 传 `logBody: false`；日志调用统一为 `_fireAndForget`（错误路径保留 `await`）；移除 `_truncateBody`，改用 `truncateJsonValues` |
| `lib/features/sync/application/sync_client_controller.dart` | 将 `ref.read(httpClientProvider)` 改为 `ref.read(peerHttpClientProvider)` |
| `lib/features/media/application/media_browser_controller.dart` | 将 `ref.read(httpClientProvider)` 改为 `ref.read(peerHttpClientProvider)` |
| `lib/features/media/application/shuffle_playback_controller.dart` | 将 `ref.read(httpClientProvider)` 改为 `ref.read(peerHttpClientProvider)` |
| `test/core/logging/network_log_redactor_test.dart` | 新增扩展敏感键覆盖测试（Cookie/X-API-Key/Token/Secret 等） |
| `test/features/chat/data/openai_compatible_chat_client_test.dart` | `_FakeNetworkLogger` 新增 `drain()` 和 `logBody` 参数 |
| `test/features/settings/data/model_list_client_test.dart` | 截断长度断言适配 `truncateJsonValues` 语义 |
| `test/features/media/helpers/media_test_helpers.dart` | `httpClientProvider` override 改为 `peerHttpClientProvider` override |
| `test/helpers/test_harness.dart` | 新增 `peerHttpClientProvider` override |

### 不修改

| 文件 | 理由 |
|---|---|
| `lib/core/http/custom_headers_http_client.dart` | 类本身不改——信任域通过 Provider 分离实现，不靠类内部逻辑 |
| `lib/core/http/custom_headers_provider.dart` | 抽象 Provider 不变，仍由 bootstrap override |
| `lib/core/logging/json_truncator.dart` | 已健壮，无缺口 |
| `lib/core/logging/app_network_logger_provider.dart` | 类型不变，仅接口扩展 |
| `lib/bootstrap.dart` | 不新增 override——`peerHttpClientProvider` 有默认实现（`http.Client()`），不需要 bootstrap override |
| `lib/app/app.dart` | `customHeadersSyncProvider` watch 不变 |
| `lib/features/settings/domain/models/custom_headers_config.dart` | 纯数据模型，无改动 |
| `lib/features/settings/application/custom_headers_controller.dart` | 不变，仍为外部 LLM 提供配置 |
| 任何 server-side handler（sync/media HTTP handler） | 服务端不涉及客户端信任域问题 |
| vendor adapter / SSE parser / streaming 逻辑 | Out Of Scope |

## 四、关键实现细节

### 4.1 `peer_http_client_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// LAN peer 信任域 HTTP Client Provider。
///
/// 返回不带自定义 header 注入的纯 [http.Client]。
/// 局域网 peer（sync / media）不应接收外部 LLM 的自定义 Header。
final peerHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
```

设计理由：默认实现无需 bootstrap override。测试可 override 为 `MockClient`。

### 4.2 `SseLogBuffer`

```dart
/// SSE 日志有界缓冲区。
///
/// 固定容量，溢出时丢弃最旧条目并写入 [sse-dropped] 标记。
/// 定时（每 500ms 或满 batchSize 条）批量 flush 到 [AppLogStore]。
/// [drain] 用于生命周期结束前排空所有缓冲条目。
final class SseLogBuffer {
  SseLogBuffer({
    required this.store,
    this.maxCapacity = 128,
    this.batchSize = 64,
    this.flushInterval = const Duration(milliseconds: 500),
  });

  final AppLogStore store;
  final int maxCapacity;
  final int batchSize;
  final Duration flushInterval;

  final List<String> _buffer = [];
  int _droppedCount = 0;
  Timer? _flushTimer;

  void enqueue(String line) { ... }
  Future<void> flush() { ... }    // 批量写 store.appendLines
  Future<void> drain() { ... }    // flush + 停 timer
  void startPeriodicFlush() { ... }
}
```

关键约束：
- `enqueue` O(1)，不阻塞 SSE 流
- 溢出时丢弃最旧条目（`_buffer.removeAt(0)`），计数 `_droppedCount++`
- `flush` 时若 `_droppedCount > 0`，先写 `[sse-dropped] $count lines dropped` 标记
- `drain` 在 `AppNetworkLogger.onAppDetached()` 和 `drain()` 中调用
- 生命周期：`AppNetworkLogger.create()` 中初始化并 `startPeriodicFlush()`；`onAppDetached()`/`drain()` 中 `drain()`

### 4.3 `AppLogStore.appendLines`

```dart
Future<void> appendLines(List<String> lines) {
  if (lines.isEmpty) return _operation;
  _operation = _operation.then((_) async {
    await _ensureExists();
    await _rotateIfExceeded();
    await _file.writeAsString(
      lines.map((l) => '$l\n').join(),
      mode: FileMode.append,
      flush: true,
    );
    await _rotateIfExceeded();
  });
  return _operation;
}
```

单次 open + 批量写入 + 单次 flush，减少磁盘 I/O。

### 4.4 `NetworkLogRedactor` 扩展

新增敏感 header 键（不区分大小写匹配）：
- `cookie`
- `x-api-key`
- `token`, `access-token`, `auth-token`
- `secret`, `client-secret`
- `proxy-authorization`

新增 JSON body 敏感字段（不区分大小写匹配）：
- `token`
- `secret`
- `password`
- `credential`

`redactHeaders` 改为：遍历 entries，若 `isSensitiveHeader(key)` 则遮罩为 `***`。

`_looksLikeApiKeyField` 扩展匹配以上新字段。

### 4.5 `NetworkLogger` 接口扩展

```dart
mixin NetworkLogger {
  // 现有方法签名新增 logBody 默认参数
  Future<void> logRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? payload,
    bool logBody = false,  // 新增
  }) async {}

  Future<void> logResponseBody({
    required Uri uri,
    required Object? body,
    bool logBody = false,  // 新增
  }) async {}

  // 新增 drain
  Future<void> drain() async {}
}
```

`logBody = false` 为安全默认——不记录 body 除非显式选择。现有调用点不受影响（默认不记录 body）。

### 4.6 `ModelListClient` 观测对齐

```dart
// 修正前
await _logger.logResponse(
  uri: uri,
  statusCode: response.statusCode,
  headers: response.headers,
  elapsed: Duration.zero,  // ← 无意义
);

// 修正后
final requestStartedAt = DateTime.now();
// ... HTTP 请求 ...
final elapsed = DateTime.now().difference(requestStartedAt);
_fireAndForget(
  _logger.logResponse(
    uri: uri,
    statusCode: response.statusCode,
    headers: response.headers,
    elapsed: elapsed,
  ),
);
```

错误路径保留 `await`（确保持久化）。成功路径统一 `_fireAndForget`。

移除独立 `_truncateBody` 函数，改用 `truncateJsonValues`（grapheme-aware，项目统一）。

## 五、测试策略

### 5.1 Commit 1 测试：`test/core/http/custom_headers_http_client_test.dart`

- header 注入到请求
- `updateHeaders` 后后续请求携带新 header
- `close` 后 `send` 抛 `ClientException`
- 空 header map 不注入任何 header
- 用户定义 header 覆盖请求中已有的同名 header
- `currentHeaders` 返回不可变快照

### 5.2 Commit 2 测试：信任域分离

- `test/core/http/peer_http_client_provider_test.dart`
  - peer Provider 返回纯 `http.Client`，不是 `CustomHeadersHttpClient`
  - peer client 的请求不携带自定义 header
- `test/core/http/http_client_provider_test.dart`
  - LLM Provider 返回 `CustomHeadersHttpClient`
  - LLM client 的请求携带自定义 header
  - 两个 Provider 返回不同实例

### 5.3 Commit 3 测试：redactor 扩展

- `test/core/logging/network_log_redactor_test.dart` 新增：
  - `Cookie` header 被遮罩
  - `X-API-Key` header 被遮罩
  - `Token` / `Access-Token` / `Auth-Token` header 被遮罩
  - `Secret` / `Client-Secret` header 被遮罩
  - `Proxy-Authorization` header 被遮罩
  - 非 sensitive header 保留原值
  - JSON body 中 `token` / `secret` / `password` / `credential` 字段被遮罩
  - `isSensitiveHeader()` 公开方法断言

### 5.4 Commit 4 测试：SSE buffer

- `test/core/logging/sse_log_buffer_test.dart`：
  - 正常入队 + flush 写入磁盘
  - 容量满时丢弃最旧条目
  - 丢弃时写 `[sse-dropped]` 标记
  - drain 排空所有条目并停止定时器
  - 批量写入（满 batchSize 时自动 flush）
- `test/core/logging/app_log_store_test.dart` 新增：
  - `appendLines` 批量写入
  - `logResponseBody` 在 `logBody: false` 时跳过
  - `logRequest` 在 `logBody: false` 时省略 payload

### 5.5 Commit 5 测试：观测统一

- `test/features/settings/data/model_list_client_test.dart`：
  - 截断长度断言适配 `truncateJsonValues` 语义（≤220 替代 ≤203）
- `test/features/chat/data/openai_compatible_chat_client_test.dart`：
  - `_FakeNetworkLogger` 新增 `drain()` 和 `logBody` 参数

### 5.6 回归测试

每个 Commit 后执行全量测试 `flutter test --reporter compact > fltest.log 2>&1; E=$?; echo "EXIT=$E"; tail -n 150 fltest.log`，期望 `EXIT=0`。

## 六、实施顺序与独立提交节点

> 全部在 Bash 执行 `git commit`。版本 bump 由 `post-commit` hook 按前缀自动处理。

### Commit 1 - `feat(http): 新增 CustomHeadersHttpClient 单元测试`（TD-01 基线）

- 新增 `test/core/http/custom_headers_http_client_test.dart`
- 验证：单文件通过 + 全量 EXIT=0
- **此提交不改动生产代码**，仅为后续信任域分离建立测试基线

### Commit 2 - `feat(http): 新增 peer HTTP Client Provider 实现信任域分离`（TD-01 核心）

- 新增 `lib/core/http/peer_http_client_provider.dart`
- 修改 `lib/features/sync/application/sync_client_controller.dart`：`httpClientProvider` → `peerHttpClientProvider`
- 修改 `lib/features/media/application/media_browser_controller.dart`：`httpClientProvider` → `peerHttpClientProvider`
- 修改 `lib/features/media/application/shuffle_playback_controller.dart`：`httpClientProvider` → `peerHttpClientProvider`
- 修改 `test/features/media/helpers/media_test_helpers.dart`：override 改为 `peerHttpClientProvider`
- 修改 `test/helpers/test_harness.dart`：新增 `peerHttpClientProvider` override
- 更新 `lib/core/http/http_client_provider.dart` 注释
- 新增 `test/core/http/peer_http_client_provider_test.dart`
- 新增 `test/core/http/http_client_provider_test.dart`
- 验证：`flutter analyze` EXIT=0；全量测试 EXIT=0；peer 测试证明 peer 请求不携带自定义 header

### Commit 3 - `feat(logging): 扩展敏感 Header 脱敏集合`（TD-16 部分）

- 修改 `lib/core/logging/network_log_redactor.dart`：扩展敏感键集合 + 新增 `isSensitiveHeader()`
- 修改 `test/core/logging/network_log_redactor_test.dart`：新增扩展覆盖测试
- 验证：单文件通过 + 全量 EXIT=0；安全测试覆盖 Cookie/X-API-Key/Token/Secret 等

### Commit 4 - `feat(logging): SSE 日志有界缓冲区与 body 日志 opt-in`（TD-16 核心）

- 新增 `lib/core/logging/sse_log_buffer.dart`
- 修改 `lib/core/logging/network_logger.dart`：新增 `drain()`，`logRequest`/`logResponseBody` 新增 `logBody` 参数
- 修改 `lib/core/logging/app_network_logger.dart`：注入 `SseLogBuffer`，`logSseLine` 入队，实现 `drain()`，`onAppDetached` 调用 `drain()`，body 日志根据 `logBody` 参数
- 修改 `lib/core/logging/app_log_store.dart`：新增 `appendLines` 批量写入
- 新增 `test/core/logging/sse_log_buffer_test.dart`
- 更新 `test/core/logging/app_log_store_test.dart`：新增 `appendLines` / `logBody` 测试
- 更新 `test/features/chat/data/openai_compatible_chat_client_test.dart`：`_FakeNetworkLogger` 新增 `drain()` 和 `logBody` 参数
- 验证：`flutter analyze` EXIT=0；全量测试 EXIT=0；buffer 测试验证边界/溢出/drain

### Commit 5 - `refactor(logging): 统一 ModelListClient 与 ChatClient 观测契约`（TD-19）

- 修改 `lib/features/settings/data/model_list_client.dart`：真实计时、`_fireAndForget` 日志（错误路径保留 `await`）、移除 `_truncateBody` 改用 `truncateJsonValues`、`logRequest` 传 `logBody: false`
- 修改 `lib/features/chat/data/openai_compatible_chat_client.dart`：`logRequest` 传 `logBody: true`，`logResponseBody` 传 `logBody: true`
- 修改 `test/features/settings/data/model_list_client_test.dart`：截断断言适配
- 验证：`flutter analyze` EXIT=0；全量测试 EXIT=0；model list 测试验证 elapsed 非零

### Commit 6 - `style: 修复 SSE buffer 测试中的 lint 提示`

- 修复 `test/core/logging/sse_log_buffer_test.dart` 中的 `unnecessary_brace_in_string_interps` lint
- 验证：`flutter analyze` EXIT=0，No issues found

> 每个提交独立可 review、可回滚。Commit 1 是纯测试基线，Commit 2 是 TD-01 核心（信任域分离），Commit 3-4 是 TD-16 核心（脱敏+缓冲），Commit 5 是 TD-19 收敛（观测统一），Commit 6 是 lint 清理。

## 七、验证清单（对照 Verification Requirements）

- [x] `flutter analyze` 必须通过 → 每次提交验证 + CI step 2；最终 No issues found
- [x] 全量测试按重定向规范执行并得 EXIT=0 → 每次提交验证；最终 880+ 用例全过
- [x] 安全测试覆盖 Cookie/X-API-Key/Token/Secret/Auth 类 Header，证明 peer 不接收且日志不明文记录 → Commit 2 peer 测试 + Commit 3 redactor 测试（21 个测试用例）
- [x] 外部 LLM 请求仍获得配置的自定义 Header → Commit 2 `http_client_provider_test.dart` 断言 `currentHeaders` 包含自定义 Header
- [x] 模型列表与 chat 的耗时不再使用无意义零值 → Commit 5 修正 `Duration.zero` 为 `DateTime.now().difference(requestStartedAt)`
- [x] 高频 SSE 日志验证队列边界、批量落盘与 drain 契约 → Commit 4 `sse_log_buffer_test.dart`（6 个测试用例）

## 八、风险与缓解

| 风险 | 缓解 |
|---|---|
| 错误归类 consumer 致外部 LLM 丢失必需 Header | Commit 2 仅迁移 3 个 LAN peer 消费者（sync/media），不改 chat/model list；新增 trust domain 测试强制覆盖 |
| 错误归类 consumer 致 peer 仍携带敏感 Header | Commit 2 新增 peer Provider 测试断言 peer 请求不含自定义 Header；同步验证 `CustomHeadersHttpClient` 仅在 LLM Provider 中使用 |
| 日志策略收紧影响诊断信息 | `logBody` 默认 `false` 但可显式开启；chat client 传 `logBody: true` 保留完整调试能力；error 日志不受影响 |
| SSE buffer 丢弃条目导致诊断丢失 | 128 条容量（远超正常 SSE 行产出速率 × 500ms flush 间隔）；丢弃时写 `[sse-dropped]` 标记保留可见性；drain 确保退出前排空 |
| `NetworkLogger` 接口变更破坏现有实现 | `logBody` 有默认值 `false`，`NoopNetworkLogger` 继承 mixin 默认实现无需改动；`drain()` 默认 no-op |
| ModelListClient 计时修正引入行为变化 | 仅改日志观测，不改业务逻辑；计时从 `Duration.zero` 变为真实值是纯信息增强 |
| peer Provider 测试用 MockClient 注入覆盖 | `peerHttpClientProvider` 有默认实现，测试用 `overrideWithValue` 注入 MockClient，与现有 `httpClientProvider` 测试模式一致 |

## 九、Out Of Scope 确认

- ❌ 不实现 Sync 配对、认证、授权、签名或重放保护（Phase 7）
- ❌ 不引入厂商 SDK，不改 `package:http` 技术选型
- ❌ 不实现 vendor capability / adapter id（Phase 18）
- ❌ 不把 HTTP 抽象扩展成通用企业网络框架
- ❌ 不改 `CustomHeadersHttpClient` 类内部逻辑
- ❌ 不改 AppLogStore 轮转语义（仅标记不真正轮转）
- ❌ 不改 vendor adapter / SSE parser / streaming 逻辑
- ❌ 不改 server-side handler（sync/media HTTP handler）
- ❌ 不改 `customHeadersProvider` / `customHeadersMapProvider` / bootstrap override
- ❌ 不改 `AppLogStore._rotateIfExceeded` 行为

## 十、实施验证结论（已实测）

| 验证项 | 命令 | 结果 | 判定 |
|---|---|---|---|
| 静态分析 | `flutter analyze` | EXIT=0，No issues found | ✅ |
| 全量测试 | `flutter test --reporter compact`（重定向） | EXIT=0，880+ 用例全过 | ✅ |
| 信任域隔离 | `flutter test test/core/http/` | peer 不携带自定义 Header，LLM 携带 | ✅ TD-01 |
| 脱敏覆盖 | `flutter test test/core/logging/network_log_redactor_test.dart` | Cookie/X-API-Key/Token/Secret 等 21 个测试全过 | ✅ TD-16 |
| SSE 缓冲区 | `flutter test test/core/logging/sse_log_buffer_test.dart` | 边界/溢出/drain/批量 6 个测试全过 | ✅ TD-16 |
| body opt-in | `flutter test test/core/logging/app_log_store_test.dart` | `logBody: false` 跳过记录，`logBody: true` 正常写入 | ✅ TD-16 |
| 观测统一 | `flutter test test/features/settings/data/model_list_client_test.dart` | 真实计时、截断适配 | ✅ TD-19 |

**版本变化**：3.17.20 → 3.18.0（Commit 1 feat）→ 3.19.0（Commit 2 feat）→ 3.20.0（Commit 3 feat）→ 3.21.0（Commit 4 feat）→ 3.21.1（Commit 5 refactor）→ 3.21.2（Commit 6 style）
