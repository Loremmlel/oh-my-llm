# Phase 3 - HTTP 信任域与日志边界

## Phase Name

HTTP 信任域、敏感日志策略与统一观测边界。

## Why this Phase exists

本 Phase 聚合 TD-01、TD-16、TD-19。三项都作用于 HTTP 请求的 Trust Boundary：先区分外部 LLM 与局域网 peer 的 Header policy，才能定义最终 Header 的安全日志；统一薄观测边界则避免 chat 与模型列表继续复制不一致的计时和错误映射。它们共享 core/http、logging 和网络 client 文件，合并可避免重复改动同一调用链。

## Included Technical Debts

- **TD-01（P0）**：全局自定义 Header 被注入外部 LLM 和局域网 peer 的所有请求。
- **TD-16（P1）**：敏感 Header 脱敏集合不足，正文日志与逐 SSE chunk 强制落盘存在隐私和吞吐风险。
- **TD-19（P3）**：模型列表与 chat 请求的计时、日志和错误映射重复且不一致。

## Dependencies

- 前置 Phase：Phase 1。
- 后续依赖：Phase 6 的 sync/media 资源注入与 Phase 7 的同步认证必须消费明确的 peer HTTP 边界；Phase 18 的 vendor capability 只能在本 Phase 稳定的外部 LLM 边界上扩展。
- 顺序理由：安全隔离优先于同步协议与高层 controller 重构；日志观测必须以隔离后的最终请求边界为依据。

## Expected Benefits

- 局域网请求不再继承外部 LLM 的 API key、Cookie、代理 token 或任意自定义 Header。
- 开放 Header 集合采用安全默认值，敏感信息和聊天正文不会无意写入磁盘。
- SSE 日志写入有界、可排空，不形成无界 Future 链和逐 chunk 磁盘写放大。
- Chat 与模型列表共享一致、可信的耗时、最终 Header 与错误摘要语义。

## File Scope

- HTTP 基础设施：`lib/core/http/custom_headers_http_client.dart`、`custom_headers_provider.dart`、`http_client_provider.dart`，以及同目录直接相关的新边界契约。
- 日志基础设施：`lib/core/logging/network_log_redactor.dart`、`app_network_logger.dart`、`network_logger.dart`、`app_log_store.dart`。
- 外部 LLM 请求：`lib/features/chat/data/openai_compatible_chat_client.dart`、`lib/features/settings/data/model_list_client.dart`。
- Peer 请求消费者：`lib/features/sync/application/sync_client_controller.dart`、`lib/features/media/application/media_browser_controller.dart` 及其 provider 绑定位置。
- 对应测试：`test/core/logging/**`、`test/features/chat/data/openai_compatible_chat_client_test.dart`、`test/features/settings/data/model_list_client_test.dart`、相关 sync/media client tests 与 integration tests。

## Refactor Scope

- 将外部 LLM HTTP 与局域网 peer HTTP 定义为不同信任域，并为每个消费者声明其所属域。
- 使 peer 请求不接受外部 LLM 自定义 Header policy。
- 将 Header 脱敏扩展为对开放自定义键安全的策略；正文记录改为显式选择。
- 将 SSE 日志写入约束为有界、可批量落盘、可在生命周期结束前排空的观测通道。
- 统一模型列表与 chat 请求的计时、最终 Header 观测和错误截断契约。

## Out Of Scope

- 不实现 Sync 配对、认证、授权、签名或重放保护；属于 Phase 7。
- 不引入厂商 SDK，不改变原始 `package:http` 技术选型。
- 不实现 vendor capability/adapter id；属于 Phase 18。
- 不把 HTTP 抽象扩展成通用企业网络框架。

## Risks

- 错误归类 consumer 可能导致外部 LLM 丢失必需 Header，或 peer 仍携带敏感 Header。
- 日志策略收紧可能影响现有诊断信息，需要保留安全的请求关联和错误摘要。
- SSE drain 与应用退出的关系若定义不清，会重现“Future 完成但日志未落盘”的语义问题。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 安全测试覆盖自定义 `Cookie`、`X-API-Key`、token/key/secret/auth 类 Header，证明 peer 不接收且日志不明文记录。
- 外部 LLM 请求仍能获得其配置的自定义 Header；模型列表与 chat 的耗时不再使用无意义零值。
- 高频 SSE 日志验证队列边界、批量落盘与生命周期 drain 契约。

## Completion Criteria

- TD-01 的 Trust Boundary 可从 Provider/consumer 契约识别并由测试强制。
- TD-16 的敏感 Header 与正文策略是安全默认，SSE logging 有界且可完成。
- TD-19 的重复观测逻辑收敛为一个轻量边界，未引入厂商 SDK或新架构体系。
- Phase 可独立部署和回滚，不依赖尚未实现的同步认证。

## Implement Context For Next Agent

本 Phase 的核心不是“重写 HTTP 层”，而是让每个请求明确属于外部 LLM 或局域网 peer。当前全局 `CustomHeadersHttpClient` 会向所有 host 注入用户 Header；sync/media 与 chat/model list 共用 HTTP client；日志只识别少数敏感键，SSE 逐 chunk fire-and-forget 且强制 flush；ModelListClient 与 chat client 的观测逻辑重复。保持 `package:http`、现有 SSE parser 和 vendor adapter 链不变。Implement Plan 应以安全契约、消费者迁移和回归测试为边界，不提前处理同步认证或 vendor capability。
