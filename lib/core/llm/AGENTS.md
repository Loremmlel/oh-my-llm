# 共享 LLM 与协议

适用于共享调用、协议编码解析和原生续接。先读根与 [lib/AGENTS.md](../../AGENTS.md)；传输、取消和日志同时读 [HTTP 规则](../http/AGENTS.md)，Chat 文本政策读 [Chat 规则](../../features/chat/AGENTS.md)。

## 调用与职责

- 使用原始 `package:http`，不引入厂商 SDK 或按 host 猜厂商。Chat Completions、Responses、Anthropic Messages 各自处理原生文本、函数工具及续接编码解析，`protocol_routing_llm_client.dart` 穷举路由。
- `app/composition/llm_bindings.dart` 统一装配，feature 经自身 application port 注入，不能直接 import 协议实现或 composition。
- `LlmClient.streamCompletion` 是单订阅惰性调用；`complete` 折叠同一事件流。`LlmCompleted` 是权威完整结果，不再与增量重复拼接。`LlmUsage` / `ReasoningEffort` 归共享层，Chat 原 JSON / SQLite 字段保持兼容。
- 空回复、默认选项、Prompt、检查点、消息树、重试与持久化终态归 Chat，避免在共享层复制产品政策。

## 工具与原生回放

- 共享层只提出工具调用，不执行工具。只有完整终态的 `LlmToolCall` 能交给调用方；每轮最多 32 个调用，单个参数/结果最多 1 MiB UTF-8。
- `LlmAssistantTurn` 原生回放必须保持同一协议、解析后的 endpoint 和模型。显式切换目标后使用 `.portable`，只保留公共正文与函数工具，由目标输入编码器构造请求，不模拟原生 envelope。
- 原生与 portable 历史都必须一次提交全部 pending 结果。Responses 原生 reasoning、Messages thinking 签名不能用显示摘要替换。
- 缺少可靠原生输出时结果的 `assistantTurn` 为 null；调用方不得猜补，也不能用公共历史代替模型终态执行工具。

## 取消与诊断

- `LlmCallControl` 仅用于一次调用，请求级取消使用 `http.AbortableRequest`，不关闭共享 HTTP client。
- 响应头等待与 SSE idle timeout 分离；Chat 的响应头等待上限为 60 秒。
- 日志用 requestId / attempt 区分调用和 Chat Completions 的一次窄兼容重发。工具或原生续接请求禁止将 SSE 原文和错误体落盘，仅记录无内容摘要。
