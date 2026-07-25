# Phase 8 - Sync 协议安全与版本契约

## Phase Name

局域网同步配对授权、敏感数据保护与 typed version protocol。

## Why this Phase exists

本 Phase 聚合 TD-02 与 TD-24。认证不能独立于协议版本和 typed payload 增补，否则新旧客户端会静默忽略安全字段；协议版本也不能在未定义身份、授权与敏感分类确认的情况下继续发布。两项共同作用于 sync domain/data/UI/测试，必须作为一个可回滚协议升级提交，但建立在 Phase 7 已解耦的 transport 和 settings facade 之上。

## Included Technical Debts

- **TD-02（P0）**：Sync HTTP 绑定所有 IPv4 地址，可被未配对 peer 请求包含 API key 的设置快照，无认证授权。
- **TD-24（P1）**：SyncMessage/version 与 SettingsExportData formatVersion 没有 supported range、拒绝或 migration，payload 二次 JSON 编码。

## Dependencies

- 前置 Phase：Phase 3 的 peer HTTP 信任域；Phase 5 的 settings transfer 边界；Phase 6 的 session 生命周期；Phase 7 的 transport/snapshot/importer facade。
- 后续依赖：Phase 16 的真实设备/release smoke 必须覆盖已认证的 sync 基本路径。
- 顺序理由：先建立可测试、可替换的资源与 transfer 边界，再升级 wire contract；否则认证实现会继续穿透 controller、handler 与 settings 内部类。

## Expected Benefits

- “同一局域网即可信”不再是隐式假设，只有已配对且获授权的 peer 能请求同步。
- 包含 provider API key 等敏感分类需要明确的二次确认和最小授权。
- 客户端能判断支持、迁移或拒绝某协议版本，不会静默丢字段。
- Payload 有 typed DTO 与结构化语义，认证元数据和业务数据不再依赖动态 Map/二次 JSON string。
- 协议具备报告要求的会话 token 基线，并为必要的签名/重放保护留下明确决策点。

## File Scope

- Sync domain：`lib/features/sync/domain/models/sync_message.dart`、`sync_types.dart` 及配对、授权、版本、typed payload contracts。
- Sync data：`lib/features/sync/data/sync_http_server.dart`、`sync_http_handler.dart`、`sync_udp_discovery.dart`，仅限 wire/auth contract。
- Sync application/presentation：`sync_client_controller.dart`、`sync_server_controller.dart`、`sync_screen.dart`、`sync_import_confirm_dialog.dart` 及 connection/operation widgets。
- Settings transfer model：`lib/features/settings/domain/models/settings_export_data.dart` 与 Phase 5/7 已建立的 snapshot/importer boundary。
- 对应 tests：`test/features/sync/**`、`test/features/settings/domain/models/settings_export_data_test.dart`、`test/integration/sync_*`。

## Refactor Scope

- 明确局域网同步 threat model、信任建立、session 生命周期、授权范围与失败行为。
- 为同步建立一次性配对与 session token 基线，并对敏感设置分类要求二次确认。
- 根据 threat model 明确请求签名、重放保护是否为当前协议必要组成；不得将未决安全假设留给调用者猜测。
- 将同步消息和设置 payload 定义为 typed contract，建立 supported version range、迁移和明确拒绝语义。
- 消除业务 payload 的二次 JSON 字符串包装，使版本与授权字段能被协议层一致验证。

## Out Of Scope

- 不暴露互联网同步，不新增云服务、账户体系或第三方认证供应商。
- 不重新设计 Settings 数据模型或添加新的同步分类。
- 不改变 Phase 7 的 transport/resource architecture。
- 不以“以后再加安全”为由保留无认证兼容入口。

## Risks

- Wire protocol 变化会影响新旧客户端互通，必须有明确拒绝/迁移而非隐式兼容。
- 配对 UX 若含糊，用户可能误授权敏感 provider secret。
- Session 生命周期过长会扩大泄露窗口，过短会造成连接不稳定。
- 仅有 token 而无适当重放策略时，局域网监听者的威胁可能仍未覆盖；须以 threat model 明确结论。

## Verification Requirements

- `flutter analyze` 必须通过。
- 全量测试按重定向规范执行并得到 `EXIT=0`。
- 未配对、token 错误/过期、未授权分类、敏感分类未确认、版本过旧/过新、迁移成功与 malformed payload 均有协议级测试。
- 现有支持版本的 settings/media 同步基本路径仍通过 integration tests。
- 安全测试证明 provider API key 不会被匿名 peer 请求获取。
- UDP discovery 只承担发现，不成为绕过 HTTP session 授权的通道。

## Completion Criteria

- Sync 只向已配对、当前会话有效且获分类授权的 peer 提供数据。
- 敏感设置同步有显式二次确认。
- Protocol 与 settings export version 有支持范围、迁移/拒绝契约和 typed payload。
- 不存在为了旧客户端保留的匿名敏感数据入口。

## Implement Context For Next Agent

当前 Sync server 绑定 `InternetAddress.anyIPv4`，任意 POST 可请求可能含 provider API key 的设置快照；没有配对、认证或授权。`SyncMessage.version` 和 `SettingsExportData.formatVersion` 目前是装饰字段，没有支持范围、迁移或拒绝，payload 还是二次 JSON 字符串。Phase 3 已区分 peer HTTP，Phase 5/7 应提供 transfer facade，Phase 6 应说明 session resource 生命周期。基于这些边界规划一个渐进但完整的协议升级：至少一次性配对/session token、敏感分类确认、typed payload 和版本策略，并以 threat model 决定签名/重放保护。不要新增云账户或改技术栈。
