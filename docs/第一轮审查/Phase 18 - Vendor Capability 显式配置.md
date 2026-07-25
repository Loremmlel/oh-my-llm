# Phase 18 - Vendor Capability 显式配置

## Phase Name

显式 Vendor Capability/Adapter 选择与 host fallback。

## Why this Phase exists

TD-18 被 Review Report 明确判定为“等真实兼容需求出现再做”，不能因为 Phase 3 修改 HTTP 边界就提前实现。本 Phase 因此单独后置并设置触发条件：当自托管、代理或同 host 不同模型能力导致现有 host 推断失效时，才增加显式 capability/adapter id，并保留 host 作为 fallback。

## Included Technical Debts

- **TD-18（P3）**：vendor adapter 主要按硬编码 host 推断能力，无法准确表达自托管、代理或同 host 不同模型差异。

## Dependencies

- 触发条件：出现可复现的真实 endpoint/model 兼容需求，现有 host fallback 无法正确选择策略。
- 前置 Phase：Phase 3 已稳定 external LLM HTTP/观测边界；Phase 5 已稳定模型设置工作流；Phase 11 已明确 port 与依赖规则。
- 后续依赖：未来新增非标准兼容 endpoint。
- 顺序理由：安全/可靠性先完成；显式 capability 只能由真实兼容案例定义，避免预建无需求插件系统。

## Expected Benefits

- 自托管、反向代理或同 host 不同模型可明确选择 payload adapter/capability。
- 新非标准 endpoint 不必修改硬编码 host 表后发版。
- 现有配置保持向后兼容，未设置 capability 时仍使用 host fallback 与 Default adapter。
- Vendor difference 继续由现有 Strategy 链处理，不污染主 chat client。

## File Scope

- Vendor strategy：`lib/features/chat/data/vendor_payload_adapters.dart`、必要的 chunk strategy 配置边界；不改无关 parser。
- Settings domain/application/presentation：`llm_provider_config.dart`、`llm_model_config.dart`、相关 controllers、provider/model form widgets，以及 settings export/import 兼容字段。
- Chat request composition：`lib/features/chat/data/openai_compatible_chat_client.dart`，仅限消费显式 adapter selection。
- Tests：vendor adapter unit/integration tests、model/provider config round-trip、settings import/export migration tests。

## Refactor Scope

- 从真实兼容案例提炼最小 capability/adapter selection contract。
- 允许 provider/model 配置显式选择支持的 adapter/capability，host inference 保留为未配置时 fallback。
- 定义未知、已删除或不受支持 adapter id 的安全 fallback/validation 行为。
- 保持现有 VendorPayloadAdapterRegistry 优先链与 DefaultPayloadAdapter 兜底，不创建通用插件系统。
- 使 settings export/import 和旧配置能兼容新增字段。

## Out Of Scope

- 无真实兼容需求时不实施本 Phase。
- 不创建动态插件市场、脚本执行或用户自定义 Dart adapter。
- 不引入厂商 SDK或按每个模型复制 client。
- 不改变 SSE parser、Reasoning/Content 分离或厂商策略优先级，除非触发案例明确要求且属于既有 strategy contract。

## Risks

- Capability 粒度过细会把供应商实现细节泄漏到 UI 配置。
- 显式配置与 host fallback 优先级不清会产生难诊断行为。
- Settings export 版本若未迁移，旧数据可能丢失或错误选择 adapter。
- 预建插件系统会明显超出报告结论并新增技术债。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 用触发本 Phase 的真实兼容案例验证显式配置优先于 host fallback。
- 覆盖未配置、未知 id、旧配置、export/import round-trip 与 Default adapter fallback。
- 现有 Gemini/DeepSeek/Standard OpenAI 请求与 chunk parsing integration tests 保持通过。

## Completion Criteria

- 真实兼容需求可以通过最小显式 capability/adapter config 解决，无需硬编码新 host。
- Host inference 与 Default adapter 仍提供向后兼容 fallback。
- 没有引入插件系统、厂商 SDK或 client 复制。
- 若触发条件尚不存在，本 Phase 保持未实施且不应被提前合并到 Phase 3。

## Implement Context For Next Agent

这是最后的条件 Phase。现有 `VendorPayloadAdapterRegistry` 按 host 匹配并由 Default adapter 兜底；报告只在真实自托管、代理或同 host 不同模型能力需求出现时建议增加 provider/model 的显式 capability/adapter id，host 继续 fallback。先记录可复现 endpoint/model 案例，再规划最小字段和迁移。不要预建插件系统、引入 SDK或重写 SSE/vendor strategy 链。
