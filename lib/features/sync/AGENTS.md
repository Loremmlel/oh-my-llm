# Sync 安全与交换格式

适用于同步、配对、授权和 Settings 交换格式任务。先读根与 [lib/AGENTS.md](../../AGENTS.md)；网络调用同时读 [HTTP 规则](../../core/http/AGENTS.md)。

- UDP 只用于发现；全部业务数据经 HTTP 配对与授权，不保留匿名兼容入口。
- 保留一次性配对码、持久化 peer identity / secret、加密 payload、短期 session token 与 nonce replay 防护。当前业务协议版本和支持范围以 [SyncProtocolVersionPolicy](domain/models/protocol/sync_protocol_version.dart) 为准，不在文档写死版本号。新增消息进入 typed `SyncProtocolMessage`，不退回动态 Map 或二次 JSON 字符串。
- 协议版本与 Settings export format 有明确 supported range 和迁移/拒绝语义；不支持的旧版、未来版或 malformed payload 显式失败，不能静默 fallback。格式生命周期同时遵守 [持久化规则](../../core/persistence/AGENTS.md)。
- 服务商 API key、自定义 Header 等敏感分类，在请求端和导入端均需显式确认；同一局域网不等于可信。peer 请求使用隔离的 peerHttpClientProvider，不能继承 LLM 凭据。
