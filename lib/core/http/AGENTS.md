# HTTP 信任域与流式传输

适用于 HTTP、SSE、请求取消和网络日志；Sync / Media 及共享 LLM 的调用方也需遵守。先读根与 [lib/AGENTS.md](../../AGENTS.md)，协议任务同时读 [LLM 规则](../llm/AGENTS.md)。

- 外部 LLM 使用 `httpClientProvider`，允许用户自定义 Header；LAN Sync / Media peer 必须使用 `peerHttpClientProvider`，绝不继承 API key、Cookie 或自定义 Header。
- 请求正文日志默认关闭，只在明确诊断路径 opt-in；敏感 Header 统一脱敏，脱敏测试覆盖所有已知敏感键。工具或原生续接请求只落无内容摘要，不落 SSE 原文和错误体。
- `LlmHttpStreamTransport`（`llm_http_stream_transport.dart`）负责流式 POST、连接异常和非 2xx 响应；`SseEventDecoder`（`sse_event_decoder.dart`）负责行/事件边界与 idle timeout，不在协议客户端各写一套传输。
- **只有 `data:` 行到达才重置 SSE idle timer**，注释 keepalive 不算活动。响应头等待和 idle timeout 是两种超时，不混为一个计时器。
- 取消使用单次调用的 `LlmCallControl` / `http.AbortableRequest`，不关闭共享 client，不影响其他请求。
